import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/shared_stream.dart';

// Datenmodell:
//   couples/{coupleId}/albums/{albumId}              -> { name, coverUrl?, photoCount, createdBy, createdAt }
//   couples/{coupleId}/albums/{albumId}/photos/{id}  -> { url, path, addedBy, createdAt }
// Die Bilddateien liegen in Firebase Storage unter couples/{coupleId}/albums/{albumId}/.

class Album {
  const Album({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.photoCount,
    required this.createdAt,
  });

  factory Album.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Album(
      id: doc.id,
      name: d['name'] as String? ?? '',
      coverUrl: d['coverUrl'] as String?,
      photoCount: (d['photoCount'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String name;
  final String? coverUrl; // Titelbild = zuletzt hinzugefügtes Foto
  final int photoCount;
  final DateTime? createdAt;
}

class AlbumPhoto {
  const AlbumPhoto({
    required this.id,
    required this.url,
    required this.path,
    required this.addedBy,
    required this.createdAt,
  });

  factory AlbumPhoto.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return AlbumPhoto(
      id: doc.id,
      url: d['url'] as String? ?? '',
      path: d['path'] as String? ?? '',
      addedBy: d['addedBy'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String url;
  final String path; // Pfad in Firebase Storage (zum Löschen)
  final String addedBy; // uid
  final DateTime? createdAt;
}

/// Gemeinsame Fotoalben.
class AlbumService {
  AlbumService._();
  static final instance = AlbumService._();

  final _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> _albums(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('albums');

  CollectionReference<Map<String, dynamic>> _photos(
    String coupleId,
    String albumId,
  ) => _albums(coupleId).doc(albumId).collection('photos');

  /// Geteilt: alle Bildschirme nutzen dieselbe Verbindung (siehe SharedStreams).
  Stream<List<Album>> albums(String coupleId) =>
      SharedStreams.get('albums/$coupleId', () => _albumsLive(coupleId));

  Stream<List<Album>> _albumsLive(String coupleId) =>
      _albums(coupleId)
          .snapshots()
          .map((s) => s.docs.map(Album.fromDoc).toList());

  /// Geteilt: alle Bildschirme nutzen dieselbe Verbindung (siehe SharedStreams).
  Stream<Album?> album(String coupleId, String albumId) => SharedStreams.get(
    'album/$coupleId/$albumId',
    () => _albumLive(coupleId, albumId),
  );

  Stream<Album?> _albumLive(String coupleId, String albumId) =>
      _albums(coupleId)
          .doc(albumId)
          .snapshots()
          .map((d) => d.exists ? Album.fromDoc(d) : null);

  /// Geteilt: alle Bildschirme nutzen dieselbe Verbindung (siehe SharedStreams).
  Stream<List<AlbumPhoto>> photos(String coupleId, String albumId) =>
      SharedStreams.get(
        'photos/$coupleId/$albumId',
        () => _photosLive(coupleId, albumId),
      );

  Stream<List<AlbumPhoto>> _photosLive(String coupleId, String albumId) =>
      _photos(coupleId, albumId)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map(AlbumPhoto.fromDoc).toList());

  Future<String> createAlbum(String coupleId, String name) async {
    final ref = await _albums(coupleId).add({
      'name': name,
      'photoCount': 0,
      'createdBy': _uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> renameAlbum(String coupleId, String albumId, String name) =>
      _albums(coupleId).doc(albumId).update({'name': name});

  /// Löscht das Album samt aller Fotos (auch die Dateien im Speicher).
  Future<void> deleteAlbum(String coupleId, String albumId) async {
    final photos = await _photos(coupleId, albumId).get();
    for (final p in photos.docs) {
      final path = p.data()['path'] as String?;
      if (path != null && path.isNotEmpty) {
        // Fehlt die Datei schon, ist das egal.
        await FirebaseStorage.instance.ref(path).delete().catchError((_) {});
      }
    }
    // Firestore erlaubt höchstens 500 Schreibvorgänge pro Batch.
    for (var i = 0; i < photos.docs.length; i += 400) {
      final batch = _db.batch();
      for (final p in photos.docs.skip(i).take(400)) {
        batch.delete(p.reference);
      }
      await batch.commit();
    }
    await _albums(coupleId).doc(albumId).delete();
  }

  /// Lädt die gewählten Bilder hoch. [onProgress] meldet (fertig, gesamt).
  Future<void> addPhotos(
    String coupleId,
    String albumId,
    List<XFile> files, {
    void Function(int done, int total)? onProgress,
  }) async {
    String? lastUrl;
    var added = 0;
    for (final file in files) {
      onProgress?.call(added, files.length);
      final name = '${DateTime.now().microsecondsSinceEpoch}_$_uid.jpg';
      final path = 'couples/$coupleId/albums/$albumId/$name';
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(
        await file.readAsBytes(),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await ref.getDownloadURL();
      await _photos(coupleId, albumId).add({
        'url': url,
        'path': path,
        'addedBy': _uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      lastUrl = url;
      added++;
      // Zähler und Titelbild nach jedem Foto, damit nichts verloren geht, wenn es abbricht.
      await _albums(coupleId)
          .doc(albumId)
          .update({'coverUrl': lastUrl, 'photoCount': FieldValue.increment(1)});
    }
    onProgress?.call(added, files.length);
  }

  /// Löscht ein Foto und passt Zähler und Titelbild an.
  Future<void> deletePhoto(
    String coupleId,
    String albumId,
    AlbumPhoto photo, {
    String? coverUrl,
  }) async {
    if (photo.path.isNotEmpty) {
      await FirebaseStorage.instance
          .ref(photo.path)
          .delete()
          .catchError((_) {});
    }
    await _photos(coupleId, albumId).doc(photo.id).delete();

    final update = <String, dynamic>{'photoCount': FieldValue.increment(-1)};
    if (coverUrl == photo.url) {
      // Das Titelbild wurde gelöscht: das neueste übrige Foto nehmen.
      final next = await _photos(
        coupleId,
        albumId,
      ).orderBy('createdAt', descending: true).limit(1).get();
      update['coverUrl'] = next.docs.isEmpty
          ? FieldValue.delete()
          : next.docs.first.data()['url'];
    }
    await _albums(coupleId).doc(albumId).update(update);
  }
}
