import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/shared_stream.dart';

/// Worauf eine Nachricht antwortet: ID, Absender und ein kurzer Vorschautext.
class ReplyTo {
  const ReplyTo({
    required this.id,
    required this.senderId,
    required this.preview,
  });

  factory ReplyTo.fromMap(Map<String, dynamic> map) => ReplyTo(
    id: map['id'] as String? ?? '',
    senderId: map['senderId'] as String? ?? '',
    preview: map['preview'] as String? ?? '',
  );

  final String id;
  final String senderId;
  final String preview;

  Map<String, dynamic> toMap() => {
    'id': id,
    'senderId': senderId,
    // gekürzt, damit das Zitat klein bleibt
    'preview': preview.length > 120 ? '${preview.substring(0, 120)}…' : preview,
  };
}

// Alles rund um "Paar": anlegen, per Code beitreten, Nachrichten.
//
// Datenmodell in Firestore:
//   users/{uid}                    -> { email, name, coupleId, photoUrl? }
//   couples/{coupleId}             -> { members: [uid, uid], inviteCode }
//   invites/{code}                 -> { coupleId }
//   couples/{coupleId}/messages/*  -> { type: 'text'|'image'|'gif'|'audio'|'video'|'file'|'deleted',
//                                       editedAt? (Text wurde bearbeitet),
//                                       text | imageUrl | gifUrl | audioUrl/videoUrl + durationMs (+ waveform)
//                                       | fileUrl + fileName + fileSize,
//                                       senderId, createdAt, read, readAt,
//                                       reactions: { uid: emoji }, replyTo? }
// Dateien liegen in Firebase Storage unter couples/{coupleId}/images/, audio/, videos/ bzw. files/.
class CoupleService {
  CoupleService._();
  static final instance = CoupleService._();

  final _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  /// Profil der Partnerin/des Partners (Name, Profilbild) – null, solange niemand beigetreten ist.
  /// Hast du einen Spitznamen festgelegt (Wir-Seite), steht dieser unter 'name'.
  /// Geteilt: alle Bildschirme nutzen dieselbe Verbindung (siehe SharedStreams).
  Stream<Map<String, dynamic>?> partnerStream(String coupleId) =>
      SharedStreams.get(
        'partner/$_uid/$coupleId',
        () => _partnerStreamLive(coupleId),
      );

  Stream<Map<String, dynamic>?> _partnerStreamLive(String coupleId) =>
      _withNickname(_partnerProfile(coupleId));

  /// Eigener Name für deinen Schatz – nur du siehst ihn. Leer = ihr eigener Name.
  Future<void> setPartnerNickname(String nickname) => _db
      .collection('users')
      .doc(_uid)
      .set({'partnerNickname': nickname.trim()}, SetOptions(merge: true));

  // Verbindet das Profil der anderen Person mit deinem Spitznamen für sie.
  Stream<Map<String, dynamic>?> _withNickname(
    Stream<Map<String, dynamic>?> partner,
  ) {
    late final StreamController<Map<String, dynamic>?> out;
    StreamSubscription<Map<String, dynamic>?>? a, b;
    Map<String, dynamic>? profile;
    var hasProfile = false;
    String? nickname;
    void emit() {
      if (!hasProfile) return;
      final p = profile;
      out.add(
        p == null
            ? null
            : {
                ...p,
                'ownName': p['name'],
                if (nickname != null && nickname!.isNotEmpty) 'name': nickname,
              },
      );
    }

    out = StreamController(
      onListen: () {
        a = partner.listen((v) {
          profile = v;
          hasProfile = true;
          emit();
        }, onError: out.addError);
        b = myProfileStream().listen((me) {
          nickname = (me?['partnerNickname'] as String?)?.trim();
          emit();
        }, onError: out.addError);
      },
      onCancel: () async {
        await a?.cancel();
        await b?.cancel();
      },
    );
    return out.stream;
  }

  Stream<Map<String, dynamic>?> _partnerProfile(
    String coupleId,
  ) => _db.collection('couples').doc(coupleId).snapshots().asyncExpand((
    couple,
  ) {
    final members =
        (couple.data()?['members'] as List?)?.cast<String>() ?? const [];
    final partner = members.where((m) => m != _uid).firstOrNull;
    if (partner == null) return Stream.value(null);
    return _db
        .collection('users')
        .doc(partner)
        .snapshots()
        // uid mitgeben, damit man z. B. die "schreibt…"-Anzeige abfragen kann.
        .map((d) => d.data() == null ? null : {...d.data()!, 'uid': d.id});
  });

  // "schreibt…": pro Person ein Dokument couples/{id}/typing/{uid} mit Zeitstempel.
  DocumentReference<Map<String, dynamic>> _typingRef(
    String coupleId,
    String uid,
  ) => _db.collection('couples').doc(coupleId).collection('typing').doc(uid);

  /// Meldet, ob ich gerade tippe (null-Zeitstempel = tippe nicht).
  Future<void> setTyping(String coupleId, bool typing) => _typingRef(
    coupleId,
    _uid,
  ).set({'at': typing ? FieldValue.serverTimestamp() : null});

  /// Zeitpunkt, zu dem die andere Person zuletzt getippt hat (null = tippt nicht).
  /// Geteilt: alle Bildschirme nutzen dieselbe Verbindung (siehe SharedStreams).
  Stream<DateTime?> typingSince(String coupleId, String partnerUid) =>
      SharedStreams.get(
        'typing/$coupleId/$partnerUid',
        () => _typingSinceLive(coupleId, partnerUid),
      );

  Stream<DateTime?> _typingSinceLive(String coupleId, String partnerUid) =>
      _typingRef(
        coupleId,
        partnerUid,
      ).snapshots().map((d) => (d.data()?['at'] as Timestamp?)?.toDate());

  /// Eigenen Anzeigenamen ändern.
  Future<void> setMyName(String name) => _db.collection('users').doc(_uid).set({
    'name': name,
  }, SetOptions(merge: true));

  /// Eigenes Profilbild aus der Galerie wählen, verkleinert hochladen und speichern.
  /// Gibt false zurück bei Abbruch.
  Future<bool> setMyPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return false;
    // Neuer Dateiname pro Bild, damit das alte nicht aus dem Zwischenspeicher kommt.
    final ref = FirebaseStorage.instance.ref(
      'users/$_uid/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await ref.putData(
      await picked.readAsBytes(),
      SettableMetadata(contentType: 'image/jpeg'),
    );
    await _db.collection('users').doc(_uid).set({
      'photoUrl': await ref.getDownloadURL(),
    }, SetOptions(merge: true));
    return true;
  }

  /// Eigenes Profil (für das ⋮-Menü: aktueller Name).
  /// Geteilt: alle Bildschirme nutzen dieselbe Verbindung (siehe SharedStreams).
  Stream<Map<String, dynamic>?> myProfileStream() =>
      SharedStreams.get('me/$_uid', () => _myProfileStreamLive());

  Stream<Map<String, dynamic>?> _myProfileStreamLive() =>
      _db.collection('users').doc(_uid).snapshots().map((d) => d.data());

  /// Liefert laufend die coupleId des Nutzers (oder null, solange nicht verbunden).
  /// Geteilt: alle Bildschirme nutzen dieselbe Verbindung (siehe SharedStreams).
  Stream<String?> coupleIdStream(String uid) =>
      SharedStreams.get('coupleId/$uid', () => _coupleIdStreamLive(uid));

  Stream<String?> _coupleIdStreamLive(String uid) => _db
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((doc) => doc.data()?['coupleId'] as String?);

  /// Legt ein neues Paar an und gibt den 6-stelligen Einladungscode zurück.
  Future<String> createCouple() async {
    final code = _randomCode();
    final coupleRef = _db.collection('couples').doc();
    final batch = _db.batch()
      ..set(coupleRef, {
        'members': [_uid],
        'inviteCode': code,
        'createdAt': FieldValue.serverTimestamp(),
      })
      ..set(_db.collection('invites').doc(code), {'coupleId': coupleRef.id})
      ..set(_db.collection('users').doc(_uid), {
        'coupleId': coupleRef.id,
      }, SetOptions(merge: true));
    await batch.commit();
    return code;
  }

  /// Tritt mit einem Code dem Paar des Partners bei.
  Future<void> joinCouple(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    final invite = await _db.collection('invites').doc(code).get();
    if (!invite.exists) throw Exception('Code nicht gefunden.');
    final coupleId = invite['coupleId'] as String;

    final batch = _db.batch()
      ..update(_db.collection('couples').doc(coupleId), {
        'members': FieldValue.arrayUnion([_uid]),
      })
      ..set(_db.collection('users').doc(_uid), {
        'coupleId': coupleId,
      }, SetOptions(merge: true));
    await batch.commit();
  }

  CollectionReference<Map<String, dynamic>> messages(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('messages');

  /// Textnachricht; mit [replyTo] als Antwort auf eine andere Nachricht.
  Future<void> sendMessage(String coupleId, String text, {ReplyTo? replyTo}) =>
      messages(coupleId).add({
        'type': 'text',
        'text': text,
        'senderId': _uid,
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
        if (replyTo != null) 'replyTo': replyTo.toMap(),
      });

  /// Text einer eigenen Nachricht ändern; editedAt zeigt "bearbeitet" an.
  Future<void> editMessage(String coupleId, String messageId, String text) =>
      messages(coupleId)
          .doc(messageId)
          .update({'text': text, 'editedAt': FieldValue.serverTimestamp()});

  /// Eigene Nachricht löschen: Inhalt wird entfernt, im Chat steht dann
  /// "Nachricht gelöscht" (so bleiben Antworten darauf verständlich).
  /// Hochgeladene Dateien (Foto, Sprachnachricht, Video, GIF) werden mitgelöscht.
  Future<void> deleteMessage(
    String coupleId,
    String messageId,
    Map<String, dynamic> data,
  ) async {
    for (final key in const ['imageUrl', 'gifUrl', 'audioUrl', 'videoUrl']) {
      final url = data[key] as String?;
      if (url != null &&
          url.startsWith('https://firebasestorage.googleapis.com/')) {
        // Fehlt die Datei schon, ist das egal – die Nachricht wird trotzdem gelöscht.
        await FirebaseStorage.instance
            .refFromURL(url)
            .delete()
            .catchError((_) {});
      }
    }
    await messages(coupleId).doc(messageId).update({
      'type': 'deleted',
      'text': FieldValue.delete(),
      'imageUrl': FieldValue.delete(),
      'gifUrl': FieldValue.delete(),
      'audioUrl': FieldValue.delete(),
      'videoUrl': FieldValue.delete(),
      'durationMs': FieldValue.delete(),
      'reactions': FieldValue.delete(),
      'replyTo': FieldValue.delete(),
      'editedAt': FieldValue.delete(),
    });
  }

  /// Setzt (oder entfernt mit null) die eigene Smiley-Reaktion auf eine Nachricht.
  /// Pro Person gibt es eine Reaktion, gespeichert als reactions: { uid: '❤️' }.
  Future<void> setReaction(String coupleId, String messageId, String? emoji) =>
      messages(coupleId)
          .doc(messageId)
          .update({'reactions.$_uid': emoji ?? FieldValue.delete()});

  /// Lässt ein Foto auswählen/aufnehmen, lädt es hoch und schickt es als Nachricht.
  /// Gibt false zurück, wenn abgebrochen wurde.
  Future<bool> sendPhoto(String coupleId, ImageSource source) async {
    // Verkleinert das Bild schon beim Auswählen -> schneller Upload, wenig Speicher.
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (picked == null) return false;
    await sendPhotoFile(coupleId, picked.path);
    return true;
  }

  /// Lädt ein fertiges Foto (z. B. aus der eigenen Kamera) hoch und schickt es.
  Future<void> sendPhotoFile(String coupleId, String path) async {
    final name = '${DateTime.now().millisecondsSinceEpoch}_$_uid.jpg';
    final ref = FirebaseStorage.instance.ref('couples/$coupleId/images/$name');
    await ref.putFile(File(path), SettableMetadata(contentType: 'image/jpeg'));
    await messages(coupleId).add({
      'type': 'image',
      'imageUrl': await ref.getDownloadURL(),
      'senderId': _uid,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });
  }

  /// Schickt ein GIF. [url] ist ein GIPHY-Link oder ein Link auf Firebase Storage.
  Future<void> sendGif(String coupleId, String url) => messages(coupleId).add({
    'type': 'gif',
    'gifUrl': url,
    'senderId': _uid,
    'createdAt': FieldValue.serverTimestamp(),
    'read': false,
  });

  /// Lässt ein GIF aus der Galerie wählen, lädt es unverändert hoch (damit es animiert
  /// bleibt) und schickt es. Gibt false zurück bei Abbruch; wirft, wenn es kein GIF ist.
  Future<bool> sendGalleryGif(String coupleId) async {
    // Bewusst ohne Verkleinern: das würde das GIF in ein starres JPEG umwandeln.
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return false;
    final isGif =
        picked.name.toLowerCase().endsWith('.gif') ||
        picked.mimeType == 'image/gif';
    if (!isGif) throw Exception('Bitte wähle eine GIF-Datei.');

    final name = '${DateTime.now().millisecondsSinceEpoch}_$_uid.gif';
    final ref = FirebaseStorage.instance.ref('couples/$coupleId/images/$name');
    await ref.putData(
      await picked.readAsBytes(),
      SettableMetadata(contentType: 'image/gif'),
    );
    await sendGif(coupleId, await ref.getDownloadURL());
    return true;
  }

  /// Lädt eine Datei (PDF, Word, Ticket …) hoch und schickt sie als Nachricht.
  /// Jede Datei bekommt einen eigenen Ordner, damit der Originalname bleibt.
  Future<void> sendFile(
    String coupleId, {
    required String path,
    required String name,
    required int size,
  }) async {
    final folder = '${DateTime.now().millisecondsSinceEpoch}_$_uid';
    final ref = FirebaseStorage.instance.ref(
      'couples/$coupleId/files/$folder/$name',
    );
    await ref.putFile(
      File(path),
      SettableMetadata(contentType: mimeTypeFor(name)),
    );
    await messages(coupleId).add({
      'type': 'file',
      'fileUrl': await ref.getDownloadURL(),
      'fileName': name,
      'fileSize': size,
      'senderId': _uid,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });
  }

  /// Lädt eine Selfie-Videobotschaft hoch und schickt sie als Nachricht.
  Future<void> sendVideo(
    String coupleId,
    String filePath,
    Duration duration,
  ) async {
    // Android liefert .mp4, iOS teilweise .mov.
    final isMov = filePath.toLowerCase().endsWith('.mov');
    final name =
        '${DateTime.now().millisecondsSinceEpoch}_$_uid.${isMov ? 'mov' : 'mp4'}';
    final ref = FirebaseStorage.instance.ref('couples/$coupleId/videos/$name');
    await ref.putFile(
      File(filePath),
      SettableMetadata(contentType: isMov ? 'video/quicktime' : 'video/mp4'),
    );
    await messages(coupleId).add({
      'type': 'video',
      'videoUrl': await ref.getDownloadURL(),
      'durationMs': duration.inMilliseconds,
      'senderId': _uid,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });
  }

  /// Lädt eine fertige Sprachaufnahme (m4a-Datei) hoch und schickt sie als Nachricht.
  Future<void> sendVoice(
    String coupleId,
    String filePath,
    Duration duration, {
    List<double>? waveform,
  }) async {
    final name = '${DateTime.now().millisecondsSinceEpoch}_$_uid.m4a';
    final ref = FirebaseStorage.instance.ref('couples/$coupleId/audio/$name');
    await ref.putFile(
      File(filePath),
      SettableMetadata(contentType: 'audio/mp4'),
    );
    await messages(coupleId).add({
      'type': 'audio',
      'audioUrl': await ref.getDownloadURL(),
      'durationMs': duration.inMilliseconds,
      // Lautstärke-Balken für die Wellenform in der Blase (0–1).
      'waveform': ?waveform,
      'senderId': _uid,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });
  }

  /// Markiert Nachrichten der Partnerin als gelesen (für die ✓✓ beim Absender).
  Future<void> markRead(String coupleId, Iterable<String> messageIds) {
    final batch = _db.batch();
    for (final id in messageIds) {
      batch.update(messages(coupleId).doc(id), {
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    return batch.commit();
  }

  /// Kurzer Vorschautext einer Nachricht (für Antwort-Zitate).
  static String previewOf(Map<String, dynamic> data) => switch (data['type']) {
    'image' => '📷 Foto',
    'gif' => 'GIF',
    'audio' => '🎤 Sprachnachricht',
    'video' => '🎥 Videobotschaft',
    'file' => '📎 ${data['fileName'] ?? 'Datei'}',
    'deleted' => 'Gelöschte Nachricht',
    _ => data['text'] as String? ?? '',
  };

  // Ohne leicht verwechselbare Zeichen wie 0/O oder 1/I.
  String _randomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
  }
}

/// Dateityp anhand der Endung (für Speicher und zum Öffnen).
String mimeTypeFor(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return const {
        'pdf': 'application/pdf',
        'doc': 'application/msword',
        'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls': 'application/vnd.ms-excel',
        'xlsx':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'ppt': 'application/vnd.ms-powerpoint',
        'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'txt': 'text/plain',
        'csv': 'text/csv',
        'zip': 'application/zip',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'heic': 'image/heic',
        'mp3': 'audio/mpeg',
        'm4a': 'audio/mp4',
        'mp4': 'video/mp4',
        'mov': 'video/quicktime',
        'pkpass': 'application/vnd.apple.pkpass',
      }[ext] ??
      'application/octet-stream';
}
