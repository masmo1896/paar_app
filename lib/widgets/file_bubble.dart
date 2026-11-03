import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../services/couple_service.dart' show mimeTypeFor;
import '../theme.dart';
import '../services/app_logger.dart';

/// "1,4 MB", "820 KB"
String formatFileSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(1).replaceAll('.', ',')} MB';
}

/// Symbol und Farbe je nach Dateiart.
(IconData, Color) _iconFor(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'pdf' => (Icons.picture_as_pdf_rounded, Kitsune.lantern),
    'doc' || 'docx' || 'txt' => (Icons.description_rounded, Kitsune.sky),
    'xls' || 'xlsx' || 'csv' => (Icons.table_chart_rounded, Color(0xFF2E9E6A)),
    'ppt' || 'pptx' => (Icons.slideshow_rounded, Color(0xFFE0782F)),
    'zip' => (Icons.folder_zip_rounded, Kitsune.plum),
    'mp3' || 'm4a' || 'wav' => (Icons.audiotrack_rounded, Kitsune.plum),
    'mp4' || 'mov' => (Icons.movie_rounded, Kitsune.plum),
    'jpg' || 'jpeg' || 'png' || 'heic' => (Icons.image_rounded, Kitsune.sky),
    _ => (Icons.insert_drive_file_rounded, Kitsune.indigo),
  };
}

/// Datei in der Sprechblase: Symbol, Name, Grösse. Antippen lädt die Datei
/// (einmal, danach aus dem Zwischenspeicher) und öffnet sie mit der passenden
/// App auf dem Handy (PDF-Ansicht, Word, Dateien …).
class FileBubble extends StatefulWidget {
  const FileBubble({
    super.key,
    required this.url,
    required this.name,
    required this.size,
    required this.color,
  });

  final String url;
  final String name;
  final int size;
  final Color color; // Schriftfarbe der Blase

  @override
  State<FileBubble> createState() => _FileBubbleState();
}

class _FileBubbleState extends State<FileBubble> {
  double? _progress; // gesetzt = wird gerade geladen

  Future<File> _localFile() async {
    final dir = await getTemporaryDirectory();
    // Eigener Ordner pro Datei (aus dem Link), damit der Originalname bleibt.
    final folder = Directory(
      '${dir.path}/chat_files/${widget.url.hashCode.toUnsigned(32)}',
    );
    await folder.create(recursive: true);
    return File('${folder.path}/${widget.name}');
  }

  Future<void> _open() async {
    if (_progress != null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await _localFile();
      if (!await file.exists() || await file.length() == 0) {
        setState(() => _progress = 0);
        final response = await http.Client().send(
          http.Request('GET', Uri.parse(widget.url)),
        );
        if (response.statusCode != 200) {
          throw Exception('Server antwortet mit ${response.statusCode}');
        }
        final total = response.contentLength ?? widget.size;
        var received = 0;
        final sink = file.openWrite();
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (mounted && total > 0) {
            setState(() => _progress = received / total);
          }
        }
        await sink.close();
      }
      if (mounted) setState(() => _progress = null);
      final result = await OpenFilex.open(
        file.path,
        type: mimeTypeFor(widget.name),
      );
      if (result.type == ResultType.noAppToOpen) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Keine App zum Öffnen dieser Datei gefunden.'),
          ),
        );
      } else if (result.type != ResultType.done) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Konnte nicht geöffnet werden: ${result.message}'),
          ),
        );
      }
    } catch (e, s) {
      AppLogger.error(e, s, where: 'Datei öffnen');
      if (mounted) setState(() => _progress = null);
      messenger.showSnackBar(
        SnackBar(content: Text('Datei konnte nicht geladen werden: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, iconColor) = _iconFor(widget.name);
    final progress = _progress;
    return Semantics(
      button: true,
      label: 'Datei ${widget.name}, ${formatFileSize(widget.size)}, öffnen',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _open,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: progress == null
                    ? Icon(icon, color: iconColor, size: 26)
                    : Padding(
                        padding: const EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          value: progress == 0 ? null : progress,
                          strokeWidth: 2.5,
                          color: iconColor,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.color,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      progress == null
                          ? '${formatFileSize(widget.size)} · Tippen zum Öffnen'
                          : 'Wird geladen …',
                      style: TextStyle(
                        color: widget.color.withValues(alpha: 0.75),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
