import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

import '../../../services/app_logger.dart';
import '../../../services/crossword_service.dart';
import '../../../theme.dart';
import '../../../utils/crossword_generator.dart';
import '../../../utils/crossword_logic.dart';
import '../../../utils/crossword_tips.dart';
import '../../../widgets/lantern_backdrop.dart';
import '../../../widgets/motion.dart';
import '../../../widgets/partner_header.dart';
import '../../../widgets/who.dart';
import '../effects.dart';

/// Gemeinsames Kreuzworträtsel: abwechselnd ein Wort raten oder einen
/// Buchstaben aufdecken. Gelöst wird zusammen. Aufgebaut wie die Startseite:
/// Laternen-Illustration im Hintergrund (Parallax), Kopf mit japanischer Zeile,
/// darunter die Karten.
class CrosswordScreen extends StatefulWidget {
  const CrosswordScreen({super.key, required this.couple});

  final Couple couple;

  @override
  State<CrosswordScreen> createState() => _CrosswordScreenState();
}

class _CrosswordScreenState extends State<CrosswordScreen> {
  final _scroll = ScrollController();

  // Das Rätsel wird erst aufgebaut, wenn die Seite ganz hereingeglitten ist –
  // so bleibt die Übergangsanimation flüssig.
  bool _settled = false;
  Animation<double>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context)?.animation;
    if (route == _route) return;
    _route?.removeStatusListener(_onRoute);
    _route = route;
    if (route == null || route.status == AnimationStatus.completed) {
      _settled = true;
    } else {
      route.addStatusListener(_onRoute);
    }
  }

  void _onRoute(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_settled) {
      setState(() => _settled = true);
    }
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_onRoute);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final couple = widget.couple;
    final top = MediaQuery.paddingOf(context).top;
    // Den deckenden Grund (Wellenmuster) gibt jetzt die Seitenanimation dazu.
    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: -44,
            left: 0,
            right: 0,
            height: 300 + top,
            child: LanternBackdrop(scroll: _scroll),
          ),
          StreamBuilder<CrosswordGame?>(
            stream: CrosswordService.instance.current(couple.coupleId),
            builder: (context, snap) {
              final loading =
                  !snap.hasData &&
                  snap.connectionState == ConnectionState.waiting;
              final game = snap.data;
              return ListView(
                controller: _scroll,
                padding: EdgeInsets.zero,
                children: [
                  _Header(couple: couple, game: game),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    child: !_settled
                        // Platzhalter während der Animation (gleich hoch wie der
                        // Ladekreis, damit nichts springt).
                        ? const SizedBox(height: 120)
                        : loading
                        ? const Padding(
                            padding: EdgeInsets.only(top: 40),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : game == null
                        ? FadeSlideIn(
                            key: const ValueKey('start'),
                            child: _Start(couple: couple, first: true),
                          )
                        : FadeSlideIn(
                            key: ValueKey('in-${game.id}'),
                            child: _Puzzle(
                              key: ValueKey(game.id),
                              couple: couple,
                              game: game,
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
          // Zurück-Knopf schwebt über den Laternen, wie die Knöpfe im Chat.
          Positioned(
            top: top + 8,
            left: 12,
            child: HeaderCircle(
              child: IconButton(
                style: HeaderCircle.buttonStyle,
                tooltip: 'Zurück',
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                onPressed: () => Navigator.maybePop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kopf wie auf der Startseite: «くろすわーど / Kreuzworträtsel / Stufe und
/// Fortschritt», darunter wie die Tagesweisheit eure gemeinsame Bilanz.
class _Header extends StatelessWidget {
  const _Header({required this.couple, required this.game});

  final Couple couple;
  final CrosswordGame? game;

  @override
  Widget build(BuildContext context) {
    final g = game;
    final level = g == null ? null : CrosswordLevel.fromName(g.difficulty);
    final line = g == null || level == null
        ? 'Von sehr leicht bis Gott – ihr wählt'
        : g.isDone
        ? '${level.label} · gelöst ✓'
        : '${level.label} ${'★' * level.stars} · '
              '${g.solved.length} von ${g.words.length} Wörtern';
    final top = MediaQuery.paddingOf(context).top;
    return SizedBox(
      height: 236 + top,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 20,
            right: 20,
            bottom: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'くろすわーど',
                  style: AppTheme.serif(
                    size: 12,
                    weight: FontWeight.w600,
                    color: Kitsune.aqua,
                  ).copyWith(letterSpacing: 3.6),
                ),
                const SizedBox(height: 3),
                Text(
                  'Kreuzworträtsel',
                  style: AppTheme.serif(size: 25).copyWith(
                    shadows: const [
                      Shadow(color: Kitsune.deep, blurRadius: 10),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  line,
                  style: const TextStyle(fontSize: 12, color: Kitsune.mist),
                ),
                const SizedBox(height: 10),
                _TogetherLine(couple: couple),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// «一緒に解いた – Ihr habt schon 12 Rätsel zusammen gelöst», mit dem feinen
/// roten Strich wie bei der Weisheit des Tages.
class _TogetherLine extends StatelessWidget {
  const _TogetherLine({required this.couple});

  final Couple couple;

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
    stream: CrosswordService.instance.solvedCount(couple.coupleId),
    builder: (context, snap) {
      final n = snap.data ?? 0;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 2,
            height: 34,
            margin: const EdgeInsets.only(right: 10, top: 2),
            color: Kitsune.lantern.withValues(alpha: 0.8),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '一緒に解いた',
                  style: AppTheme.serif(size: 14, color: Kitsune.paper),
                ),
                Text(
                  n == 0
                      ? 'Euer erstes gemeinsames Rätsel wartet'
                      : n == 1
                      ? 'Ein Rätsel habt ihr schon zusammen gelöst'
                      : '$n Rätsel habt ihr schon zusammen gelöst',
                  style: const TextStyle(fontSize: 12, color: Kitsune.mist),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// Karte wie auf der Startseite: dunkles Nachtblau, feiner heller Rand.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
    decoration: BoxDecoration(
      color: Kitsune.deep.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0x40F3EBD3)),
    ),
    child: child,
  );
}

Future<void> _newPuzzle(
  BuildContext context,
  Couple couple,
  CrosswordLevel level,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    // Bei Fehlern (z. B. offline) einfach ohne Merkliste würfeln.
    final recent = await CrosswordService.instance
        .recentAnswers(couple.coupleId)
        .catchError((_) => <String>[]);
    final r = generateForLevel(level, avoid: recent);
    await CrosswordService.instance.newGame(
      couple.coupleId,
      r.puzzle.size,
      r.puzzle.words,
      difficulty: level.name,
      revealed: r.revealed,
    );
  } catch (e, s) {
    AppLogger.error(e, s, where: 'Kreuzwort: neues Rätsel');
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Die Stufe «${level.label}» konnte nicht gestartet werden. '
          'Bitte Verbindung prüfen und noch einmal versuchen.',
        ),
      ),
    );
  }
}

class _Start extends StatelessWidget {
  const _Start({required this.couple, this.first = false});

  final Couple couple;
  final bool first;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Card(
        child: Row(
          children: [
            const Hanko('謎', size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    first ? 'Euer erstes Rätsel' : 'Neues Rätsel',
                    style: AppTheme.serif(size: 19),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Abwechselnd ein Wort prüfen oder einen Buchstaben aufdecken. '
                    'Jedes Wort hat einen versiegelten Tipp 💡.',
                    style: const TextStyle(fontSize: 13, color: Kitsune.mist),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text('WIE KNIFFLIG?', style: AppTheme.label()),
      const SizedBox(height: 8),
      _LevelPicker(onPick: (level) => _newPuzzle(context, couple, level)),
    ],
  );
}

/// Gleich grosse Knöpfe: Einfach / Mittel / Schwer / Experte / Gott.
class _LevelPicker extends StatefulWidget {
  const _LevelPicker({required this.onPick});

  final Future<void> Function(CrosswordLevel level) onPick;

  @override
  State<_LevelPicker> createState() => _LevelPickerState();
}

class _LevelPickerState extends State<_LevelPicker> {
  CrosswordLevel? _busy;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final level in CrosswordLevel.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: level == CrosswordLevel.medium
                ? Kitsune.paper
                : Kitsune.deep.withValues(alpha: 0.85),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: const BorderSide(color: Color(0x4DF3EBD3)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _busy != null
                  ? null
                  : () async {
                      setState(() => _busy = level);
                      await widget.onPick(level);
                      if (mounted) setState(() => _busy = null);
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Hanko(
                      switch (level) {
                        CrosswordLevel.veryEasy => '初',
                        CrosswordLevel.easy => '易',
                        CrosswordLevel.medium => '中',
                        CrosswordLevel.hard => '難',
                        CrosswordLevel.expert => '極',
                        CrosswordLevel.god => '神',
                      },
                      size: 26,
                      filled: level.index > 1,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                level.label,
                                style: AppTheme.serif(
                                  size: 17,
                                  color: level == CrosswordLevel.medium
                                      ? Kitsune.night
                                      : Kitsune.paper,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '★' * level.stars + '☆' * (6 - level.stars),
                                style: TextStyle(
                                  fontSize: 11,
                                  letterSpacing: 1,
                                  color: level == CrosswordLevel.medium
                                      ? Kitsune.lantern
                                      : Kitsune.aqua,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            level.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: level == CrosswordLevel.medium
                                  ? Kitsune.inkSoft
                                  : Kitsune.mist,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_busy == level)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _Puzzle extends StatefulWidget {
  const _Puzzle({super.key, required this.couple, required this.game});

  final Couple couple;
  final CrosswordGame game;

  @override
  State<_Puzzle> createState() => _PuzzleState();
}

class _PuzzleState extends State<_Puzzle> with TickerProviderStateMixin {
  String? _selected;
  late final _fx = EffectLayer();
  // Läuft nur, solange ein Effekt zu sehen ist – sonst hielte sie die App
  // dauernd im Animationsmodus (macht u. a. das Öffnen und Schliessen zäh).
  late final Ticker _ticker = createTicker((e) {
    final dt = ((e - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = e;
    _fx.tick(dt);
    if (!_fx.busy) _ticker.stop();
  });
  Duration _last = Duration.zero;
  late bool _wasDone = widget.game.isDone;
  Size _gridSize = Size.zero;

  // Frisch eingetragene Felder kurz «einstempeln».
  late final _stamp = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..value = 1;
  Set<Point<int>> _fresh = {};
  late Map<String, String> _solvedBefore = Map.of(widget.game.solved);

  /// Feuerwerk über dem Gitter zünden und die Effekt-Uhr starten.
  void _fireworks(int bursts) {
    if (reduceMotion(context) || _gridSize == Size.zero) return;
    _fx.fireworks(_gridSize, bursts: bursts);
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(_Puzzle old) {
    super.didUpdateWidget(old);
    final g = widget.game;
    final newly = g.solved.keys.where((k) => !_solvedBefore.containsKey(k));
    if (newly.isNotEmpty) {
      _fresh = {
        for (final w in g.words)
          if (newly.contains(w.id)) ...w.cells,
      };
      _stamp.forward(from: 0);
    }
    _solvedBefore = Map.of(g.solved);
    // Der Schatz hat gezogen und ich bin dran: kurz spürbar machen.
    final me = widget.couple.myUid;
    if (!g.isDone &&
        g.turn == me &&
        old.game.turn != me &&
        g.lastMove?.type == 'solved') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        HapticFeedback.mediumImpact();
        if (mounted) _fireworks(2);
      });
    }
    if (g.isDone && !_wasDone) {
      _wasDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        HapticFeedback.heavyImpact();
        if (mounted) _fireworks(8);
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _fx.dispose();
    _stamp.dispose();
    super.dispose();
  }

  bool get _myTurn =>
      !widget.game.isDone && widget.game.turn == widget.couple.myUid;

  // Tipps, die nur hier sichtbar sind (falls die Server-Regeln sie noch nicht kennen).
  final _localTips = <String>{};
  Set<String> get _tips => {...widget.game.tips, ..._localTips};

  /// Tipp aufdecken. true = er darf angezeigt werden.
  Future<bool> _revealTip(CrosswordWord word) async {
    try {
      final shared = await CrosswordService.instance.revealTip(
        widget.couple.coupleId,
        widget.game,
        word,
      );
      if (!shared && mounted) setState(() => _localTips.add(word.id));
      return true;
    } catch (e, s) {
      AppLogger.error(e, s, where: 'Kreuzwort: Tipp');
      _saveFailed();
      return false;
    }
  }

  CrosswordWord? get _word =>
      widget.game.words.where((w) => w.id == _selected).firstOrNull;

  void _tapCell(Point<int> p) {
    final words = widget.game.words.where((w) => w.cells.contains(p)).toList();
    if (words.isEmpty) return;
    HapticFeedback.selectionClick();
    // Zweimal auf ein Kreuzungsfeld tippen wechselt zwischen waagrecht und senkrecht.
    final current = words.indexWhere((w) => w.id == _selected);
    final next = words[(current + 1) % words.length];
    setState(() => _selected = next.id);
    _openInput(next);
  }

  Future<void> _openInput(CrosswordWord word) async {
    if (widget.game.solved.containsKey(word.id)) return;
    if (!_myTurn) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${widget.couple.partnerLabel} ist gerade dran.'),
            duration: const Duration(seconds: 2),
          ),
        );
      return;
    }
    await showFormSheet<void>(
      context,
      (_) => _GuessSheet(
        word: word,
        number: clueNumbers(widget.game.words)[Point(word.x, word.y)] ?? 0,
        known: _knownLetters(word),
        onGuess: (text) => _guess(word, text),
        onHint: () => _hint(word),
        hintsLeft: _level.maxHints - widget.game.hintsUsed,
        tip: crosswordTipFor(word.answer),
        tipOpen: _tips.contains(word.id),
        tipCost: _level.pointsPerLetter * 2,
        onTip: () => _revealTip(word),
      ),
    );
  }

  CrosswordLevel get _level => CrosswordLevel.fromName(widget.game.difficulty);

  /// Bereits sichtbare Buchstaben (aus Kreuzungen oder Hinweisen), sonst null.
  List<String?> _knownLetters(CrosswordWord word) {
    final filled = widget.game.filledBy;
    return [
      for (var i = 0; i < word.answer.length; i++)
        filled.containsKey(word.cells[i]) ? word.answer[i] : null,
    ];
  }

  /// true = der Zug wurde gespeichert (egal ob richtig oder falsch).
  Future<bool> _guess(CrosswordWord word, String text) async {
    final partner = widget.couple.partnerUid;
    if (partner == null) return false;
    try {
      final ok = await CrosswordService.instance.submitWord(
        widget.couple.coupleId,
        widget.game,
        word,
        text,
        partner,
      );
      if (!mounted) return true;
      if (ok) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.vibrate();
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Richtig! ✨ Jetzt ist ${widget.couple.partnerLabel} dran.'
                  : 'Leider nicht – jetzt versucht es ${widget.couple.partnerLabel}.',
            ),
          ),
        );
      return true;
    } catch (e, s) {
      AppLogger.error(e, s, where: 'Kreuzwort: Wort raten');
      _saveFailed();
      return false;
    }
  }

  void _saveFailed() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Dein Zug wurde nicht gespeichert. Bitte Verbindung prüfen und noch einmal versuchen.',
          ),
        ),
      );
  }

  Future<bool> _hint(CrosswordWord word) async {
    final partner = widget.couple.partnerUid;
    if (partner == null) return false;
    try {
      await CrosswordService.instance.hint(
        widget.couple.coupleId,
        widget.game,
        word,
        partner,
      );
      return true;
    } catch (e, s) {
      AppLogger.error(e, s, where: 'Kreuzwort: Hinweis');
      _saveFailed();
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final across = g.words.where((w) => w.across).toList();
    final down = g.words.where((w) => !w.across).toList();
    final numbers = clueNumbers(g.words);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TurnBar(game: g, couple: widget.couple),
        if (_myTurn) _MoveBanner(game: g, couple: widget.couple),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: g.progress,
            minHeight: 6,
            backgroundColor: Kitsune.inkSoft,
            color: Kitsune.lantern,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${CrosswordLevel.fromName(g.difficulty).label} · '
          '${g.solved.length} von ${g.words.length} Wörtern · '
          '${g.attempts} ${g.attempts == 1 ? 'Versuch' : 'Versuche'} · '
          '${g.hintsUsed} ${g.hintsUsed == 1 ? 'Hinweis' : 'Hinweise'}'
          '${_tips.isEmpty ? '' : ' · ${_tips.length} ${_tips.length == 1 ? 'Tipp' : 'Tipps'}'}',
          style: const TextStyle(fontSize: 12, color: Kitsune.mist),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final side = c.maxWidth;
            _gridSize = Size.square(side);
            return SizedBox.square(
              dimension: side,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _stamp,
                        builder: (context, _) => _Grid(
                          game: g,
                          couple: widget.couple,
                          numbers: numbers,
                          selected: _word,
                          fresh: _fresh,
                          stamp: _stamp.value,
                          tipStarts: {
                            for (final w in g.words)
                              if (_tips.contains(w.id)) Point(w.x, w.y),
                          },
                          onTap: _tapCell,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: EffectPainter(_fx)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        if (g.isDone) ...[
          Text(
            'Gelöst! Ihr seid ein Team 🎆',
            textAlign: TextAlign.center,
            style: AppTheme.serif(size: 20),
          ),
          const SizedBox(height: 10),
          _ResultCard(game: g, couple: widget.couple, level: _level),
          const SizedBox(height: 14),
          const SizedBox(height: 6),
          Text(
            'Neues Rätsel – wie knifflig?',
            textAlign: TextAlign.center,
            style: AppTheme.label(),
          ),
          const SizedBox(height: 12),
          _LevelPicker(
            onPick: (level) => _newPuzzle(context, widget.couple, level),
          ),
          const SizedBox(height: 18),
        ],
        if (across.isNotEmpty)
          _Card(
            child: _ClueList(
              title: 'WAAGRECHT →',
              words: across,
              numbers: numbers,
              game: g,
              tips: _tips,
              selected: _selected,
              onTap: (w) {
                setState(() => _selected = w.id);
                _openInput(w);
              },
            ),
          ),
        const SizedBox(height: 14),
        if (down.isNotEmpty)
          _Card(
            child: _ClueList(
              title: 'SENKRECHT ↓',
              words: down,
              numbers: numbers,
              game: g,
              tips: _tips,
              selected: _selected,
              onTap: (w) {
                setState(() => _selected = w.id);
                _openInput(w);
              },
            ),
          ),
      ],
    );
  }
}

class _TurnBar extends StatelessWidget {
  const _TurnBar({required this.game, required this.couple});

  final CrosswordGame game;
  final Couple couple;

  @override
  Widget build(BuildContext context) {
    final mine = !game.isDone && game.turn == couple.myUid;
    final text = game.isDone
        ? 'Geschafft – alle Wörter gefunden'
        : mine
        ? 'Du bist dran – tippe ein Wort an'
        : '${couple.partnerLabel} ist dran';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mine
            ? Kitsune.lantern.withValues(alpha: 0.18)
            : Kitsune.deep.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: mine
              ? Kitsune.lantern.withValues(alpha: 0.6)
              : const Color(0x4DF3EBD3),
        ),
      ),
      child: Row(
        children: [
          Hanko(game.isDone ? '済' : (mine ? '番' : '待'), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Das Papiergitter. Von dir gelöst = Indigo, vom Schatz = Pflaume, Hinweis = Rot.
class _Grid extends StatelessWidget {
  const _Grid({
    required this.game,
    required this.couple,
    required this.numbers,
    required this.selected,
    required this.fresh,
    required this.stamp,
    required this.tipStarts,
    required this.onTap,
  });

  final CrosswordGame game;
  final Couple couple;
  final Map<Point<int>, int> numbers;
  final CrosswordWord? selected;
  final Set<Point<int>> fresh;
  final double stamp;

  /// Anfangsfelder von Wörtern, deren Tipp aufgedeckt ist (kleines Lämpchen).
  final Set<Point<int>> tipStarts;
  final ValueChanged<Point<int>> onTap;

  @override
  Widget build(BuildContext context) {
    final solution = solutionGrid(game.words);
    final filled = game.filledBy;
    final sel = selected?.cells.toSet() ?? const <Point<int>>{};
    return LayoutBuilder(
      builder: (context, c) {
        final cell = c.maxWidth / game.size;
        // Schmale Rätsel waagrecht/senkrecht mittig setzen.
        final xs = solution.keys.map((p) => p.x),
            ys = solution.keys.map((p) => p.y);
        final dx = (game.size - (xs.reduce(max) + 1)) * cell / 2;
        final dy = (game.size - (ys.reduce(max) + 1)) * cell / 2;
        return Stack(
          children: [
            for (final e in solution.entries)
              Positioned(
                left: dx + e.key.x * cell,
                top: dy + e.key.y * cell,
                width: cell,
                height: cell,
                child: GestureDetector(
                  onTap: () => onTap(e.key),
                  child: _Cell(
                    letter: filled.containsKey(e.key) ? e.value : null,
                    by: filled[e.key],
                    myUid: couple.myUid,
                    number: numbers[e.key],
                    tip: tipStarts.contains(e.key),
                    selected: sel.contains(e.key),
                    scale: fresh.contains(e.key)
                        ? Curves.elasticOut.transform(stamp)
                        : 1,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.letter,
    required this.by,
    required this.myUid,
    required this.number,
    required this.selected,
    required this.scale,
    this.tip = false,
  });

  final String? letter;
  final String? by;
  final String myUid;
  final int? number;
  final bool selected;
  final double scale;
  final bool tip;

  @override
  Widget build(BuildContext context) {
    final color = by == null
        ? Kitsune.indigo
        : by == ''
        ? Kitsune.lantern
        : by == myUid
        ? Kitsune.indigo
        : Kitsune.plum;
    return Padding(
      padding: const EdgeInsets.all(1),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF4D6) : Kitsune.paper,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: selected ? Kitsune.lantern : const Color(0x33133174),
            width: selected ? 1.6 : 1,
          ),
          // Harte Schattenkante statt Unschärfe: sieht gleich aus, kostet fast nichts.
          boxShadow: const [
            BoxShadow(color: Color(0x55000000), offset: Offset(0, 1)),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, c) => Stack(
            children: [
              if (number != null)
                Positioned(
                  left: 2,
                  top: 1,
                  child: Text(
                    '$number',
                    style: TextStyle(
                      fontSize: c.maxWidth * 0.24,
                      color: Kitsune.inkSoft,
                      height: 1,
                    ),
                  ),
                ),
              if (tip)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    width: c.maxWidth * 0.17,
                    height: c.maxWidth * 0.17,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Kitsune.lantern,
                      boxShadow: [
                        BoxShadow(
                          color: Kitsune.lantern.withValues(alpha: 0.6),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              if (letter != null)
                Center(
                  child: Transform.scale(
                    scale: scale,
                    child: Text(
                      letter!,
                      style: AppTheme.serif(
                        size: c.maxWidth * 0.55,
                        color: color,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClueList extends StatelessWidget {
  const _ClueList({
    required this.title,
    required this.words,
    required this.numbers,
    required this.game,
    required this.tips,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final List<CrosswordWord> words;
  final Map<Point<int>, int> numbers;
  final CrosswordGame game;

  /// Wörter mit aufgedecktem Tipp.
  final Set<String> tips;
  final String? selected;
  final ValueChanged<CrosswordWord> onTap;

  @override
  Widget build(BuildContext context) {
    if (words.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: AppTheme.label()),
        const SizedBox(height: 6),
        for (final w in words)
          InkWell(
            onTap: () => onTap(w),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: w.id == selected
                    ? Kitsune.lantern.withValues(alpha: 0.12)
                    : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 26,
                    child: Text(
                      '${numbers[Point(w.x, w.y)]}',
                      style: AppTheme.serif(size: 14, color: Kitsune.aqua),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${w.clue} (${w.answer.length})',
                          style: TextStyle(
                            fontSize: 14,
                            decoration: game.solved.containsKey(w.id)
                                ? TextDecoration.lineThrough
                                : null,
                            color: game.solved.containsKey(w.id)
                                ? Kitsune.dim
                                : Kitsune.paper,
                          ),
                        ),
                        if (tips.contains(w.id) &&
                            !game.solved.containsKey(w.id) &&
                            crosswordTipFor(w.answer) != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              '💡 ${crosswordTipFor(w.answer)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                color: Kitsune.aqua,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (game.solved.containsKey(w.id))
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Hanko('済', size: 20),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Eingabe für ein Wort, mit bekannten Buchstaben als Vorlage.
class _GuessSheet extends StatefulWidget {
  const _GuessSheet({
    required this.word,
    required this.number,
    required this.known,
    required this.onGuess,
    required this.onHint,
    required this.hintsLeft,
    required this.tip,
    required this.tipOpen,
    required this.tipCost,
    required this.onTip,
  });

  final int hintsLeft;

  /// Zweiter, hilfreicherer Hinweis (null = gibt es für dieses Wort nicht).
  final String? tip;
  final bool tipOpen;
  final int tipCost;
  final Future<bool> Function() onTip;
  final CrosswordWord word;
  final int number;
  final List<String?> known;
  final Future<bool> Function(String) onGuess;
  final Future<bool> Function() onHint;

  @override
  State<_GuessSheet> createState() => _GuessSheetState();
}

class _GuessSheetState extends State<_GuessSheet>
    with SingleTickerProviderStateMixin {
  final _input = TextEditingController();
  late final _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = normalizeAnswer(_input.text);
    if (text.length != widget.word.answer.length) {
      HapticFeedback.selectionClick();
      _shake.forward(from: 0);
      return;
    }
    setState(() => _busy = true);
    final saved = await widget.onGuess(text);
    if (!mounted) return;
    // Nur schliessen, wenn der Zug gespeichert wurde – sonst bleibt die Eingabe offen.
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.word;
    final pattern = widget.known.map((c) => c ?? '_').join(' ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${widget.number} ${w.across ? 'waagrecht' : 'senkrecht'}',
          style: AppTheme.label(),
        ),
        const SizedBox(height: 6),
        Text(w.clue, style: AppTheme.serif(size: 19)),
        if (widget.tip != null) ...[
          const SizedBox(height: 12),
          _TipCard(
            tip: widget.tip!,
            open: widget.tipOpen,
            cost: widget.tipCost,
            onReveal: widget.onTip,
          ),
        ],
        const SizedBox(height: 10),
        Text(
          pattern,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            letterSpacing: 2,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) => Transform.translate(
            offset: Offset(
              sin(_shake.value * pi * 6) * 8 * (1 - _shake.value),
              0,
            ),
            child: child,
          ),
          child: TextField(
            controller: _input,
            autofocus: true,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            maxLength: w.answer.length + 4,
            decoration: InputDecoration(
              hintText: '${w.answer.length} Buchstaben',
              counterText: '',
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                // Gesperrt, wenn keine Hinweise mehr übrig oder alle Buchstaben schon da sind.
                onPressed:
                    _busy ||
                        widget.hintsLeft <= 0 ||
                        !widget.known.contains(null)
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        final saved = await widget.onHint();
                        if (!context.mounted) return;
                        if (saved) {
                          Navigator.pop(context);
                        } else {
                          setState(() => _busy = false);
                        }
                      },
                icon: const Icon(Icons.lightbulb_outline_rounded),
                label: Text(
                  widget.hintsLeft <= 0
                      ? 'Keine Hinweise mehr'
                      : 'Buchstabe (${widget.hintsLeft})',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: const Text('Wort prüfen'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Wort prüfen oder Buchstabe aufdecken beendet deinen Zug – ein Tipp nicht.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Kitsune.mist),
        ),
      ],
    );
  }
}

/// «Billie hat «KUSS» gelöst»: was der Schatz in seinem Zug gemacht hat –
/// steht da, sobald man selbst dran ist.
class _MoveBanner extends StatelessWidget {
  const _MoveBanner({required this.game, required this.couple});

  final CrosswordGame game;
  final Couple couple;

  @override
  Widget build(BuildContext context) {
    final move = game.lastMove;
    if (move == null || move.by == couple.myUid) return const SizedBox.shrink();
    final word = game.words.where((w) => w.id == move.wordId).firstOrNull;
    if (word == null) return const SizedBox.shrink();
    final nr = clueNumbers(game.words)[Point(word.x, word.y)] ?? 0;
    final where = '$nr ${word.across ? 'waagrecht' : 'senkrecht'}';
    final partner = couple.partnerLabel;
    final (icon, title, detail) = switch (move.type) {
      'solved' => (
        '✨',
        '$partner hat «${word.answer}» gelöst'
            '${game.tips.contains(word.id) ? ' (mit Tipp 💡)' : ''}',
        '$where · ${word.clue}',
      ),
      'hint' => (
        '💡',
        '$partner hat bei $where einen Buchstaben aufgedeckt',
        word.clue,
      ),
      _ => (
        '🤔',
        '$partner lag bei $where daneben',
        'Das Wort ist noch offen – vielleicht klappt es bei dir.',
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Kitsune.plum.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Kitsune.plum),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(fontSize: 12, color: Kitsune.mist),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Auswertung nach dem Lösen: Sterne, Punkte, wer wie viel gefunden hat.
class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.game,
    required this.couple,
    required this.level,
  });

  final CrosswordGame game;
  final Couple couple;
  final CrosswordLevel level;

  @override
  Widget build(BuildContext context) {
    final score = crosswordScore(
      words: game.words,
      solved: game.solved.length,
      attempts: game.attempts,
      hints: game.hintsUsed,
      tips: game.tips.length,
      pointsPerLetter: level.pointsPerLetter,
    );
    final mine = game.solved.values.where((u) => u == couple.myUid).length;
    final theirs = game.solved.length - mine;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Kitsune.deep.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x4DF3EBD3)),
      ),
      child: Column(
        children: [
          Text(
            '★' * score.stars + '☆' * (3 - score.stars),
            style: const TextStyle(
              fontSize: 34,
              letterSpacing: 4,
              color: Kitsune.lantern,
            ),
          ),
          const SizedBox(height: 4),
          Text('${score.points} Punkte', style: AppTheme.serif(size: 22)),
          Text(level.label, style: AppTheme.label()),
          const SizedBox(height: 10),
          Text(
            'Du $mine · ${couple.partnerLabel} $theirs Wörter\n'
            '${score.misses} ${score.misses == 1 ? 'Fehlversuch' : 'Fehlversuche'} · '
            '${game.hintsUsed} ${game.hintsUsed == 1 ? 'Hinweis' : 'Hinweise'} · '
            '${game.tips.length} ${game.tips.length == 1 ? 'Tipp' : 'Tipps'}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Kitsune.mist),
          ),
        ],
      ),
    );
  }
}

/// Versiegelter Tipp. Antippen dreht die Karte um und zeigt ihn – für euch
/// beide sichtbar, kostet Punkte, der Zug bleibt.
class _TipCard extends StatefulWidget {
  const _TipCard({
    required this.tip,
    required this.open,
    required this.cost,
    required this.onReveal,
  });

  final String tip;
  final bool open;
  final int cost;
  final Future<bool> Function() onReveal;

  @override
  State<_TipCard> createState() => _TipCardState();
}

class _TipCardState extends State<_TipCard> with TickerProviderStateMixin {
  late final _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
    value: widget.open ? 1 : 0,
  );
  // Lichtstreifen, der über das Siegel wandert.
  late final _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hier statt in initState: reduceMotion liest die Systemeinstellung.
    final animate = !widget.open && _flip.value == 0 && !reduceMotion(context);
    if (animate && !_shine.isAnimating) _shine.repeat();
    if (!animate && _shine.isAnimating) _shine.stop();
  }

  @override
  void dispose() {
    _flip.dispose();
    _shine.dispose();
    super.dispose();
  }

  Future<void> _reveal() async {
    if (_busy || _flip.value > 0) return;
    setState(() => _busy = true);
    HapticFeedback.selectionClick();
    final ok = await widget.onReveal();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    _shine.stop();
    HapticFeedback.mediumImpact();
    if (reduceMotion(context)) {
      _flip.value = 1;
    } else {
      await _flip.animateTo(1, curve: Curves.easeOutBack);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
    alignment: Alignment.topCenter,
    child: AnimatedBuilder(
      animation: Listenable.merge([_flip, _shine]),
      builder: (context, _) {
        final angle = _flip.value * pi;
        final back = angle > pi / 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateY(angle),
          child: back
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationY(pi),
                  child: _back(),
                )
              : _front(),
        );
      },
    ),
  );

  Widget _front() {
    final x = -1.8 + 3.6 * _shine.value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busy ? null : _reveal,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Kitsune.lantern.withValues(alpha: 0.7)),
            gradient: LinearGradient(
              begin: Alignment(x - 0.6, -1),
              end: Alignment(x + 0.6, 1),
              colors: [
                Kitsune.plum.withValues(alpha: 0.55),
                const Color(0xCCB4567F),
                Kitsune.plum.withValues(alpha: 0.55),
              ],
            ),
          ),
          child: Row(
            children: [
              const Hanko('秘', size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tipp aufdecken',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '−${widget.cost} Punkte · du bleibst am Zug',
                      style: const TextStyle(fontSize: 12, color: Kitsune.mist),
                    ),
                  ],
                ),
              ),
              if (_busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.touch_app_rounded, color: Kitsune.paper),
            ],
          ),
        ),
      ),
    );
  }

  Widget _back() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
    decoration: BoxDecoration(
      color: Kitsune.paper,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Kitsune.hairline),
      boxShadow: [
        BoxShadow(
          color: Kitsune.lantern.withValues(alpha: 0.35),
          blurRadius: 14,
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('💡', style: TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TIPP',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                  color: Kitsune.lantern,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.tip,
                style: AppTheme.serif(size: 16, color: Kitsune.night),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
