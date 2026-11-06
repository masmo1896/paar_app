import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/daily_magic.dart';
import 'motion.dart';
import 'sky_extras.dart';

/// Fuchs-Besuch: Alle 15 Minuten schaut der Fuchs vom Laternenhimmel gross
/// vom Bildschirmrand herein, schickt drei Küsse und taucht wieder ab – jedes
/// Mal an einem anderen Rand und an anderer Stelle. Liegt als Ebene über den
/// Bereichen (HomeShell) und fängt keine Tipps ab.
///
/// Zum Ausprobieren schneller: `--dart-define=FOX_EVERY_SECONDS=20`.
class FoxVisitLayer extends StatefulWidget {
  const FoxVisitLayer({super.key});

  @override
  State<FoxVisitLayer> createState() => _FoxVisitLayerState();
}

const _testEverySeconds = int.fromEnvironment('FOX_EVERY_SECONDS');

class _FoxVisitLayerState extends State<FoxVisitLayer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _every = _testEverySeconds > 0
      ? Duration(seconds: _testEverySeconds)
      : Duration(minutes: 15);

  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 6200),
  );
  final _rnd = math.Random();
  Timer? _timer;
  late DateTime _next = DateTime.now().add(_every);
  _Visit? _visit;
  _Edge? _lastEdge;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Im Hintergrund keine Uhr laufen lassen; beim Zurückkommen weiterzählen.
    if (state == AppLifecycleState.resumed) {
      _schedule();
    } else {
      _timer?.cancel();
    }
  }

  void _schedule() {
    _timer?.cancel();
    final wait = _next.difference(DateTime.now());
    _timer = Timer(
      wait.isNegative ? const Duration(seconds: 2) : wait,
      _tryVisit,
    );
  }

  void _tryVisit() {
    if (!mounted) return;
    // Nur wenn die Hauptseite obenauf ist (kein Spiel, keine Einstellungen
    // darüber) – sonst kurz später nochmals schauen.
    final onTop = ModalRoute.of(context)?.isCurrent ?? true;
    if (!onTop || _anim.isAnimating) {
      _next = DateTime.now().add(const Duration(seconds: 30));
      return _schedule();
    }
    _next = DateTime.now().add(_every);
    _schedule();
    if (reduceMotion(context)) return;
    setState(() => _visit = _Visit.random(_rnd, avoid: _lastEdge));
    _lastEdge = _visit!.edge;
    _anim.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _visit = null);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visit = _visit;
    if (visit == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _FoxVisitPainter(
            t: _anim,
            visit: visit,
            outfit: foxOutfitFor(DateTime.now()),
          ),
        ),
      ),
    );
  }
}

/// Nur für Tests: ein Einzelbild des Besuchs zum Zeitpunkt [progress] (0–1).
@visibleForTesting
class FoxVisitFrame extends StatelessWidget {
  const FoxVisitFrame({
    super.key,
    required this.edge,
    required this.along,
    required this.tilt,
    required this.progress,
  });

  /// 0 links, 1 rechts, 2 unten.
  final int edge;
  final double along;
  final double tilt;
  final double progress;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.infinite,
    painter: _FoxVisitPainter(
      t: AlwaysStoppedAnimation(progress),
      visit: _Visit(_Edge.values[edge], along, tilt),
      outfit: foxOutfitFor(DateTime(2026, 11, 6)),
    ),
  );
}

enum _Edge { left, right, bottom }

/// Wo und wie der Fuchs diesmal hereinschaut.
class _Visit {
  const _Visit(this.edge, this.along, this.tilt);

  final _Edge edge;

  /// Stelle entlang des Randes (0–1).
  final double along;

  /// Leichte Schräglage, damit es nie gleich aussieht (Bogenmass).
  final double tilt;

  factory _Visit.random(math.Random rnd, {_Edge? avoid}) {
    final edges = [
      for (final e in _Edge.values)
        if (e != avoid) e,
    ];
    final edge = edges[rnd.nextInt(edges.length)];
    final along = edge == _Edge.bottom
        ? 0.22 + rnd.nextDouble() * 0.56
        : 0.25 + rnd.nextDouble() * 0.5;
    return _Visit(edge, along, (rnd.nextDouble() - 0.5) * 0.5);
  }
}

/// Zeichnet den Fuchs (wie foxlogo.svg, Masse 48 × 48) gross am Rand, dazu
/// fliegende Herzen. Alles hängt an einer Zeit 0–1:
/// 0–0.15 hereinschauen · 0.15–0.8 Küsse · 0.8–0.95 abtauchen.
class _FoxVisitPainter extends CustomPainter {
  _FoxVisitPainter({required this.t, required this.visit, required this.outfit})
    : super(repaint: t);

  final Animation<double> t;
  final _Visit visit;
  final FoxOutfit outfit;

  static const _paper = Color(0xFFF3EBD3);
  static const _ink = Color(0xFF0A1838);
  static const _blush = Color(0xFFF29BB4);

  // Drei Küsse: Startzeitpunkte, jedes Herz lebt 0.32 der Zeit.
  static const _kisses = [0.24, 0.39, 0.54];
  static const _heartLife = 0.32;

  static final _chu = TextPainter(
    text: TextSpan(
      text: 'ちゅっ',
      // Systemschrift (auf dem iPhone Hiragino) – muss nicht erst geladen werden.
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: Kitsune.lantern,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  double _seg(double v, double a, double b) => ((v - a) / (b - a)).clamp(0, 1);

  /// Kleiner Ausschlag um den Zeitpunkt [at] (für Nicken und Zucken).
  double _bump(double v, double at, double width) {
    final d = (v - at).abs() / width;
    return d >= 1 ? 0 : math.sin((1 - d) * math.pi / 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    // Hereinschauen (mit kleinem Überschwingen) und wieder abtauchen.
    final peek = v < 0.8
        ? Curves.easeOutBack.transform(_seg(v, 0, 0.15))
        : 1 - Curves.easeInCubic.transform(_seg(v, 0.8, 0.95));
    if (peek <= 0 && v > 0.5) return;

    // Gross: das Gesicht (gut die Hälfte der 48er-Zeichnung) nimmt etwa ein
    // Drittel des Bildschirms ein.
    final head = math.min(size.width * 0.9, size.height * 0.42);
    final s = head / 48;

    // Punkt am Rand und Blickrichtung (Fuchs-«oben» zeigt in den Bildschirm).
    final (anchor, angle) = switch (visit.edge) {
      _Edge.bottom => (Offset(size.width * visit.along, size.height), 0.0),
      _Edge.left => (Offset(0, size.height * visit.along), math.pi / 2),
      _Edge.right => (
        Offset(size.width, size.height * visit.along),
        -math.pi / 2,
      ),
    };

    // Nicken bei jedem Kuss: lehnt sich kurz in den Bildschirm.
    var nod = 0.0;
    for (final k in _kisses) {
      nod += _bump(v, k + 0.015, 0.05) * 0.13;
    }
    final rotation = angle + visit.tilt * 0.6 + nod;

    // Wie tief der Fuchs hereinschaut: ganz versteckt (Ohrspitzen y=5) bis
    // knapp unter die Schnauze (y=36) sichtbar.
    final baseY = 5 + (36 - 5) * peek;

    // Mund in Bildschirm-Koordinaten (für die Herzen).
    Offset toScreen(Offset fox) {
      final local = (fox - Offset(24, baseY)) * s;
      final c = math.cos(rotation), sn = math.sin(rotation);
      return anchor +
          Offset(local.dx * c - local.dy * sn, local.dx * sn + local.dy * c);
    }

    final mouth = toScreen(const Offset(24, 31.5));
    final inward = Offset(math.sin(rotation), -math.cos(rotation));

    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    canvas.rotate(rotation);
    canvas.scale(s);
    canvas.translate(-24, -baseY);
    _paintFox(canvas, v);
    canvas.save();
    // Accessoire des Tages – derselbe Fuchs wie bei den Laternen.
    FoxOutfitPainter(outfit).paint(canvas, const Size.square(48));
    canvas.restore();
    canvas.restore();

    // Herzen: zuerst seitlich vom Mund weg (nicht übers Gesicht), dann
    // schwebend in den Bildschirm – abwechselnd nach links und rechts.
    final across = Offset(-inward.dy, inward.dx);
    for (final (i, k) in _kisses.indexed) {
      final life = (v - k) / _heartLife;
      if (life <= 0 || life >= 1) continue;
      final ease = Curves.easeOutCubic.transform(life);
      final out = Curves.easeOutCubic.transform(math.min(life * 3, 1));
      final sideSign = i.isEven ? 1.0 : -1.0;
      final sway = math.sin(life * math.pi * 2.2 + i) * head * 0.05;
      final pos =
          mouth +
          across * (sideSign * head * (0.36 * out + 0.1 * ease) + sway) +
          inward * (head * (0.02 + 0.85 * ease));
      final heartSize =
          head *
          (0.1 + 0.12 * Curves.easeOutBack.transform(math.min(life * 2.5, 1)));
      final alpha = life < 0.75 ? 1.0 : 1 - (life - 0.75) / 0.25;
      _paintHeart(canvas, pos, heartSize, alpha, i.isEven);
      // «ちゅっ» beim ersten Kuss.
      if (i == 0 && life < 0.6) {
        final a = life < 0.45 ? 1.0 : 1 - (life - 0.45) / 0.15;
        final at =
            mouth +
            inward * (head * 0.42) +
            across * (-head * 0.34) -
            Offset(_chu.width / 2, _chu.height / 2);
        // Ebene nur so gross wie der Text (zum Ausblenden).
        canvas.saveLayer(
          at & _chu.size,
          Paint()..color = Color.fromRGBO(0, 0, 0, a),
        );
        _chu.paint(canvas, at);
        canvas.restore();
      }
    }
  }

  void _paintFox(Canvas canvas, double v) {
    // Weicher Schein hinter dem Kopf.
    canvas.drawCircle(
      const Offset(24, 24),
      24,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                Kitsune.lantern.withValues(alpha: 0.28),
                Kitsune.lantern.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(center: const Offset(24, 24), radius: 24),
            ),
    );

    final paper = Paint()..color = _paper;
    // Ohren zucken zweimal.
    final twitch = _bump(v, 0.17, 0.035) + _bump(v, 0.72, 0.035);
    for (final (tip, base, sign) in [
      (const Offset(13, 7), const Offset(16, 17), -1.0),
      (const Offset(35, 7), const Offset(32, 17), 1.0),
    ]) {
      canvas.save();
      canvas.translate(base.dx, base.dy);
      canvas.rotate(sign * 0.22 * twitch);
      canvas.translate(-base.dx, -base.dy);
      final ear = Path()
        ..moveTo(sign < 0 ? 11 : 37, 20)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(sign < 0 ? 21 : 27, 15)
        ..close();
      canvas.drawPath(ear, paper);
      // Inneres Ohr in Laternenrot.
      final inner = Path()
        ..moveTo(sign < 0 ? 13.6 : 34.4, 17.5)
        ..lineTo(sign < 0 ? 13.8 : 34.2, 10.5)
        ..lineTo(sign < 0 ? 18.4 : 29.6, 15.4)
        ..close();
      canvas.drawPath(
        inner,
        Paint()..color = Kitsune.lantern.withValues(alpha: 0.55),
      );
      canvas.restore();
    }

    // Gesicht (wie im SVG).
    final face = Path()
      ..moveTo(11, 20)
      ..quadraticBezierTo(12, 14, 21, 15)
      ..quadraticBezierTo(24, 13, 27, 15)
      ..quadraticBezierTo(36, 14, 37, 20)
      ..quadraticBezierTo(38, 30, 24, 40)
      ..quadraticBezierTo(10, 30, 11, 20)
      ..close();
    canvas.drawPath(face, paper);

    // Rosa Wangen, kräftiger während der Küsse.
    final blush = 0.25 + 0.55 * _seg(v, 0.2, 0.3) * (1 - _seg(v, 0.8, 0.9));
    final cheek = Paint()..color = _blush.withValues(alpha: blush);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(15.5, 28), width: 5.5, height: 3.2),
      cheek,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(32.5, 28), width: 5.5, height: 3.2),
      cheek,
    );

    // Augen: fröhliche Bögen; beim Zwinkern wird das rechte zum Strich.
    final eye = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(16, 23)
        ..quadraticBezierTo(19, 21, 21, 24),
      eye,
    );
    final wink = _bump(v, 0.68, 0.04);
    canvas.drawPath(
      Path()
        ..moveTo(32, 23 + wink)
        ..quadraticBezierTo(29, 21 + 3 * wink, 27, 24),
      eye,
    );
    // Rote Zeichen über den Augen.
    final mark = Paint()
      ..color = Kitsune.lantern
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(17, 19)
        ..quadraticBezierTo(19, 17, 20, 19)
        ..moveTo(31, 19)
        ..quadraticBezierTo(29, 17, 28, 19),
      mark,
    );

    // Näschen.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(24, 29.3), width: 3.2, height: 2.2),
      Paint()..color = _ink,
    );
    // Kussmund kurz vor jedem Kuss, sonst ein kleines Lächeln.
    var pucker = 0.0;
    for (final k in _kisses) {
      pucker = math.max(pucker, _bump(v, k - 0.01, 0.045));
    }
    if (pucker > 0.05) {
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(24, 32.2),
          width: 2.2 + 1.2 * pucker,
          height: 1.6 + 1.6 * pucker,
        ),
        Paint()..color = Kitsune.lantern,
      );
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(22.3, 31.6)
          ..quadraticBezierTo(24, 33, 25.7, 31.6),
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _paintHeart(
    Canvas canvas,
    Offset c,
    double size,
    double alpha,
    bool red,
  ) {
    final w = size, h = size * 0.9;
    final path = Path()
      ..moveTo(c.dx, c.dy + h * 0.35)
      ..cubicTo(
        c.dx - w * 0.9,
        c.dy - h * 0.2,
        c.dx - w * 0.35,
        c.dy - h * 0.85,
        c.dx,
        c.dy - h * 0.35,
      )
      ..cubicTo(
        c.dx + w * 0.35,
        c.dy - h * 0.85,
        c.dx + w * 0.9,
        c.dy - h * 0.2,
        c.dx,
        c.dy + h * 0.35,
      )
      ..close();
    final color = red ? Kitsune.lantern : _blush;
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: alpha));
    // Kleiner Glanzpunkt.
    canvas.drawCircle(
      c + Offset(-w * 0.28, -h * 0.38),
      size * 0.09,
      Paint()..color = Colors.white.withValues(alpha: 0.55 * alpha),
    );
  }

  @override
  bool shouldRepaint(_FoxVisitPainter old) =>
      old.visit != visit || old.outfit != outfit;
}
