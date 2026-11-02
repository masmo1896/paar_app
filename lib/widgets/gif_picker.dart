import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// Was im GIF-Fenster ausgewählt wurde: ein GIPHY-GIF (Link) oder "aus Galerie".
sealed class GifChoice {}

class GiphyGif extends GifChoice {
  GiphyGif(this.url);
  final String url;
}

class GalleryGif extends GifChoice {}

/// Unteres Fenster mit GIPHY-Suche und Knopf für GIFs aus der Galerie.
class GifPickerSheet extends StatefulWidget {
  const GifPickerSheet({super.key});

  static Future<GifChoice?> show(BuildContext context) =>
      showModalBottomSheet<GifChoice>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const GifPickerSheet(),
      );

  @override
  State<GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends State<GifPickerSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<({String preview, String full})> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (giphyApiKey.isNotEmpty) _load(''); // zuerst die aktuell beliebten GIFs
  }

  // Erst suchen, wenn 400 ms nicht mehr getippt wurde (spart Anfragen).
  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _load(text.trim()),
    );
  }

  Future<void> _load(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final uri = Uri.https(
      'api.giphy.com',
      query.isEmpty ? '/v1/gifs/trending' : '/v1/gifs/search',
      {
        'api_key': giphyApiKey,
        'limit': '30',
        'rating': 'pg-13',
        if (query.isNotEmpty) 'q': query,
        if (query.isNotEmpty) 'lang': 'de',
      },
    );
    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('GIPHY antwortet mit ${response.statusCode}');
      }
      final data = (jsonDecode(response.body)['data'] as List)
          .cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _results = [
          for (final gif in data)
            (
              preview: gif['images']['fixed_width_small']['url'] as String,
              full: gif['images']['fixed_width']['url'] as String,
            ),
        ];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'GIFs konnten nicht geladen werden.';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context)
              .bottom, // Platz für die Tastatur
        ),
        child: Column(
          children: [
            if (giphyApiKey.isNotEmpty)
              TextField(
                controller: _search,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'GIFs suchen, z. B. „kuss“',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: giphyApiKey.isEmpty
                  ? Center(
                      child: Text(
                        'Die GIF-Suche ist noch nicht eingerichtet.\n'
                        'GIFs aus deiner Galerie kannst du trotzdem senden.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6,
                          ),
                      itemCount: _results.length,
                      itemBuilder: (context, i) {
                        final gif = _results[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () =>
                              Navigator.pop(context, GiphyGif(gif.full)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              gif.preview,
                              fit: BoxFit.cover,
                              cacheWidth: 300,
                              semanticLabel: 'GIF',
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.pop(context, GalleryGif()),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('GIF aus Galerie'),
                ),
                const Spacer(),
                // GIPHY verlangt diesen Hinweis bei Nutzung der Suche.
                if (giphyApiKey.isNotEmpty)
                  Text(
                    'Powered by GIPHY',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
