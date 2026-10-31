import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// "mm:ss" für Aufnahme- und Abspieldauer.
String formatDuration(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// Mikrofon-Knopf: gedrückt halten = aufnehmen, loslassen = senden.
/// Kürzer als 1 Sekunde wird verworfen, nach 2 Minuten wird automatisch gesendet.
class VoiceRecordButton extends StatefulWidget {
  const VoiceRecordButton({
    super.key,
    required this.onRecorded,
    required this.onElapsed,
  });

  /// Fertige Aufnahme: Dateipfad + Länge.
  final void Function(String path, Duration duration) onRecorded;

  /// Laufende Aufnahmezeit (null = keine Aufnahme), für die Anzeige im Chat.
  final ValueChanged<Duration?> onElapsed;

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton> {
  static const _maxLength = Duration(minutes: 2);

  final _recorder = AudioRecorder();
  Timer? _timer;
  DateTime? _startedAt;
  bool _starting = false; // Start läuft noch (z. B. Berechtigungsdialog offen)
  bool _pressed = false; // Finger liegt gerade auf dem Knopf

  bool get _recording => _startedAt != null;

  Future<void> _start() async {
    _pressed = true;
    if (_starting || _recording) return;
    _starting = true;
    try {
      await _startRecording();
    } finally {
      _starting = false;
    }
    // Schon losgelassen, während der Start lief (z. B. beim Berechtigungsdialog)?
    if (!_pressed) await _stop(discard: true);
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) {
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
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );

    if (!mounted) return;
    final startedAt = DateTime.now();
    setState(() => _startedAt = startedAt);
    widget.onElapsed(Duration.zero);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final elapsed = DateTime.now().difference(startedAt);
      widget.onElapsed(elapsed);
      if (elapsed >= _maxLength) _stop();
    });
  }

  Future<void> _release() async {
    _pressed = false;
    if (!_starting) await _stop();
  }

  Future<void> _stop({bool discard = false}) async {
    final startedAt = _startedAt;
    if (startedAt == null) return;
    _timer?.cancel();
    final duration = DateTime.now().difference(startedAt);
    if (mounted) setState(() => _startedAt = null);
    widget.onElapsed(null);

    final path = await _recorder.stop();
    if (path == null || discard) return;
    // Versehentlich angetippt.
    if (duration < const Duration(seconds: 1)) return;
    widget.onRecorded(path, duration);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Gedrückt halten für Sprachnachricht',
      child: GestureDetector(
        onLongPressStart: (_) => _start(),
        onLongPressEnd: (_) => _release(),
        onLongPressCancel: _release,
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Gedrückt halten zum Aufnehmen, loslassen zum Senden.',
            ),
            duration: Duration(seconds: 2),
          ),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: _recording ? 56 : 48,
          height: _recording ? 56 : 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _recording ? scheme.error : scheme.tertiary,
          ),
          child: Icon(
            Icons.mic_rounded,
            color: _recording ? scheme.onError : scheme.onTertiary,
          ),
        ),
      ),
    );
  }
}

/// Sprachnachricht in der Sprechblase: Play/Pause, Fortschritt, Länge.
class AudioBubble extends StatefulWidget {
  const AudioBubble({
    super.key,
    required this.url,
    required this.duration,
    required this.color,
  });

  final String url;
  final Duration duration;
  final Color color; // Schriftfarbe der Blase

  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  AudioPlayer? _player; // wird erst beim ersten Abspielen geladen
  bool _loading = false;

  Future<void> _toggle() async {
    var player = _player;
    if (player == null) {
      setState(() => _loading = true);
      player = AudioPlayer();
      await player.setUrl(widget.url);
      // Am Ende zurückspulen, damit man nochmals abspielen kann.
      player.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) {
          player!.pause();
          player.seek(Duration.zero);
        }
      });
      setState(() {
        _player = player;
        _loading = false;
      });
    }
    player.playing ? await player.pause() : await player.play();
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
        SizedBox(
          width: 40,
          height: 40,
          child: _loading
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.color,
                  ),
                )
              : StreamBuilder<bool>(
                  stream: player?.playingStream,
                  builder: (context, snap) {
                    final playing = snap.data ?? false;
                    return IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: _toggle,
                      tooltip: playing ? 'Pause' : 'Abspielen',
                      icon: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: widget.color,
                        size: 30,
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(width: 6),
        StreamBuilder<Duration>(
          stream: player?.positionStream,
          builder: (context, snap) {
            final pos = snap.data ?? Duration.zero;
            final total = widget.duration.inMilliseconds;
            final progress = total == 0
                ? 0.0
                : (pos.inMilliseconds / total).clamp(0.0, 1.0);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 120,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                    color: widget.color,
                    backgroundColor: widget.color.withValues(alpha: 0.3),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatDuration(pos > Duration.zero ? pos : widget.duration),
                  style: TextStyle(color: widget.color, fontSize: 13),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
