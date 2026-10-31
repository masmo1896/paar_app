import 'package:flutter/material.dart';

import '../services/planner_service.dart' show both;

/// Wer gehört zu einer Aufgabe oder einem Termin? Alles, was To-dos und Kalender
/// über die beiden Personen wissen müssen, an einem Ort.
class Couple {
  const Couple({
    required this.coupleId,
    required this.myUid,
    this.partnerUid,
    this.partnerName,
  });

  final String coupleId;
  final String myUid;
  final String? partnerUid; // null, solange niemand beigetreten ist
  final String? partnerName;

  String get partnerLabel {
    final name = partnerName?.trim();
    return name == null || name.isEmpty ? 'Dein Schatz' : name;
  }

  /// "Beide", "Du" oder der Name der anderen Person.
  String label(String who) {
    if (who == both) return 'Beide';
    return who == myUid ? 'Du' : partnerLabel;
  }
}

/// Farben je Person: beide = Terrakotta, du = Dunkelbraun (hell: Creme), sie = Bernstein.
({Color bg, Color fg}) whoColors(
  BuildContext context,
  Couple couple,
  String who,
) {
  final scheme = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (who == both) return (bg: scheme.primary, fg: scheme.onPrimary);
  if (who == couple.myUid) return (bg: scheme.tertiary, fg: scheme.onTertiary);
  // Sie: warmes Bernstein mit dunkler Schrift, gut lesbar und klar von Terrakotta unterscheidbar.
  return dark
      ? (bg: const Color(0xFFF0B35A), fg: const Color(0xFF2B211C))
      : (bg: const Color(0xFFE8A33D), fg: const Color(0xFF2B211C));
}

/// Kleine Plakette "Du" / "Beide" / Name.
class WhoPill extends StatelessWidget {
  const WhoPill({super.key, required this.couple, required this.who});

  final Couple couple;
  final String who;

  @override
  Widget build(BuildContext context) {
    final c = whoColors(context, couple, who);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        couple.label(who),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: c.fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Auswahl: Du / (Name) / Beide.
class WhoPicker extends StatelessWidget {
  const WhoPicker({
    super.key,
    required this.couple,
    required this.value,
    required this.onChanged,
  });

  final Couple couple;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = [
      couple.myUid,
      if (couple.partnerUid != null) couple.partnerUid!,
      both,
    ];
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [
        for (final who in options)
          ButtonSegment(
            value: who,
            label: Text(
              couple.label(who),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

/// Unteres Fenster für Formulare, das mit der Tastatur nach oben rutscht.
Future<T?> showFormSheet<T>(BuildContext context, WidgetBuilder builder) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(child: builder(context)),
      ),
    );

/// Sicherheitsfrage vor dem Löschen. true = wirklich löschen.
Future<bool> confirmDelete(BuildContext context, String what) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('$what löschen?'),
      content: const Text('Das gilt für euch beide.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          child: const Text('Löschen'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
