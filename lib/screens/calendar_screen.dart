import 'package:flutter/material.dart';

import '../theme.dart';
import '../services/planner_service.dart';
import '../utils/dates.dart';
import '../widgets/who.dart';

/// Gemeinsamer Kalender: Monatsansicht, darunter die Termine (und fälligen Aufgaben)
/// des gewählten Tages. Punkte unter den Zahlen zeigen, wem ein Termin gehört.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.couple});

  final Couple couple;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month = DateTime(today().year, today().month);
  late DateTime _selected = today();

  Couple get couple => widget.couple;

  void _goToMonth(DateTime month) => setState(() {
    _month = DateTime(month.year, month.month);
    // Im aktuellen Monat gleich "heute" wählen, sonst den 1.
    _selected = sameDay(DateTime(today().year, today().month), _month)
        ? today()
        : _month;
  });

  void _goToday() => _goToMonth(today());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Kopfzeile mit Ahornblättern: Jahr und japanischer Monatsname klein darüber.
      appBar: kitsuneAppBar(
        art: KitsuneArt.leaves,
        kana: '${_month.year} · ${_kanjiMonths[_month.month - 1]}',
        titleText: monthsLong[_month.month - 1],
        actions: [
          for (final (tip, icon, onTap) in [
            (
              'Vorheriger Monat',
              Icons.chevron_left_rounded,
              () => _goToMonth(DateTime(_month.year, _month.month - 1)),
            ),
            ('Heute', Icons.today_outlined, _goToday),
            (
              'Nächster Monat',
              Icons.chevron_right_rounded,
              () => _goToMonth(DateTime(_month.year, _month.month + 1)),
            ),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                tooltip: tip,
                icon: Icon(icon),
                onPressed: onTap,
                style: IconButton.styleFrom(
                  backgroundColor: Kitsune.deep.withValues(alpha: 0.8),
                  side: const BorderSide(color: Color(0x73F3EBD3)),
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<CalEvent>>(
        stream: PlannerService.instance.events(couple.coupleId),
        builder: (context, eventSnap) => StreamBuilder<List<Todo>>(
          stream: PlannerService.instance.todos(couple.coupleId),
          builder: (context, todoSnap) {
            if (!eventSnap.hasData || !todoSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return _body(context, eventSnap.data!, todoSnap.data!);
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Termin hinzufügen',
        onPressed: () => _editEvent(null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _body(BuildContext context, List<CalEvent> events, List<Todo> todos) {
    final scheme = Theme.of(context).colorScheme;
    final dayEvents = events.where((e) => e.occursOn(_selected)).toList()
      ..sort((a, b) {
        // Ganztägige zuerst, dann nach Uhrzeit.
        final at = a.startTime == null
            ? -1
            : a.startTime!.hour * 60 + a.startTime!.minute;
        final bt = b.startTime == null
            ? -1
            : b.startTime!.hour * 60 + b.startTime!.minute;
        return at.compareTo(bt);
      });
    final dayTodos = todos
        .where((t) => t.due != null && sameDay(t.due!, _selected))
        .toList();

    return GestureDetector(
      // Nach links/rechts wischen = Monat wechseln.
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -300) _goToMonth(DateTime(_month.year, _month.month + 1));
        if (v > 300) _goToMonth(DateTime(_month.year, _month.month - 1));
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _MonthGrid(
              month: _month,
              selected: _selected,
              events: events,
              couple: couple,
              onSelect: (d) => setState(() => _selected = d),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final who in [both, couple.myUid, ?couple.partnerUid]) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: whoColors(context, couple, who).bg,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    couple.label(who),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
              ],
            ),
          ),
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  // Gewählter Tag in Mincho mit feiner Linie bis zum Rand.
                  Row(
                    children: [
                      Text(
                        sameDay(_selected, today())
                            ? 'Heute · ${longDay(_selected)}'
                            : longDay(_selected),
                        style: AppTheme.serif(size: 17),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(height: 1, color: scheme.outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (dayEvents.isEmpty && dayTodos.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Nichts geplant.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  for (final e in dayEvents)
                    _EventTile(event: e, couple: couple, onTap: _editEvent),
                  for (final t in dayTodos)
                    _DueTodoTile(todo: t, couple: couple),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editEvent(CalEvent? event) => showFormSheet<void>(
    context,
    (_) => _EventForm(couple: couple, event: event, initialDay: _selected),
  );
}

// Japanische Monatsnamen für die kleine Zeile über dem Titel.
const _kanjiMonths = [
  '一月',
  '二月',
  '三月',
  '四月',
  '五月',
  '六月',
  '七月',
  '八月',
  '九月',
  '十月',
  '十一月',
  '十二月',
];

/// Monatsraster, Montag zuerst.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.events,
    required this.couple,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final List<CalEvent> events;
  final Couple couple;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading =
        DateTime(month.year, month.month, 1).weekday -
        1; // Leerfelder vor dem 1.
    final rows = ((leading + daysInMonth) / 7).ceil();

    return Column(
      children: [
        Row(
          children: [
            for (final d in weekdaysShort)
              Expanded(
                child: Center(
                  child: Text(
                    d.toUpperCase(),
                    style: AppTheme.label(size: 10.5),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: _cell(context, r * 7 + c - leading + 1, daysInMonth),
                ),
            ],
          ),
      ],
    );
  }

  Widget _cell(BuildContext context, int dayNumber, int daysInMonth) {
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: 46);
    }
    final scheme = Theme.of(context).colorScheme;
    final day = DateTime(month.year, month.month, dayNumber);
    final isSelected = sameDay(day, selected);
    final isToday = sameDay(day, today());
    // Höchstens drei verschiedene Farbpunkte pro Tag.
    final owners = {for (final e in events.where((e) => e.occursOn(day))) e.who}
        .take(3)
        .toList();

    // Mehrtägige Termine (z. B. "Wochenende am See") als durchgehendes Band,
    // abgerundet am ersten und letzten Tag bzw. am Wochenanfang und -ende.
    final trip = events.where((e) => e.multiDay && e.occursOn(day)).firstOrNull;
    final band = trip == null
        ? null
        : Positioned(
            left: 0,
            right: 0,
            top: 6,
            height: 34,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: whoColors(
                  context,
                  couple,
                  trip.who,
                ).bg.withValues(alpha: 0.22),
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(
                    sameDay(day, trip.start) || day.weekday == 1 ? 17 : 0,
                  ),
                  right: Radius.circular(
                    sameDay(day, trip.end) || day.weekday == 7 ? 17 : 0,
                  ),
                ),
              ),
            ),
          );

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => onSelect(day),
      child: SizedBox(
        height: 46,
        child: Stack(
          children: [
            ?band,
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Gewählter Tag: roter, leicht schräger Stempel mit Doppelrand.
                  Transform.rotate(
                    angle: isSelected ? -0.1 : 0,
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected ? Kitsune.lantern : null,
                        border: isToday && !isSelected
                            ? Border.all(color: Kitsune.lantern, width: 1.5)
                            : null,
                        boxShadow: isSelected
                            ? const [
                                BoxShadow(
                                  color: Kitsune.night,
                                  spreadRadius: 2,
                                ),
                                BoxShadow(
                                  color: Kitsune.lantern,
                                  spreadRadius: 3.5,
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        '$dayNumber',
                        style: AppTheme.serif(
                          size: 15,
                          color: isSelected
                              ? Kitsune.paper
                              : day.weekday >= 6
                              ? Kitsune.aqua
                              : scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    height: 5,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final who in owners)
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: whoColors(context, couple, who).bg,
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
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.couple,
    required this.onTap,
  });

  final CalEvent event;
  final Couple couple;
  final ValueChanged<CalEvent> onTap;

  String _meta(BuildContext context) {
    final parts = <String>[];
    final start = event.startTime;
    if (start == null) {
      parts.add('Ganztägig');
    } else {
      final end = event.endTime;
      parts.add(
        end == null
            ? start.format(context)
            : '${start.format(context)} – ${end.format(context)}',
      );
    }
    if (event.multiDay) {
      parts.add('${shortDay(event.start)} – ${shortDay(event.end)}');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) => Paper(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(event),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 5,
                color: whoColors(context, couple, event.who).bg,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.title, style: AppTheme.serif(size: 15)),
                      const SizedBox(height: 2),
                      Text(
                        _meta(context),
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (event.note.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            event.note,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: WhoPill(couple: couple, who: event.who),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aufgabe, die an diesem Tag fällig ist (abhakbar, wie in der To-do-Liste).
class _DueTodoTile extends StatelessWidget {
  const _DueTodoTile({required this.todo, required this.couple});

  final Todo todo;
  final Couple couple;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconButton(
          tooltip: todo.done ? 'Wieder öffnen' : 'Abhaken',
          onPressed: () => PlannerService.instance.setTodoDone(
            couple.coupleId,
            todo.id,
            !todo.done,
          ),
          icon: todo.done
              ? const Hanko('済', size: 24)
              : Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Kitsune.paper, width: 2),
                  ),
                ),
        ),
        Expanded(
          child: Text(
            'Aufgabe: ${todo.title}',
            style: TextStyle(
              decoration: todo.done ? TextDecoration.lineThrough : null,
              color: todo.done ? scheme.onSurfaceVariant : null,
            ),
          ),
        ),
        WhoPill(couple: couple, who: todo.assignee),
      ],
    );
  }
}

/// Formular zum Anlegen und Bearbeiten eines Termins.
class _EventForm extends StatefulWidget {
  const _EventForm({
    required this.couple,
    required this.event,
    required this.initialDay,
  });

  final Couple couple;
  final CalEvent? event;
  final DateTime initialDay;

  @override
  State<_EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<_EventForm> {
  late final _title = TextEditingController(text: widget.event?.title ?? '');
  late final _note = TextEditingController(text: widget.event?.note ?? '');
  late String _who = widget.event?.who ?? both;
  late DateTime _start = widget.event?.start ?? widget.initialDay;
  late DateTime _end = widget.event?.end ?? widget.initialDay;
  late bool _allDay = widget.event?.allDay ?? true;
  late TimeOfDay _startTime =
      widget.event?.startTime ?? const TimeOfDay(hour: 18, minute: 0);
  late TimeOfDay? _endTime = widget.event?.endTime;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDate(DateTime initial, {DateTime? first}) =>
      showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: first ?? DateTime(2020),
        lastDate: DateTime(2100),
      );

  Future<void> _pickStartDate() async {
    final d = await _pickDate(_start);
    if (d == null) return;
    setState(() {
      // Das Ende rutscht mit, damit es nie vor dem Anfang liegt.
      final length = _end.difference(_start);
      _start = d;
      _end = d.add(length);
    });
  }

  Future<void> _pickEndDate() async {
    final d = await _pickDate(_end, first: _start);
    if (d != null) setState(() => _end = d);
  }

  Future<void> _pickTime(bool start) async {
    final t = await showTimePicker(
      context: context,
      initialTime: start ? _startTime : (_endTime ?? _startTime),
    );
    if (t != null) setState(() => start ? _startTime = t : _endTime = t);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    await PlannerService.instance.saveEvent(
      widget.couple.coupleId,
      id: widget.event?.id,
      title: title,
      who: _who,
      start: _start,
      end: _end,
      startTime: _allDay ? null : _startTime,
      endTime: _allDay ? null : _endTime,
      note: _note.text.trim(),
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirmDelete(context, 'Termin')) return;
    await PlannerService.instance.deleteEvent(
      widget.couple.coupleId,
      widget.event!.id,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = Theme.of(context).textTheme.labelLarge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.event == null ? 'Neuer Termin' : 'Termin bearbeiten',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _title,
          autofocus: widget.event == null,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 200,
          decoration: const InputDecoration(
            labelText: 'Titel',
            counterText: '',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        Text('Für wen?', style: label),
        const SizedBox(height: 8),
        WhoPicker(
          couple: widget.couple,
          value: _who,
          onChanged: (v) => setState(() => _who = v),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ganztägig'),
          value: _allDay,
          onChanged: (v) => setState(() => _allDay = v),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _pickStartDate,
              icon: const Icon(Icons.event_outlined),
              label: Text('Von ${shortDay(_start)}'),
            ),
            OutlinedButton.icon(
              onPressed: _pickEndDate,
              icon: const Icon(Icons.event_available_outlined),
              label: Text('Bis ${shortDay(_end)}'),
            ),
            if (!_allDay) ...[
              OutlinedButton.icon(
                onPressed: () => _pickTime(true),
                icon: const Icon(Icons.schedule),
                label: Text(_startTime.format(context)),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickTime(false),
                icon: const Icon(Icons.schedule_outlined),
                label: Text(
                  _endTime == null
                      ? 'Ende (optional)'
                      : _endTime!.format(context),
                ),
              ),
              if (_endTime != null)
                IconButton(
                  tooltip: 'Ende entfernen',
                  onPressed: () => setState(() => _endTime = null),
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          maxLines: 2,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Notiz (optional)',
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving || _title.text.trim().isEmpty ? null : _save,
          child: const Text('Speichern'),
        ),
        if (widget.event != null)
          TextButton.icon(
            onPressed: _delete,
            icon: Icon(Icons.delete_outline, color: scheme.error),
            label: Text(
              'Termin löschen',
              style: TextStyle(color: scheme.error),
            ),
          ),
      ],
    );
  }
}
