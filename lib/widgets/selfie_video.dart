import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'voice.dart' show formatDuration;

/// Ergebnis einer Selfie-Aufnahme.
typedef SelfieVideo = ({String path, Duration duration});

/// Vollbild-Aufnahme mit der Frontkamera: quadratische Vorschau,
/// grossen Knopf gedrückt halten = aufnehmen, loslassen = fertig (max. 60 s).
/// Gibt das Video per Navigator.pop zurück (oder null bei Abbruch).
class SelfieRecorderPage extends StatefulWidget {
  const SelfieRecorderPage({super.key});

  @override
  State<SelfieRecorderPage> createState() => _SelfieRecorderPageState();
}

class _SelfieRecorderPageState extends State<SelfieRecorderPage> {
  static const _maxLength = Duration(seconds: 60);

  CameraController? _camera;
  String? _error;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      // "medium" (ca. 480p) hält die Dateien klein: etwa 5 MB pro Minute.
      final camera = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await camera.initialize();
      if (!mounted) return await camera.dispose();
      setState(() => _camera = camera);
    } catch (e) {
      setState(() => _error = 'Kamera konnte nicht gestartet werden.\n$e');
    }
  }

  Future<void> _start() async {
    _pressed = true;
    final camera = _camera;
    if (camera == null || camera.value.isRecordingVideo) return;
    // Zeit schon vor dem (manchmal langsamen) Kamerastart nehmen, sonst wird die
    // gespeicherte Länge kürzer als das echte Video.
    final startedAt = DateTime.now();
    await camera.startVideoRecording();
    if (!_pressed) return _stop(); // schon wieder losgelassen
    setState(() {
      _startedAt = startedAt;
      _elapsed = Duration.zero;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      setState(() => _elapsed = DateTime.now().difference(startedAt));
      if (_elapsed >= _maxLength) _stop();
    });
  }

  Future<void> _stop() async {
    _pressed = false;
    final camera = _camera;
    final startedAt = _startedAt;
    if (camera == null || startedAt == null || !camera.value.isRecordingVideo) {
      return;
    }
    _timer?.cancel();
    final duration = DateTime.now().difference(startedAt);
    setState(() => _startedAt = null);
    final file = await camera.stopVideoRecording();
    if (!mounted) return;
    if (duration < const Duration(seconds: 1)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Zu kurz – halte den Knopf gedrückt, solange du sprichst.',
          ),
        ),
      );
      return;
    }
    Navigator.of(context)
        .pop<SelfieVideo>((path: file.path, duration: duration));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final camera = _camera;
    final recording = _startedAt != null;
    final size = MediaQuery.sizeOf(context).width * 0.8;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Selfie-Video'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Center(
              child: SizedBox.square(
                dimension: size,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: camera == null
                      ? Center(
                          child: _error == null
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                        )
                      // Vorschau quadratisch zuschneiden, wie die fertige Videobotschaft.
                      : FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: 100,
                            height: 100 * camera.value.aspectRatio,
                            child: CameraPreview(camera),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Fortschritt als Balken unter der Vorschau.
            SizedBox(
              width: size,
              child: LinearProgressIndicator(
                value: _elapsed.inMilliseconds / _maxLength.inMilliseconds,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
                color: scheme.secondary,
                backgroundColor: Colors.white24,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              recording
                  ? '${formatDuration(_elapsed)} / ${formatDuration(_maxLength)}'
                  : 'Gedrückt halten zum Aufnehmen',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const Spacer(),
            Semantics(
              button: true,
              label: 'Gedrückt halten zum Aufnehmen, loslassen zum Senden',
              child: GestureDetector(
                onLongPressStart: (_) => _start(),
                onLongPressEnd: (_) => _stop(),
                onLongPressCancel: _stop,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: recording ? 92 : 80,
                  height: recording ? 92 : 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: recording ? scheme.error : Colors.white,
                    border: Border.all(color: Colors.white54, width: 4),
                  ),
                  child: Icon(
                    Icons.videocam_rounded,
                    size: 36,
                    color: recording ? scheme.onError : Colors.black,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

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
