import 'package:flutter/material.dart';

import '../theme.dart';
import '../services/planner_service.dart';
import '../utils/dates.dart';
import '../widgets/who.dart';

/// Gemeinsame To-do-Liste: abhaken, zuweisen, Fälligkeit. Antippen = bearbeiten.
class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key, required this.couple});

  final Couple couple;

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

enum _Filter { alle, meine, ihre, einkauf }

class _TodoScreenState extends State<TodoScreen> {
  _Filter _filter = _Filter.alle;
  final _newTitle = TextEditingController();

  Couple get couple => widget.couple;

  @override
  void dispose() {
    _newTitle.dispose();
    super.dispose();
  }

  bool _matches(Todo t) => switch (_filter) {
    _Filter.alle => !t.isShopping,
    _Filter.meine =>
      !t.isShopping && (t.assignee == couple.myUid || t.assignee == both),
    _Filter.ihre =>
      !t.isShopping && (t.assignee == couple.partnerUid || t.assignee == both),
    _Filter.einkauf => t.isShopping,
  };

  // Offene zuerst: nach Fälligkeit (ohne Datum ganz unten), sonst alphabetisch.
  int _byDue(Todo a, Todo b) {
    if (a.due != null && b.due != null) {
      final c = a.due!.compareTo(b.due!);
      if (c != 0) return c;
    } else if (a.due != null) {
      return -1;
    } else if (b.due != null) {
      return 1;
    }
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  // Erledigte: zuletzt erledigte zuerst.
  int _byDoneAt(Todo a, Todo b) =>
      (b.doneAt ?? DateTime(2100)).compareTo(a.doneAt ?? DateTime(2100));

  /// Schnell hinzufügen über das Feld unten: für beide, ohne Datum.
  Future<void> _quickAdd() async {
    final title = _newTitle.text.trim();
    if (title.isEmpty) return;
    _newTitle.clear();
    await PlannerService.instance.saveTodo(
      couple.coupleId,
      title: title,
      assignee: _filter == _Filter.meine ? couple.myUid : both,
      list: _filter == _Filter.einkauf ? shoppingList : todoList,
    );
  }

  @override
  Widget build(BuildContext context) {
    final shopping = _filter == _Filter.einkauf;
    return StreamBuilder<List<Todo>>(
      stream: PlannerService.instance.todos(couple.coupleId),
      builder: (context, snap) {
        final everything = snap.data;
        // Zähler oben rechts wie im Mockup: "2 / 5 済" (erledigt / alle).
        final counted = (everything ?? [])
            .where((t) => t.isShopping == shopping)
            .toList();
        final doneCount = counted.where((t) => t.done).length;

        return Scaffold(
          appBar: kitsuneAppBar(
            art: KitsuneArt.koi,
            kana: shopping ? 'かいもの' : 'やること',
            titleText: shopping ? 'Einkaufsliste' : 'Unsere To-dos',
            height: 104,
            actions: [
              if (counted.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 20, top: 34),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Kitsune.paper,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        '$doneCount / ${counted.length} 済',
                        style: AppTheme.serif(size: 15, color: Kitsune.night),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              SizedBox(
                height: 50,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                  children: [
                    for (final (filter, label) in [
                      (_Filter.alle, 'Alle'),
                      (
                        _Filter.meine,
                        couple.myName?.trim().isNotEmpty == true
                            ? couple.myName!.trim()
                            : 'Meine',
                      ),
                      if (couple.partnerUid != null)
                        (_Filter.ihre, couple.partnerLabel),
                      (_Filter.einkauf, 'Einkauf'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _FilterChip(
                          label: label,
                          icon: filter == _Filter.einkauf
                              ? Icons.shopping_basket_outlined
                              : null,
                          selected: _filter == filter,
                          onTap: () => setState(() => _filter = filter),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(child: _list(context, everything, shopping)),
              // Eingabefeld unten wie im Mockup: Text + roter Plus-Knopf.
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                decoration: BoxDecoration(
                  color: Kitsune.deep.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0x59F3EBD3)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newTitle,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _quickAdd(),
                        style: const TextStyle(fontSize: 14.5),
                        decoration: InputDecoration(
                          hintText: shopping
                              ? 'Was brauchen wir noch…'
                              : 'Neues To-do für euch zwei…',
                          filled: false,
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    IconButton.filled(
                      tooltip: 'Hinzufügen',
                      onPressed: _quickAdd,
                      style: IconButton.styleFrom(
                        backgroundColor: Kitsune.lantern,
                        foregroundColor: Kitsune.deep,
                        fixedSize: const Size(44, 44),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 24),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _list(BuildContext context, List<Todo>? everything, bool shopping) {
    if (everything == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final all = everything.where(_matches).toList();
    final open = all.where((t) => !t.done).toList()..sort(_byDue);
    final done = all.where((t) => t.done).toList()..sort(_byDoneAt);
    if (all.isEmpty) {
      return Center(
        child: Text(
          shopping
              ? 'Der Kühlschrank ist voll.\nUnten trägst du ein, was fehlt.'
              : 'Noch nichts zu tun.\nUnten trägst du etwas ein.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Kitsune.mist),
        ),
      );
    }
    final items = [...open, ...done];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      itemCount: items.length,
      itemBuilder: (context, i) =>
          _TodoTile(todo: items[i], couple: couple, index: i, onEdit: _edit),
    );
  }

  Future<void> _edit(Todo? todo) => showFormSheet<void>(
    context,
    (_) => _TodoForm(couple: couple, todo: todo),
  );
}

/// Filter-Knopf: gewählt = Creme mit nachtblauer Schrift, sonst nur Umriss.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected ? Kitsune.paper : Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? Kitsune.paper : const Color(0x66F3EBD3),
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 16,
                  color: selected ? Kitsune.night : Kitsune.paper,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Kitsune.night : Kitsune.paper,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Papierkarte wie im Mockup: leicht schräg, mit buntem Klebeband oben,
/// rundem Kreis zum Abhaken (erledigt = roter 済-Stempel) und Namens-Stempel rechts.
class _TodoTile extends StatelessWidget {
  const _TodoTile({
    required this.todo,
    required this.couple,
    required this.index,
    required this.onEdit,
  });

  final Todo todo;
  final Couple couple;
  final int index;
  final ValueChanged<Todo> onEdit;

  static const _tapes = [
    Kitsune.lantern,
    Kitsune.aqua,
    Kitsune.sky,
    Kitsune.plum,
  ];

  String? _subtitle() {
    if (todo.done) {
      final at = todo.doneAt;
      if (at == null) return 'erledigt';
      final days = daysBetween(DateTime(at.year, at.month, at.day), today());
      return switch (days) {
        0 => 'erledigt heute',
        1 => 'erledigt gestern',
        < 7 => 'erledigt am ${weekdaysShort[at.weekday - 1]}',
        _ => 'erledigt am ${shortDay(at)}',
      };
    }
    final due = todo.due;
    if (due == null) return null;
    if (due.isBefore(today())) return 'überfällig · ${shortDay(due)}';
    return relativeDay(due);
  }

  @override
  Widget build(BuildContext context) {
    final done = todo.done;
    final bg = done ? const Color(0xFFD9D3BF) : Kitsune.paper;
    final sub = _subtitle();
    final overdue = !done && todo.due != null && todo.due!.isBefore(today());
    final tapeLeft = 24.0 + (index * 47) % 180;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Transform.rotate(
        angle: index.isOdd ? 0.009 : -0.009,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: bg,
              borderRadius: BorderRadius.circular(3),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onEdit(todo),
                child: Container(
                  // Feiner Innenrahmen wie bei den Papierkarten.
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0x40133174)),
                  ),
                  padding: const EdgeInsets.fromLTRB(2, 2, 10, 2),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: done ? 'Wieder öffnen' : 'Abhaken',
                        onPressed: () => PlannerService.instance.setTodoDone(
                          couple.coupleId,
                          todo.id,
                          !done,
                        ),
                        icon: done
                            ? const Hanko('済', size: 28)
                            : Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Kitsune.indigo,
                                    width: 2,
                                  ),
                                ),
                              ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              todo.title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: done
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                                color: done
                                    ? const Color(0xFF4A5470)
                                    : Kitsune.night,
                                decoration: done
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            if (sub != null)
                              Text(
                                sub,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: overdue ? FontWeight.w700 : null,
                                  color: overdue
                                      ? const Color(0xFFB0204D)
                                      : Kitsune.inkSoft,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _WhoStamp(couple: couple, who: todo.assignee),
                    ],
                  ),
                ),
              ),
            ),
            // Klebeband-Streifen oben auf der Karte.
            Positioned(
              top: -6,
              left: tapeLeft,
              child: IgnorePointer(
                child: Transform.rotate(
                  angle: index.isOdd ? 0.07 : -0.09,
                  child: Container(
                    width: 46,
                    height: 12,
                    color: _tapes[todo.id.hashCode.abs() % _tapes.length]
                        .withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Runder Namens-Stempel: du = Indigo, dein Schatz = Pflaume, beide = beide Kreise.
class _WhoStamp extends StatelessWidget {
  const _WhoStamp({required this.couple, required this.who});

  final Couple couple;
  final String who;

  @override
  Widget build(BuildContext context) {
    Widget circle(String uid) => Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: uid == couple.myUid ? Kitsune.indigo : Kitsune.plum,
        border: Border.all(color: Kitsune.paper, width: 1.5),
      ),
      child: Text(
        couple.initialOf(uid),
        style: AppTheme.serif(size: 13, color: Kitsune.paper),
      ),
    );
    final partner = couple.partnerUid;
    return Semantics(
      label: couple.label(who),
      child: ExcludeSemantics(
        child: who == both && partner != null
            ? SizedBox(
                width: 46,
                height: 28,
                child: Stack(
                  children: [
                    circle(couple.myUid),
                    Positioned(left: 18, child: circle(partner)),
                  ],
                ),
              )
            : circle(who == both ? couple.myUid : who),
      ),
    );
  }
}

/// Formular zum Anlegen und Bearbeiten einer Aufgabe.
class _TodoForm extends StatefulWidget {
  const _TodoForm({required this.couple, required this.todo});

  final Couple couple;
  final Todo? todo;

  @override
  State<_TodoForm> createState() => _TodoFormState();
}

class _TodoFormState extends State<_TodoForm> {
  late final _title = TextEditingController(text: widget.todo?.title ?? '');
  late String _assignee = widget.todo?.assignee ?? both;
  late DateTime? _due = widget.todo?.due;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? today(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _due = picked);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    await PlannerService.instance.saveTodo(
      widget.couple.coupleId,
      id: widget.todo?.id,
      title: title,
      assignee: _assignee,
      due: _due,
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirmDelete(context, 'Aufgabe')) return;
    await PlannerService.instance.deleteTodo(
      widget.couple.coupleId,
      widget.todo!.id,
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
          widget.todo == null ? 'Neue Aufgabe' : 'Aufgabe bearbeiten',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _title,
          autofocus: widget.todo == null,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 200,
          decoration: const InputDecoration(
            labelText: 'Was ist zu tun?',
            counterText: '',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        Text('Wer macht es?', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        WhoPicker(
          couple: widget.couple,
          value: _assignee,
          onChanged: (v) => setState(() => _assignee = v),
        ),
        const SizedBox(height: 16),
        Text('Bis wann?', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined),
              label: Text(_due == null ? 'Datum wählen' : longDay(_due!)),
            ),
            if (_due != null)
              IconButton(
                tooltip: 'Datum entfernen',
                onPressed: () => setState(() => _due = null),
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _saving || _title.text.trim().isEmpty ? null : _save,
          child: const Text('Speichern'),
        ),
        if (widget.todo != null)
          TextButton.icon(
            onPressed: _delete,
            icon: Icon(Icons.delete_outline, color: scheme.error),
            label: Text(
              'Aufgabe löschen',
              style: TextStyle(color: scheme.error),
            ),
          ),
      ],
    );
  }
}
