import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'motion.dart';

/// Herzen über den ganzen Bildschirm (ca. 3,4 s), wenn ihr gleichzeitig eine
/// Laterne geschickt habt:
/// 1. Herzen steigen von unten auf, pendeln und drehen sich leicht.
/// 2. Alle fliegen zur Mitte zusammen …
/// 3. … und werden ein grosses Herz, das zweimal pocht und in Funken zerfällt.
/// Liegt über allem (Overlay), lässt Antippen aber durch.
class HeartRain {
  HeartRain._();

  static OverlayEntry? _current;

  static void show(BuildContext context) {
    if (_current != null) return; // läuft schon
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _HeartRain(
        onDone: () {
          entry.remove();
          _current = null;
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

class _HeartRain extends StatefulWidget {
  const _HeartRain({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_HeartRain> createState() => _HeartRainState();
}

class _HeartRainState extends State<_HeartRain>
    with SingleTickerProviderStateMixin {
  late final _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400),
  );
  final _hearts = <_Heart>[];
  bool _popped = false;
  bool _calm = false;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random();
    for (var i = 0; i < 46; i++) {
      _hearts.add(_Heart.random(rnd));
    }
    _t.addListener(() {
      // Ein kräftiges Tippen, wenn das grosse Herz erscheint.
      if (!_popped && _t.value >= _popAt) {
        _popped = true;
        HapticFeedback.heavyImpact();
      }
    });
    _t.forward().whenComplete(widget.onDone);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _calm = reduceMotion(context);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        size: MediaQuery.sizeOf(context),
        painter: _HeartPainter(_t, _hearts, calm: _calm),
      ),
    ),
  );
}

// Zeitplan (Anteil der Gesamtdauer).
const _gatherFrom = 0.62; // Herzen fliegen zur Mitte
const _popAt = 0.76; // grosses Herz erscheint
const _fadeFrom = 0.9; // alles klingt aus

class _Heart {
  _Heart.random(math.Random r)
    : x = r.nextDouble(),
      delay = r.nextDouble() * 0.28,
      speed = 0.75 + r.nextDouble() * 0.5,
      size = 14 + r.nextDouble() * 22,
      swayAmp = 10 + r.nextDouble() * 22,
      swayFreq = 1.5 + r.nextDouble() * 2,
      phase = r.nextDouble() * 2 * math.pi,
      color = const [
        Kitsune.lantern,
        Color(0xFFFF7FA8),
        Kitsune.paper,
        Color(0xFFFFB3C8),
        Kitsune.aqua,
      ][r.nextInt(5)];

  final double x; // Startposition 0–1 über die Breite
  final double delay;
  final double speed;
  final double size;
  final double swayAmp;
  final double swayFreq;
  final double phase;
  final Color color;

  /// Position beim Aufsteigen zur Zeit [t] (0–1).
  Offset rising(double t, Size s) {
    final local = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
    final y = s.height + size - local * speed * (s.height * 1.15);
    final sway = math.sin(local * swayFreq * 2 * math.pi + phase) * swayAmp;
    return Offset(x * s.width + sway, y);
  }
}

class _HeartPainter extends CustomPainter {
  _HeartPainter(this.t, this.hearts, {required this.calm}) : super(repaint: t);

  final Animation<double> t;
  final List<_Heart> hearts;
  final bool calm;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final center = Offset(size.width / 2, size.height * 0.45);
    final fade = v < _fadeFrom ? 1.0 : 1 - (v - _fadeFrom) / (1 - _fadeFrom);

    // Leichter warmer Schleier, der mit dem grossen Herz am stärksten ist.
    final veil = math.sin(v * math.pi).clamp(0.0, 1.0) * 0.22;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Kitsune.lantern.withValues(alpha: veil),
            Kitsune.deeper.withValues(alpha: veil * 0.6),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: size.height)),
    );

    if (!calm) {
      // 1 + 2: aufsteigen, dann zur Mitte zusammenfliegen.
      final gather = ((v - _gatherFrom) / (_popAt - _gatherFrom)).clamp(
        0.0,
        1.0,
      );
      final g = Curves.easeInCubic.transform(gather);
      for (final h in hearts) {
        if (v < h.delay) continue;
        final rise = h.rising(math.min(v, _gatherFrom), size);
        final pos = Offset.lerp(rise, center, g)!;
        final scale =
            (1 - g * 0.7) * (v - h.delay < 0.05 ? (v - h.delay) / 0.05 : 1);
        final alpha = gather >= 1 ? 0.0 : 0.9;
        _heart(
          canvas,
          pos,
          h.size * scale,
          h.color.withValues(alpha: alpha),
          math.sin(v * 6 + h.phase) * 0.25,
        );
      }
    }

    // 3: grosses Herz – springt auf, pocht zweimal, wächst und verblasst.
    if (v >= _popAt) {
      final p = (v - _popAt) / (1 - _popAt);
      final pop = Curves.elasticOut.transform((p / 0.35).clamp(0.0, 1.0));
      final beat = 1 + 0.08 * math.sin(p * math.pi * 4).abs() * (1 - p);
      final grow = p > 0.6 ? 1 + (p - 0.6) * 0.9 : 1.0;
      final r = size.shortestSide * 0.22 * pop * beat * grow;
      // Schein
      canvas.drawCircle(
        center,
        r * 1.6,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Kitsune.lantern.withValues(alpha: 0.5 * fade),
              Kitsune.lantern.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: r * 1.6)),
      );
      _heart(canvas, center, r * 2, Kitsune.lantern.withValues(alpha: fade), 0);
      // Funken fliegen am Ende nach aussen.
      if (p > 0.55) {
        final s = Curves.easeOutCubic.transform((p - 0.55) / 0.45);
        for (var k = 0; k < 16; k++) {
          final a = k / 16 * 2 * math.pi;
          final d = Offset(math.cos(a), math.sin(a));
          _heart(
            canvas,
            center + d * (r * 0.8 + s * size.shortestSide * 0.45),
            10 * (1 - s * 0.5),
            (k.isEven ? Kitsune.paper : const Color(0xFFFF7FA8)).withValues(
              alpha: (1 - s) * fade,
            ),
            a,
          );
        }
      }
      // Kleiner Text unter dem Herz.
      final tp = TextPainter(
        text: TextSpan(
          text: 'Gleichzeitig ♥',
          style: AppTheme.serif(
            size: 22,
            color: Kitsune.paper.withValues(alpha: fade * pop.clamp(0.0, 1.0)),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        center + Offset(-tp.width / 2, size.shortestSide * 0.26),
      );
    }
  }

  /// Herz mit Mittelpunkt [c] und Breite [w].
  void _heart(Canvas canvas, Offset c, double w, Color color, double angle) {
    if (w <= 0.5 || color.a == 0) return;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    canvas.scale(w / 2);
    final path = Path()
      ..moveTo(0, 0.85)
      ..cubicTo(-0.3, 0.6, -1.0, 0.25, -1.0, -0.3)
      ..cubicTo(-1.0, -0.8, -0.4, -1.0, 0, -0.55)
      ..cubicTo(0.4, -1.0, 1.0, -0.8, 1.0, -0.3)
      ..cubicTo(1.0, 0.25, 0.3, 0.6, 0, 0.85)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HeartPainter old) => false;
}
