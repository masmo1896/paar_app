import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/couple_service.dart';
import '../utils/shared_stream.dart';
import '../services/planner_service.dart';
import '../theme.dart';
import '../utils/dates.dart';
import '../widgets/lantern_sky.dart';
import '../widgets/who.dart';
import 'countdown_screen.dart';
import 'us_features.dart';
import '../widgets/motion.dart';

/// Startseite: Begrüssung unter Laternen, dann (1) ungelesene Nachricht,
/// (2) euer Laternenhimmel, (3) Countdown-Ticket, (4) Frage des Tages,
/// danach die Termine von heute und die nächsten To-dos. Die Laternen-
/// Illustration liegt gross im Hintergrund, läuft weich ausgeblendet hinter die
/// Karten und wandert beim Scrollen etwas langsamer mit (Parallax).
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.couple,
    required this.onOpenTab,
    this.active = true,
  });

  final Couple couple;

  /// Ist die Home-Seite gerade zu sehen? (Für den Fuchs-Boten im Laternenhimmel.)
  final bool active;

  /// Wechselt den Tab unten (1 = Chat, 2 = Kalender, 3 = To-dos).
  final ValueChanged<int> onOpenTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final couple = widget.couple;
    final onOpenTab = widget.onOpenTab;
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: Stack(
        children: [
          // Etwas nach oben versetzt, damit die Laternen über der Begrüssung hängen.
          Positioned(
            top: -44,
            left: 0,
            right: 0,
            height: 300 + top,
            child: _ParallaxLanterns(scroll: _scroll),
          ),
          ListView(
            controller: _scroll,
            padding: EdgeInsets.zero,
            children: [
              _Header(couple: couple),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  // Karten erscheinen beim Öffnen sanft nacheinander.
                  children: staggered([
                    // 1. Ungelesene Nachricht (nur wenn es eine gibt)
                    _LastMessage(couple: couple, onOpen: () => onOpenTab(1)),
                    // 2. Unser Laternenhimmel
                    LanternSky(couple: couple, active: widget.active),
                    const SizedBox(height: 16),
                    // 3. Countdown
                    _NextCountdown(couple: couple),
                    const SizedBox(height: 16),
                    // 4. Frage des Tages; verschwindet, wenn beide geantwortet haben.
                    _QuestionOnTop(couple: couple),
                    _Today(couple: couple, onOpenCalendar: () => onOpenTab(2)),
                    const SizedBox(height: 14),
                    _TodoSummary(couple: couple, onOpen: () => onOpenTab(3)),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Grosse Laternen-Illustration im Hintergrund: oben kräftig, nach unten weich
/// ausgeblendet (läuft subtil hinter die Karten). Beim Scrollen wandert sie nur
/// mit 45 % der Geschwindigkeit mit – das gibt Tiefe. Eigene Ebene, damit das
/// Verschieben nichts neu malen muss.
class _ParallaxLanterns extends StatelessWidget {
  const _ParallaxLanterns({required this.scroll});

  final ScrollController scroll;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: scroll,
    builder: (context, child) {
      final offset = scroll.hasClients ? math.max(0.0, scroll.offset) : 0.0;
      return Transform.translate(
        offset: Offset(0, -offset * 0.45),
        child: child,
      );
    },
    child: RepaintBoundary(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            Colors.white,
            Color(0x66FFFFFF),
            Colors.transparent,
          ],
          stops: [0, 0.5, 0.78, 1],
        ).createShader(rect),
        child: SvgPicture.asset(
          KitsuneArt.lanterns.asset,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
      ),
    ),
  );
}

/// Frage des Tages mit Abstand darunter – nur solange sie offen ist.
class _QuestionOnTop extends StatelessWidget {
  const _QuestionOnTop({required this.couple});

  final Couple couple;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DailyQuestionCard(couple: couple, hideWhenDone: true),
  );
}

/// Begrüssung "こんばんは / Guten Abend, Marc / Samstag, 31. Oktober" über den Laternen.
class _Header extends StatelessWidget {
  const _Header({required this.couple});

  final Couple couple;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final (kana, hello) = hour < 11
        ? ('おはよう', 'Guten Morgen')
        : hour < 18
        ? ('こんにちは', 'Guten Tag')
        : ('こんばんは', 'Guten Abend');
    final top = MediaQuery.paddingOf(context).top;

    // Nur Text – die Illustration liegt als Hintergrund dahinter.
    return SizedBox(
      height: 214 + top,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 20,
            right: 20,
            bottom: 26,
            child: StreamBuilder<Map<String, dynamic>?>(
              stream: CoupleService.instance.myProfileStream(),
              builder: (context, snap) {
                final name = (snap.data?['name'] as String?)?.trim();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kana,
                      style: AppTheme.serif(
                        size: 12,
                        weight: FontWeight.w600,
                        color: Kitsune.aqua,
                      ).copyWith(letterSpacing: 3.6),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      name == null || name.isEmpty ? hello : '$hello, $name',
                      style: AppTheme.serif(size: 25).copyWith(
                        shadows: const [
                          Shadow(color: Kitsune.deep, blurRadius: 10),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      longDay(today()),
                      style: const TextStyle(fontSize: 12, color: Kitsune.mist),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Der nächste Countdown als Ticket zwischen zwei Pflaumen-Rollen.
class _NextCountdown extends StatelessWidget {
  const _NextCountdown({required this.couple});

  final Couple couple;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Countdown>>(
      stream: PlannerService.instance.countdowns(couple.coupleId),
      builder: (context, snap) {
        final next = (snap.data ?? []).where((c) => c.daysLeft >= 0).toList()
          ..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
        final c = next.isEmpty ? null : next.first;

        // Bis Mitternacht des Tages: Tage, Stunden, Minuten.
        final left = c == null
            ? Duration.zero
            : DateTime(
                c.next.year,
                c.next.month,
                c.next.day,
              ).difference(DateTime.now());
        final days = left.isNegative ? 0 : left.inDays;

        Widget chip(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: Kitsune.night,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Kitsune.paper,
            ),
          ),
        );

        // Kompaktes Ticket: Zahl, Titel und Restzeit in einer Zeile.
        final ticket = Material(
          color: Kitsune.paper,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CountdownScreen(couple: couple),
              ),
            ),
            child: Container(
              // Doppelter Rahmen: Creme-Rand, dann feine nachtblaue Linie.
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0x4D133174)),
              ),
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: c == null
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Noch kein Countdown – tippe hier, um einen einzutragen.',
                        style: TextStyle(color: Kitsune.night, fontSize: 13),
                      ),
                    )
                  : Row(
                      children: [
                        CountUp(
                          value: days,
                          style: AppTheme.serif(
                            size: 30,
                            color: Kitsune.indigo,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          days == 1 ? 'TAG' : 'TAGE',
                          style: AppTheme.label(color: Kitsune.plum, size: 10),
                        ),
                        Container(
                          width: 1,
                          height: 30,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          color: const Color(0x4D133174),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.serif(
                                  size: 16,
                                  color: Kitsune.night,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Wrap(
                                spacing: 5,
                                children: [
                                  chip('${left.inHours % 24} Std'),
                                  chip('${left.inMinutes % 60} Min'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Hanko('旅', size: 20, filled: false),
                      ],
                    ),
            ),
          ),
        );

        Widget rail(bool left) => Container(
          width: 8,
          decoration: BoxDecoration(
            color: Kitsune.plum,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                offset: Offset(left ? -3 : 3, 0),
                spreadRadius: -1,
              ),
            ],
          ),
        );

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              rail(true),
              Expanded(child: ticket),
              rail(false),
            ],
          ),
        );
      },
    );
  }
}

/// Termine von heute als kleine Zeitleiste.
class _Today extends StatelessWidget {
  const _Today({required this.couple, required this.onOpenCalendar});

  final Couple couple;
  final VoidCallback onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CalEvent>>(
      stream: PlannerService.instance.events(couple.coupleId),
      builder: (context, snap) {
        final now = today();
        final events = (snap.data ?? []).where((e) => e.occursOn(now)).toList()
          ..sort(
            (a, b) =>
                (a.startTime?.hour ?? -1) * 60 +
                (a.startTime?.minute ?? 0) -
                ((b.startTime?.hour ?? -1) * 60 + (b.startTime?.minute ?? 0)),
          );
        final evening = DateTime.now().hour >= 17;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    evening ? 'Heute Abend' : 'Heute',
                    style: AppTheme.serif(size: 17)
                        .copyWith(letterSpacing: 0.7),
                  ),
                ),
                TextButton(
                  onPressed: onOpenCalendar,
                  child: const Text(
                    'Kalender ›',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'Noch frei. Zeit für ein kleines Abenteuer?',
                  style: TextStyle(fontSize: 13, color: Kitsune.mist),
                ),
              )
            else
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Linie mit rotem Punkt oben und Aqua-Ring unten.
                    SizedBox(
                      width: 14,
                      child: Column(
                        children: [
                          const SizedBox(height: 6),
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Kitsune.lantern,
                            ),
                          ),
                          if (events.length > 1) ...[
                            Expanded(
                              child: Container(
                                width: 1,
                                color: const Color(0x66F3EBD3),
                              ),
                            ),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Kitsune.aqua,
                                  width: 2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children: [
                          for (final e in events)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  SizedBox(
                                    width: 54,
                                    child: Text(
                                      e.startTime == null
                                          ? 'Tag'
                                          : timeKey(e.startTime!),
                                      style: AppTheme.serif(size: 16),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      e.title,
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Fortschrittsring "2/4" und die nächsten zwei offenen Aufgaben.
class _TodoSummary extends StatelessWidget {
  const _TodoSummary({required this.couple, required this.onOpen});

  final Couple couple;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Todo>>(
      stream: PlannerService.instance.todos(couple.coupleId),
      builder: (context, snap) {
        final todos = (snap.data ?? []).where((t) => !t.isShopping).toList();
        final done = todos.where((t) => t.done).length;
        final open = todos.where((t) => !t.done).toList()
          ..sort((a, b) {
            final ad = a.due, bd = b.due;
            if (ad == null && bd == null) return 0;
            if (ad == null) return 1;
            if (bd == null) return -1;
            return ad.compareTo(bd);
          });

        return Material(
          color: Kitsune.deep.withValues(alpha: 0.85),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: const BorderSide(color: Color(0x4DF3EBD3)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 54,
                    height: 54,
                    child: CustomPaint(
                      painter: _RingPainter(
                        todos.isEmpty ? 0 : done / todos.length,
                      ),
                      child: Center(
                        child: Text(
                          '$done/${todos.length}',
                          style: AppTheme.serif(size: 15),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ALS NÄCHSTES', style: AppTheme.label(size: 10.5)),
                        const SizedBox(height: 4),
                        Text(
                          open.isEmpty ? 'Alles erledigt' : open.first.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (open.length > 1)
                          Text(
                            open[1].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Kitsune.mist,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: 22);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      paint..color = Kitsune.paper.withValues(alpha: 0.2),
    );
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        paint..color = Kitsune.aqua,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

/// Die neueste Nachricht deines Schatzes, mit rotem Punkt, solange sie ungelesen ist.
class _LastMessage extends StatelessWidget {
  const _LastMessage({required this.couple, required this.onOpen});

  final Couple couple;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final partner = couple.partnerUid;
    if (partner == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // Geteilt, damit nicht bei jedem Neuzeichnen neu geladen wird.
      stream: SharedStreams.get(
        'recentMessages/${couple.coupleId}',
        () => CoupleService.instance
            .messages(couple.coupleId)
            .orderBy('createdAt', descending: true)
            .limit(50)
            .snapshots(),
      ),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final msg = docs
            .map((d) => d.data())
            .where((d) => d['senderId'] == partner && d['type'] != 'deleted')
            .firstOrNull;
        // Nur zeigen, wenn die neueste Nachricht des Schatzes noch ungelesen ist.
        if (msg == null || msg['read'] == true) return const SizedBox.shrink();
        final time = (msg['createdAt'] as Timestamp?)?.toDate();
        const unread = true;
        final name = couple.partnerLabel;

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Material(
            color: Kitsune.paper,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: Kitsune.night,
                      child: Text(
                        name.characters.first.toUpperCase(),
                        style: AppTheme.serif(size: 15, color: Kitsune.paper),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            time == null
                                ? name
                                : '$name · ${timeKey(TimeOfDay.fromDateTime(time))}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Kitsune.plum,
                            ),
                          ),
                          Text(
                            CoupleService.previewOf(msg),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Kitsune.night,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (unread)
                      Container(
                        width: 9,
                        height: 9,
                        margin: const EdgeInsets.only(left: 8),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Kitsune.lantern,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
