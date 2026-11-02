import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../theme.dart';

/// "mm:ss" für Aufnahme- und Abspieldauer.
String formatDuration(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// So viele Balken hat die gespeicherte Wellenform einer Sprachnachricht.
const waveformBars = 48;

enum VoiceState {
  idle, // keine Aufnahme
  holding, // Finger liegt auf dem Mikrofon
  locked, // hochgeschoben: nimmt ohne Finger weiter auf
  review, // gestoppt: anhören, löschen, neu oder senden
}

/// Steuert eine Sprachaufnahme wie bei WhatsApp/Signal:
/// halten = aufnehmen, loslassen = senden, hochschieben = sperren,
/// nach links schieben = abbrechen. Misst dabei die Lautstärke für die Wellenform.
class VoiceRecorderController extends ChangeNotifier {
  VoiceRecorderController({required this.onSend});

  /// Fertige Aufnahme: Datei, Länge und Wellenform (0–1, [waveformBars] Werte).
  final void Function(String path, Duration duration, List<double> waveform)
  onSend;

  static const maxLength = Duration(minutes: 5);

  /// Ab so viel Verschiebung wird gesperrt bzw. abgebrochen (logische Pixel).
  static const lockDistance = 70.0;
  static const cancelDistance = 110.0;

  final _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _timer;
  DateTime? _startedAt;
  bool _starting = false;
  bool _fingerDown = false;

  VoiceState state = VoiceState.idle;
  Duration elapsed = Duration.zero;

  /// Lautstärke-Messwerte der laufenden Aufnahme (0–1), ca. 12 pro Sekunde.
  final levels = <double>[];

  /// Wie weit der Finger nach links geschoben ist (für den Abbrechen-Hinweis).
  double dragX = 0;
  double dragY = 0;

  // Gestoppte Aufnahme zum Anhören.
  String? reviewPath;
  Duration reviewDuration = Duration.zero;
  List<double> reviewWave = const [];

  bool get active => state != VoiceState.idle;

  /// Finger auf dem Mikrofon: Aufnahme starten.
  Future<void> press(BuildContext context) async {
    _fingerDown = true;
    if (_starting || active) return;
    _starting = true;
    try {
      if (!await _recorder.hasPermission()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Bitte erlaube den Mikrofon-Zugriff in den Einstellungen.',
              ),
            ),
          );
        }
        return;
      }
      await _begin();
      state = VoiceState.holding;
      HapticFeedback.mediumImpact();
      notifyListeners();
    } finally {
      _starting = false;
    }
    // Schon losgelassen, während der Start lief (z. B. Berechtigungsdialog)?
    if (!_fingerDown) await discard();
  }

  Future<void> _begin() async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    levels.clear();
    dragX = dragY = 0;
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    final startedAt = DateTime.now();
    _startedAt = startedAt;
    elapsed = Duration.zero;
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 80))
        .listen((a) {
          // dBFS: ca. -50 (still) bis 0 (laut) -> 0–1.
          levels.add(((a.current + 50) / 50).clamp(0.05, 1.0));
          notifyListeners();
        });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      elapsed = DateTime.now().difference(startedAt);
      notifyListeners();
      if (elapsed >= maxLength) {
        state == VoiceState.holding ? _finishAndSend() : stopToReview();
      }
    });
  }

  /// Finger bewegt sich: hoch = sperren, links = abbrechen.
  void drag(Offset fromStart) {
    if (state != VoiceState.holding) return;
    dragX = math.min(0, fromStart.dx);
    dragY = math.min(0, fromStart.dy);
    if (-dragY > lockDistance) {
      state = VoiceState.locked;
      dragX = dragY = 0;
      HapticFeedback.mediumImpact();
    } else if (-dragX > cancelDistance) {
      HapticFeedback.heavyImpact();
      discard();
      return;
    }
    notifyListeners();
  }

  /// Finger losgelassen: im Halten-Modus sofort senden, gesperrt weiter aufnehmen.
  Future<void> release() async {
    _fingerDown = false;
    if (_starting) return;
    if (state == VoiceState.holding) await _finishAndSend();
  }

  Future<(String?, Duration, List<double>)> _stopRecorder() async {
    _timer?.cancel();
    await _ampSub?.cancel();
    _ampSub = null;
    final startedAt = _startedAt;
    _startedAt = null;
    final duration = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt);
    final path = await _recorder.stop();
    return (path, duration, compress(levels));
  }

  Future<void> _finishAndSend() async {
    final (path, duration, wave) = await _stopRecorder();
    _reset();
    // Unter 1 Sekunde: versehentlich angetippt.
    if (path == null || duration < const Duration(seconds: 1)) return;
    onSend(path, duration, wave);
  }

  /// Gesperrt: Aufnahme beenden und zum Anhören bereitstellen.
  Future<void> stopToReview() async {
    if (state != VoiceState.locked) return;
    final (path, duration, wave) = await _stopRecorder();
    if (path == null || duration < const Duration(seconds: 1)) {
      _reset();
      return;
    }
    reviewPath = path;
    reviewDuration = duration;
    reviewWave = wave;
    state = VoiceState.review;
    notifyListeners();
  }

  /// Gesperrt oder beim Anhören: senden.
  Future<void> send() async {
    if (state == VoiceState.locked) return _finishAndSend();
    if (state == VoiceState.review && reviewPath != null) {
      final path = reviewPath!, duration = reviewDuration, wave = reviewWave;
      _reset();
      onSend(path, duration, wave);
    }
  }

  /// Aufnahme verwerfen (Papierkorb oder nach links geschoben).
  Future<void> discard() async {
    String? path = reviewPath;
    if (_startedAt != null) (path, _, _) = await _stopRecorder();
    _reset();
    if (path != null) {
      unawaited(File(path).delete().then((_) {}, onError: (_) {}));
    }
  }

  /// Verwerfen und sofort neu aufnehmen (bleibt gesperrt).
  Future<void> restart() async {
    await discard();
    await _begin();
    state = VoiceState.locked;
    HapticFeedback.mediumImpact();
    notifyListeners();
  }

  void _reset() {
    state = VoiceState.idle;
    elapsed = Duration.zero;
    dragX = dragY = 0;
    reviewPath = null;
    reviewWave = const [];
    notifyListeners();
  }

  /// Messwerte auf [waveformBars] Balken verdichten (jeweils der lauteste Wert).
  static List<double> compress(List<double> raw) {
    if (raw.isEmpty) return List.filled(waveformBars, 0.15);
    return [
      for (var i = 0; i < waveformBars; i++)
        () {
          final from = (i * raw.length / waveformBars).floor();
          final to = math.max(
            from + 1,
            ((i + 1) * raw.length / waveformBars).floor(),
          );
          final slice = raw.sublist(from, math.min(to, raw.length));
          final peak = slice.isEmpty
              ? raw[math.min(from, raw.length - 1)]
              : slice.reduce(math.max);
          return double.parse(peak.toStringAsFixed(2));
        }(),
    ];
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ampSub?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}

/// Mikrofon-Knopf: halten = aufnehmen, hochschieben = sperren, links = abbrechen.
/// Während man hält, zeigt ein Schloss über dem Knopf, wohin man schieben kann.
class VoiceRecordButton extends StatelessWidget {
  const VoiceRecordButton({super.key, required this.controller});

  final VoiceRecorderController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final holding = controller.state == VoiceState.holding;
        // Je weiter hochgeschoben, desto näher kommt das Schloss.
        final lockPull =
            (-controller.dragY / VoiceRecorderController.lockDistance).clamp(
              0.0,
              1.0,
            );
        return Semantics(
          button: true,
          label:
              'Gedrückt halten für Sprachnachricht. Hochschieben zum Sperren, '
              'nach links zum Abbrechen.',
          child: GestureDetector(
            onLongPressStart: (_) => controller.press(context),
            onLongPressMoveUpdate: (d) => controller.drag(d.offsetFromOrigin),
            onLongPressEnd: (_) => controller.release(),
            onLongPressCancel: controller.release,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Gedrückt halten zum Aufnehmen – hochschieben zum Sperren.',
                ),
                duration: Duration(seconds: 2),
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (holding)
                  Positioned(
                    bottom: 62 + 18 * (1 - lockPull),
                    child: Container(
                      width: 40,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Kitsune.paper,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(color: Colors.black38, blurRadius: 8),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            lockPull > 0.9
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                            color: Kitsune.night,
                            size: 20,
                          ),
                          const Icon(
                            Icons.keyboard_arrow_up_rounded,
                            color: Kitsune.inkSoft,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                Transform.translate(
                  offset: Offset(
                    controller.dragX * 0.4,
                    controller.dragY * 0.4,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: holding ? 64 : 48,
                    height: holding ? 64 : 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: holding ? Kitsune.lantern : scheme.tertiary,
                    ),
                    child: Icon(
                      Icons.mic_rounded,
                      size: holding ? 30 : 24,
                      color: holding ? Kitsune.paper : scheme.onTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Anzeige links im Eingabefeld während der Aufnahme:
/// halten: rote Zeit + Live-Welle + "‹ Zum Abbrechen wischen";
/// gesperrt: Löschen, Zeit + Live-Welle, Stopp;
/// anhören: Löschen, Abspielen mit Wellenform, Neu.
class VoiceRecordingBar extends StatelessWidget {
  const VoiceRecordingBar({super.key, required this.controller});

  final VoiceRecorderController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final live = Row(
          children: [
            const _BlinkingDot(),
            const SizedBox(width: 8),
            Text(
              formatDuration(c.elapsed),
              style: const TextStyle(
                color: Kitsune.paper,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: _LiveWave(levels: c.levels)),
          ],
        );
        final Widget content = switch (c.state) {
          VoiceState.holding => Row(
            children: [
              Expanded(child: live),
              const SizedBox(width: 8),
              // Hinweis rutscht mit dem Finger mit und verblasst.
              Opacity(
                opacity: (1 + c.dragX / VoiceRecorderController.cancelDistance)
                    .clamp(0.2, 1.0),
                child: Transform.translate(
                  offset: Offset(c.dragX * 0.6, 0),
                  child: const Text(
                    '‹ Zum Abbrechen wischen',
                    style: TextStyle(color: Kitsune.mist, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
          VoiceState.locked => Row(
            children: [
              _RoundAction(
                icon: Icons.delete_outline_rounded,
                label: 'Aufnahme löschen',
                onTap: c.discard,
              ),
              const SizedBox(width: 8),
              Expanded(child: live),
              _RoundAction(
                icon: Icons.stop_rounded,
                label: 'Aufnahme beenden und anhören',
                color: Kitsune.lantern,
                onTap: c.stopToReview,
              ),
            ],
          ),
          VoiceState.review => Row(
            children: [
              _RoundAction(
                icon: Icons.delete_outline_rounded,
                label: 'Aufnahme löschen',
                onTap: c.discard,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: AudioBubble(
                  key: ValueKey(c.reviewPath),
                  url: c.reviewPath!,
                  isFile: true,
                  duration: c.reviewDuration,
                  waveform: c.reviewWave,
                  color: Kitsune.paper,
                  accent: Kitsune.lantern,
                ),
              ),
              _RoundAction(
                icon: Icons.restart_alt_rounded,
                label: 'Neu aufnehmen',
                onTap: c.restart,
              ),
            ],
          ),
          VoiceState.idle => const SizedBox.shrink(),
        };
        return Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Kitsune.deeper,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Kitsune.paper.withValues(alpha: 0.15)),
          ),
          child: content,
        );
      },
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onTap,
    icon: Icon(icon, color: color ?? Kitsune.mist),
  );
}

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.25, end: 1.0).animate(_blink),
    child: Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: Kitsune.lantern,
        shape: BoxShape.circle,
      ),
    ),
  );
}

/// Live-Welle während der Aufnahme: die neuesten Messwerte, von rechts einlaufend.
class _LiveWave extends StatelessWidget {
  const _LiveWave({required this.levels});

  final List<double> levels;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final fit = (box.maxWidth / 5).floor();
      final shown = levels.length > fit
          ? levels.sublist(levels.length - fit)
          : levels;
      return CustomPaint(
        size: Size(box.maxWidth, 28),
        painter: _BarsPainter(
          levels: shown,
          progress: 1,
          played: Kitsune.aqua,
          rest: Kitsune.aqua,
          barWidth: 3,
          gap: 2,
          alignRight: true,
        ),
      );
    },
  );
}

/// Wellenform einer Sprachnachricht: gespielter Teil kräftig, Rest blass.
/// Antippen oder Ziehen springt an diese Stelle.
class Waveform extends StatelessWidget {
  const Waveform({
    super.key,
    required this.levels,
    required this.progress,
    required this.color,
    this.onSeek,
    this.height = 30,
  });

  final List<double> levels;
  final double progress; // 0–1
  final Color color;
  final ValueChanged<double>? onSeek;
  final double height;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      void seek(double dx) => onSeek?.call((dx / box.maxWidth).clamp(0.0, 1.0));
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => seek(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => seek(d.localPosition.dx),
        child: CustomPaint(
          size: Size(box.maxWidth, height),
          painter: _BarsPainter(
            levels: levels,
            progress: progress,
            played: color,
            rest: color.withValues(alpha: 0.35),
          ),
        ),
      );
    },
  );
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.levels,
    required this.progress,
    required this.played,
    required this.rest,
    this.barWidth,
    this.gap,
    this.alignRight = false,
  });

  final List<double> levels;
  final double progress;
  final Color played;
  final Color rest;
  final double? barWidth;
  final double? gap;
  final bool alignRight;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    final n = levels.length;
    // Breite so wählen, dass alle Balken passen (Lücke = 2/3 Balkenbreite).
    final w = barWidth ?? size.width / (n * 1.66);
    final g = gap ?? w * 0.66;
    final total = n * w + (n - 1) * g;
    final startX = alignRight ? size.width - total : 0.0;
    final mid = size.height / 2;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w;
    for (var i = 0; i < n; i++) {
      final x = startX + i * (w + g) + w / 2;
      final h = math.max(w, levels[i] * size.height);
      paint.color = (i + 0.5) / n <= progress ? played : rest;
      canvas.drawLine(
        Offset(x, mid - h / 2 + w / 2),
        Offset(x, mid + h / 2 - w / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.progress != progress || old.levels != levels || old.played != played;
}

/// Ersatz-Wellenform für ältere Sprachnachrichten ohne gespeicherte Werte –
/// aus dem Link berechnet, damit sie immer gleich aussieht.
List<double> fallbackWaveform(String seed) {
  final r = math.Random(seed.hashCode);
  return [
    for (var i = 0; i < waveformBars; i++)
      0.25 +
          0.6 * (0.5 + 0.5 * math.sin(i * 0.55)) * (0.6 + 0.4 * r.nextDouble()),
  ];
}

/// Sprachnachricht in der Sprechblase: runder Play-Knopf, Wellenform, Zeit.
class AudioBubble extends StatefulWidget {
  const AudioBubble({
    super.key,
    required this.url,
    required this.duration,
    required this.color,
    required this.accent,
    this.waveform,
    this.isFile = false,
  });

  final String url; // Link oder (mit isFile) lokaler Dateipfad
  final Duration duration;
  final Color color; // Schriftfarbe der Blase (Zeit, blasse Balken)
  final Color accent; // Play-Knopf und gespielte Balken
  final List<double>? waveform;
  final bool isFile;

  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  AudioPlayer? _player; // wird erst beim ersten Abspielen geladen
  bool _loading = false;

  late final _levels = widget.waveform?.isNotEmpty == true
      ? widget.waveform!
      : fallbackWaveform(widget.url);

  Future<AudioPlayer> _ensurePlayer() async {
    final existing = _player;
    if (existing != null) return existing;
    setState(() => _loading = true);
    final player = AudioPlayer();
    widget.isFile
        ? await player.setFilePath(widget.url)
        : await player.setUrl(widget.url);
    // Am Ende zurückspulen, damit man nochmals abspielen kann.
    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        player.pause();
        player.seek(Duration.zero);
      }
    });
    if (mounted) {
      setState(() {
        _player = player;
        _loading = false;
      });
    }
    return player;
  }

  Future<void> _toggle() async {
    final player = await _ensurePlayer();
    player.playing ? await player.pause() : await player.play();
  }

  Future<void> _seek(double fraction) async {
    final player = await _ensurePlayer();
    final total = player.duration ?? widget.duration;
    await player.seek(total * fraction);
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Runder, gefüllter Play-/Pause-Knopf.
        StreamBuilder<bool>(
          stream: player?.playingStream,
          builder: (context, snap) {
            final playing = snap.data ?? false;
            return Semantics(
              button: true,
              label: playing ? 'Pause' : 'Sprachnachricht abspielen',
              child: GestureDetector(
                onTap: _loading ? null : _toggle,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.accent,
                  ),
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Kitsune.paper,
                          ),
                        )
                      : Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Kitsune.paper,
                          size: 26,
                        ),
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 10),
        Flexible(
          child: StreamBuilder<Duration>(
            stream: player?.positionStream,
            builder: (context, snap) {
              final pos = snap.data ?? Duration.zero;
              final total = widget.duration.inMilliseconds;
              final progress = total == 0
                  ? 0.0
                  : (pos.inMilliseconds / total).clamp(0.0, 1.0);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Eigene Ebene: beim Abspielen wird nur die Welle neu gemalt.
                  RepaintBoundary(
                    child: SizedBox(
                      width: 150,
                      child: Waveform(
                        levels: _levels,
                        progress: progress,
                        color: widget.accent,
                        onSeek: _seek,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatDuration(pos > Duration.zero ? pos : widget.duration),
                    style: TextStyle(
                      color: widget.color.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
