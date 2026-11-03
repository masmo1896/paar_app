import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_gate.dart';
import 'firebase_options.dart';
import 'services/app_logger.dart';
import 'theme.dart';

// Einstiegspunkt der App: Firebase starten, dann die Oberfläche zeichnen.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (_useEmulators) await _connectEmulators();
  // App Check zuerst, damit schon die ersten Firebase-Anfragen ein Siegel tragen.
  await _startAppCheck();
  await AppLogger.init();
  runApp(const PaarApp());
}

// Nur zum Testen am Mac: --dart-define=USE_EMULATORS=true hängt die App an die lokalen
// Firebase-Emulatoren (Testkonten, Testdaten). Echte Builds lassen das weg.
const _useEmulators = bool.fromEnvironment('USE_EMULATORS');

Future<void> _connectEmulators() async {
  // Aus dem Android-Emulator heisst der Mac 10.0.2.2.
  final host = defaultTargetPlatform == TargetPlatform.android
      ? '10.0.2.2'
      : 'localhost';
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  await FirebaseStorage.instance.useStorageEmulator(host, 9199);
}

// App Check: Firebase nimmt nur Anfragen von eurer eigenen App an.
// Weil die Apps selbst installiert sind (nicht aus Play Store/App Store), nutzen wir den
// Debug-Anbieter mit einem festen Geheimcode, den ihr in der Firebase-Konsole eintragt.
// Der Code steht NICHT im Projekt, sondern wird beim Bauen mitgegeben:
//   flutter build apk --dart-define=APPCHECK_DEBUG_TOKEN=<UUID>
// Ohne Code erzeugt die App selbst einen und schreibt ihn ins Log (nur zum Ausprobieren).
const _appCheckDebugToken = String.fromEnvironment('APPCHECK_DEBUG_TOKEN');

Future<void> _startAppCheck() async {
  final token = _appCheckDebugToken.isEmpty ? null : _appCheckDebugToken;
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: AndroidDebugProvider(debugToken: token),
      providerApple: AppleDebugProvider(debugToken: token),
    );
  } catch (e, s) {
    // Die App soll auch ohne App Check starten; der Fehler landet im Bericht.
    debugPrint('App Check konnte nicht starten: $e');
    FirebaseCrashlytics.instance.recordError(e, s, reason: 'App Check start');
  }
}

class PaarApp extends StatelessWidget {
  const PaarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SchmiegiHOME',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Folgt automatisch der Systemeinstellung (Hell/Dunkel).
      themeMode: ThemeMode.system,
      // Deutsch für Datums- und Zeitauswahl (Wochenstart Montag).
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Nachtblaues Wellenmuster hinter allen Bildschirmen.
      builder: (context, child) => AppBackground(child: child),
      home: const AppGate(),
    );
  }
}
