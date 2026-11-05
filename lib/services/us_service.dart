import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/shared_stream.dart';

// Datenmodell in Firestore (alles für die "Wir"-Seite):
//   couples/{coupleId}/days/{2026-11-02}             -> { question, answered: [uid, …] }
//   couples/{coupleId}/days/{tag}/answers/{uid}       -> { text, at }
//       Die Antwort des Schatzes darf man erst lesen, wenn die eigene existiert
//       (das prüfen die Firestore-Regeln, nicht nur die App).
//   couples/{coupleId}/letters/{id}                   -> { from, to, openAt, createdAt, openedAt? }
//   couples/{coupleId}/letters/{id}/content/text      -> { text }
//       Den Text gibt der Server erst ab openAt heraus (Absender: immer).
//   couples/{coupleId}/dateIdeas/{id}                 -> { text, createdBy, createdAt }

class DayQuestion {
  const DayQuestion({required this.question, required this.answered});

  final String question;
  final List<String> answered; // wer schon geantwortet hat
}

class Answer {
  const Answer({required this.text, required this.at});

  final String text;
  final DateTime? at;
}

class Letter {
  const Letter({
    required this.id,
    required this.from,
    required this.to,
    required this.openAt,
    required this.createdAt,
    this.openedAt,
  });

  factory Letter.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Letter(
      id: d.id,
      from: m['from'] as String? ?? '',
      to: m['to'] as String? ?? '',
      openAt: (m['openAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      openedAt: (m['openedAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String from;
  final String to;
  final DateTime openAt; // ab diesem Moment lässt sich der Brief öffnen
  final DateTime? createdAt;
  final DateTime? openedAt;

  bool get canOpen => !DateTime.now().isBefore(openAt);
}

class Idea {
  const Idea({required this.id, required this.text});

  final String id;
  final String text;
}

class UsService {
  UsService._();
  static final instance = UsService._();

  final _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> _couple(String coupleId) =>
      _db.collection('couples').doc(coupleId);

  // --- Frage des Tages -------------------------------------------------------

  DocumentReference<Map<String, dynamic>> _day(String coupleId, String day) =>
      _couple(coupleId).collection('days').doc(day);

  /// Geteilt: alle Bildschirme nutzen dieselbe Verbindung (siehe SharedStreams).
  Stream<DayQuestion?> day(String coupleId, String day) =>
      SharedStreams.get('day/$coupleId/$day', () => _dayLive(coupleId, day));

  Stream<DayQuestion?> _dayLive(String coupleId, String day) =>
      _day(coupleId, day).snapshots().map((d) {
        final m = d.data();
        if (m == null) return null;
        return DayQuestion(
          question: m['question'] as String? ?? '',
          answered: List<String>.from(m['answered'] as List? ?? const []),
        );
      });

  /// Antwort von [uid]. Die des Schatzes liefert der Server erst, wenn ich
  /// selbst geantwortet habe – vorher kommt null (statt eines Fehlers).
  /// Geteilt: alle Bildschirme nutzen dieselbe Verbindung (siehe SharedStreams).
  Stream<Answer?> answer(String coupleId, String day, String uid) =>
      SharedStreams.get(
        'answer/$coupleId/$day/$uid',
        () => _answerLive(coupleId, day, uid),
      );

  /// Live-Antwort. Wird der Zugriff verweigert, versucht es die App nochmals
  /// (nach 1, 2, 4, 8 … Sekunden): Wer als Zweite antwortet, fragt die Antwort
  /// des Schatzes sonst ab, bevor die eigene beim Server angekommen ist – und
  /// hätte sie danach nie mehr gesehen.
  Stream<Answer?> _answerLive(String coupleId, String day, String uid) async* {
    final ref = _day(coupleId, day).collection('answers').doc(uid);
    for (var attempt = 0; ; attempt++) {
      try {
        await for (final d in ref.snapshots()) {
          final m = d.data();
          yield m == null
              ? null
              : Answer(
                  text: m['text'] as String? ?? '',
                  at: (m['at'] as Timestamp?)?.toDate(),
                );
        }
        return;
      } on FirebaseException {
        yield null;
        if (attempt >= 6) return; // nach gut einer Minute aufgeben
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      }
    }
  }

  /// Eigene Antwort speichern. Zuerst die Antwort, dann "ich habe geantwortet"
  /// am Tag eintragen – in einem Schritt (Batch).
  /// Antwort für [day] – den Tag, dessen Frage gerade angezeigt wird (nicht
  /// "heute" beim Senden: wer um 23:59 tippt und um 0:01 sendet, beantwortet
  /// sonst die falsche Frage).
  Future<void> answerDay(
    String coupleId,
    String day,
    String question,
    String text,
  ) {
    final batch = _db.batch()
      ..set(_day(coupleId, day).collection('answers').doc(_uid), {
        'text': text.trim(),
        'at': FieldValue.serverTimestamp(),
      })
      ..set(_day(coupleId, day), {
        'question': question,
        'answered': FieldValue.arrayUnion([_uid]),
      }, SetOptions(merge: true));
    return batch.commit();
  }

  /// Frühere Tage (neueste zuerst), an denen mindestens jemand geantwortet hat.
  /// Geteilt: alle Bildschirme nutzen dieselbe Verbindung (siehe SharedStreams).
  Stream<List<(String day, DayQuestion q)>> archive(String coupleId) =>
      SharedStreams.get('archive/$coupleId', () => _archiveLive(coupleId));

  Stream<List<(String day, DayQuestion q)>> _archiveLive(String coupleId) =>
      _couple(coupleId)
          .collection('days')
          .orderBy(FieldPath.documentId, descending: true)
          .limit(120)
          .snapshots()
          .map(
            (s) => [
              for (final d in s.docs)
                (
                  d.id,
                  DayQuestion(
                    question: d.data()['question'] as String? ?? '',
                    answered: List<String>.from(
                      d.data()['answered'] as List? ?? const [],
                    ),
                  ),
                ),
            ],
          );

  // --- Liebesbriefe ------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _letters(String coupleId) =>
      _couple(coupleId).collection('letters');

  /// Geteilt: alle Bildschirme nutzen dieselbe Verbindung (siehe SharedStreams).
  Stream<List<Letter>> letters(String coupleId) =>
      SharedStreams.get('letters/$coupleId', () => _lettersLive(coupleId));

  Stream<List<Letter>> _lettersLive(String coupleId) =>
      _letters(coupleId)
          .orderBy('openAt')
          .snapshots()
          .map((s) => s.docs.map(Letter.fromDoc).toList());

  Future<void> sendLetter(
    String coupleId, {
    required String to,
    required String text,
    required DateTime openAt,
  }) {
    final ref = _letters(coupleId).doc();
    final batch = _db.batch()
      ..set(ref, {
        'from': _uid,
        'to': to,
        'openAt': Timestamp.fromDate(openAt),
        'createdAt': FieldValue.serverTimestamp(),
      })
      ..set(ref.collection('content').doc('text'), {'text': text.trim()});
    return batch.commit();
  }

  /// Text eines Briefs (erst ab dem Öffnungs-Datum lesbar).
  Future<String> letterText(String coupleId, String letterId) async {
    final d = await _letters(coupleId)
        .doc(letterId)
        .collection('content')
        .doc('text')
        .get();
    return d.data()?['text'] as String? ?? '';
  }

  /// Öffnungszeitpunkt eines noch versiegelten Briefs ändern (nur der Schreiber).
  Future<void> rescheduleLetter(
    String coupleId,
    String letterId,
    DateTime openAt,
  ) =>
      _letters(coupleId)
          .doc(letterId)
          .update({'openAt': Timestamp.fromDate(openAt)});

  /// Brief samt Text löschen (nur der Schreiber).
  Future<void> deleteLetter(String coupleId, String letterId) {
    final ref = _letters(coupleId).doc(letterId);
    return (_db.batch()
          ..delete(ref.collection('content').doc('text'))
          ..delete(ref))
        .commit();
  }

  Future<void> markLetterOpened(String coupleId, String letterId) =>
      _letters(coupleId)
          .doc(letterId)
          .update({'openedAt': FieldValue.serverTimestamp()});

  // --- Date-Glas ---------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _dateIdeas(String coupleId) =>
      _couple(coupleId).collection('dateIdeas');

  /// Geteilt: alle Bildschirme nutzen dieselbe Verbindung (siehe SharedStreams).
  Stream<List<Idea>> dateIdeas(String coupleId) =>
      SharedStreams.get('dateIdeas/$coupleId', () => _dateIdeasLive(coupleId));

  Stream<List<Idea>> _dateIdeasLive(String coupleId) => _dateIdeas(coupleId)
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs)
            Idea(id: d.id, text: d.data()['text'] as String? ?? ''),
        ],
      );

  Future<void> addDateIdea(String coupleId, String text) => _dateIdeas(coupleId)
      .add({
        'text': text.trim(),
        'createdBy': _uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> deleteDateIdea(String coupleId, String id) =>
      _dateIdeas(coupleId).doc(id).delete();
}
