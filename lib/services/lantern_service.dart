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

  /// Gibt es zu [l] eine Laterne der anderen Person im Gleichzeitig-Fenster?
  static bool isSync(Lantern l, List<Lantern> all) => all.any(
    (o) => o.from != l.from && o.at.difference(l.at).abs() <= syncWindow,
  );
}
