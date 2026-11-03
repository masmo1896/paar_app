import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';
import '../utils/daily_magic.dart';

// Tägliche Überraschungen im Laternenhimmel: echter Mond, Kirschblüten am
// Monatstag, Sternschnuppe und der Fuchs des Tages.

/// Gold der seltenen goldenen Laternen.
const lanternGold = Color(0xFFFFC94D);

/// Mond in seiner echten Phase von heute; bei Vollmond mit warmem Schein.
class MoonPainter extends CustomPainter {
  const MoonPainter({required this.phase, required this.center, this.r = 13});

  final double phase; // 0 = Neumond, 0.5 = Vollmond
  final Offset center;
  final double r;

  @override
  void paint(Canvas canvas, Size size) {
    final disc = Rect.fromCircle(center: center, radius: r);
    final full = (phase - 0.5).abs() < 0.034;
    if (full) {
      canvas.drawCircle(
        center,
        r * 3,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Kitsune.paper.withValues(alpha: 0.35),
              Kitsune.paper.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: r * 3)),
      );
    }
    // Dunkle Mondscheibe, kaum sichtbar.
    canvas.drawCircle(
      center,
      r,
      Paint()..color = Kitsune.paper.withValues(alpha: 0.08),
    );
    // Beleuchteter Teil: Halbscheibe auf der hellen Seite, plus/minus Ellipse
    // bis zur Schattengrenze (zunehmend: rechts hell, abnehmend: links).
    final waxing = phase < 0.5;
    final k = math.cos(2 * math.pi * phase); // 1 = Neumond, -1 = Vollmond
    final half = Path()
      ..addArc(disc, waxing ? -math.pi / 2 : math.pi / 2, math.pi)
      ..close();
    final ellipse = Path()
      ..addOval(
        Rect.fromCenter(center: center, width: 2 * r * k.abs(), height: 2 * r),
      );
    final lit = k > 0
        ? Path.combine(PathOperation.difference, half, ellipse)
        : Path.combine(PathOperation.union, half, ellipse);
    canvas.drawPath(lit, Paint()..color = Kitsune.paper);
  }

  @override
  bool shouldRepaint(MoonPainter old) =>
      old.phase != phase || old.center != center || old.r != r;
}

/// Kirschblüten-Blätter, die am Monatstag langsam durch den Himmel fallen.
class PetalPainter extends CustomPainter {
  PetalPainter(this.time) : super(repaint: time);

  final ValueListenable<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    for (var i = 0; i < 18; i++) {
      final seed = stableHash('petal$i');
      final speed = 10 + seed % 14; // px pro Sekunde
      final x0 = (seed % 1000) / 1000 * size.width;
      final y = ((t * speed + (seed ~/ 1000) % 400) % (size.height + 30)) - 15;
      final x = x0 + math.sin(t * 0.8 + i) * 14;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * (0.6 + (seed % 7) / 10) + i);
      canvas.drawOval(
        const Rect.fromLTWH(-4, -2.5, 8, 5),
        Paint()
          ..color = Color.lerp(
            const Color(0xFFFFC1D6),
            const Color(0xFFFF8FB4),
            (seed % 10) / 10,
          )!.withValues(alpha: 0.85),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(PetalPainter old) => false;
}

/// Sternschnuppe: fliegt alle [every] Sekunden für [flight] Sekunden quer
/// über den Himmel, solange [active] true ist.
class ShootingStarPainter extends CustomPainter {
  ShootingStarPainter(this.time, {required this.active}) : super(repaint: time);

  final ValueListenable<double> time;
  final ValueListenable<bool> active;

  static const every = 18.0;
  static const flight = 2.6;

  /// Fliegt sie gerade? (Dann zählt ein Antippen als «gefangen».)
  static bool flying(double t) => t % every < flight;

  @override
  void paint(Canvas canvas, Size size) {
    if (!active.value) return;
    final t = time.value;
    final local = t % every;
    if (local >= flight) return;
    final p = local / flight;
    final start = Offset(size.width * 0.15, size.height * 0.12);
    final end = Offset(size.width * 0.85, size.height * 0.55);
    final head = Offset.lerp(start, end, Curves.easeInOutSine.transform(p))!;
    final dir = (end - start) / (end - start).distance;
    final fade = p < 0.15 ? p / 0.15 : (p > 0.8 ? (1 - p) / 0.2 : 1.0);
    // Schweif
    canvas.drawLine(
      head - dir * 60,
      head,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Kitsune.paper.withValues(alpha: 0),
            Kitsune.paper.withValues(alpha: 0.9 * fade),
          ],
        ).createShader(Rect.fromPoints(head - dir * 60, head))
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      head,
      7,
      Paint()
        ..shader = RadialGradient(
          colors: [
            lanternGold.withValues(alpha: 0.7 * fade),
            lanternGold.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: head, radius: 7)),
    );
    canvas.drawCircle(
      head,
      2.2,
      Paint()..color = Colors.white.withValues(alpha: fade),
    );
  }

  @override
  bool shouldRepaint(ShootingStarPainter old) => false;
}

/// Fuchs des Tages: lugt unten aus dem Himmel und trägt jeden Tag etwas anderes.
class DailyFox extends StatelessWidget {
  const DailyFox({
    super.key,
    required this.outfit,
    required this.time,
    this.size = 44,
  });

  final FoxOutfit outfit;
  final ValueListenable<double> time;
  final double size;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: time,
    builder: (context, t, child) => Transform.translate(
      // Ruhiges Atmen: kaum merklich auf und ab.
      offset: Offset(0, math.sin(t * 1.4) * 1.5),
      child: Transform.rotate(angle: math.sin(t * 0.7) * 0.05, child: child),
    ),
    child: SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SvgPicture.asset('assets/kitsune/foxlogo.svg', width: size),
          Positioned.fill(
            child: CustomPaint(painter: FoxOutfitPainter(outfit)),
          ),
        ],
      ),
    ),
  );
}

/// Zeichnet das Accessoire passend auf den Fuchskopf (foxlogo.svg, 48 × 48).
class FoxOutfitPainter extends CustomPainter {
  const FoxOutfitPainter(this.outfit);

  final FoxOutfit outfit;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48);
    final ink = Paint()..color = Kitsune.deeper;
    switch (outfit) {
      case FoxOutfit.sunglasses:
        for (final x in [13.5, 25.5]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, 20, 9, 6),
              const Radius.circular(2.5),
            ),
            ink,
          );
        }
        canvas.drawLine(
          const Offset(22, 22),
          const Offset(26, 22),
          ink..strokeWidth = 1.4,
        );
        canvas.drawLine(
          const Offset(15, 21.5),
          const Offset(17.5, 21.5),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.6)
            ..strokeWidth = 0.8,
        );
      case FoxOutfit.scarf:
        final red = Paint()..color = Kitsune.lantern;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(12, 35, 24, 5.5),
            const Radius.circular(2.5),
          ),
          red,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(28, 38, 5, 9),
            const Radius.circular(2),
          ),
          red,
        );
        final stripe = Paint()
          ..color = Kitsune.paper.withValues(alpha: 0.7)
          ..strokeWidth = 0.8;
        for (final x in [16.0, 21.0, 26.0]) {
          canvas.drawLine(Offset(x, 35.5), Offset(x, 40), stripe);
        }
      case FoxOutfit.flowers:
        const colors = [
          Color(0xFFFF8FB4),
          Color(0xFFFFE08A),
          Color(0xFFA6ECF2),
          Color(0xFFFF8FB4),
          Color(0xFFFFE08A),
        ];
        for (var i = 0; i < 5; i++) {
          final c = Offset(13 + i * 5.5, 15.5 - math.sin(i / 4 * math.pi) * 2);
          for (var k = 0; k < 5; k++) {
            final a = k / 5 * 2 * math.pi;
            canvas.drawCircle(
              c + Offset(math.cos(a), math.sin(a)) * 1.6,
              1.3,
              Paint()..color = colors[i],
            );
          }
          canvas.drawCircle(c, 0.9, Paint()..color = Colors.white);
        }
      case FoxOutfit.partyHat:
        final hat = Path()
          ..moveTo(19, 15)
          ..lineTo(29, 15)
          ..lineTo(24, -3)
          ..close();
        canvas.drawPath(hat, Paint()..color = Kitsune.sky);
        canvas.save();
        canvas.clipPath(hat);
        for (var y = -3.0; y < 16; y += 4) {
          canvas.drawLine(
            Offset(17, y + 3),
            Offset(31, y - 2),
            Paint()
              ..color = const Color(0xFFFFE08A)
              ..strokeWidth = 1.4,
          );
        }
        canvas.restore();
        canvas.drawCircle(
          const Offset(24, -3.5),
          2,
          Paint()..color = Kitsune.lantern,
        );
      case FoxOutfit.santaHat:
        final hat = Path()
          ..moveTo(9, 16)
          ..quadraticBezierTo(22, 2, 41, 3)
          ..lineTo(39, 16)
          ..close();
        canvas.drawPath(hat, Paint()..color = Kitsune.lantern);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(8, 14, 32, 4.5),
            const Radius.circular(2),
          ),
          Paint()..color = Colors.white,
        );
        canvas.drawCircle(
          const Offset(41.5, 3),
          2.6,
          Paint()..color = Colors.white,
        );
    }
  }

  @override
  bool shouldRepaint(FoxOutfitPainter old) => old.outfit != outfit;
}

/// Fenster nach dem Fangen der Sternschnuppe: Wunsch aufschreiben und dem
/// Schatz schicken – oder geheim halten.
class WishSheet extends StatefulWidget {
  const WishSheet({super.key, required this.partner, required this.onSend});

  final String partner;
  final Future<void> Function(String? wish) onSend;

  @override
  State<WishSheet> createState() => _WishSheetState();
}

class _WishSheetState extends State<WishSheet> {
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(String? wish) async {
    setState(() => _busy = true);
    await widget.onSend(wish);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '🌠',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 40),
      ),
      const SizedBox(height: 6),
      Text(
        'Du hast die Sternschnuppe gefangen!',
        textAlign: TextAlign.center,
        style: AppTheme.serif(size: 19),
      ),
      const SizedBox(height: 4),
      Text(
        'Was wünschst du dir für euch? ${widget.partner} bekommt es im Chat.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Kitsune.mist, fontSize: 13),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _text,
        autofocus: true,
        enabled: !_busy,
        maxLength: 200,
        maxLines: 3,
        minLines: 1,
        decoration: const InputDecoration(hintText: 'Ich wünsche uns …'),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : () => _send(null),
              child: const Text('Geheim halten'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _busy || _text.text.trim().isEmpty
                  ? null
                  : () => _send(_text.text.trim()),
              child: const Text('Wunsch schicken'),
            ),
          ),
        ],
      ),
    ],
  );
}
