import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../screens/games/battleship/battleship_screen.dart';
import '../screens/games/crossword/crossword_screen.dart';
import '../services/battleship_service.dart';
import '../services/crossword_service.dart';
import '../services/games_service.dart';
import '../theme.dart';
import 'motion.dart';
import 'who.dart';

/// Zwei quadratische Spiele-Knöpfe auf Home. Roter Punkt = du bist am Zug.
class GameTiles extends StatelessWidget {
  const GameTiles({super.key, required this.couple});

  final Couple couple;

  @override
  Widget build(BuildContext context) {
    final games = GamesService.instance;
    final id = couple.coupleId;
    final ready = couple.partnerUid != null;
    return Row(
      children: [
        Expanded(
          child: _GameTile(
            title: 'Schiffe versenken',
            kana: '海戦',
            art: _TileArt.sea,
            enabled: ready,
            myTurn: games.battleshipMyTurn(id),
            status: BattleshipService.instance
                .current(id)
                .map((g) => _battleStatus(g)),
            onOpen: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BattleshipScreen(couple: couple),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _GameTile(
            title: 'Kreuzworträtsel',
            kana: '言葉',
            art: _TileArt.words,
            enabled: ready,
            myTurn: games.crosswordMyTurn(id),
            status: CrosswordService.instance
                .current(id)
                .map((g) => _crosswordStatus(g)),
            onOpen: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CrosswordScreen(couple: couple),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _battleStatus(BattleGame? g) {
    if (g == null || g.isDone) return 'Neues Spiel';
    if (g.isSetup) return 'Flotte aufstellen';
    return _turnText(g.turn);
  }

  String _crosswordStatus(CrosswordGame? g) {
    if (g == null || g.isDone) return 'Neues Rätsel';
    return _turnText(g.turn);
  }

  String _turnText(String? turn) =>
      turn == couple.myUid ? 'Du bist dran' : '${couple.partnerLabel} ist dran';
}

enum _TileArt { sea, words }

class _GameTile extends StatelessWidget {
  const _GameTile({
    required this.title,
    required this.kana,
    required this.art,
    required this.enabled,
    required this.myTurn,
    required this.status,
    required this.onOpen,
  });

  final String title;
  final String kana;
  final _TileArt art;
  final bool enabled;
  final Stream<bool> myTurn;
  final Stream<String> status;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: StreamBuilder<bool>(
        stream: enabled ? myTurn : const Stream.empty(),
        builder: (context, turnSnap) {
          final mine = turnSnap.data ?? false;
          return Opacity(
            opacity: enabled ? 1 : 0.5,
            child: PressScale(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Material(
                      color: Kitsune.deep.withValues(alpha: 0.85),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                        side: BorderSide(
                          color: mine
                              ? Kitsune.lantern.withValues(alpha: 0.8)
                              : const Color(0x4DF3EBD3),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: enabled ? onOpen : null,
                        child: Stack(
                          children: [
                            Positioned.fill(child: _AnimatedArt(art: art)),
                            // Dunkler Verlauf unten, damit die Schrift lesbar bleibt.
                            const Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    stops: [0.35, 1],
                                    colors: [
                                      Colors.transparent,
                                      Color(0xE6071230),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 10,
                              left: 12,
                              child: Text(
                                kana,
                                style: AppTheme.label(size: 11),
                              ),
                            ),
                            Positioned(
                              left: 12,
                              right: 12,
                              bottom: 12,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 2,
                                    style: AppTheme.serif(
                                      size: 16,
                                      height: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  StreamBuilder<String>(
                                    stream: enabled ? status : null,
                                    builder: (context, s) => Text(
                                      enabled
                                          ? (s.data ?? ' ')
                                          : 'Erst verbinden',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: mine
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                        color: mine
                                            ? Kitsune.paper
                                            : Kitsune.mist,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (mine)
                    const Positioned(top: -5, right: -5, child: TurnBadge()),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Pulsierender roter Punkt: «Du bist am Zug».
class TurnBadge extends StatefulWidget {
  const TurnBadge({super.key});

  @override
  State<TurnBadge> createState() => _TurnBadgeState();
}

class _TurnBadgeState extends State<TurnBadge>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Du bist am Zug',
    child: AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = _pulse.value;
        return SizedBox(
          width: 22,
          height: 22,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Leuchtring, der nach aussen verblasst.
              Container(
                width: 12 + 10 * t,
                height: 12 + 10 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Kitsune.lantern.withValues(alpha: 0.45 * (1 - t)),
                ),
              ),
              Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Kitsune.lantern,
                  border: Border.all(color: Kitsune.deeper, width: 2),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Kleine, langsam bewegte Illustration im Knopf.
class _AnimatedArt extends StatefulWidget {
  const _AnimatedArt({required this.art});

  final _TileArt art;

  @override
  State<_AnimatedArt> createState() => _AnimatedArtState();
}

class _AnimatedArtState extends State<_AnimatedArt>
    with SingleTickerProviderStateMixin {
  late final _t = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _t.stop();
    } else if (!_t.isAnimating) {
      _t.repeat();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: widget.art == _TileArt.sea
        ? _SeaTilePainter(_t)
        : _WordsTilePainter(_t),
  );
}

class _SeaTilePainter extends CustomPainter {
  _SeaTilePainter(this.t) : super(repaint: t);

  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = t.value * 2 * math.pi;
    final w = size.width, h = size.height;
    // Mond
    canvas.drawCircle(
      Offset(w * 0.76, h * 0.22),
      w * 0.09,
      Paint()..color = Kitsune.paper.withValues(alpha: 0.9),
    );
    canvas.drawCircle(
      Offset(w * 0.76, h * 0.22),
      w * 0.16,
      Paint()
        ..color = Kitsune.aqua.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    // Wellen in drei Lagen
    for (var layer = 0; layer < 3; layer++) {
      final baseY = h * (0.5 + layer * 0.1);
      final path = Path()..moveTo(0, baseY);
      for (var x = 0.0; x <= w; x += 4) {
        path.lineTo(
          x,
          baseY + math.sin(x / w * 2 * math.pi * 1.5 + phase + layer) * 3,
        );
      }
      path
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.lerp(
            Kitsune.indigo,
            Kitsune.deeper,
            layer / 2,
          )!.withValues(alpha: 0.9),
      );
    }
    // Papierboot schaukelt
    final bob = math.sin(phase * 2) * 2.5;
    canvas.save();
    canvas.translate(w * 0.36, h * 0.5 + bob);
    canvas.rotate(math.sin(phase * 2 + 1) * 0.05);
    paintPaperBoat(canvas, w * 0.34);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SeaTilePainter old) => false;
}

/// Gefaltetes Papierboot mit Fuchs-Wappen; Mittelpunkt unten am Rumpf.
void paintPaperBoat(Canvas canvas, double width) {
  final hw = width / 2, hull = width * 0.22;
  final hullPath = Path()
    ..moveTo(-hw, -hull * 0.4)
    ..lineTo(hw, -hull * 0.4)
    ..lineTo(hw * 0.7, hull * 0.5)
    ..lineTo(-hw * 0.7, hull * 0.5)
    ..close();
  canvas.drawPath(hullPath, Paint()..color = Kitsune.paper);
  canvas.drawLine(
    Offset(-hw * 0.7, hull * 0.05),
    Offset(hw * 0.7, hull * 0.05),
    Paint()
      ..color = Kitsune.mist
      ..strokeWidth = 1,
  );
  final sail = Path()
    ..moveTo(0, -hull * 0.4)
    ..lineTo(0, -width * 0.62)
    ..lineTo(hw * 0.7, -hull * 0.4)
    ..close();
  canvas.drawPath(sail, Paint()..color = Kitsune.lantern);
  final sail2 = Path()
    ..moveTo(-2, -hull * 0.4)
    ..lineTo(-2, -width * 0.48)
    ..lineTo(-hw * 0.55, -hull * 0.4)
    ..close();
  canvas.drawPath(sail2, Paint()..color = const Color(0xFFE9DFC2));
  // Fuchs-Wappen: Kreis mit zwei Ohren
  final c = Offset(hw * 0.22, -width * 0.3);
  final r = width * 0.055;
  final crest = Paint()..color = Kitsune.paper;
  canvas.drawCircle(c, r, crest);
  canvas.drawPath(
    Path()
      ..moveTo(c.dx - r, c.dy - r * 0.2)
      ..lineTo(c.dx - r * 0.7, c.dy - r * 1.7)
      ..lineTo(c.dx - r * 0.1, c.dy - r * 0.8)
      ..moveTo(c.dx + r, c.dy - r * 0.2)
      ..lineTo(c.dx + r * 0.7, c.dy - r * 1.7)
      ..lineTo(c.dx + r * 0.1, c.dy - r * 0.8),
    crest,
  );
}

class _WordsTilePainter extends CustomPainter {
  _WordsTilePainter(this.t) : super(repaint: t);

  final Animation<double> t;

  static const _letters = ['ア', 'イ', 'L', 'I', 'E', 'B', 'E', '愛', '?'];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    // 5 Felder breit, 4 hoch, mittig im oberen Teil (unten steht der Titel).
    final cell = w * 0.13;
    final origin = Offset((w - 5 * cell) / 2, w * 0.12);
    // Ein kleines Kreuz aus Papierfeldern
    const pattern = [
      (0, 1), (1, 1), (2, 1), (3, 1), (4, 1), //
      (2, 0), (2, 2), (2, 3),
    ];
    final active = (t.value * pattern.length).floor() % pattern.length;
    for (var i = 0; i < pattern.length; i++) {
      final (x, y) = pattern[i];
      final r = Rect.fromLTWH(
        origin.dx + x * cell,
        origin.dy + y * cell,
        cell - 2,
        cell - 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(2)),
        Paint()
          ..color = i == active
              ? Kitsune.paper
              : Kitsune.paper.withValues(alpha: 0.82),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: _letters[i % _letters.length],
          style: AppTheme.serif(
            size: cell * 0.55,
            color: i == active ? Kitsune.lantern : Kitsune.indigo,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_WordsTilePainter old) => false;
}
