import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/couple_service.dart';
import '../theme.dart';
import '../widgets/selfie_video.dart';
import '../widgets/voice.dart' show formatDuration;

/// Ein Foto oder Video aus dem Chat.
class ChatMedia {
  const ChatMedia({
    required this.id,
    required this.isVideo,
    required this.url,
    required this.senderId,
    required this.at,
    this.duration = Duration.zero,
  });

  final String id;
  final bool isVideo;
  final String url;
  final String senderId;
  final DateTime at;
  final Duration duration;
}

/// Alle Fotos und Videos aus dem Chat, die neuesten zuerst.
/// Ohne orderBy in der Abfrage – sonst bräuchte Firestore einen extra Index.
Stream<List<ChatMedia>> chatMediaStream(String coupleId) => CoupleService
    .instance
    .messages(coupleId)
    .where('type', whereIn: ['image', 'video'])
    .snapshots()
    .map((snap) {
      final list = <ChatMedia>[];
      for (final d in snap.docs) {
        final m = d.data();
        final isVideo = m['type'] == 'video';
        final url = (isVideo ? m['videoUrl'] : m['imageUrl']) as String?;
        if (url == null) continue;
        list.add(
          ChatMedia(
            id: d.id,
            isVideo: isVideo,
            url: url,
            senderId: m['senderId'] as String? ?? '',
            at: (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
            duration: Duration(milliseconds: m['durationMs'] as int? ?? 0),
          ),
        );
      }
      return list..sort((a, b) => b.at.compareTo(a.at));
    });

enum _Filter { alle, fotos, videos }

/// Ordner "Aus dem Chat": Raster nach Monaten, Filter Alle / Fotos / Videos.
class ChatMediaScreen extends StatefulWidget {
  const ChatMediaScreen({super.key, required this.coupleId});

  final String coupleId;

  @override
  State<ChatMediaScreen> createState() => _ChatMediaScreenState();
}

class _ChatMediaScreenState extends State<ChatMediaScreen> {
  late final _media = chatMediaStream(widget.coupleId);
  var _filter = _Filter.alle;

  static const _months = [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: kitsuneAppBar(
        art: KitsuneArt.leaves,
        kana: 'しゃしん',
        titleText: 'Aus dem Chat',
        height: 104,
      ),
      body: StreamBuilder<List<ChatMedia>>(
        stream: _media,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Konnte nicht geladen werden.'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data!;
          final shown = [
            for (final m in all)
              if (_filter == _Filter.alle ||
                  (_filter == _Filter.videos) == m.isVideo)
                m,
          ];
          final photos = all.where((m) => !m.isVideo).length;
          final videos = all.length - photos;

          // Nach Monat gruppieren ("November 2026").
          final groups = <String, List<ChatMedia>>{};
          for (final m in shown) {
            final key = '${_months[m.at.month - 1]} ${m.at.year}';
            (groups[key] ??= []).add(m);
          }

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final (f, label) in [
                        (_Filter.alle, 'Alle ${all.length}'),
                        (_Filter.fotos, 'Fotos $photos'),
                        (_Filter.videos, 'Videos $videos'),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          showCheckmark: false,
                          // Ausgewählt: Papier mit dunkler Schrift, gut lesbar.
                          labelStyle: TextStyle(
                            color: _filter == f ? Kitsune.night : Kitsune.paper,
                          ),
                          selectedColor: Kitsune.paper,
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                    ],
                  ),
                ),
              ),
              if (shown.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'Noch nichts hier 📸\nFotos und Videos aus dem Chat\nlanden automatisch in diesem Ordner.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              for (final MapEntry(key: month, value: items)
                  in groups.entries) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Text(month, style: AppTheme.serif(size: 17)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _Tile(
                      media: items[i],
                      onTap: () => _open(context, items[i], shown),
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }

  void _open(BuildContext context, ChatMedia media, List<ChatMedia> shown) {
    if (media.isVideo) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => FullscreenVideoPage(url: media.url),
        ),
      );
      return;
    }
    final photos = shown.where((m) => !m.isVideo).toList();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PhotoPager(
          coupleId: widget.coupleId,
          photos: photos,
          initialIndex: photos.indexOf(media),
        ),
      ),
    );
  }
}

/// Quadratische Kachel: Foto als Vorschau, Video als Nachtblau mit Play-Knopf.
class _Tile extends StatelessWidget {
  const _Tile({required this.media, required this.onTap});

  final ChatMedia media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: media.isVideo
          ? 'Video, ${formatDuration(media.duration)}'
          : 'Foto vom ${media.at.day}.${media.at.month}.',
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: media.isVideo
              ? DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Kitsune.indigo, Kitsune.plum],
                    ),
                  ),
                  child: Stack(
                    children: [
                      const Center(
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: Kitsune.lantern,
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: Kitsune.paper,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 6,
                        bottom: 5,
                        child: Text(
                          formatDuration(media.duration),
                          style: const TextStyle(
                            color: Kitsune.paper,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : ColoredBox(
                  color: Kitsune.deep,
                  child: Image.network(
                    media.url,
                    fit: BoxFit.cover,
                    cacheWidth: 300, // klein dekodieren, spart Speicher
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Kitsune.dim,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Fotos im Vollbild: wischen, mit zwei Fingern zoomen; unten wer und wann.
class _PhotoPager extends StatefulWidget {
  const _PhotoPager({
    required this.coupleId,
    required this.photos,
    required this.initialIndex,
  });

  final String coupleId;
  final List<ChatMedia> photos;
  final int initialIndex;

  @override
  State<_PhotoPager> createState() => _PhotoPagerState();
}

class _PhotoPagerState extends State<_PhotoPager> {
  late final _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  final _myUid = FirebaseAuth.instance.currentUser!.uid;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_index + 1} / ${widget.photos.length}',
          style: const TextStyle(fontSize: 16, color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.photos.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => InteractiveViewer(
                child: Center(child: Image.network(widget.photos[i].url)),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: StreamBuilder<Map<String, dynamic>?>(
                stream: CoupleService.instance.partnerStream(widget.coupleId),
                builder: (context, snap) {
                  final partner = (snap.data?['name'] as String?)?.trim();
                  final who = photo.senderId == _myUid
                      ? 'Von dir'
                      : 'Von ${partner == null || partner.isEmpty ? 'deinem Schatz' : partner}';
                  final t = photo.at;
                  return Text(
                    '$who · ${t.day}.${t.month}.${t.year}',
                    style: const TextStyle(color: Colors.white70),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
