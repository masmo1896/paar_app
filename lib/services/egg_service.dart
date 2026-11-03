import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/shared_stream.dart';

// Datenmodell in Firestore:
//   couples/{coupleId}/eggs/{yyyy-mm-dd} -> { found: {uid: Zeitpunkt} }
// Wer das versteckte Kanji des Tages gefunden hat (siehe utils/daily_magic.dart).

class EggService {
  EggService._();
  static final instance = EggService._();

  final _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> _day(String coupleId, String day) =>
      _db.collection('couples').doc(coupleId).collection('eggs').doc(day);

  /// Wer hat das Zeichen von [day] schon gefunden? (uids)
  Stream<Set<String>> found(String coupleId, String day) => SharedStreams.get(
    'eggs/$coupleId/$day',
    () => _day(coupleId, day).snapshots().map(
      (d) => {
        ...((d.data()?['found'] as Map?) ?? const {}).keys.cast<String>(),
      },
    ),
  );

  Future<void> markFound(String coupleId, String day) =>
      _day(coupleId, day).set({
        'found': {_uid: FieldValue.serverTimestamp()},
      }, SetOptions(merge: true));
}
