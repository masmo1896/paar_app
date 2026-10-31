import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/couple_service.dart';
import '../theme.dart';
import '../utils/dates.dart';

/// Nachrichten durchsuchen. Lädt die letzten 2000 Nachrichten einmal und
/// filtert dann direkt auf dem Handy. Antippen = zurück in den Chat zur Nachricht.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.coupleId,
    required this.myUid,
    required this.partnerName,
  });

  final String coupleId;
  final String myUid;
  final String partnerName;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  late final Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _all =
      CoupleService.instance
          .messages(widget.coupleId)
          .orderBy('createdAt', descending: true)
          .limit(2000)
          .get()
          .then((s) => s.docs);

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'In euren Nachrichten suchen…',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Leeren',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(_query.clear),
                  ),
            isDense: true,
          ),
        ),
        actions: const [SizedBox(width: 12)],
      ),
      body: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        future: _all,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final q = _query.text.trim().toLowerCase();
          if (q.length < 2) {
            return const _Hint('Mindestens zwei Buchstaben eingeben.');
          }
          final hits = snap.data!.where((d) {
            final data = d.data();
            if ((data['type'] ?? 'text') != 'text') return false;
            return (data['text'] as String? ?? '').toLowerCase().contains(q);
          }).toList();
          if (hits.isEmpty) return const _Hint('Nichts gefunden.');
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: hits.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Text(
                  hits.length == 1 ? '1 Treffer' : '${hits.length} Treffer',
                  style: AppTheme.label(),
                );
              }
              final doc = hits[i - 1];
              final data = doc.data();
              final mine = data['senderId'] == widget.myUid;
              final time = (data['createdAt'] as Timestamp?)?.toDate();
              return Paper(
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.pop(context, doc.id),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${mine ? 'Du' : widget.partnerName}'
                            '${time == null ? '' : ' · ${shortDay(time)}, ${timeKey(TimeOfDay.fromDateTime(time))}'}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Kitsune.plum,
                            ),
                          ),
                          const SizedBox(height: 2),
                          _Highlighted(
                            text: data['text'] as String? ?? '',
                            query: q,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(text, style: const TextStyle(color: Kitsune.mist)),
  );
}

/// Text mit markiertem Suchbegriff (Aqua-Hintergrund).
class _Highlighted extends StatelessWidget {
  const _Highlighted({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final i = lower.indexOf(query, start);
      if (i < 0) break;
      spans
        ..add(TextSpan(text: text.substring(start, i)))
        ..add(
          TextSpan(
            text: text.substring(i, i + query.length),
            style: const TextStyle(
              backgroundColor: Kitsune.aqua,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      start = i + query.length;
    }
    spans.add(TextSpan(text: text.substring(start)));
    return Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 15, color: Kitsune.night),
        children: spans,
      ),
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
    );
  }
}
