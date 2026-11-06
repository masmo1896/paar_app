import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../services/app_logger.dart';

/// Ergebnis der Kamera: Foto oder Video (mit Länge).
typedef CameraShot = ({String path, bool isVideo, Duration duration});

enum CameraMode { video, photo }

/// Kamera im Stil der iPhone-Kamera: schwarzer Rahmen, oben Blitz und Selbstauslöser,
/// Sucher mit 1×/2×-Zoom, darunter VIDEO · FOTO zum Umschalten (auch per Wischen),
/// unten Vorschaubild (öffnet die Galerie), grosser Auslöser und Kamera wechseln.
/// Nach der Aufnahme: "Wiederholen" oder "… verwenden". Gibt [CameraShot] zurück.
class CameraPage extends StatefulWidget {
  const CameraPage({
    super.key,
    this.mode = CameraMode.photo,
    this.front = false,
  });

  final CameraMode mode;

  /// Mit der Frontkamera starten (für Selfie-Videos).
  final bool front;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  static const _yellow = Color(0xFFFFD60A); // Apple-Gelb für aktive Elemente
  static const _maxVideo = Duration(seconds: 60);

  List<CameraDescription> _cameras = [];
  CameraController? _camera;
  String? _error;
  late CameraMode _mode = widget.mode;
  late bool _front = widget.front;

  FlashMode _flash = FlashMode.off;
  int _selfTimer = 0; // 0, 3 oder 10 Sekunden
  int? _countdown; // läuft gerade der Selbstauslöser?
  double _zoom = 1;
  double _maxZoom = 1;
  bool _blink = false; // kurzes Schwarz beim Auslösen

  DateTime? _recordingSince;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;

  CameraShot? _review; // Aufnahme, die gerade begutachtet wird
  String? _lastThumb; // Vorschaubild unten links

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      _cameras = await availableCameras();
      await _open();
    } catch (e, s) {
      AppLogger.error(e, s, where: 'Kamera starten');
      if (!mounted) return;
      setState(() => _error = 'Kamera konnte nicht gestartet werden.\n$e');
    }
  }

  /// (Neu) öffnen – nötig beim Wechsel von Kamera oder Modus.
  Future<void> _open() async {
    final old = _camera;
    setState(() => _camera = null);
    await old?.dispose();
    if (!mounted) return;
    if (_cameras.isEmpty) {
      setState(() => _error = 'Keine Kamera gefunden.');
      return;
    }
    final wanted = _front
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final description = _cameras.firstWhere(
      (c) => c.lensDirection == wanted,
      orElse: () => _cameras.first,
    );
    // Fotos scharf, Videos klein (ca. 5 MB pro Minute).
    final camera = CameraController(
      description,
      _mode == CameraMode.photo
          ? ResolutionPreset.veryHigh
          : ResolutionPreset.medium,
      enableAudio: _mode == CameraMode.video,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await camera.initialize();
      _maxZoom = await camera.getMaxZoomLevel();
      _zoom = 1;
      await camera.setFlashMode(
        _mode == CameraMode.photo ? _flash : FlashMode.off,
      );
    } catch (e, s) {
      AppLogger.error(e, s, where: 'Kamera öffnen');
      await camera.dispose();
      if (mounted) setState(() => _error = 'Kamera-Fehler: $e');
      return;
    }
    if (!mounted) return camera.dispose();
    setState(() {
      _camera = camera;
      _error = null;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  bool get _recording => _recordingSince != null;

  void _setMode(CameraMode mode) {
    if (mode == _mode || _recording || _countdown != null) return;
    HapticFeedback.selectionClick();
    setState(() => _mode = mode);
    _open();
  }

  void _flip() {
    if (_recording || _countdown != null) return;
    HapticFeedback.selectionClick();
    _front = !_front;
    _open();
  }

  Future<void> _cycleFlash() async {
    final next = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    setState(() => _flash = next);
    await _camera?.setFlashMode(next).catchError((_) {});
  }

  void _cycleTimer() => setState(
    () => _selfTimer = switch (_selfTimer) {
      0 => 3,
      3 => 10,
      _ => 0,
    },
  );

  Future<void> _toggleZoom() async {
    final camera = _camera;
    if (camera == null || _maxZoom < 2) return;
    final next = _zoom == 1 ? 2.0 : 1.0;
    HapticFeedback.selectionClick();
    setState(() => _zoom = next);
    await camera.setZoomLevel(next);
  }

  Future<void> _shutter() async {
    if (_camera == null || _countdown != null) return;
    if (_mode == CameraMode.video && _recording) return _stopVideo();
    // Selbstauslöser: 3 … 2 … 1 im Sucher.
    if (_selfTimer > 0) {
      for (var i = _selfTimer; i > 0; i--) {
        if (!mounted) return;
        setState(() => _countdown = i);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (!mounted) return;
      setState(() => _countdown = null);
    }
    _mode == CameraMode.photo ? await _takePhoto() : await _startVideo();
  }

  Future<void> _takePhoto() async {
    final camera = _camera!;
    HapticFeedback.mediumImpact();
    setState(() => _blink = true);
    try {
      final file = await camera.takePicture();
      if (!mounted) return;
      setState(() {
        _blink = false;
        _lastThumb = file.path;
        _review = (path: file.path, isVideo: false, duration: Duration.zero);
      });
    } catch (e, s) {
      AppLogger.error(e, s, where: 'Kamera: Foto aufnehmen');
      if (mounted) setState(() => _blink = false);
      _toast('Foto fehlgeschlagen: $e');
    }
  }

  Future<void> _startVideo() async {
    final camera = _camera!;
    HapticFeedback.mediumImpact();
    // Zeit schon vor dem (manchmal langsamen) Start nehmen, sonst wird die
    // gespeicherte Länge kürzer als das echte Video.
    final since = DateTime.now();
    if (_flash == FlashMode.always && !_front) {
      await camera.setFlashMode(FlashMode.torch).catchError((_) {});
    }
    await camera.startVideoRecording();
    if (!mounted) return;
    setState(() {
      _recordingSince = since;
      _elapsed = Duration.zero;
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      setState(() => _elapsed = DateTime.now().difference(since));
      if (_elapsed >= _maxVideo) _stopVideo();
    });
  }

  Future<void> _stopVideo() async {
    final camera = _camera;
    final since = _recordingSince;
    if (camera == null || since == null) return;
    _ticker?.cancel();
    HapticFeedback.mediumImpact();
    final duration = DateTime.now().difference(since);
    setState(() => _recordingSince = null);
    final file = await camera.stopVideoRecording();
    await camera.setFlashMode(FlashMode.off).catchError((_) {});
    if (!mounted) return;
    if (duration < const Duration(seconds: 1)) {
      _toast('Zu kurz – tippe nochmals, um die Aufnahme zu beenden.');
      return;
    }
    setState(
      () => _review = (path: file.path, isVideo: true, duration: duration),
    );
  }

  /// Vorschaubild unten links: Foto aus der Galerie wählen.
  Future<void> _pickFromGallery() async {
    if (_recording) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (picked == null || !mounted) return;
    Navigator.of(context).pop<CameraShot>((
      path: picked.path,
      isVideo: false,
      duration: Duration.zero,
    ));
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final review = _review;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: review != null
            ? _ReviewView(
                shot: review,
                onRetake: () => setState(() => _review = null),
                onUse: () => Navigator.of(context).pop<CameraShot>(review),
              )
            : SafeArea(
                child: Column(
                  children: [
                    _topBar(),
                    Expanded(child: _viewfinder()),
                    const SizedBox(height: 14),
                    _modeSwitcher(),
                    const SizedBox(height: 14),
                    _bottomBar(),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _topBar() {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_recording)
            // Laufende Aufnahme: rote Zeit-Pille wie beim iPhone.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                _clock(_elapsed),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            )
          else
            _TopIcon(
              tooltip: _selfTimer == 0
                  ? 'Selbstauslöser aus'
                  : 'Selbstauslöser $_selfTimer Sekunden',
              icon: switch (_selfTimer) {
                3 => Icons.timer_3_outlined,
                10 => Icons.timer_10_outlined,
                _ => Icons.timer_outlined,
              },
              active: _selfTimer > 0,
              onTap: _cycleTimer,
            ),
          Positioned(
            left: 12,
            child: _TopIcon(
              tooltip: switch (_flash) {
                FlashMode.auto => 'Blitz automatisch',
                FlashMode.always => 'Blitz an',
                _ => 'Blitz aus',
              },
              icon: switch (_flash) {
                FlashMode.auto => Icons.flash_auto_rounded,
                FlashMode.always => Icons.flash_on_rounded,
                _ => Icons.flash_off_rounded,
              },
              active: _flash != FlashMode.off,
              onTap: _front || _recording ? null : _cycleFlash,
            ),
          ),
          Positioned(
            right: 12,
            child: _TopIcon(
              tooltip: 'Schliessen',
              icon: Icons.close_rounded,
              active: false,
              onTap: _recording ? null : () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewfinder() {
    final camera = _camera;
    // Foto 3:4 wie beim iPhone, Video füllt den Platz (9:16).
    final aspect = _mode == CameraMode.photo ? 3 / 4 : 9 / 16;
    return GestureDetector(
      // Seitlich wischen wechselt zwischen VIDEO und FOTO.
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -200) _setMode(CameraMode.photo);
        if (v > 200) _setMode(CameraMode.video);
      },
      child: Center(
        child: AspectRatio(
          aspectRatio: aspect,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRect(
                child: camera == null
                    ? Center(
                        child: _error == null
                            ? const CircularProgressIndicator(
                                color: Colors.white54,
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
                    // Vorschau so beschneiden, dass sie den Sucher füllt.
                    : FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: 100,
                          height: 100 * camera.value.aspectRatio,
                          child: CameraPreview(camera),
                        ),
                      ),
              ),
              // Kurzes Schwarz beim Auslösen.
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _blink ? 1 : 0,
                  duration: const Duration(milliseconds: 90),
                  child: const ColoredBox(color: Colors.black),
                ),
              ),
              if (_countdown case final n?)
                Center(
                  child: Text(
                    '$n',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 120,
                      fontWeight: FontWeight.w200,
                      shadows: [Shadow(blurRadius: 20)],
                    ),
                  ),
                ),
              if (camera != null && _maxZoom >= 2)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 14,
                  child: Center(child: _zoomPills()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 1× und 2× in einer dunklen Kapsel; die aktive Stufe gelb und grösser.
  Widget _zoomPills() {
    Widget pill(double level) {
      final active = _zoom == level;
      return Semantics(
        button: true,
        selected: active,
        label: 'Zoom ${level.toInt()}-fach',
        child: GestureDetector(
          onTap: active ? null : _toggleZoom,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: active ? 38 : 30,
            height: active ? 38 : 30,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0x99000000),
            ),
            child: Text(
              active ? '${level.toInt()}×' : '${level.toInt()}',
              style: TextStyle(
                color: active ? _yellow : Colors.white,
                fontSize: active ? 13 : 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0x40000000),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [pill(1), pill(2)]),
    );
  }

  /// VIDEO · FOTO: der aktive Modus steht gelb in der Mitte.
  Widget _modeSwitcher() {
    const labelWidth = 76.0;
    final index = CameraMode.values.indexOf(_mode);
    return SizedBox(
      height: 24,
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              top: 0,
              bottom: 0,
              left: box.maxWidth / 2 - labelWidth / 2 - index * labelWidth,
              child: Row(
                children: [
                  for (final mode in CameraMode.values)
                    SizedBox(
                      width: labelWidth,
                      child: Semantics(
                        button: true,
                        selected: mode == _mode,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _setMode(mode),
                          child: Center(
                            child: Text(
                              mode == CameraMode.video ? 'VIDEO' : 'FOTO',
                              style: TextStyle(
                                color: mode == _mode ? _yellow : Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final thumb = _lastThumb;
    return SizedBox(
      height: 84,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Vorschaubild = Galerie öffnen.
          Semantics(
            button: true,
            label: 'Foto aus der Galerie wählen',
            child: GestureDetector(
              onTap: _pickFromGallery,
              child: Container(
                width: 48,
                height: 48,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: thumb != null
                    ? Image.file(
                        File(thumb),
                        fit: BoxFit.cover,
                        cacheWidth: 150,
                      )
                    : const Icon(
                        Icons.photo_library_outlined,
                        color: Colors.white70,
                        size: 22,
                      ),
              ),
            ),
          ),
          _ShutterButton(mode: _mode, recording: _recording, onTap: _shutter),
          // Kamera wechseln (vorne / hinten).
          Semantics(
            button: true,
            label: 'Kamera wechseln',
            child: GestureDetector(
              onTap: _flip,
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF2C2C2E),
                ),
                child: Icon(
                  Icons.cached_rounded,
                  color: _recording ? Colors.white30 : Colors.white,
                  size: 26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _clock(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }
}

/// Weisser Ring mit Kern: Foto = weiss, Video = rot, Aufnahme = rotes Quadrat.
class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
    required this.mode,
    required this.recording,
    required this.onTap,
  });

  final CameraMode mode;
  final bool recording;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFFF3B30);
    final video = mode == CameraMode.video;
    final size = recording ? 30.0 : 62.0;
    return Semantics(
      button: true,
      label: video
          ? (recording ? 'Aufnahme beenden' : 'Video aufnehmen')
          : 'Foto aufnehmen',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: video ? red : Colors.white,
              borderRadius: BorderRadius.circular(recording ? 6 : 31),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopIcon extends StatelessWidget {
  const _TopIcon({
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    icon: Icon(icon, size: 24),
    color: active ? _CameraPageState._yellow : Colors.white,
    disabledColor: Colors.white30,
  );
}

/// Nach der Aufnahme: Foto oder Video ansehen, dann "Wiederholen" oder verwenden.
class _ReviewView extends StatefulWidget {
  const _ReviewView({
    required this.shot,
    required this.onRetake,
    required this.onUse,
  });

  final CameraShot shot;
  final VoidCallback onRetake;
  final VoidCallback onUse;

  @override
  State<_ReviewView> createState() => _ReviewViewState();
}

class _ReviewViewState extends State<_ReviewView> {
  VideoPlayerController? _video;

  @override
  void initState() {
    super.initState();
    if (widget.shot.isVideo) {
      final video = VideoPlayerController.file(File(widget.shot.path));
      _video = video;
      video.initialize().then((_) {
        if (!mounted) return;
        video
          ..setLooping(true)
          ..play();
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: video == null
                  ? Image.file(File(widget.shot.path))
                  : video.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: video.value.aspectRatio,
                      child: VideoPlayer(video),
                    )
                  : const CircularProgressIndicator(color: Colors.white54),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: widget.onRetake,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text(
                    'Wiederholen',
                    style: TextStyle(fontSize: 17),
                  ),
                ),
                TextButton(
                  onPressed: widget.onUse,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: Text(
                    widget.shot.isVideo ? 'Video senden' : 'Foto senden',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
