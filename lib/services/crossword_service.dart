import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/crossword_logic.dart';
import '../utils/shared_stream.dart';

// Datenmodell in Firestore:
//   couples/{c}/crosswords/{g} -> { status: 'playing'|'done', turn, size,
//                                   words: [{id, clue, answer, x, y, across}],
//                                   solved: {wordId: uid}, revealed: [Feld-Nr.],
//                                   lastMove?: {by, type: 'solved'|'miss'|'hint', wordId},
//                                   tips?: [wordId] (aufgedeckte Tipps, für beide sichtbar),
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
    this.lastMove,
    this.tips = const {},
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
      lastMove: switch (m['lastMove']) {
        final Map lm when lm['by'] is String && lm['wordId'] is String => (
          by: lm['by'] as String,
          type: lm['type'] as String? ?? 'miss',
          wordId: lm['wordId'] as String,
        ),
        _ => null,
      },
      tips: {
        for (final v in (m['tips'] as List?) ?? const [])
          if (v is String) v,
      },
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

  /// 'veryEasy', 'easy', 'medium', 'hard', 'expert' oder 'god' (ältere Rätsel: 'medium').
  final String difficulty;

  /// Der letzte Zug: wer, was ('solved', 'miss', 'hint') und bei welchem Wort.
  final ({String by, String type, String wordId})? lastMove;

  /// Wörter, deren Tipp schon aufgedeckt ist (sehen beide).
  final Set<String> tips;

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

  /// Zug speichern. Kennen die Server-Regeln «lastMove» noch nicht (ältere Regeln
  /// online), wird der Zug ohne diese Meldung gespeichert statt still zu scheitern.
  Future<void> _updateWithMove(
    String coupleId,
    String gameId,
    Map<String, Object?> data,
  ) async {
    final ref = _games(coupleId).doc(gameId);
    try {
      await ref.update(data);
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied' || !data.containsKey('lastMove')) {
        rethrow;
      }
      await ref.update({...data}..remove('lastMove'));
    }
  }

  /// Lösungswörter der letzten [games] Rätsel, das zuletzt gespielte zuerst.
  /// Der Generator nimmt zuerst nie gespielte Wörter, dann die am längsten
  /// nicht mehr gesehenen – so wiederholt sich lange nichts.
  Future<List<String>> recentAnswers(String coupleId, {int games = 40}) async {
    final snap = await _games(coupleId)
        .orderBy('createdAt', descending: true)
        .limit(games)
        .get();
    return {
      for (final d in snap.docs)
        for (final w in (d.data()['words'] as List?) ?? const [])
          if ((w as Map)['answer'] is String) w['answer'] as String,
    }.toList();
  }

  /// Tipp zu [word] aufdecken – der Zug bleibt bei dir, kostet aber Punkte.
  /// false = die Server-Regeln kennen Tipps noch nicht; dann sieht ihn nur,
  /// wer ihn aufgedeckt hat (bis die neuen Regeln hochgeladen sind).
  Future<bool> revealTip(
    String coupleId,
    CrosswordGame game,
    CrosswordWord word,
  ) async {
    if (game.tips.contains(word.id)) return true;
    try {
      await _games(coupleId).doc(game.id).update({
        'tips': FieldValue.arrayUnion([word.id]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return false;
      rethrow;
    }
  }

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
    await _updateWithMove(coupleId, game.id, {
      if (correct) 'solved.${word.id}': _uid,
      'lastMove': {
        'by': _uid,
        'type': correct ? 'solved' : 'miss',
        'wordId': word.id,
      },
      'attempts': FieldValue.increment(1),
      'turn': partnerUid,
      if (allSolved) 'status': 'done',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return correct;
  }

  /// Einen noch unbekannten Buchstaben von [word] aufdecken – kostet den Zug.
  Future<void> hint(
    String coupleId,
    CrosswordGame game,
    CrosswordWord word,
    String partnerUid,
  ) {
    // Nur Felder, die noch leer sind – auch keine, die schon durch ein gelöstes
    // Kreuzungswort sichtbar sind (sonst gäbe es keinen neuen Buchstaben).
    final visible = game.filledBy.keys.toSet();
    final open = word.cells
        .where((c) => !visible.contains(c))
        .map((c) => cellIndex(c, game.size))
        .toList();
    if (open.isEmpty) return Future.value();
    return _updateWithMove(coupleId, game.id, {
      'revealed': FieldValue.arrayUnion([open[Random().nextInt(open.length)]]),
      'hintsUsed': FieldValue.increment(1),
      'lastMove': {'by': _uid, 'type': 'hint', 'wordId': word.id},
      'turn': partnerUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
