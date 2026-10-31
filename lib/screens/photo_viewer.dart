import 'package:flutter/material.dart';

import '../services/album_service.dart';
import '../widgets/who.dart';
import 'albums_screen.dart' show photoCaption;

/// Vollbild-Betrachter: nach links/rechts wischen, mit zwei Fingern zoomen,
/// oben löschen. Zeigt unten, wer das Foto wann hinzugefügt hat.
class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({
    super.key,
    required this.couple,
    required this.album,
    required this.photos,
    required this.initialIndex,
  });

  final Couple couple;
  final Album album;
  final List<AlbumPhoto> photos;
  final int initialIndex;

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late final _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final photo = widget.photos[_index];
    if (!await confirmDelete(context, 'Foto')) return;
    await AlbumService.instance.deletePhoto(
      widget.couple.coupleId,
      widget.album.id,
      photo,
      coverUrl: widget.album.coverUrl,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${photos.length}'),
        actions: [
          IconButton(
            tooltip: 'Foto löschen',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: photos.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    photos[i].url,
                    fit: BoxFit.contain,
                    semanticLabel: 'Foto ${i + 1} von ${photos.length}',
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                        ? child
                        : const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                photoCaption(widget.couple, photos[_index]),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
