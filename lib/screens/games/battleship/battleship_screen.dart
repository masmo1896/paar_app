import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/app_logger.dart';
import '../../../services/battleship_service.dart';
import '../../../theme.dart';
import '../../../utils/battleship_logic.dart';
import '../../../widgets/motion.dart';
import '../../../widgets/who.dart';
import '../effects.dart';
import 'fleet_setup.dart';
import 'sea_board.dart';

/// Schiffe versenken: Flotte aufstellen, dann abwechselnd aufs Feindmeer schiessen.
/// Ausgewertet wird auf dem Server (Cloud Function onBattleShot).
class BattleshipScreen extends StatelessWidget {
  const BattleshipScreen({super.key, required this.couple});

  final Couple couple;

  @override
  Widget build(BuildContext context) {
    final service = BattleshipService.instance;
    return Scaffold(
      backgroundColor: Kitsune.deeper,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('Schiffe versenken', style: AppTheme.serif(size: 20)),
        actions: [
          StreamBuilder<BattleGame?>(
            stream: service.current(couple.coupleId),
            builder: (context, snap) {
              final g = snap.data;
              if (g == null || g.isDone) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v != 'giveUp') return;
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Aufgeben?'),
                      content: Text(
                        '${couple.partnerLabel} gewinnt diese Runde.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Weiterspielen'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Aufgeben'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) await service.giveUp(couple.coupleId, g);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'giveUp', child: Text('Aufgeben')),
                ],
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<BattleGame?>(
        stream: service.current(couple.coupleId),
        builder: (context, snap) {
          if (!snap.hasData &&
              snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final game = snap.data;
          if (game == null) return _NewGame(couple: couple, first: true);
          return _GameView(key: ValueKey(game.id), couple: couple, game: game);
        },
      ),
    );
  }
}

class _NewGame extends StatelessWidget {
  const _NewGame({required this.couple, this.first = false});

  final Couple couple;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final partner = couple.partnerUid;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('海戦', style: AppTheme.serif(size: 44, color: Kitsune.lantern)),
            const SizedBox(height: 8),
            Text(
              first ? 'Eure erste Seeschlacht' : 'Noch eine Runde?',
              style: AppTheme.serif(size: 22),
            ),
            const SizedBox(height: 10),
            const Text(
              'Stellt beide eure Flotte auf. Dann schiesst ihr abwechselnd – '
              'bei einem Treffer darfst du gleich nochmal.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Kitsune.mist),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: partner == null
                  ? null
                  : () => BattleshipService.instance
                        .newGame(couple.coupleId, partner)
                        .catchError((Object e, StackTrace s) {
                          AppLogger.error(e, s, where: 'Schiffe: neues Spiel');
                        }),
              icon: const Icon(Icons.sailing_rounded),
              label: const Text('Neues Spiel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameView extends StatefulWidget {
  const _GameView({super.key, required this.couple, required this.game});

  final Couple couple;
  final BattleGame game;

  @override
  State<_GameView> createState() => _GameViewState();
}

class _GameViewState extends State<_GameView> {
  final _enemyFx = EffectLayer();
  final _homeFx = EffectLayer();
  late final _pages = PageController(
    initialPage: widget.game.isPlaying && widget.game.turn != _me ? 1 : 0,
  );
  int _page = 0;
  Point<int>? _aim;
  bool _firing = false;
  bool _editFleet = false;

  BoardGeometry? _geo;
  // Bekannte Ergebnisse je Schuss – Änderungen lösen Effekte aus.
  final _known = <String, ShotResult>{};
  bool _primed = false;
  final _replay = <Shot>[];
  bool _replaying = false;
  String? _lastStatus;

  String get _me => widget.couple.myUid;
  String get _partner => widget.couple.partnerUid ?? '';
  BattleshipService get _service => BattleshipService.instance;

  @override
  void initState() {
    super.initState();
    _page = _pages.initialPage;
    _lastStatus = widget.game.status;
  }

  @override
  void didUpdateWidget(_GameView old) {
    super.didUpdateWidget(old);
    final status = widget.game.status;
    if (status == 'done' && _lastStatus == 'playing') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _gameOver());
    }
    if (status == 'playing' && _lastStatus == 'setup') {
      _goTo(widget.game.turn == _me ? 0 : 1);
    }
    _lastStatus = status;
  }

  @override
  void dispose() {
    _enemyFx.dispose();
    _homeFx.dispose();
    _pages.dispose();
    super.dispose();
  }

  bool get _calm => reduceMotion(context);

  void _goTo(int page) {
    if (!_pages.hasClients || _page == page) return;
    _pages.animateToPage(
      page,
      duration: const Duration(milliseconds: 380),
      curve: motionCurve,
    );
  }

  // ---- Effekte -----------------------------------------------------------

  /// Neue Schüsse und neue Ergebnisse erkennen.
  Future<void> _react(List<Shot> shots) async {
    if (!_primed) {
      _primed = true;
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getInt(_seenKey) ?? 0;
      final theirs = shots
          .where((s) => s.by == _partner && s.result != ShotResult.pending)
          .toList();
      for (final s in shots) {
        _known[s.id] = s.result;
      }
      // Züge des Schatzes seit dem letzten Öffnen nachspielen.
      if (theirs.length > seen && !widget.game.isDone) {
        _replay.addAll(theirs.skip(seen).take(6));
        unawaited(_playReplay());
      }
      await _markSeen(theirs.length);
      return;
    }
    for (final s in shots) {
      final before = _known[s.id];
      _known[s.id] = s.result;
      if (before == s.result) continue;
      if (s.by == _me) {
        if (s.result != ShotResult.pending) _impact(_enemyFx, s, mine: true);
      } else if (s.result != ShotResult.pending) {
        _replay.add(s);
        unawaited(_playReplay());
      }
    }
    final theirCount = shots
        .where((s) => s.by == _partner && s.result != ShotResult.pending)
        .length;
    await _markSeen(theirCount);
  }

  String get _seenKey => 'bs_seen_${widget.game.id}';

  Future<void> _markSeen(int count) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_seenKey, count);
    } catch (_) {
      // Nur eine Komfort-Funktion – ohne Speicher wird halt nichts nachgespielt.
    }
  }

  /// Schüsse des Schatzes nacheinander auf «Dein Meer» zeigen.
  Future<void> _playReplay() async {
    if (_replaying) return;
    _replaying = true;
    _goTo(1);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    while (_replay.isNotEmpty && mounted) {
      final s = _replay.removeAt(0);
      final geo = _geo;
      if (geo != null && !_calm) {
        final done = Completer<void>();
        _homeFx.fireball(
          Offset(geo.label + geo.cell * 5, -geo.cell),
          geo.center(s.x, s.y),
          onArrive: done.complete,
        );
        await done.future;
      }
      if (!mounted) break;
      _impact(_homeFx, s, mine: false);
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    _replaying = false;
    if (mounted && widget.game.isPlaying && widget.game.turn == _me) _goTo(0);
  }

  void _impact(EffectLayer fx, Shot s, {required bool mine}) {
    final geo = _geo;
    switch (s.result) {
      case ShotResult.miss:
        HapticFeedback.lightImpact();
        if (geo != null && !_calm) fx.splash(geo.center(s.x, s.y), geo.cell);
      case ShotResult.hit:
        HapticFeedback.heavyImpact();
        if (geo != null && !_calm) fx.explosion(geo.center(s.x, s.y), geo.cell);
      case ShotResult.sunk:
        HapticFeedback.heavyImpact();
        Future<void>.delayed(
          const Duration(milliseconds: 160),
          HapticFeedback.heavyImpact,
        );
        if (geo != null && !_calm) {
          final cells = s.shipCells.isEmpty ? [Point(s.x, s.y)] : s.shipCells;
          fx.foxfire([for (final c in cells) geo.center(c.x, c.y)], geo.cell);
        }
        _toast(
          mine
              ? 'Versenkt! ${_shipWord(s.shipLen)} geht unter 🔥'
              : '${widget.couple.partnerLabel} hat dein ${_shipWord(s.shipLen)} versenkt',
        );
      case ShotResult.pending:
        break;
    }
  }

  String _shipWord(int? len) => switch (len) {
    5 => 'Flaggschiff',
    4 => 'Mondsegler',
    3 => 'Boot',
    _ => 'Papierboot',
  };

  void _gameOver() {
    final geo = _geo;
    final won = widget.game.winner == _me;
    if (won) {
      HapticFeedback.heavyImpact();
    }
    if (geo != null && !_calm) {
      final size = Size.square(geo.label + geo.cell * boardSize);
      if (won) {
        _enemyFx.fireworks(size, bursts: 8);
        _homeFx.fireworks(size, bursts: 5);
      } else {
        _homeFx.rain(size);
        _enemyFx.rain(size);
      }
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
      );
  }

  // ---- Schiessen ---------------------------------------------------------

  void _tapEnemy(int x, int y, List<Shot> shots) {
    final g = widget.game;
    if (!g.isPlaying || g.turn != _me || g.resolving || _firing) return;
    if (shots.any((s) => s.by == _me && s.x == x && s.y == y)) {
      HapticFeedback.selectionClick();
      _toast('Da hast du schon hingeschossen.');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _aim = Point(x, y));
  }

  Future<void> _fire() async {
    final aim = _aim;
    if (aim == null) return;
    setState(() => _firing = true);
    HapticFeedback.mediumImpact();
    final geo = _geo;
    if (geo != null && !_calm) {
      _enemyFx.fireball(
        Offset(geo.label + geo.cell * 5, geo.label + geo.cell * 11.5),
        geo.center(aim.x, aim.y),
      );
    }
    try {
      await _service.shoot(
        widget.couple.coupleId,
        widget.game.id,
        aim.x,
        aim.y,
      );
      if (mounted) setState(() => _aim = null);
    } catch (e, s) {
      AppLogger.error(e, s, where: 'Schiffe: schiessen');
      _toast('Schuss ging nicht durch – nochmal versuchen.');
    } finally {
      if (mounted) setState(() => _firing = false);
    }
  }

  // ---- Oberfläche --------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    return StreamBuilder<List<Ship>?>(
      stream: _service.myFleet(widget.couple.coupleId, g.id),
      builder: (context, fleetSnap) {
        final myFleet = fleetSnap.data;
        if (g.isSetup && (myFleet == null || _editFleet)) {
          if (fleetSnap.connectionState == ConnectionState.waiting &&
              !fleetSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              FleetSetup(
                initial: myFleet,
                onReady: (ships) async {
                  try {
                    await _service.placeFleet(
                      widget.couple.coupleId,
                      g.id,
                      ships,
                    );
                    if (mounted) setState(() => _editFleet = false);
                  } catch (e, s) {
                    AppLogger.error(e, s, where: 'Schiffe: Flotte speichern');
                    _toast('Flotte konnte nicht gespeichert werden.');
                  }
                },
              ),
            ],
          );
        }
        return StreamBuilder<List<Shot>>(
          stream: _service.shots(widget.couple.coupleId, g.id),
          builder: (context, shotSnap) {
            final shots = shotSnap.data ?? const <Shot>[];
            if (shotSnap.hasData) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _react(shots);
              });
            }
            return _board(g, myFleet ?? const [], shots);
          },
        );
      },
    );
  }

  Widget _board(BattleGame g, List<Ship> myFleet, List<Shot> shots) {
    final myShots = shots.where((s) => s.by == _me).toList();
    final theirShots = shots.where((s) => s.by != _me).toList();
    final mySunk = g.sunk[_me]?.toSet() ?? const <String>{};
    final theirSunk = g.sunk[_partner] ?? const <String>[];
    final enemyShips = g.isDone
        ? (g.revealed[_partner] ?? const <Ship>[])
        : const <Ship>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _StatusBar(
          game: g,
          me: _me,
          partnerLabel: widget.couple.partnerLabel,
          firing: _firing,
        ),
        const SizedBox(height: 10),
        _Scoreboard(
          game: g,
          couple: widget.couple,
          myShipsLeft: 5 - mySunk.length,
          theirShipsLeft: 5 - theirSunk.length,
        ),
        const SizedBox(height: 10),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, label: Text('Feindmeer')),
            ButtonSegment(value: 1, label: Text('Dein Meer')),
          ],
          selected: {_page},
          onSelectionChanged: (s) => _goTo(s.first),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final side = c.maxWidth;
            _geo = BoardGeometry(side);
            return SizedBox(
              height: side,
              child: PageView(
                controller: _pages,
                onPageChanged: (p) => setState(() => _page = p),
                children: [
                  BattleBoard(
                    effects: _enemyFx,
                    ships: enemyShips,
                    shots: myShots,
                    aim: _aim,
                    onTapCell: (x, y) => _tapEnemy(x, y, shots),
                  ),
                  BattleBoard(
                    effects: _homeFx,
                    ships: myFleet,
                    shots: theirShots,
                    sunkIds: mySunk,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        if (g.isSetup) ...[
          Text(
            'Deine Flotte ist bereit. Sobald ${widget.couple.partnerLabel} '
            'aufgestellt hat, geht es los.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Kitsune.mist),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _editFleet = true),
            child: const Text('Flotte umstellen'),
          ),
        ] else if (g.isPlaying && _page == 0)
          Center(
            child: AnimatedOpacity(
              opacity: _aim != null && g.turn == _me && !g.resolving ? 1 : 0.4,
              duration: const Duration(milliseconds: 200),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Kitsune.lantern,
                  foregroundColor: Kitsune.paper,
                  minimumSize: const Size(168, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                ),
                onPressed:
                    _aim != null && g.turn == _me && !g.resolving && !_firing
                    ? _fire
                    : null,
                icon: const Text('火', style: TextStyle(fontSize: 18)),
                label: Text(_aim == null ? 'Feld wählen' : 'Feuer!'),
              ),
            ),
          )
        else if (g.isDone)
          _Result(game: g, me: _me, couple: widget.couple),
        if (g.resolving && g.turn == _me) ...[
          const SizedBox(height: 8),
          _StuckHelper(couple: widget.couple, game: g),
        ],
      ],
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.game,
    required this.me,
    required this.partnerLabel,
    required this.firing,
  });

  final BattleGame game;
  final String me;
  final String partnerLabel;
  final bool firing;

  @override
  Widget build(BuildContext context) {
    final (text, hot) = switch (game) {
      BattleGame(isSetup: true) => ('Flotten werden aufgestellt …', false),
      BattleGame(isDone: true) => (
        game.winner == me
            ? 'Gewonnen! 🎆'
            : '$partnerLabel gewinnt diese Runde',
        game.winner == me,
      ),
      BattleGame(resolving: true) => ('Der Schuss fliegt …', true),
      _ when game.turn == me => (
        'Du bist dran – wähle ein Feld im Feindmeer',
        true,
      ),
      _ => ('$partnerLabel zielt …', false),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: hot
            ? Kitsune.lantern.withValues(alpha: 0.18)
            : Kitsune.deep.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hot
              ? Kitsune.lantern.withValues(alpha: 0.6)
              : const Color(0x4DF3EBD3),
        ),
      ),
      child: Row(
        children: [
          Hanko(hot ? '番' : '待', size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (firing || game.resolving)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

/// Punktestand dieser Partie, Allzeit-Rekord und Siege – mittig ausgerichtet.
class _Scoreboard extends StatelessWidget {
  const _Scoreboard({
    required this.game,
    required this.couple,
    required this.myShipsLeft,
    required this.theirShipsLeft,
  });

  final BattleGame game;
  final Couple couple;
  final int myShipsLeft;
  final int theirShipsLeft;

  @override
  Widget build(BuildContext context) {
    final me = couple.myUid, partner = couple.partnerUid ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Kitsune.deep.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x4DF3EBD3)),
      ),
      child: StreamBuilder<BattleRecords>(
        stream: BattleshipService.instance.records(couple.coupleId),
        builder: (context, snap) {
          final r = snap.data;
          final holder = r?.bestBy == null
              ? null
              : r!.bestBy == me
              ? 'Du'
              : couple.partnerLabel;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ScoreColumn(
                  label: 'Du',
                  score: game.scores[me] ?? 0,
                  shipsLeft: myShipsLeft,
                  wins: r?.wins[me] ?? 0,
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text('REKORD', style: AppTheme.label(size: 10)),
                    const SizedBox(height: 4),
                    Text(
                      '${r?.best ?? 0}',
                      style: AppTheme.serif(size: 22, color: Kitsune.lantern),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      holder ?? 'noch offen',
                      style: const TextStyle(fontSize: 11, color: Kitsune.mist),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _ScoreColumn(
                  label: couple.partnerLabel,
                  score: game.scores[partner] ?? 0,
                  shipsLeft: theirShipsLeft,
                  wins: r?.wins[partner] ?? 0,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScoreColumn extends StatelessWidget {
  const _ScoreColumn({
    required this.label,
    required this.score,
    required this.shipsLeft,
    required this.wins,
  });

  final String label;
  final int score;
  final int shipsLeft;
  final int wins;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.label(size: 10),
      ),
      const SizedBox(height: 4),
      Text('$score', style: AppTheme.serif(size: 22)),
      const SizedBox(height: 4),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 5; i++)
            Icon(
              Icons.sailing_rounded,
              size: 13,
              color: i < shipsLeft ? Kitsune.paper : Kitsune.inkSoft,
            ),
        ],
      ),
      const SizedBox(height: 2),
      Text(
        wins == 1 ? '1 Sieg' : '$wins Siege',
        style: const TextStyle(fontSize: 11, color: Kitsune.mist),
      ),
    ],
  );
}

class _Result extends StatelessWidget {
  const _Result({required this.game, required this.me, required this.couple});

  final BattleGame game;
  final String me;
  final Couple couple;

  @override
  Widget build(BuildContext context) {
    final partner = couple.partnerUid;
    return Column(
      children: [
        StreamBuilder<BattleRecords>(
          stream: BattleshipService.instance.records(couple.coupleId),
          builder: (context, snap) {
            final r = snap.data;
            final mine = game.scores[me] ?? 0;
            final newRecord = r != null && mine > 0 && mine >= r.best;
            return Text(
              newRecord
                  ? 'Neuer Rekord: $mine Punkte! 🏆'
                  : 'Diese Runde: $mine Punkte',
              textAlign: TextAlign.center,
              style: AppTheme.serif(size: 16),
            );
          },
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size(168, 46),
            padding: const EdgeInsets.symmetric(horizontal: 26),
          ),
          onPressed: partner == null
              ? null
              : () => BattleshipService.instance.newGame(
                  couple.coupleId,
                  partner,
                ),
          icon: const Icon(Icons.replay_rounded),
          label: const Text('Revanche'),
        ),
      ],
    );
  }
}

/// Falls die Auswertung hängt (z. B. kein Netz beim Server): nach 1 Minute lösen.
class _StuckHelper extends StatefulWidget {
  const _StuckHelper({required this.couple, required this.game});

  final Couple couple;
  final BattleGame game;

  @override
  State<_StuckHelper> createState() => _StuckHelperState();
}

class _StuckHelperState extends State<_StuckHelper> {
  bool _show = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 65), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_show
      ? const SizedBox.shrink()
      : TextButton(
          onPressed: () => BattleshipService.instance
              .unlock(widget.couple.coupleId, widget.game.id)
              .catchError((Object e, StackTrace s) {
                AppLogger.error(e, s, where: 'Schiffe: Sperre lösen');
              }),
          child: const Text('Hängt? Auswertung neu starten'),
        );
}
