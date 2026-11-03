import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/crossword_logic.dart';
import '../utils/shared_stream.dart';

// Datenmodell in Firestore:
//   couples/{c}/crosswords/{g} -> { status: 'playing'|'done', turn, size,
//                                   words: [{id, clue, answer, x, y, across}],
//                                   solved: {wordId: uid}, revealed: [Feld-Nr.],
//                                   attempts, hintsUsed, createdBy, createdAt, updatedAt }
// Ihr löst gemeinsam: abwechselnd ein Wort raten oder einen Buchstaben aufdecken.

class CrosswordGame {
  const CrosswordGame({
    required this.id,
    required this.status,
    required this.turn,
    required this.size,
    required this.words,
    required this.solved,
    required this.revealed,
    required this.attempts,
    required this.hintsUsed,
    this.difficulty = 'medium',
  });

  factory CrosswordGame.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return CrosswordGame(
      id: d.id,
      status: m['status'] as String? ?? 'playing',
      turn: m['turn'] as String?,
      size: (m['size'] as num?)?.toInt() ?? 11,
      words: [
        for (final w in (m['words'] as List?) ?? const [])
          CrosswordWord.fromMap(Map<String, dynamic>.from(w as Map)),
      ],
      solved: Map<String, String>.from((m['solved'] as Map?) ?? const {}),
      revealed: {
        for (final v in (m['revealed'] as List?) ?? const [])
          (v as num).toInt(),
      },
      attempts: (m['attempts'] as num?)?.toInt() ?? 0,
      hintsUsed: (m['hintsUsed'] as num?)?.toInt() ?? 0,
      difficulty: m['difficulty'] as String? ?? 'medium',
    );
  }

  final String id;
  final String status;
  final String? turn;
  final int size;
  final List<CrosswordWord> words;

  /// Gelöste Wörter: wer sie gefunden hat.
  final Map<String, String> solved;

  /// Per Hinweis aufgedeckte Felder.
  final Set<int> revealed;
  final int attempts;
  final int hintsUsed;

  /// 'easy', 'medium' oder 'hard' (ältere Rätsel: 'medium').
  final String difficulty;

  bool get isDone => status == 'done';
  double get progress => words.isEmpty ? 0 : solved.length / words.length;

  /// Wer hat welches Feld gelöst? (Für die Färbung; aufgedeckt = '').
  Map<Point<int>, String> get filledBy {
    final out = <Point<int>, String>{};
    for (final w in words) {
      final by = solved[w.id];
      if (by != null) {
        for (final c in w.cells) {
          out.putIfAbsent(c, () => by);
        }
      }
    }
    for (final i in revealed) {
      out.putIfAbsent(Point(i % size, i ~/ size), () => '');
    }
    return out;
  }
}

class CrosswordService {
  CrosswordService._();
  static final instance = CrosswordService._();

  final _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> _games(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('crosswords');

  /// Das neueste Rätsel (null = noch keins).
  Stream<CrosswordGame?> current(String coupleId) => SharedStreams.get(
    'crossword/$coupleId',
    () => _games(coupleId)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map(
          (s) => s.docs.isEmpty ? null : CrosswordGame.fromDoc(s.docs.first),
        ),
  );

  /// Wie viele Rätsel ihr schon zusammen gelöst habt.
  Stream<int> solvedCount(String coupleId) => SharedStreams.get(
    'crosswordSolved/$coupleId',
    () =>
        _games(coupleId)
            .where('status', isEqualTo: 'done')
            .snapshots()
            .map((s) => s.size),
  );

  /// Neues Rätsel; wer es startet, beginnt.
  Future<void> newGame(
    String coupleId,
    int size,
    List<CrosswordWord> words, {
    String difficulty = 'medium',
    List<int> revealed = const [],
  }) => _games(coupleId).add({
    'difficulty': difficulty,
    'status': 'playing',
    'turn': _uid,
    'createdBy': _uid,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'size': size,
    'words': [for (final w in words) w.toMap()],
    'solved': <String, dynamic>{},
    'attempts': 0,
    'hintsUsed': 0,
    'revealed': revealed,
  });

  /// Ein Wort raten. Richtig oder falsch – danach ist der Schatz dran.
  /// Gibt zurück, ob es richtig war.
  Future<bool> submitWord(
    String coupleId,
    CrosswordGame game,
    CrosswordWord word,
    String guess,
    String partnerUid,
  ) async {
    final correct = normalizeAnswer(guess) == word.answer;
    final allSolved = correct && game.solved.length + 1 >= game.words.length;
    await _games(coupleId).doc(game.id).update({
      if (correct) 'solved.${word.id}': _uid,
      'attempts': FieldValue.increment(1),
      'turn': partnerUid,
      if (allSolved) 'status': 'done',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return correct;
  }

  /// Einen Buchstaben von [word] aufdecken – kostet den Zug.
  Future<void> hint(
    String coupleId,
    CrosswordGame game,
    CrosswordWord word,
    String partnerUid,
  ) {
    final open = word.cells
        .map((c) => cellIndex(c, game.size))
        .where((i) => !game.revealed.contains(i))
        .toList();
    if (open.isEmpty) return Future.value();
    return _games(coupleId).doc(game.id).update({
      'revealed': FieldValue.arrayUnion([open[Random().nextInt(open.length)]]),
      'hintsUsed': FieldValue.increment(1),
      'turn': partnerUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
