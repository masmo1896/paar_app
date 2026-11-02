import 'dart:async';

/// Geteilte Datenströme mit Gedächtnis.
///
/// Problem ohne das: Ein Bildschirm, der `PlannerService.instance.todos(id)` in
/// `build()` aufruft, bekommt bei jedem Neuzeichnen einen NEUEN Stream. Der
/// StreamBuilder meldet sich dann ab und neu an, zeigt kurz "lädt…" (Flackern)
/// und Firestore baut eine neue Verbindung auf.
///
/// Lösung: Pro Schlüssel (z. B. `todos/<coupleId>`) gibt es genau eine
/// Verbindung. Wer sich anmeldet, bekommt sofort den letzten Wert. Hört niemand
/// mehr zu, bleibt die Verbindung noch kurz offen (Tab-Wechsel) und wird dann
/// geschlossen.
abstract final class SharedStreams {
  static final _all = <String, _Shared<Object?>>{};

  /// Liefert immer DIESELBE Stream-Instanz für [key].
  static Stream<T> get<T>(String key, Stream<T> Function() create) {
    final shared = _all.putIfAbsent(key, () => _Shared<T>(create));
    return (shared as _Shared<T>).stream;
  }

  /// Beim Abmelden: alle Verbindungen schliessen und vergessen.
  static void clear() {
    for (final s in _all.values) {
      s.close();
    }
    _all.clear();
  }
}

class _Shared<T> {
  _Shared(this._create);

  final Stream<T> Function() _create;
  final _listeners = <MultiStreamController<T>>{};
  StreamSubscription<T>? _source;
  Timer? _idle;
  T? _last;
  bool _hasLast = false;

  late final Stream<T> stream = Stream<T>.multi((listener) {
    _idle?.cancel();
    _listeners.add(listener);
    if (_hasLast) listener.add(_last as T);
    _source ??= _create().listen(
      (value) {
        _last = value;
        _hasLast = true;
        for (final l in [..._listeners]) {
          l.add(value);
        }
      },
      onError: (Object e, StackTrace s) {
        for (final l in [..._listeners]) {
          l.addError(e, s);
        }
      },
      // Verbindung beendet (z. B. Zugriff verweigert): beim nächsten Mal neu aufbauen.
      onDone: () => _source = null,
    );
    listener.onCancel = () {
      _listeners.remove(listener);
      if (_listeners.isEmpty) {
        _idle = Timer(const Duration(seconds: 30), close);
      }
    };
  });

  void close() {
    _idle?.cancel();
    _source?.cancel();
    _source = null;
    _hasLast = false;
    _last = null;
  }
}
