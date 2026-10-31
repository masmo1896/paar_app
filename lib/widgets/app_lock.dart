import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

/// App-Sperre: Wenn eingeschaltet, fragt die App beim Start und nach mehr als
/// 30 Sekunden im Hintergrund nach Fingerabdruck, Gesicht oder Geräte-PIN.
/// Die Einstellung gilt nur für dieses Handy (lokal gespeichert).
class AppLock {
  AppLock._();
  static final instance = AppLock._();

  static const _key = 'appLock';
  final _auth = LocalAuthentication();

  /// null = noch nicht geladen.
  final enabled = ValueNotifier<bool?>(null);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_key) ?? false;
  }

  /// Fragt einmal nach dem Fingerabdruck. true = erfolgreich.
  Future<bool> unlock() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Entsperre „Wir zwei“',
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException {
      return false;
    }
  }

  /// Einschalten nur, wenn das Handy eine Sperre kann und du dich bestätigst.
  /// Gibt eine Fehlermeldung zurück oder null bei Erfolg.
  Future<String?> setEnabled(bool on) async {
    if (on) {
      if (!await _auth.isDeviceSupported()) {
        return 'Auf diesem Handy ist keine Bildschirmsperre eingerichtet.';
      }
      if (!await unlock()) return 'Nicht bestätigt – App-Sperre bleibt aus.';
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, on);
    enabled.value = on;
    return null;
  }
}

/// Legt den Sperrbildschirm über die App, solange sie gesperrt ist.
/// Die App darunter bleibt geladen – nach dem Entsperren ist alles wie vorher.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  static const _grace = Duration(seconds: 30);
  bool _locked = true; // bis die Einstellung geladen ist
  bool _authenticating = false;
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLock.instance.load().then((_) {
      if (!mounted) return;
      final on = AppLock.instance.enabled.value == true;
      setState(() => _locked = on);
      if (on) _tryUnlock();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_authenticating) return; // der Fingerabdruck-Dialog selbst zählt nicht
    if (state == AppLifecycleState.paused) {
      _leftAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (AppLock.instance.enabled.value == true &&
          left != null &&
          DateTime.now().difference(left) > _grace &&
          !_locked) {
        setState(() => _locked = true);
        _tryUnlock();
      }
    }
  }

  Future<void> _tryUnlock() async {
    if (_authenticating) return;
    _authenticating = true;
    final ok = await AppLock.instance.unlock();
    _authenticating = false;
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    final loading = AppLock.instance.enabled.value == null;
    return Stack(
      children: [
        // Unsichtbar und nicht bedienbar, solange gesperrt.
        Offstage(offstage: _locked, child: widget.child),
        if (_locked)
          Scaffold(
            body: loading
                ? const SizedBox.shrink()
                : SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        children: [
                          const Spacer(),
                          SvgPicture.asset(
                            KitsuneArt.foxlogo.asset,
                            width: 72,
                            height: 72,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'ふたりだけ',
                            style: AppTheme.serif(
                              size: 12,
                              weight: FontWeight.w600,
                              color: Kitsune.aqua,
                            ).copyWith(letterSpacing: 4),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Nur für euch zwei',
                            style: AppTheme.serif(size: 26),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Die App ist gesperrt.',
                            style: TextStyle(color: Kitsune.mist),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: _tryUnlock,
                            icon: const Icon(Icons.fingerprint_rounded),
                            label: const Text('Entsperren'),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
      ],
    );
  }
}
