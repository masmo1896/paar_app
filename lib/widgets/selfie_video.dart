import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'voice.dart' show formatDuration;

/// Quadratische Videobotschaft im Chat. Antippen öffnet das Video im Vollbild.
class VideoBubble extends StatelessWidget {
  const VideoBubble({super.key, required this.url, required this.duration});

  final String url;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label:
          'Selfie-Videobotschaft, ${formatDuration(duration)}, im Vollbild abspielen',
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => FullscreenVideoPage(url: url),
          ),
        ),
        child: Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: scheme.primaryContainer,
            border: Border.all(color: scheme.secondaryContainer, width: 3),
          ),
          child: Stack(
            children: [
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary,
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: scheme.onPrimary,
                    size: 32,
                  ),
                ),
              ),
              Positioned(
                bottom: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    formatDuration(duration),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vollbild-Player: startet sofort, Antippen = Pause/Weiter, unten Fortschritt und Zeit.
class FullscreenVideoPage extends StatefulWidget {
  const FullscreenVideoPage({super.key, required this.url});

  final String url;

  @override
  State<FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<FullscreenVideoPage> {
  late final VideoPlayerController _video = VideoPlayerController.networkUrl(
    Uri.parse(widget.url),
  );
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _video.addListener(_onUpdate);
    _video
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => _ready = true);
          _video.play();
        })
        .catchError((Object _) {
          if (mounted) setState(() => _failed = true);
        });
  }

  void _onUpdate() {
    // Am Ende zurück an den Anfang und anhalten, damit man nochmals abspielen kann.
    if (_video.value.isCompleted) {
      _video.pause();
      _video.seekTo(Duration.zero);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _video.removeListener(_onUpdate);
    _video.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _video.value;
    final total = value.duration.inMilliseconds;
    final progress = total == 0 ? 0.0 : value.position.inMilliseconds / total;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Videobotschaft'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _ready
                    ? () => value.isPlaying ? _video.pause() : _video.play()
                    : null,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_failed)
                      const Text(
                        'Video konnte nicht geladen werden.',
                        style: TextStyle(color: Colors.white),
                      )
                    else if (!_ready)
                      const CircularProgressIndicator(color: Colors.white)
                    else
                      Center(
                        child: AspectRatio(
                          aspectRatio: value.aspectRatio,
                          child: VideoPlayer(_video),
                        ),
                      ),
                    // Grosses Play-Symbol, solange pausiert.
                    if (_ready && !value.isPlaying)
                      Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black54,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Row(
                children: [
                  Text(
                    formatDuration(value.position),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formatDuration(value.duration),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
