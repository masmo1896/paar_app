import 'package:flutter/material.dart';

import '../theme.dart';

/// Sprechblase mit zwei Fuchsohren oben – wie ein echter Rotfuchs: geschwungene
/// Ohren, leicht nach aussen gekippt, mit dunklen Spitzen und hellem Fell innen.
/// Eigene Blasen bekommen unten zusätzlich eine buschige Schwanzspitze.
class FoxBubble extends StatelessWidget {
  const FoxBubble({
    super.key,
    required this.color,
    required this.isMine,
    required this.child,
  });

  final Color color;
  final bool isMine;
  final Widget child;

  /// Platz über der Blase für die Ohren.
  static const earSpace = 20.0;

  /// Platz unter eigenen Blasen für die Schwanzspitze.
  static const tailSpace = 13.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: earSpace,
        bottom: isMine ? tailSpace : 0,
        right: isMine ? 12 : 0,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Kitsune.deep, width: 1.5),
            ),
            child: child,
          ),
          // Ohren sitzen auf der Seite der sprechenden Person.
          Positioned(
            top: -earSpace + 1,
            left: isMine ? null : 10,
            right: isMine ? 10 : null,
            child: CustomPaint(
              size: const Size(62, earSpace + 1),
              painter: _EarsPainter(color),
            ),
          ),
          if (isMine)
            Positioned(
              right: -16,
              bottom: -tailSpace - 3,
              child: CustomPaint(
                size: const Size(38, 26),
                painter: _TailPainter(color),
              ),
            ),
        ],
      ),
    );
  }
}

const _tipColor = Color(0xFF2B1B24); // dunkle Ohren- und Fellspitzen
const _furWhite = Color(0xFFFFFCF4);
final _outline = Paint()
  ..color = Kitsune.deep
  ..style = PaintingStyle.stroke
  ..strokeWidth = 1.5
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.round;

class _EarsPainter extends CustomPainter {
  _EarsPainter(this.color);

  final Color color;

  static const _w = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    // Linkes Ohr nach links gekippt, rechtes nach rechts – wie ein aufmerksamer Fuchs.
    _ear(canvas, const Offset(2, 0), h, -0.26, mirror: false);
    _ear(canvas, Offset(size.width - _w - 2, 0), h, 0.26, mirror: true);
  }

  // Aussenform: breite Basis, Vorderkante fast gerade, Hinterkante bauchig,
  // die Spitze leicht nach vorn gebogen.
  Path _outer(double h, {double base = 2}) => Path()
    ..moveTo(0, h + base)
    ..cubicTo(0.6, h * 0.6, 4.5, h * 0.2, 10, 0)
    ..cubicTo(15.5, h * 0.18, 21.5, h * 0.58, _w, h + base);

  void _ear(
    Canvas canvas,
    Offset at,
    double h,
    double tilt, {
    required bool mirror,
  }) {
    const w = _w;
    canvas.save();
    // Um die Mitte der Ohrbasis drehen.
    canvas.translate(at.dx + w / 2, at.dy + h);
    canvas.rotate(tilt);
    if (mirror) canvas.scale(-1, 1);
    canvas.translate(-w / 2, -h);

    final outer = _outer(h)..close();
    canvas.drawPath(outer, Paint()..color = color);

    canvas.save();
    canvas.clipPath(outer);
    // Dunkle Ohrspitze mit fransigem Fellrand (wie beim Rotfuchs).
    final tip = Path()..moveTo(-1, -1);
    tip.lineTo(-1, h * 0.46);
    const steps = 7;
    for (var i = 0; i <= steps; i++) {
      final x = w * i / steps;
      final y = h * (0.40 + (i.isEven ? 0.06 : -0.02)) - (i / steps) * h * 0.04;
      tip.lineTo(x, y);
    }
    tip
      ..lineTo(w + 1, -1)
      ..close();
    canvas.drawPath(tip, Paint()..color = _tipColor);

    // Innenohr: weisses Fell, aussen fransig, mit leichtem Schatten zur Mitte.
    final inner = Path()..moveTo(4.5, h + 2);
    final pts = [
      Offset(5.2, h * 0.86),
      Offset(4.4, h * 0.74),
      Offset(6.6, h * 0.66),
      Offset(6.0, h * 0.54),
      Offset(8.4, h * 0.50),
      Offset(10, h * 0.40),
      Offset(11.8, h * 0.50),
      Offset(14.2, h * 0.52),
      Offset(14, h * 0.64),
      Offset(16.6, h * 0.70),
      Offset(16, h * 0.82),
      Offset(18.6, h + 2),
    ];
    for (final p in pts) {
      inner.lineTo(p.dx, p.dy);
    }
    inner.close();
    canvas.drawPath(inner, Paint()..color = _furWhite);
    // Tiefe im Ohr: ein schmaler, warmer Schatten in der Mitte.
    final depth = Path()
      ..moveTo(9, h + 2)
      ..quadraticBezierTo(9.6, h * 0.72, 10.6, h * 0.58)
      ..quadraticBezierTo(11.6, h * 0.74, 13, h + 2)
      ..close();
    canvas.drawPath(depth, Paint()..color = const Color(0x33712557));
    // Feine Fellstriche.
    final fur = Paint()
      ..color = Kitsune.deep.withValues(alpha: 0.25)
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(7.4, h + 1), Offset(8.4, h * 0.66), fur);
    canvas.drawLine(Offset(15.4, h + 1), Offset(13.2, h * 0.68), fur);
    canvas.restore();

    // Umriss nur aussen herum – unten geht das Ohr nahtlos in die Blase über.
    canvas.drawPath(_outer(h, base: 0.5), _outline);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EarsPainter old) => old.color != color;
}

/// Buschige Schwanzspitze mit weissem Ende, die unten rechts hervorschaut.
class _TailPainter extends CustomPainter {
  _TailPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Buschiger Schwanz mit gezackter Fellkante, der sich nach oben einrollt.
    final tail = Path()
      ..moveTo(0, 2)
      ..cubicTo(2, 18, 18, 28, 32, 18)
      ..lineTo(34, 15)
      ..lineTo(36, 13.5)
      ..lineTo(35.5, 10.5)
      ..lineTo(37, 8)
      ..cubicTo(36, 3, 32, 0, 29, 0)
      ..lineTo(29.5, 3)
      ..lineTo(27, 5)
      ..cubicTo(24, 11, 14, 12, 7, 6)
      ..lineTo(4, 3)
      ..close();
    canvas.drawPath(tail, Paint()..color = color);
    canvas.save();
    canvas.clipPath(tail);
    // Weisse Schwanzspitze mit fransigem Übergang.
    final white = Path()..moveTo(40, -2);
    final edge = [
      const Offset(24, -2),
      const Offset(26.5, 4),
      const Offset(23.5, 8),
      const Offset(26.5, 11),
      const Offset(24, 15),
      const Offset(27.5, 17),
      const Offset(25, 22),
      const Offset(40, 24),
    ];
    for (final p in edge) {
      white.lineTo(p.dx, p.dy);
    }
    white.close();
    canvas.drawPath(white, Paint()..color = _furWhite);
    canvas.restore();
    // Ein paar Fellstriche, damit es buschig wirkt.
    final fur = Paint()
      ..color = Kitsune.deep.withValues(alpha: 0.3)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in [
      (const Offset(9, 13), const Offset(14, 12)),
      (const Offset(14, 17), const Offset(19, 15)),
      (const Offset(19, 20), const Offset(23, 17)),
    ]) {
      canvas.drawLine(a, b, fur);
    }
    canvas.drawPath(tail, _outline);
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.color != color;
}
