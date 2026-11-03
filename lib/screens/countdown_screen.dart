import 'package:flutter/material.dart';

import '../services/planner_service.dart';
import '../theme.dart';
import '../utils/dates.dart';
import '../widgets/motion.dart';
import '../widgets/who.dart';

/// Countdowns zu wichtigen Tagen: Urlaub, Jahrestag, Geburtstag …
/// Der nächste steht gross oben, vergangene einmalige Tage unten bei "Vergangen".
class CountdownScreen extends StatelessWidget {
  const CountdownScreen({super.key, required this.couple, this.heroTag});

  final Couple couple;

  /// Von der Home-Karte geöffnet: Seite zieht sich aus der Karte auf.
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final page = _page(context);
    return heroTag == null ? page : ExpandHero(tag: heroTag!, child: page);
  }

  Widget _page(BuildContext context) {
    return Scaffold(
      appBar: kitsuneAppBar(
        art: KitsuneArt.lanterns,
        kana: 'あといくつ',
        titleText: 'Countdown',
        height: 104,
      ),
      body: StreamBuilder<List<Countdown>>(
        stream: PlannerService.instance.countdowns(couple.coupleId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data!;
          // Bevorstehende: nächster zuerst. Vergangene: zuletzt Vergangenes zuerst.
          final upcoming = all.where((c) => c.daysLeft >= 0).toList()
            ..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
          final past = all.where((c) => c.daysLeft < 0).toList()
            ..sort((a, b) => b.daysLeft.compareTo(a.daysLeft));

          if (all.isEmpty) {
            return const Center(
              child: Text(
                'Noch kein Countdown ✈️\nMit + legst du einen an, z. B. für euren Urlaub.',
                textAlign: TextAlign.center,
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              for (var i = 0; i < upcoming.length; i++)
                _CountdownCard(
                  countdown: upcoming[i],
                  hero: i == 0,
                  onTap: (c) => _edit(context, c),
                ),
              if (past.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
                  child: Text(
                    'Vergangen',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final c in past)
                  _CountdownCard(
                    countdown: c,
                    hero: false,
                    onTap: (c) => _edit(context, c),
                  ),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        // Kein eigener Hero: die ganze Seite fliegt schon als ExpandHero.
        heroTag: null,
        tooltip: 'Countdown hinzufügen',
        onPressed: () => _edit(context, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _edit(BuildContext context, Countdown? countdown) =>
      showCountdownForm(context, couple, countdown: countdown);
}

/// Countdown anlegen oder bearbeiten (auch aus dem Kalender, dann mit [date]).
Future<void> showCountdownForm(
  BuildContext context,
  Couple couple, {
  Countdown? countdown,
  DateTime? date,
}) => showFormSheet<void>(
  context,
  (_) => _CountdownForm(couple: couple, countdown: countdown, date: date),
);

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({
    required this.countdown,
    required this.hero,
    required this.onTap,
  });

  final Countdown countdown;
  final bool hero; // der nächste Countdown: grösser und farbig
  final ValueChanged<Countdown> onTap;

  @override
  Widget build(BuildContext context) {
    final days = countdown.daysLeft;

    // Zahl gross, darunter das Wort: "12" "Tage", "Morgen", "Heute".
    final (big, small) = switch (days) {
      0 => ('Heute', ''),
      1 => ('Morgen', ''),
      < 0 => ('${-days}', days == -1 ? 'Tag her' : 'Tage her'),
      _ => ('$days', 'Tage'),
    };

    final since = countdown.daysSince;
    final dateLine = countdown.yearly
        ? 'Jedes Jahr am ${countdown.date.day}. ${monthsLong[countdown.date.month - 1]}'
        : longDay(countdown.date) +
              (countdown.date.year == DateTime.now().year
                  ? ''
                  : ' ${countdown.date.year}');

    // Papier-Ticket: links und rechts pflaumenfarbene Rollen wie bei einer Schriftrolle.
    // Der nächste Countdown ist grösser: "NOCH 13 TAGE" und ein roter 旅-Stempel.
    final card = Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(countdown),
        child: Padding(
          padding: EdgeInsets.all(hero ? 16 : 12),
          child: Row(
            children: [
              SizedBox(
                width: hero ? 82 : 64,
                child: Column(
                  children: [
                    if (hero && days > 1)
                      Text('NOCH', style: AppTheme.label(color: Kitsune.plum)),
                    Text(
                      big,
                      maxLines: 1,
                      style: AppTheme.serif(
                        size: big.length > 3 ? 22 : (hero ? 52 : 34),
                        color: Kitsune.indigo,
                        height: 1.05,
                      ),
                    ),
                    if (small.isNotEmpty)
                      Text(
                        small.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: AppTheme.label(color: Kitsune.plum, size: 10.5),
                      ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: hero ? 76 : 52,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: Kitsune.hairline,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hero)
                      Text(
                        'ALS NÄCHSTES',
                        style: AppTheme.label(color: Kitsune.plum, size: 10.5),
                      ),
                    Text(
                      '${countdown.emoji}  ${countdown.title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.serif(size: hero ? 18 : 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateLine,
                      style: const TextStyle(
                        color: Kitsune.inkSoft,
                        fontSize: 12.5,
                      ),
                    ),
                    // Bei Jahrestagen: wie lange es das schon gibt.
                    if (countdown.yearly && since != null)
                      Text(
                        'Seit $since Tagen',
                        style: const TextStyle(
                          color: Kitsune.inkSoft,
                          fontSize: 12.5,
                        ),
                      ),
                  ],
                ),
              ),
              if (hero) const Hanko('旅', size: 24, filled: false),
            ],
          ),
        ),
      ),
    );

    Widget rail(bool left) => Container(
      width: hero ? 12 : 8,
      decoration: BoxDecoration(
        color: Kitsune.plum,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            offset: Offset(left ? -3 : 3, 0),
            blurRadius: 0,
            spreadRadius: -1,
          ),
        ],
      ),
    );

    return Paper(
      child: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              rail(true),
              Expanded(child: card),
              rail(false),
            ],
          ),
        ),
      ),
    );
  }
}

/// Formular zum Anlegen und Bearbeiten eines Countdowns.
class _CountdownForm extends StatefulWidget {
  const _CountdownForm({
    required this.couple,
    required this.countdown,
    this.date,
  });

  final Couple couple;
  final Countdown? countdown;

  /// Vorgewähltes Datum für einen neuen Countdown.
  final DateTime? date;

  @override
  State<_CountdownForm> createState() => _CountdownFormState();
}

class _CountdownFormState extends State<_CountdownForm> {
  static const _emojis = [
    '✈️',
    '🏖️',
    '💍',
    '❤️',
    '🎂',
    '🎉',
    '🏠',
    '🎁',
    '🎓',
    '🚗',
  ];

  late final _title = TextEditingController(
    text: widget.countdown?.title ?? '',
  );
  late String _emoji = widget.countdown?.emoji ?? _emojis.first;
  late DateTime _date =
      widget.countdown?.date ??
      widget.date ??
      today().add(const Duration(days: 30));
  late bool _yearly = widget.countdown?.yearly ?? false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    await PlannerService.instance.saveCountdown(
      widget.couple.coupleId,
      id: widget.countdown?.id,
      title: title,
      date: _date,
      emoji: _emoji,
      yearly: _yearly,
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirmDelete(context, 'Countdown')) return;
    await PlannerService.instance.deleteCountdown(
      widget.couple.coupleId,
      widget.countdown!.id,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.countdown == null ? 'Neuer Countdown' : 'Countdown bearbeiten',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _title,
          autofocus: widget.countdown == null,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 100,
          decoration: const InputDecoration(
            labelText: 'Worauf freut ihr euch?',
            hintText: 'z. B. Urlaub in Lissabon',
            counterText: '',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in _emojis)
              ChoiceChip(
                label: Text(e, style: const TextStyle(fontSize: 22)),
                selected: e == _emoji,
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                onSelected: (_) => setState(() => _emoji = e),
              ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.event_outlined),
          label: Text(
            longDay(_date) +
                (_date.year == DateTime.now().year ? '' : ' ${_date.year}'),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Jedes Jahr wiederholen'),
          subtitle: const Text('Für Jahrestage und Geburtstage'),
          value: _yearly,
          onChanged: (v) => setState(() => _yearly = v),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _saving || _title.text.trim().isEmpty ? null : _save,
          child: const Text('Speichern'),
        ),
        if (widget.countdown != null)
          TextButton.icon(
            onPressed: _delete,
            icon: Icon(Icons.delete_outline, color: scheme.error),
            label: Text(
              'Countdown löschen',
              style: TextStyle(color: scheme.error),
            ),
          ),
      ],
    );
  }
}
