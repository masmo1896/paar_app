import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/dates.dart';
import '../widgets/motion.dart';

/// Nachtblaue Karte für einen Bereich der "Wir"-Seite: Stempel, Titel, Inhalt.
class UsCard extends StatelessWidget {
  const UsCard({
    super.key,
    required this.stamp,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String stamp; // ein Schriftzeichen im roten Hanko
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  // Material statt Container: Gleiches Nachtblau wie die Illustration oben,
  // feiner heller Rand – und Listenzeilen darin zeigen ihren Tipp-Effekt.
  Widget build(BuildContext context) => Material(
    color: Kitsune.deep,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: Kitsune.paper.withValues(alpha: 0.14)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Hanko(stamp, size: 24),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: AppTheme.serif(size: 17))),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// 1. Zusammen-seit-Zähler und Meilensteine

/// "1 Jahr, 3 Monate, 12 Tage" zwischen [since] und [until].
({int years, int months, int days}) _ymd(DateTime since, DateTime until) {
  var years = until.year - since.year;
  var months = until.month - since.month;
  var days = until.day - since.day;
  if (days < 0) {
    months--;
    days += DateTime(until.year, until.month, 0).day;
  }
  if (months < 0) {
    years--;
    months += 12;
  }
  return (years: years, months: months, days: days);
}

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// Grosser Zähler unter den Namen. Antippen zeigt die nächsten Meilensteine.
class TogetherCounter extends StatelessWidget {
  const TogetherCounter({super.key, required this.since});

  final DateTime since;

  @override
  Widget build(BuildContext context) {
    final now = today();
    final totalDays = now.difference(since).inDays;
    final p = _ymd(since, now);
    final parts = [
      if (p.years > 0) _plural(p.years, 'Jahr', 'Jahre'),
      if (p.months > 0) _plural(p.months, 'Monat', 'Monate'),
      _plural(p.days, 'Tag', 'Tage'),
    ];
    return Semantics(
      button: true,
      label: 'Zusammen seit $totalDays Tagen. Meilensteine anzeigen',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showMilestones(context, since),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              CountUp(
                value: totalDays,
                duration: const Duration(milliseconds: 1100),
                style: AppTheme.serif(size: 46, color: Kitsune.paper).copyWith(
                  height: 1,
                  shadows: const [
                    Shadow(color: Kitsune.lantern, blurRadius: 18),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Tage zusammen',
                style: AppTheme.serif(
                  size: 12,
                  weight: FontWeight.w600,
                  color: Kitsune.aqua,
                ).copyWith(letterSpacing: 2.4),
              ),
              const SizedBox(height: 6),
              Text(
                parts.join(', '),
                style: const TextStyle(fontSize: 13, color: Kitsune.mist),
              ),
              const SizedBox(height: 4),
              const Text(
                'Meilensteine ›',
                style: TextStyle(fontSize: 12, color: Kitsune.aqua),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Die nächsten Meilensteine: runde Tageszahlen und Jahrestage.
List<({String title, DateTime date})> nextMilestones(
  DateTime since, {
  int count = 5,
}) {
  final now = today();
  final list = <({String title, DateTime date})>[];
  for (final d in [
    100,
    200,
    300,
    500,
    1000,
    1111,
    1500,
    2000,
    2500,
    3000,
    4000,
    5000,
    10000,
  ]) {
    final date = since.add(Duration(days: d));
    if (!date.isBefore(now)) list.add((title: '$d Tage', date: date));
  }
  for (var y = 1; y <= 60; y++) {
    final date = DateTime(since.year + y, since.month, since.day);
    if (!date.isBefore(now)) list.add((title: '$y. Jahrestag', date: date));
  }
  list.sort((a, b) => a.date.compareTo(b.date));
  return list.take(count).toList();
}

void _showMilestones(BuildContext context, DateTime since) {
  final now = today();
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Unsere nächsten Meilensteine',
              style: AppTheme.serif(size: 20),
            ),
            const SizedBox(height: 12),
            for (final m in nextMilestones(since))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Text('✦ ', style: TextStyle(color: Kitsune.lantern)),
                    Expanded(
                      child: Text(
                        '${m.title} · ${m.date.day}. ${monthsLong[m.date.month - 1]} ${m.date.year}',
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                    Text(
                      m.date == now
                          ? 'heute! 🎉'
                          : 'in ${m.date.difference(now).inDays} Tagen',
                      style: const TextStyle(color: Kitsune.aqua, fontSize: 13),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Zeichnungen: Briefumschlag und Date-Glas

/// Versiegelter Umschlag mit rotem Siegel.
class EnvelopeIcon extends StatelessWidget {
  const EnvelopeIcon({super.key, this.width = 64});

  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: width * 0.72,
    child: CustomPaint(painter: _EnvelopePainter()),
  );
}

class _EnvelopePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(4),
    );
    canvas.drawRRect(r, Paint()..color = const Color(0xFFFFFCF4));
    final line = Paint()
      ..color = Kitsune.deep
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(r, line);
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height * 0.58)
        ..lineTo(size.width, 0),
      line,
    );
    final seal = Offset(size.width / 2, size.height * 0.58);
    canvas.drawCircle(seal, 8, Paint()..color = Kitsune.lantern);
    final heart = Path()
      ..moveTo(seal.dx, seal.dy + 3.5)
      ..cubicTo(
        seal.dx - 6,
        seal.dy - 1,
        seal.dx - 2.5,
        seal.dy - 5,
        seal.dx,
        seal.dy - 2,
      )
      ..cubicTo(
        seal.dx + 2.5,
        seal.dy - 5,
        seal.dx + 6,
        seal.dy - 1,
        seal.dx,
        seal.dy + 3.5,
      );
    canvas.drawPath(heart, Paint()..color = Kitsune.paper);
  }

  @override
  bool shouldRepaint(_EnvelopePainter old) => false;
}

// ---------------------------------------------------------------------------
/// Einmachglas mit bunten, gefalteten Zettelchen.
class JarPainter extends CustomPainter {
  const JarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final outline = Paint()
      ..color = Kitsune.paper.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    // Deckel.
    final lid = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.18, 0, w * 0.64, h * 0.12),
      const Radius.circular(3),
    );
    canvas.drawRRect(lid, Paint()..color = Kitsune.plum);
    canvas.drawRRect(lid, outline);
    // Glas.
    final glass = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.06, h * 0.12, w * 0.88, h * 0.88),
      const Radius.circular(14),
    );
    canvas.drawRRect(
      glass,
      Paint()..color = Kitsune.aqua.withValues(alpha: 0.35),
    );
    // Zettel im Glas.
    canvas.save();
    canvas.clipRRect(glass);
    final rnd = math.Random(4);
    const colors = [
      Kitsune.lantern,
      Kitsune.paper,
      Kitsune.plum,
      Kitsune.sky,
      Color(0xFFF2C14E),
    ];
    for (var i = 0; i < 16; i++) {
      final cx = w * (0.18 + rnd.nextDouble() * 0.64);
      final cy = h * (0.5 + rnd.nextDouble() * 0.45);
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(rnd.nextDouble() * math.pi);
      final slip = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 16, height: 9),
        const Radius.circular(2),
      );
      canvas.drawRRect(slip, Paint()..color = colors[i % colors.length]);
      canvas.drawRRect(
        slip,
        Paint()
          ..color = Kitsune.deep.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
      canvas.restore();
    }
    canvas.restore();
    // Glanzlicht.
    canvas.drawLine(
      Offset(w * 0.2, h * 0.24),
      Offset(w * 0.2, h * 0.5),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawRRect(glass, outline);
  }

  @override
  bool shouldRepaint(JarPainter old) => false;
}
