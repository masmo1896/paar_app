import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme.dart';
import '../services/album_service.dart';
import '../utils/dates.dart';
import '../widgets/who.dart';
import 'photo_viewer.dart';
import '../services/app_logger.dart';

/// Alle gemeinsamen Alben als Kacheln mit Titelbild.
class AlbumsScreen extends StatelessWidget {
  const AlbumsScreen({super.key, required this.couple});

  final Couple couple;

  Future<void> _create(BuildContext context) async {
    final name = await _askName(
      context,
      title: 'Neues Album',
      confirm: 'Erstellen',
    );
    if (name == null || !context.mounted) return;
    final id = await AlbumService.instance.createAlbum(couple.coupleId, name);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AlbumScreen(couple: couple, albumId: id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: kitsuneAppBar(
        art: KitsuneArt.leaves,
        kana: 'おもいで',
        titleText: 'Unsere Alben',
        height: 104,
      ),
      body: StreamBuilder<List<Album>>(
        stream: AlbumService.instance.albums(couple.coupleId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          // Neueste Alben zuerst; ein Album, das gerade erst angelegt wird, ganz oben.
          final albums = snap.data!.toList()
            ..sort((a, b) {
              final at = a.createdAt, bt = b.createdAt;
              if (at == null) return -1;
              if (bt == null) return 1;
              return bt.compareTo(at);
            });
          if (albums.isEmpty) {
            return const Center(
              child: Text(
                'Noch kein Album 📸\nMit + legst du eines an, z. B. „Urlaub 2026“.',
                textAlign: TextAlign.center,
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.9,
            ),
            itemCount: albums.length,
            itemBuilder: (context, i) => _AlbumTile(
              album: albums[i],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      AlbumScreen(couple: couple, albumId: albums[i].id),
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Album erstellen',
        onPressed: () => _create(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({required this.album, required this.onTap});

  final Album album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cover = album.coverUrl;
    return Semantics(
      button: true,
      label: '${album.name}, ${album.photoCount} Fotos',
      // Wie ein Abzug auf Washi-Papier: Foto mit cremefarbenem Rand, Name darunter.
      child: Material(
        color: Kitsune.paper,
        borderRadius: BorderRadius.circular(4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    color: Kitsune.deep,
                    child: cover != null
                        ? Image(
                            image: ResizeImage(
                              CachedNetworkImageProvider(cover),
                              width: 500, // klein dekodieren, spart Speicher
                            ),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          )
                        : const Icon(
                            Icons.photo_library_outlined,
                            size: 40,
                            color: Kitsune.dim,
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                  child: Text(
                    album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.serif(size: 15, color: Kitsune.night),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
                  child: Text(
                    album.photoCount == 1
                        ? '1 Foto'
                        : '${album.photoCount} Fotos',
                    style: const TextStyle(
                      color: Kitsune.inkSoft,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fragt nach einem Albumnamen. null = abgebrochen.
Future<String?> _askName(
  BuildContext context, {
  required String title,
  required String confirm,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'z. B. Urlaub 2026',
          counterText: '',
        ),
        onSubmitted: (v) => Navigator.pop(dialogContext, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          child: Text(confirm),
        ),
      ],
    ),
  );
  controller.dispose();
  final trimmed = name?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Ein Album: Fotoraster, Fotos hinzufügen, umbenennen, löschen.
class AlbumScreen extends StatefulWidget {
  const AlbumScreen({super.key, required this.couple, required this.albumId});

  final Couple couple;
  final String albumId;

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  // (fertig, gesamt) während eines Uploads, sonst null.
  (int, int)? _upload;

  Couple get couple => widget.couple;

  Future<void> _addPhotos() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Aus Galerie wählen (mehrere möglich)'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Foto aufnehmen'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    // Beim Auswählen schon verkleinern: schneller Upload, wenig Speicher.
    final picker = ImagePicker();
    final files = source == ImageSource.gallery
        ? await picker.pickMultiImage(
            maxWidth: 1600,
            maxHeight: 1600,
            imageQuality: 80,
          )
        : [
            ?await picker.pickImage(
              source: source,
              maxWidth: 1600,
              maxHeight: 1600,
              imageQuality: 80,
            ),
          ];
    if (files.isEmpty || !mounted) return;

    setState(() => _upload = (0, files.length));
    try {
      await AlbumService.instance.addPhotos(
        couple.coupleId,
        widget.albumId,
        files,
        onProgress: (done, total) {
          if (mounted) setState(() => _upload = (done, total));
        },
      );
    } catch (e, s) {
      AppLogger.error(e, s, where: 'Album: Fotos hochladen');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotos konnten nicht hochgeladen werden: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _upload = null);
    }
  }

  Future<void> _rename(Album album) async {
    final name = await _askName(
      context,
      title: 'Album umbenennen',
      confirm: 'Speichern',
      initial: album.name,
    );
    if (name != null) {
      await AlbumService.instance.renameAlbum(couple.coupleId, album.id, name);
    }
  }

  Future<void> _delete(Album album) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Album löschen?'),
        content: Text(
          'Das Album „${album.name}“ und alle ${album.photoCount} Fotos werden für euch beide gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AlbumService.instance.deleteAlbum(couple.coupleId, album.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Album?>(
      stream: AlbumService.instance.album(couple.coupleId, widget.albumId),
      builder: (context, albumSnap) {
        final album = albumSnap.data;
        if (album == null) {
          // Noch am Laden oder von der anderen Person gelöscht.
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: albumSnap.connectionState == ConnectionState.waiting
                  ? const CircularProgressIndicator()
                  : const Text('Dieses Album gibt es nicht mehr.'),
            ),
          );
        }
        final upload = _upload;
        return Scaffold(
          appBar: AppBar(
            title: Text(album.name),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Menü',
                onSelected: (v) =>
                    v == 'rename' ? _rename(album) : _delete(album),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'rename',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Umbenennen'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Album löschen'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              if (upload != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lade ${upload.$1 + (upload.$1 < upload.$2 ? 1 : 0)} von ${upload.$2} hoch …',
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: upload.$2 == 0 ? null : upload.$1 / upload.$2,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: StreamBuilder<List<AlbumPhoto>>(
                  stream: AlbumService.instance.photos(
                    couple.coupleId,
                    widget.albumId,
                  ),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final photos = snap.data!;
                    if (photos.isEmpty) {
                      return const Center(
                        child: Text(
                          'Noch keine Fotos.\nMit „Fotos hinzufügen“ geht es los.',
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(3, 0, 3, 96),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 3,
                            crossAxisSpacing: 3,
                          ),
                      itemCount: photos.length,
                      itemBuilder: (context, i) => InkWell(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PhotoViewerPage(
                              couple: couple,
                              album: album,
                              photos: photos,
                              initialIndex: i,
                            ),
                          ),
                        ),
                        child: Image(
                          image: ResizeImage(
                            CachedNetworkImageProvider(photos[i].url),
                            width: 360,
                          ),
                          fit: BoxFit.cover,
                          semanticLabel: 'Foto ${i + 1} von ${photos.length}',
                          errorBuilder: (_, _, _) => const ColoredBox(
                            color: Colors.black12,
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: upload == null ? _addPhotos : null,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Fotos hinzufügen'),
          ),
        );
      },
    );
  }
}

/// Wer hat das Foto wann hinzugefügt? "Von Du · Fr, 30. Okt."
String photoCaption(Couple couple, AlbumPhoto photo) {
  final who = couple.label(photo.addedBy);
  final date = photo.createdAt;
  return date == null ? 'Von $who' : 'Von $who · ${shortDay(date)}';
}
