import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/battleship_logic.dart';
import '../utils/shared_stream.dart';

// Datenmodell in Firestore:
//   couples/{c}/battleships/{g}       -> { status: 'setup'|'playing'|'done', players: [a, b],
//                                          turn, resolving, winner?, sunk: {uid: [shipIds]},
//                                          revealed?: {uid: [ships]}, createdBy, createdAt, updatedAt }
//   .../battleships/{g}/fleets/{uid}  -> { ships: [...] }   nur die Besitzerin darf lesen
//   .../battleships/{g}/shots/{by_x_y}-> { by, x, y, at, result?, shipLen? }
// Treffer/Wasser trägt die Cloud Function onBattleShot ein (functions/index.js).

class BattleGame {
  const BattleGame({
    required this.id,
    required this.status,
    required this.players,
    required this.turn,
    required this.resolving,
    required this.createdBy,
    required this.sunk,
    this.winner,
    this.revealed = const {},
    this.scores = const {},
  });

  factory BattleGame.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return BattleGame(
      id: d.id,
      status: m['status'] as String? ?? 'setup',
      players: (m['players'] as List?)?.cast<String>() ?? const [],
      turn: m['turn'] as String?,
      resolving: m['resolving'] as bool? ?? false,
      createdBy: m['createdBy'] as String? ?? '',
      winner: m['winner'] as String?,
      sunk: {
        for (final e in ((m['sunk'] as Map?) ?? const {}).entries)
          e.key as String: (e.value as List).cast<String>(),
      },
      scores: {
        for (final e in ((m['scores'] as Map?) ?? const {}).entries)
          e.key as String: (e.value as num).toInt(),
      },
      revealed: {
        for (final e in ((m['revealed'] as Map?) ?? const {}).entries)
          e.key as String: [
            for (final s in e.value as List)
              Ship.fromMap(Map<String, dynamic>.from(s as Map)),
          ],
      },
    );
  }

  final String id;
  final String status;
  final List<String> players;
  final String? turn;
  final bool resolving;
  final String createdBy;
  final String? winner;

  /// Versenkte Schiffe je Besitzerin.
  final Map<String, List<String>> sunk;

  /// Punkte je Person (zählt die Cloud Function).
  final Map<String, int> scores;

  /// Am Spielende: beide Flotten offen.
  final Map<String, List<Ship>> revealed;

  bool get isSetup => status == 'setup';
  bool get isPlaying => status == 'playing';
  bool get isDone => status == 'done';
}

class BattleRecords {
  const BattleRecords({required this.wins, required this.best, this.bestBy});

  final Map<String, int> wins;

  /// Höchste Punktzahl in einer beendeten Partie (0 = noch keine).
  final int best;
  final String? bestBy;
}

class BattleshipService {
  BattleshipService._();
  static final instance = BattleshipService._();

  final _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> _games(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('battleships');

  /// Das neueste Spiel (null = noch nie gespielt).
  Stream<BattleGame?> current(String coupleId) => SharedStreams.get(
    'battleship/$coupleId',
    () => _games(coupleId)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isEmpty ? null : BattleGame.fromDoc(s.docs.first)),
  );

  /// Siege je Person und der Allzeit-Rekord (höchste Punktzahl in einer Partie).
  Stream<BattleRecords> records(String coupleId) => SharedStreams.get(
    'battleshipRecords/$coupleId',
    () =>
        _games(coupleId)
            .where('status', isEqualTo: 'done')
            .snapshots()
            .map((s) {
              final wins = <String, int>{};
              var best = 0;
              String? bestBy;
              for (final d in s.docs) {
                final g = BattleGame.fromDoc(d);
                final w = g.winner;
                if (w != null) wins[w] = (wins[w] ?? 0) + 1;
                for (final e in g.scores.entries) {
                  if (e.value > best) {
                    best = e.value;
                    bestBy = e.key;
                  }
                }
              }
              return BattleRecords(wins: wins, best: best, bestBy: bestBy);
            }),
  );

  /// Meine Aufstellung im Spiel [gameId] (null = noch nicht gesetzt).
  Stream<List<Ship>?> myFleet(String coupleId, String gameId) =>
      SharedStreams.get(
        'battleshipFleet/$coupleId/$gameId/$_uid',
        () =>
            _games(coupleId)
                .doc(gameId)
                .collection('fleets')
                .doc(_uid)
                .snapshots()
                .map(
                  (d) => d.exists
                      ? [
                          for (final s in (d.data()!['ships'] as List))
                            Ship.fromMap(Map<String, dynamic>.from(s as Map)),
                        ]
                      : null,
                ),
      );

  /// Alle Schüsse beider Personen, älteste zuerst.
  Stream<List<Shot>> shots(String coupleId, String gameId) => SharedStreams.get(
    'battleshipShots/$coupleId/$gameId',
    () =>
        _games(coupleId)
            .doc(gameId)
            .collection('shots')
            .orderBy('at')
            .snapshots()
            .map((s) => [for (final d in s.docs) _shot(d.id, d.data())]),
  );

  Future<void> newGame(String coupleId, String partnerUid) =>
      _games(coupleId).add({
        'status': 'setup',
        'players': [_uid, partnerUid],
        'turn': null,
        'resolving': false,
        'createdBy': _uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'sunk': <String, dynamic>{},
      });

  Future<void> placeFleet(String coupleId, String gameId, List<Ship> ships) =>
      _games(coupleId).doc(gameId).collection('fleets').doc(_uid).set({
        'ships': [for (final s in ships) s.toMap()],
      });

  /// Schuss auf (x, y). Die Sperre "resolving" verhindert einen zweiten Schuss,
  /// bis die Cloud Function ausgewertet hat.
  Future<void> shoot(String coupleId, String gameId, int x, int y) {
    final game = _games(coupleId).doc(gameId);
    return (_db.batch()
          ..set(game.collection('shots').doc('${_uid}_${x}_$y'), {
            'by': _uid,
            'x': x,
            'y': y,
            'at': FieldValue.serverTimestamp(),
          })
          ..update(game, {'resolving': true}))
        .commit();
  }

  /// Aufgeben: der Schatz gewinnt.
  Future<void> giveUp(String coupleId, BattleGame game) =>
      _games(coupleId).doc(game.id).update({
        'status': 'done',
        'winner': game.players.firstWhere((p) => p != _uid),
        'turn': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Hängt die Auswertung (Function nicht erreichbar), Sperre nach 1 Minute lösen.
  Future<void> unlock(String coupleId, String gameId) =>
      _games(coupleId).doc(gameId).update({'resolving': false});
}

Shot _shot(String id, Map<String, dynamic> m) => Shot(
  id: id,
  by: m['by'] as String? ?? '',
  x: (m['x'] as num?)?.toInt() ?? 0,
  y: (m['y'] as num?)?.toInt() ?? 0,
  at: (m['at'] as Timestamp?)?.toDate() ?? DateTime.now(),
  result: shotResultFrom(m['result'] as String?),
  shipLen: (m['shipLen'] as num?)?.toInt(),
  shipCells: [
    for (final c in (m['shipCells'] as List?) ?? const [])
      Point((c['x'] as num).toInt(), (c['y'] as num).toInt()),
  ],
);
