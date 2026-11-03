import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/shared_stream.dart';

// Datenmodell in Firestore:
//   couples/{coupleId}/lanterns/{id} -> { from: uid, createdAt }
//   users/{uid}.lanternsSeenAt       -> bis wann ich die Laternen meines Schatzes gesehen habe

/// Eine Laterne = "Ich denk an dich". Gespeichert bleibt sie für immer,
/// am Himmel steht sie bis Mitternacht.
class Lantern {
  const Lantern({required this.id, required this.from, required this.at});

  final String id;
  final String from;

  /// Zeitpunkt (bei noch nicht gespeicherten Laternen: jetzt).
  final DateTime at;
}

class LanternService {
  LanternService._();
  static final instance = LanternService._();

  /// Liegen zwei Laternen von euch beiden höchstens so weit auseinander,
  /// habt ihr "gleichzeitig" aneinander gedacht.
  static const syncWindow = Duration(minutes: 5);

  final _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> _lanterns(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('lanterns');

  /// Höchstens so viele Laternen zeigt der Himmel an einem Tag.
  static const maxPerDay = 1000;

  /// Die Laternen von heute (ab Mitternacht), die neuesten zuerst.
  /// Jeden Tag beginnt der Himmel leer; die alten Laternen bleiben gespeichert.
  /// Geteilt: alle Bildschirme nutzen dieselbe Verbindung (siehe SharedStreams).
  Stream<List<Lantern>> lanterns(String coupleId) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return SharedStreams.get(
      'lanterns/$coupleId/${today.toIso8601String()}',
      () => _lanternsLive(coupleId, today),
    );
  }

  Stream<List<Lantern>> _lanternsLive(String coupleId, DateTime since) =>
      _lanterns(coupleId)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .orderBy('createdAt', descending: true)
          .limit(maxPerDay)
          .snapshots()
          .map(
            (snap) => [
              for (final d in snap.docs)
                Lantern(
                  id: d.id,
                  from: d.data()['from'] as String? ?? '',
                  at:
                      (d.data()['createdAt'] as Timestamp?)?.toDate() ??
                      DateTime.now(),
                ),
            ],
          );

  /// Neue ID vorab holen – so weiss die Animation schon, wohin die Laterne fliegt.
  String newId(String coupleId) => _lanterns(coupleId).doc().id;

  Future<void> send(String coupleId, String id) =>
      _lanterns(coupleId)
          .doc(id)
          .set({'from': _uid, 'createdAt': FieldValue.serverTimestamp()});

  /// Merken, dass ich alle Laternen bis jetzt gesehen habe (der Fuchs kam vorbei).
  Future<void> markSeen() => _db.collection('users').doc(_uid).set({
    'lanternsSeenAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  /// Wie viele Gleichzeitig-Momente gab es? Zwei Laternen von euch beiden
  /// höchstens 5 Minuten auseinander = ein Moment; weitere Laternen kurz danach
  /// zählen nicht nochmal.
  static int syncMoments(List<Lantern> all) {
    final sorted = [...all]..sort((a, b) => a.at.compareTo(b.at));
    var count = 0;
    DateTime? lastMoment;
    for (var i = 1; i < sorted.length; i++) {
      final a = sorted[i - 1], b = sorted[i];
      if (a.from != b.from &&
          b.at.difference(a.at) <= syncWindow &&
          (lastMoment == null || a.at.difference(lastMoment) > syncWindow)) {
        count++;
        lastMoment = b.at;
      }
    }
    return count;
  }

  /// Entsteht durch [added] ein neuer Gleichzeitig-Moment? (Dann wird gefeiert –
  /// jeder Moment genau einmal.)
  static bool addsSyncMoment(List<Lantern> before, List<Lantern> added) =>
      syncMoments([...before, ...added]) > syncMoments(before);
}
