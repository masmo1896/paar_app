import 'dart:math' as math;
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../theme.dart';
import '../../../utils/battleship_logic.dart';
import '../../../widgets/motion.dart';
import '../effects.dart';

/// Wo liegt welches Feld? Rand links/oben für die Beschriftung, rechts gleich breit.
class BoardGeometry {
  // Gleicher Rand links und rechts, damit das Meer mittig steht.
  BoardGeometry(double side)
    : label = side * 0.07,
      cell = (side - 2 * side * 0.07) / boardSize;

  final double label;
  final double cell;

  Offset origin(int x, int y) => Offset(label + x * cell, label + y * cell);
  Offset center(int x, int y) => origin(x, y) + Offset(cell / 2, cell / 2);

  /// Feld unter einem Punkt, oder null ausserhalb.
  Point<int>? cellAt(Offset p) {
    final x = ((p.dx - label) / cell).floor();
    final y = ((p.dy - label) / cell).floor();
    if (x < 0 || y < 0 || x >= boardSize || y >= boardSize) return null;
    return Point(x, y);
  }
}

/// Ein Spielfeld: animiertes Nachtmeer, Gitter, Schiffe, Treffer und Effekte.
class BattleBoard extends StatefulWidget {
  const BattleBoard({
    super.key,
    required this.effects,
    this.ships = const [],
    this.shots = const [],
    this.sunkIds = const {},
    this.invalidIds = const {},
    this.liftedId,
    this.onTapCell,
    this.aim,
  });

  final EffectLayer effects;

  /// Sichtbare Schiffe (eigene, oder am Ende die aufgedeckten).
  final List<Ship> ships;

  /// Schüsse auf dieses Feld.
  final List<Shot> shots;
  final Set<String> sunkIds;

  /// Beim Aufstellen: rot markierte Schiffe.
  final Set<String> invalidIds;

  /// Beim Aufstellen: das gerade gezogene Schiff (leicht angehoben).
  final String? liftedId;

  final void Function(int x, int y)? onTapCell;

  /// Zielkreuz auf diesem Feld (ausgewählt, noch nicht geschossen).
  final Point<int>? aim;

  @override
  State<BattleBoard> createState() => _BattleBoardState();
}

class _BattleBoardState extends State<BattleBoard>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);
  Duration _last = Duration.zero;
  bool _calm = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _calm = reduceMotion(context);
    if (!_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    widget.effects.tick(dt);
    if (!_calm) _time.value = elapsed.inMicroseconds / 1e6;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final side = math.min(c.maxWidth, c.maxHeight);
        final geo = BoardGeometry(side);
        return SizedBox.square(
          dimension: side,
          child: ListenableBuilder(
            listenable: widget.effects,
            builder: (context, child) => Transform.translate(
              offset: widget.effects.shakeOffset,
              child: child,
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: widget.onTapCell == null
                  ? null
                  : (d) {
                      final cell = geo.cellAt(d.localPosition);
                      if (cell != null) widget.onTapCell!(cell.x, cell.y);
                    },
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _SeaPainter(_time, geo),
                  foregroundPainter: _BoardPainter(
                    time: _time,
                    geo: geo,
                    ships: widget.ships,
                    shots: widget.shots,
                    sunkIds: widget.sunkIds,
                    invalidIds: widget.invalidIds,
                    liftedId: widget.liftedId,
                    aim: widget.aim,
                  ),
                  child: CustomPaint(
                    size: Size.square(side),
                    foregroundPainter: EffectPainter(widget.effects),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

const _kana = ['あ', 'い', 'う', 'え', 'お', 'か', 'き', 'く', 'け', 'こ'];

/// Hintergrund: Nachtmeer, Mondspiegelung, Wellen, treibende Laternen, Koi.
class _SeaPainter extends CustomPainter {
  _SeaPainter(this.time, this.geo) : super(repaint: time);

  final ValueNotifier<double> time;
  final BoardGeometry geo;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final sea = Rect.fromLTWH(
      geo.label,
      geo.label,
      geo.cell * boardSize,
      geo.cell * boardSize,
    );
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(sea, const Radius.circular(8)));

    // Tiefes Wasser mit Verlauf
    canvas.drawRect(
      sea,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF173A86), Kitsune.indigo, Kitsune.deeper],
          stops: [0, 0.45, 1],
        ).createShader(sea),
    );

    // Mondspiegelung: flimmernde helle Striche
    final moonX = sea.left + sea.width * 0.72;
    for (var i = 0; i < 16; i++) {
      final y = sea.top + sea.height * (0.06 + i * 0.055);
      final wobble = math.sin(t * 1.6 + i * 1.3) * geo.cell * 0.25;
      final w = geo.cell * (1.6 - i * 0.07) * (0.7 + 0.3 * math.sin(t * 2 + i));
      canvas.drawLine(
        Offset(moonX - w / 2 + wobble, y),
        Offset(moonX + w / 2 + wobble, y),
        Paint()
          ..color = Kitsune.paper.withValues(alpha: 0.16 - i * 0.008)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Koi-Schatten zieht langsam einen Kreis
    final koiT = t * 0.12;
    final koi = Offset(
      sea.center.dx + math.cos(koiT) * sea.width * 0.32,
      sea.center.dy + math.sin(koiT * 1.3) * sea.height * 0.3,
    );
    canvas.save();
    canvas.translate(koi.dx, koi.dy);
    canvas.rotate(
      math.atan2(math.cos(koiT * 1.3) * 1.3 * 0.3, -math.sin(koiT) * 0.32),
    );
    final koiPaint = Paint()
      ..color = const Color(0x33E73162)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final k = geo.cell;
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: k * 1.4, height: k * 0.5),
      koiPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(-k * 0.6, 0)
        ..lineTo(-k * 1.0 + math.sin(t * 6) * k * 0.08, -k * 0.3)
        ..lineTo(-k * 1.0 - math.sin(t * 6) * k * 0.08, k * 0.3)
        ..close(),
      koiPaint,
    );
    canvas.restore();

    // Wellenlinien in mehreren Lagen
    for (var row = 0; row < 14; row++) {
      final baseY = sea.top + sea.height * (row + 0.5) / 14;
      final path = Path();
      for (var x = 0.0; x <= sea.width; x += 6) {
        final y =
            baseY +
            math.sin(x / sea.width * math.pi * 4 + t * 1.2 + row * 0.9) *
                geo.cell *
                0.08;
        if (x == 0) {
          path.moveTo(sea.left + x, y);
        } else {
          path.lineTo(sea.left + x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Kitsune.aqua.withValues(alpha: 0.06 + (row % 3) * 0.02),
      );
    }

    // Laternen treiben langsam über das Wasser
    for (var i = 0; i < 5; i++) {
      final speed = 0.015 + i * 0.004;
      final px = ((i * 0.23 + t * speed) % 1.2) - 0.1;
      final py = 0.15 + ((i * 0.37) % 0.75);
      final p = Offset(
        sea.left + sea.width * px,
        sea.top + sea.height * py + math.sin(t + i) * 3,
      );
      canvas.drawCircle(
        p,
        geo.cell * 0.45,
        Paint()
          ..color = Kitsune.lantern.withValues(alpha: 0.18)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, geo.cell * 0.35),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: p,
            width: geo.cell * 0.18,
            height: geo.cell * 0.24,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xCCFF8A8A),
      );
    }
    canvas.restore();

    // Beschriftung: Kana oben, Zahlen links
    for (var i = 0; i < boardSize; i++) {
      _label(
        canvas,
        _kana[i],
        Offset(geo.label + (i + 0.5) * geo.cell, geo.label / 2),
      );
      _label(
        canvas,
        '${i + 1}',
        Offset(geo.label / 2, geo.label + (i + 0.5) * geo.cell),
      );
    }
  }

  void _label(Canvas canvas, String text, Offset center) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Kitsune.mist.withValues(alpha: 0.75),
          fontSize: geo.label * 0.55,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_SeaPainter old) => old.geo.cell != geo.cell;
}

/// Gitter, Schiffe und Markierungen der Schüsse.
class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.time,
    required this.geo,
    required this.ships,
    required this.shots,
    required this.sunkIds,
    required this.invalidIds,
    required this.liftedId,
    required this.aim,
  }) : super(repaint: time);

  final ValueNotifier<double> time;
  final BoardGeometry geo;
  final List<Ship> ships;
  final List<Shot> shots;
  final Set<String> sunkIds;
  final Set<String> invalidIds;
  final String? liftedId;
  final Point<int>? aim;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final grid = Paint()
      ..color = Kitsune.paper.withValues(alpha: 0.13)
      ..strokeWidth = 1;
    for (var i = 0; i <= boardSize; i++) {
      final d = geo.label + i * geo.cell;
      final end = geo.label + boardSize * geo.cell;
      canvas.drawLine(Offset(d, geo.label), Offset(d, end), grid);
      canvas.drawLine(Offset(geo.label, d), Offset(end, d), grid);
    }

    // Versenkte Schiffe des Gegners kennen wir aus den Schüssen (shipCells).
    for (final s in shots) {
      if (s.result == ShotResult.sunk && s.shipCells.isNotEmpty) {
        final xs = s.shipCells.map((c) => c.x),
            ys = s.shipCells.map((c) => c.y);
        final vertical = xs.toSet().length == 1 && s.shipCells.length > 1;
        _ship(
          canvas,
          Ship(
            id: 'sunk${s.id}',
            len: s.shipCells.length,
            x: xs.reduce(math.min),
            y: ys.reduce(math.min),
            vertical: vertical,
          ),
          t,
          sunk: true,
        );
      }
    }
    for (final s in ships) {
      if (s.id == liftedId) continue;
      _ship(canvas, s, t, sunk: sunkIds.contains(s.id));
    }
    // Das gezogene Schiff zuletzt, damit es über allen anderen liegt.
    for (final s in ships.where((s) => s.id == liftedId)) {
      _ship(canvas, s, t, lifted: true);
    }

    final sunkCells = {
      for (final s in shots)
        if (s.result == ShotResult.sunk) ...s.shipCells,
    };
    for (final s in shots) {
      final c = geo.center(s.x, s.y);
      switch (s.result) {
        case ShotResult.pending:
          _target(canvas, c, t, Kitsune.paper);
        case ShotResult.miss:
          _ripple(canvas, c, t + s.x * 0.7 + s.y * 0.3);
        case ShotResult.hit:
        case ShotResult.sunk:
          final ownSunk = ships.any(
            (sh) =>
                sunkIds.contains(sh.id) && sh.cells.contains(Point(s.x, s.y)),
          );
          final blue = ownSunk || sunkCells.contains(Point(s.x, s.y));
          _flame(canvas, c, t + s.x * 1.7 + s.y * 0.9, blue: blue);
      }
    }
    if (aim != null) {
      _target(canvas, geo.center(aim!.x, aim!.y), t, Kitsune.lantern);
    }
  }

  /// Papierboot über [s.len] Felder; senkrechte Schiffe werden gedreht.
  void _ship(
    Canvas canvas,
    Ship s,
    double t, {
    bool sunk = false,
    bool lifted = false,
  }) {
    final cell = geo.cell;
    final length = s.len * cell;
    final o = geo.origin(s.x, s.y);
    final bob = sunk
        ? 0.0
        : math.sin(t * 1.8 + s.id.hashCode % 7) * cell * 0.04;
    canvas.save();
    if (s.vertical) {
      canvas.translate(o.dx + cell, o.dy);
      canvas.rotate(math.pi / 2);
    } else {
      canvas.translate(o.dx, o.dy);
    }
    canvas.translate(0, bob - (lifted ? cell * 0.12 : 0));
    // Rumpf mittig ins Feld (die Segel ragen nach oben)
    canvas.translate(0, -cell * 0.08);
    if (sunk) {
      canvas.translate(length / 2, cell / 2);
      canvas.rotate(0.06);
      canvas.translate(-length / 2, -cell / 2);
    }

    final h = cell;
    final paper = sunk ? const Color(0xFF59607A) : Kitsune.paper;
    final fold = sunk ? const Color(0xFF474D63) : const Color(0xFFDCCFAB);

    // Schatten im Wasser
    canvas.drawOval(
      Rect.fromLTWH(length * 0.06, h * 0.7, length * 0.88, h * 0.3),
      Paint()
        ..color = Colors.black.withValues(alpha: lifted ? 0.45 : 0.3)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          h * (lifted ? 0.2 : 0.1),
        ),
    );

    // Rumpf: gefaltetes Papier, Bug rechts etwas spitzer
    final hull = Path()
      ..moveTo(length * 0.03, h * 0.36)
      ..lineTo(length * 0.97, h * 0.36)
      ..lineTo(length * 0.86, h * 0.9)
      ..lineTo(length * 0.12, h * 0.9)
      ..close();
    canvas.drawPath(hull, Paint()..color = paper);
    canvas.drawPath(
      Path()
        ..moveTo(length * 0.03, h * 0.36)
        ..lineTo(length * 0.18, h * 0.36)
        ..lineTo(length * 0.12, h * 0.9)
        ..close()
        ..moveTo(length * 0.97, h * 0.36)
        ..lineTo(length * 0.9, h * 0.36)
        ..lineTo(length * 0.86, h * 0.9)
        ..close(),
      Paint()..color = fold,
    );
    canvas.drawLine(
      Offset(length * 0.14, h * 0.63),
      Offset(length * 0.86, h * 0.63),
      Paint()
        ..color = fold
        ..strokeWidth = 1,
    );

    // Segel: eines je Feld in der Mitte, abwechselnd rot / creme / pflaume
    final sails = math.max(1, s.len - 2);
    const colors = [Kitsune.lantern, Color(0xFFEDE3C6), Kitsune.plum];
    for (var i = 0; i < sails; i++) {
      final mx = length * (i + 1) / (sails + 1);
      final sw = cell * 0.36;
      final sail = Path()
        ..moveTo(mx, h * 0.36)
        ..lineTo(mx, h * 0.06)
        ..quadraticBezierTo(mx + sw * 0.9, h * 0.22, mx + sw, h * 0.36)
        ..close();
      final color = sunk
          ? const Color(0xFF3A3F55)
          : colors[(i + s.len) % colors.length];
      canvas.drawPath(sail, Paint()..color = color);
      canvas.drawLine(
        Offset(mx, h * 0.38),
        Offset(mx, h * 0.04),
        Paint()
          ..color = const Color(0xFF6B5A44)
          ..strokeWidth = 1.2,
      );
    }

    // Flaggschiff: Fuchs-Wappen und Laterne am Heck
    if (s.len == 5 && !sunk) {
      final c = Offset(length * 0.5 + cell * 0.18, h * 0.3);
      final r = cell * 0.08;
      final crest = Paint()..color = Kitsune.paper;
      canvas.drawCircle(c, r, crest);
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - r, c.dy - r * 0.2)
          ..lineTo(c.dx - r * 0.7, c.dy - r * 1.8)
          ..lineTo(c.dx - r * 0.1, c.dy - r * 0.8)
          ..moveTo(c.dx + r, c.dy - r * 0.2)
          ..lineTo(c.dx + r * 0.7, c.dy - r * 1.8)
          ..lineTo(c.dx + r * 0.1, c.dy - r * 0.8),
        crest,
      );
      final lamp = Offset(length * 0.08, h * 0.32 + math.sin(t * 3) * 1.5);
      canvas.drawCircle(
        lamp,
        cell * 0.22,
        Paint()
          ..color = Kitsune.lantern.withValues(
            alpha: 0.35 + 0.1 * math.sin(t * 5),
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.15),
      );
      canvas.drawCircle(
        lamp,
        cell * 0.07,
        Paint()..color = const Color(0xFFFFB0A8),
      );
    }

    if (invalidIds.contains(s.id)) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1, 1, length - 2, h - 2),
          Radius.circular(cell * 0.2),
        ),
        Paint()
          ..color = Kitsune.lantern.withValues(alpha: 0.35)
          ..style = PaintingStyle.fill,
      );
    }
    canvas.restore();
  }

  void _ripple(Canvas canvas, Offset c, double t) {
    final r = geo.cell;
    for (var i = 0; i < 2; i++) {
      final p = (t * 0.5 + i * 0.5) % 1;
      canvas.drawCircle(
        c,
        r * (0.12 + p * 0.3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Kitsune.aqua.withValues(alpha: 0.55 * (1 - p)),
      );
    }
    canvas.drawCircle(
      c,
      r * 0.08,
      Paint()..color = Kitsune.aqua.withValues(alpha: 0.8),
    );
  }

  /// Flackernde Flamme: rot (Treffer) oder blaues Fuchsfeuer (versenkt).
  void _flame(Canvas canvas, Offset c, double t, {required bool blue}) {
    final r = geo.cell;
    final outer = blue ? const Color(0xFF5B8CFF) : const Color(0xFFFF6A3C);
    final inner = blue ? const Color(0xFFB8F4FF) : const Color(0xFFFFE08A);
    canvas.drawCircle(
      c,
      r * 0.42,
      Paint()
        ..color = outer.withValues(alpha: 0.35 + 0.1 * math.sin(t * 7))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.25),
    );
    for (var i = 0; i < 3; i++) {
      final flick = math.sin(t * (8 + i * 3) + i) * r * 0.05;
      final height = r * (0.42 - i * 0.1) + flick;
      final width = r * (0.26 - i * 0.06);
      final base = c + Offset(0, r * 0.2);
      final flame = Path()
        ..moveTo(base.dx - width, base.dy)
        ..quadraticBezierTo(
          base.dx - width,
          base.dy - height * 0.6,
          base.dx + flick,
          base.dy - height,
        )
        ..quadraticBezierTo(
          base.dx + width,
          base.dy - height * 0.6,
          base.dx + width,
          base.dy,
        )
        ..close();
      canvas.drawPath(
        flame,
        Paint()
          ..color = Color.lerp(outer, inner, i / 2)!.withValues(alpha: 0.95),
      );
    }
  }

  void _target(Canvas canvas, Offset c, double t, Color color) {
    final r = geo.cell * (0.38 + 0.04 * math.sin(t * 6));
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = color.withValues(alpha: 0.9);
    canvas.drawCircle(c, r, p);
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2 + t;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * r * 0.55,
        c + Offset(math.cos(a), math.sin(a)) * r * 1.2,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.ships != ships ||
      old.shots != shots ||
      old.sunkIds != sunkIds ||
      old.invalidIds != invalidIds ||
      old.liftedId != liftedId ||
      old.aim != aim;
}
