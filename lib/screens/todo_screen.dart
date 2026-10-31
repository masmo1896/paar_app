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

enum _Filter { alle, meine, ihre }

class _TodoScreenState extends State<TodoScreen> {
  _Filter _filter = _Filter.alle;

  Couple get couple => widget.couple;

  bool _matches(Todo t) => switch (_filter) {
    _Filter.alle => true,
    _Filter.meine => t.assignee == couple.myUid || t.assignee == both,
    _Filter.ihre => t.assignee == couple.partnerUid || t.assignee == both,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: kitsuneAppBar(
        art: KitsuneArt.koi,
        kana: 'やること',
        titleText: 'Unsere To-dos',
        height: 104,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (filter, label) in [
                  (_Filter.alle, 'Alle'),
                  (_Filter.meine, 'Meine'),
                  if (couple.partnerUid != null)
                    (_Filter.ihre, couple.partnerLabel),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _filter == filter,
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _filter == filter ? Kitsune.deep : Kitsune.paper,
                    ),
                    onSelected: (_) => setState(() => _filter = filter),
                  ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Todo>>(
              stream: PlannerService.instance.todos(couple.coupleId),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data!.where(_matches).toList();
                final open = all.where((t) => !t.done).toList()..sort(_byDue);
                final done = all.where((t) => t.done).toList()..sort(_byDue);
                if (all.isEmpty) {
                  return const Center(
                    child: Text(
                      'Noch nichts zu tun 🎉\nMit + fügst du etwas hinzu.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  children: [
                    for (final t in open)
                      _TodoTile(todo: t, couple: couple, onEdit: _edit),
                    if (done.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                        child: Text(
                          'Erledigt (${done.length})',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                      for (final t in done)
                        _TodoTile(todo: t, couple: couple, onEdit: _edit),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Aufgabe hinzufügen',
        onPressed: () => _edit(null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _edit(Todo? todo) => showFormSheet<void>(
    context,
    (_) => _TodoForm(couple: couple, todo: todo),
  );
}

class _TodoTile extends StatelessWidget {
  const _TodoTile({
    required this.todo,
    required this.couple,
    required this.onEdit,
  });

  final Todo todo;
  final Couple couple;
  final ValueChanged<Todo> onEdit;

  // Auf Papier: Schrift und Symbole der Karte werden nachtblau.
  @override
  Widget build(BuildContext context) => Paper(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final due = todo.due;
    final overdue = due != null && !todo.done && due.isBefore(today());
    final isToday = due != null && sameDay(due, today());

    // Papierkarte; erledigte werden blasser und bekommen den roten 済-Stempel.
    return Opacity(
      opacity: todo.done ? 0.82 : 1,
      child: Card(
        margin: const EdgeInsets.only(top: 10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onEdit(todo),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
            child: Row(
              children: [
                // Eigene Hitbox von 48 Pixeln, damit das Abhaken leicht trifft.
                IconButton(
                  tooltip: todo.done ? 'Wieder öffnen' : 'Abhaken',
                  onPressed: () => PlannerService.instance.setTodoDone(
                    couple.coupleId,
                    todo.id,
                    !todo.done,
                  ),
                  icon: todo.done
                      ? const Hanko('済', size: 28)
                      : Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Kitsune.indigo, width: 2),
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
                          fontSize: 16,
                          fontWeight: todo.done
                              ? FontWeight.normal
                              : FontWeight.w600,
                          decoration: todo.done
                              ? TextDecoration.lineThrough
                              : null,
                          color: todo.done
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface,
                        ),
                      ),
                      if (due != null && !todo.done)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Icon(
                                Icons.event_outlined,
                                size: 14,
                                color: overdue
                                    ? scheme.error
                                    : scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                overdue
                                    ? 'Überfällig · ${shortDay(due)}'
                                    : relativeDay(due),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isToday || overdue
                                      ? FontWeight.w700
                                      : null,
                                  color: overdue
                                      ? scheme.error
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (!todo.done) ...[
                  const SizedBox(width: 8),
                  WhoPill(couple: couple, who: todo.assignee),
                ],
              ],
            ),
          ),
        ),
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
