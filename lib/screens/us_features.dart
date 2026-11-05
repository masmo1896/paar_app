import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/planner_service.dart';
import '../services/us_service.dart';
import '../theme.dart';
import '../utils/couple_ideas.dart';
import '../utils/dates.dart';
import '../widgets/who.dart';
import 'us_sections.dart';
import '../widgets/motion.dart';
import '../services/app_logger.dart';

const _hint = TextStyle(fontSize: 13, color: Kitsune.mist, height: 1.35);

String _shortDate(DateTime d) =>
    '${d.day}. ${monthsLong[d.month - 1]} ${d.year}';

String _clock(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Öffnungszeitpunkt eines Briefs: «5. November 2026 um 22:00»
/// (ältere Briefe ohne Uhrzeit: nur das Datum).
String _openLabel(DateTime d) => d.hour == 0 && d.minute == 0
    ? _shortDate(d)
    : '${_shortDate(d)} um ${_clock(d)}';

// ===========================================================================
// Frage des Tages

/// Frage des Tages. Erst antworten, dann sieht man die Antwort des Schatzes.
/// Mit [hideWhenDone] (Home-Seite) verschwindet die Karte, sobald beide
/// geantwortet haben; auf der Wir-Seite bleiben beide Antworten stehen.
class DailyQuestionCard extends StatefulWidget {
  const DailyQuestionCard({
    super.key,
    required this.couple,
    this.hideWhenDone = false,
  });

  final Couple couple;
  final bool hideWhenDone;

  @override
  State<DailyQuestionCard> createState() => _DailyQuestionCardState();
}

class _DailyQuestionCardState extends State<DailyQuestionCard> {
  final _service = UsService.instance;
  final _input = TextEditingController();
  bool _sending = false;

  // Der Tag kann wechseln, während die App offen bleibt (Mitternacht).
  late String _day;
  late String _question;
  late Stream<DayQuestion?> _dayStream;
  late Stream<Answer?> _mine;
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    _loadDay();
  }

  void _loadDay() {
    final now = today();
    _day = dayKey(now);
    _question = questionFor(now);
    _dayStream = _service.day(widget.couple.coupleId, _day);
    _mine = _service.answer(widget.couple.coupleId, _day, widget.couple.myUid);
    // Kurz nach Mitternacht auf die neue Frage wechseln.
    _midnight?.cancel();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    _midnight = Timer(next.difference(DateTime.now()), () {
      if (mounted) setState(_loadDay);
    });
  }

  @override
  void dispose() {
    _midnight?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    setState(() => _sending = true);
    try {
      await _service.answerDay(widget.couple.coupleId, _day, _question, text);
      _input.clear();
    } catch (e, s) {
      AppLogger.error(e, s, where: 'Frage des Tages: Antwort speichern');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Nicht gespeichert: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final couple = widget.couple;
    final partnerUid = couple.partnerUid;
    if (partnerUid == null) return const SizedBox.shrink();
    final partner = couple.partnerLabel;

    return StreamBuilder<DayQuestion?>(
      stream: _dayStream,
      builder: (context, daySnap) {
        final answered = daySnap.data?.answered ?? const [];
        final partnerAnswered = answered.contains(partnerUid);
        final iAnswered = answered.contains(couple.myUid);
        if (widget.hideWhenDone && iAnswered && partnerAnswered) {
          return const SizedBox.shrink();
        }
        return UsCard(
          title: 'Frage des Tages',
          trailing: widget.hideWhenDone
              ? null
              : TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => QuestionArchiveScreen(couple: couple),
                    ),
                  ),
                  child: const Text('Archiv ›'),
                ),
          child: StreamBuilder<Answer?>(
            stream: _mine,
            builder: (context, mineSnap) {
              final mine = mineSnap.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _question,
                    style: AppTheme.serif(size: 19).copyWith(height: 1.3),
                  ),
                  const SizedBox(height: 12),
                  if (mine == null) ...[
                    TextField(
                      controller: _input,
                      minLines: 2,
                      maxLines: 6,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Deine Antwort …',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 10),
                    PressScale(
                      child: FilledButton.icon(
                        onPressed: _sending ? null : _send,
                        style: FilledButton.styleFrom(
                          backgroundColor: Kitsune.lantern,
                          foregroundColor: Kitsune.paper,
                        ),
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: const Text('Antwort senden'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _StatusLine(
                      icon: partnerAnswered
                          ? Icons.mark_email_read_outlined
                          : Icons.lock_outline_rounded,
                      text: partnerAnswered
                          ? '$partner hat schon geantwortet – antworte, um es zu lesen.'
                          : 'Die Antwort von $partner siehst du, sobald ihr beide geantwortet habt.',
                    ),
                  ] else ...[
                    _AnswerBubble(who: 'Du', text: mine.text, mine: true),
                    const SizedBox(height: 8),
                    if (partnerAnswered)
                      StreamBuilder<Answer?>(
                        stream: _service.answer(
                          couple.coupleId,
                          _day,
                          partnerUid,
                        ),
                        builder: (context, s) => s.data == null
                            ? const SizedBox.shrink()
                            : _AnswerBubble(
                                who: partner,
                                text: s.data!.text,
                                mine: false,
                              ),
                      )
                    else
                      _StatusLine(
                        icon: Icons.hourglass_empty_rounded,
                        text: 'Warte auf die Antwort von $partner …',
                      ),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 15, color: Kitsune.mist),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, color: Kitsune.mist),
        ),
      ),
    ],
  );
}

/// Antwort als kleine Papierkarte: eigene leicht aqua, die des Schatzes creme.
class _AnswerBubble extends StatelessWidget {
  const _AnswerBubble({
    required this.who,
    required this.text,
    required this.mine,
  });

  final String who;
  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
    decoration: BoxDecoration(
      color: mine ? Kitsune.aqua : Kitsune.paper,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          who,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Kitsune.plum,
          ),
        ),
        const SizedBox(height: 2),
        Text(text, style: const TextStyle(fontSize: 15, color: Kitsune.night)),
      ],
    ),
  );
}

/// Frühere Fragen: Antippen zeigt beide Antworten (wenn beide geantwortet haben).
class QuestionArchiveScreen extends StatelessWidget {
  const QuestionArchiveScreen({super.key, required this.couple});

  final Couple couple;

  @override
  Widget build(BuildContext context) {
    final partnerUid = couple.partnerUid;
    return Scaffold(
      appBar: kitsuneAppBar(
        art: KitsuneArt.koi,
        kana: 'しつもん',
        titleText: 'Unsere Antworten',
        height: 96,
      ),
      body: StreamBuilder<List<(String, DayQuestion)>>(
        stream: UsService.instance.archive(couple.coupleId),
        builder: (context, snap) {
          final days = snap.data ?? const [];
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (days.isEmpty) {
            return const Center(
              child: Text('Noch keine Antworten 💬', style: _hint),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: days.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final (day, q) = days[i];
              final date = parseDayKey(day) ?? today();
              final both =
                  partnerUid != null &&
                  q.answered.contains(couple.myUid) &&
                  q.answered.contains(partnerUid);
              return UsCard(
                title: _shortDate(date),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(q.question, style: AppTheme.serif(size: 16)),
                    const SizedBox(height: 10),
                    for (final (uid, who) in [
                      (couple.myUid, 'Du'),
                      if (partnerUid != null) (partnerUid, couple.partnerLabel),
                    ])
                      if (q.answered.contains(uid) &&
                          (both || uid == couple.myUid))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: StreamBuilder<Answer?>(
                            stream: UsService.instance.answer(
                              couple.coupleId,
                              day,
                              uid,
                            ),
                            builder: (context, s) => s.data == null
                                ? const SizedBox.shrink()
                                : _AnswerBubble(
                                    who: who,
                                    text: s.data!.text,
                                    mine: uid == couple.myUid,
                                  ),
                          ),
                        ),
                    if (!both)
                      const _StatusLine(
                        icon: Icons.lock_outline_rounded,
                        text: 'Nicht von beiden beantwortet.',
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ===========================================================================
// Liebesbriefe mit Zeitschloss

class LoveLettersCard extends StatelessWidget {
  const LoveLettersCard({super.key, required this.couple});

  final Couple couple;

  @override
  Widget build(BuildContext context) {
    final partner = couple.partnerLabel;
    return UsCard(
      title: 'Liebesbriefe',
      child: StreamBuilder<List<Letter>>(
        stream: UsService.instance.letters(couple.coupleId),
        builder: (context, snap) {
          final letters = snap.data ?? const [];
          // Zuerst Briefe, die ich jetzt öffnen kann, dann versiegelte, dann gelesene.
          int rank(Letter l) {
            if (l.to == couple.myUid && l.canOpen && l.openedAt == null) {
              return 0;
            }
            if (!l.canOpen) return 1;
            return 2;
          }

          final sorted = [...letters]
            ..sort((a, b) {
              final r = rank(a).compareTo(rank(b));
              return r != 0 ? r : a.openAt.compareTo(b.openAt);
            });
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sorted.isEmpty)
                Row(
                  children: [
                    const EnvelopeIcon(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Schreib $partner einen Brief, der sich erst an einem '
                        'bestimmten Tag öffnen lässt – zum Jahrestag, Geburtstag '
                        'oder einfach so.',
                        style: _hint,
                      ),
                    ),
                  ],
                )
              else
                for (final l in sorted.take(5))
                  _LetterRow(couple: couple, letter: l),
              const SizedBox(height: 12),
              PressScale(
                child: FilledButton.icon(
                  onPressed: couple.partnerUid == null
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            fullscreenDialog: true,
                            builder: (_) => LetterComposer(couple: couple),
                          ),
                        ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Kitsune.paper.withValues(alpha: 0.1),
                    foregroundColor: Kitsune.paper,
                  ),
                  icon: const Icon(Icons.mail_outline_rounded, size: 18),
                  label: const Text('Brief schreiben'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LetterRow extends StatelessWidget {
  const _LetterRow({required this.couple, required this.letter});

  final Couple couple;
  final Letter letter;

  @override
  Widget build(BuildContext context) {
    final l = letter;
    final toMe = l.to == couple.myUid;
    final partner = couple.partnerLabel;
    final days = l.openAt.difference(DateTime.now()).inHours / 24;
    final daysLeft = days.ceil();
    final (title, subtitle, highlight) = switch ((
      toMe,
      l.canOpen,
      l.openedAt != null,
    )) {
      (true, true, false) => ('Brief von $partner', 'Jetzt öffnen! 💌', true),
      (true, false, _) => (
        'Brief von $partner',
        'öffnet sich ${sameDay(l.openAt, DateTime.now()) ? 'heute um ${_clock(l.openAt)}' : 'am ${_openLabel(l.openAt)}'}'
            '${sameDay(l.openAt, DateTime.now()) ? '' : ' · ${daysLeft <= 1 ? 'morgen' : 'in $daysLeft Tagen'}'}',
        false,
      ),
      (true, true, true) => (
        'Brief von $partner',
        'gelesen · nochmals lesen',
        false,
      ),
      (false, false, _) => (
        'Dein Brief an $partner',
        'öffnet sich am ${_openLabel(l.openAt)}',
        false,
      ),
      (false, true, true) => (
        'Dein Brief an $partner',
        '$partner hat ihn gelesen ✓',
        false,
      ),
      (false, true, false) => (
        'Dein Brief an $partner',
        'kann jetzt geöffnet werden',
        false,
      ),
    };
    // Eigene Briefe darf man immer lesen; fremde erst ab dem Datum.
    final canRead = !toMe || l.canOpen;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: canRead
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LetterPage(couple: couple, letter: l),
              ),
            )
          : () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Noch versiegelt – öffnet sich am ${_openLabel(l.openAt)}.',
                ),
              ),
            ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Opacity(
              opacity: canRead ? 1 : 0.6,
              child: const EnvelopeIcon(width: 44),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15)),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: highlight ? Kitsune.lantern : Kitsune.mist,
                      fontWeight: highlight
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              canRead
                  ? Icons.chevron_right_rounded
                  : Icons.lock_outline_rounded,
              color: Kitsune.mist,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Brief schreiben: Text auf Papier, darunter wann er sich öffnen lässt.
class LetterComposer extends StatefulWidget {
  const LetterComposer({super.key, required this.couple});

  final Couple couple;

  @override
  State<LetterComposer> createState() => _LetterComposerState();
}

class _LetterComposerState extends State<LetterComposer> {
  final _text = TextEditingController();
  // Standard: in einer Woche um 08:00.
  DateTime _openAt = DateTime(today().year, today().month, today().day + 7, 8);
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _openAt.isBefore(today()) ? today() : _openAt,
      firstDate: today(),
      lastDate: today().add(const Duration(days: 3650)),
      helpText: 'Wann darf der Brief geöffnet werden?',
    );
    if (picked != null) _setDate(picked);
  }

  /// Datum ändern, Uhrzeit behalten.
  void _setDate(DateTime d) => setState(
    () => _openAt = DateTime(
      d.year,
      d.month,
      d.day,
      _openAt.hour,
      _openAt.minute,
    ),
  );

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_openAt),
      helpText: 'Um wie viel Uhr?',
    );
    if (picked == null) return;
    setState(
      () => _openAt = DateTime(
        _openAt.year,
        _openAt.month,
        _openAt.day,
        picked.hour,
        picked.minute,
      ),
    );
  }

  Future<void> _send() async {
    if (_text.text.trim().isEmpty || _sending) return;
    if (!_openAt.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wähle einen Zeitpunkt in der Zukunft.')),
      );
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await UsService.instance.sendLetter(
        widget.couple.coupleId,
        to: widget.couple.partnerUid!,
        text: _text.text,
        openAt: _openAt,
      );
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Brief versiegelt 💌 – ${widget.couple.partnerLabel} kann ihn am '
            '${_openLabel(_openAt)} öffnen.',
          ),
        ),
      );
    } catch (e, s) {
      AppLogger.error(e, s, where: 'Liebesbrief senden');
      messenger.showSnackBar(SnackBar(content: Text('Nicht gesendet: $e')));
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = today();
    final chips = [
      ('Heute', t),
      ('Morgen', t.add(const Duration(days: 1))),
      ('In 1 Woche', t.add(const Duration(days: 7))),
      ('In 1 Monat', DateTime(t.year, t.month + 1, t.day)),
      ('In 1 Jahr', DateTime(t.year + 1, t.month, t.day)),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('Brief an ${widget.couple.partnerLabel}'),
        actions: [
          TextButton(
            onPressed: _sending ? null : _send,
            child: const Text('Versiegeln'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Briefpapier: creme mit dunkler Schrift.
          Paper(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Kitsune.paper,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Kitsune.hairline),
              ),
              child: TextField(
                controller: _text,
                minLines: 12,
                maxLines: null,
                maxLength: 5000,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                style: AppTheme.serif(
                  size: 17,
                  color: Kitsune.night,
                ).copyWith(height: 1.5),
                decoration: InputDecoration(
                  hintText: 'Liebe/r ${widget.couple.partnerLabel}, …',
                  border: InputBorder.none,
                  filled: false,
                  counterText: '',
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Öffnet sich am', style: AppTheme.serif(size: 16)),
          const SizedBox(height: 4),
          Text(
            _openLabel(_openAt),
            style: AppTheme.serif(size: 22, color: Kitsune.aqua),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, date) in chips)
                ChoiceChip(
                  label: Text(label),
                  selected: sameDay(_openAt, date),
                  showCheckmark: false,
                  selectedColor: Kitsune.paper,
                  labelStyle: TextStyle(
                    color: sameDay(_openAt, date)
                        ? Kitsune.night
                        : Kitsune.paper,
                  ),
                  onSelected: (_) => _setDate(date),
                ),
              ActionChip(
                avatar: const Icon(Icons.calendar_month_outlined, size: 18),
                label: const Text('Datum wählen'),
                onPressed: _pickDate,
              ),
              ActionChip(
                avatar: const Icon(Icons.schedule_rounded, size: 18),
                label: Text('Uhrzeit: ${_clock(_openAt)}'),
                onPressed: _pickTime,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Bis dahin sieht ${widget.couple.partnerLabel} nur einen versiegelten '
            'Umschlag – der Text bleibt auch auf dem Server verschlossen.',
            style: _hint,
          ),
        ],
      ),
    );
  }
}

/// Einen Brief lesen (auf Briefpapier). Beim ersten Öffnen: als gelesen merken.
class LetterPage extends StatefulWidget {
  const LetterPage({super.key, required this.couple, required this.letter});

  final Couple couple;
  final Letter letter;

  @override
  State<LetterPage> createState() => _LetterPageState();
}

class _LetterPageState extends State<LetterPage> {
  late final Future<String> _text = UsService.instance.letterText(
    widget.couple.coupleId,
    widget.letter.id,
  );

  @override
  void initState() {
    super.initState();
    final l = widget.letter;
    if (l.to == widget.couple.myUid && l.openedAt == null) {
      unawaited(
        UsService.instance
            .markLetterOpened(widget.couple.coupleId, l.id)
            .catchError((_) {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.letter;
    final fromMe = l.from == widget.couple.myUid;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          fromMe ? 'Dein Brief' : 'Brief von ${widget.couple.partnerLabel}',
        ),
      ),
      body: FutureBuilder<String>(
        future: _text,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
              child: Text('Dieser Brief ist noch versiegelt.', style: _hint),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Paper(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
                  decoration: BoxDecoration(
                    color: Kitsune.paper,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Kitsune.hairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Hanko('愛', size: 28),
                          const Spacer(),
                          Text(
                            _shortDate(l.createdAt ?? l.openAt),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Kitsune.inkSoft,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        snap.data!,
                        style: AppTheme.serif(
                          size: 18,
                          color: Kitsune.night,
                        ).copyWith(height: 1.55),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ===========================================================================
// Date-Glas

class DateJarCard extends StatefulWidget {
  const DateJarCard({super.key, required this.couple});

  final Couple couple;

  @override
  State<DateJarCard> createState() => _DateJarCardState();
}

class _DateJarCardState extends State<DateJarCard>
    with SingleTickerProviderStateMixin {
  late final _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final _custom = UsService.instance.dateIdeas(widget.couple.coupleId);
  final _random = math.Random();
  Idea? _idea; // gezogene Idee (id leer = Vorschlag)

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Future<void> _draw(List<Idea> pool) async {
    await _shake.forward(from: 0);
    if (!mounted || pool.isEmpty) return;
    Idea next;
    do {
      next = pool[_random.nextInt(pool.length)];
    } while (next.text == _idea?.text && pool.length > 1);
    setState(() => _idea = next);
  }

  Future<void> _addOwn() async {
    final text = await askText(
      context,
      title: 'Eigene Date-Idee',
      hint: 'z. B. Zusammen Sushi rollen',
    );
    if (text == null || text.trim().isEmpty) return;
    await UsService.instance.addDateIdea(widget.couple.coupleId, text);
  }

  Future<void> _plan(Idea idea) async {
    final date = await showDatePicker(
      context: context,
      initialDate: today(),
      firstDate: today(),
      lastDate: today().add(const Duration(days: 730)),
      helpText: 'Wann machen wir das?',
    );
    if (date == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await PlannerService.instance.saveEvent(
      widget.couple.coupleId,
      title: idea.text,
      who: both,
      start: date,
      end: date,
    );
    messenger.showSnackBar(
      SnackBar(content: Text('Im Kalender eingetragen: ${longDay(date)} 📅')),
    );
    if (mounted) setState(() => _idea = null);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Idea>>(
      stream: _custom,
      builder: (context, snap) {
        final custom = snap.data ?? const [];
        final pool = [
          for (final t in suggestedDateIdeas) Idea(id: '', text: t),
          ...custom,
        ];
        final idea = _idea;
        return UsCard(
          title: 'Date-Glas',
          trailing: Text(
            '${pool.length} Ideen',
            style: const TextStyle(fontSize: 12, color: Kitsune.mist),
          ),
          child: Row(
            children: [
              Semantics(
                button: true,
                label: 'Glas schütteln und eine Date-Idee ziehen',
                child: GestureDetector(
                  onTap: () => _draw(pool),
                  child: AnimatedBuilder(
                    animation: _shake,
                    builder: (context, child) => Transform.rotate(
                      angle:
                          math.sin(_shake.value * math.pi * 6) *
                          0.12 *
                          (1 - _shake.value),
                      child: child,
                    ),
                    child: const SizedBox(
                      width: 64,
                      height: 80,
                      child: CustomPaint(painter: JarPainter()),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  // Linksbündig statt (Standard) zentriert.
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, ?current],
                  ),
                  child: idea == null
                      ? Column(
                          key: const ValueKey('leer'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Tipp aufs Glas und zieh eine zufällige Date-Idee.',
                              style: _hint,
                            ),
                            const SizedBox(height: 6),
                            TextButton.icon(
                              onPressed: _addOwn,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Eigene Idee hineinlegen'),
                            ),
                          ],
                        )
                      : Column(
                          key: ValueKey(idea.text),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              idea.text,
                              style: AppTheme.serif(size: 17)
                                  .copyWith(height: 1.3),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                PressScale(
                                  child: FilledButton(
                                    onPressed: () => _plan(idea),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Kitsune.lantern,
                                      foregroundColor: Kitsune.paper,
                                      minimumSize: const Size(0, 38),
                                    ),
                                    child: const Text('Machen wir!'),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _draw(pool),
                                  child: const Text('Nochmals'),
                                ),
                                // Eigene Ideen kann man wieder herausnehmen.
                                if (idea.id.isNotEmpty)
                                  IconButton(
                                    tooltip: 'Idee aus dem Glas nehmen',
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Kitsune.mist,
                                    ),
                                    onPressed: () async {
                                      await UsService.instance.deleteDateIdea(
                                        widget.couple.coupleId,
                                        idea.id,
                                      );
                                      setState(() => _idea = null);
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
