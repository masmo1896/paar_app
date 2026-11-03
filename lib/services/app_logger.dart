import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

// Einfacher Fehler-Logger: schickt Abstürze und gemeldete Fehler an Crashlytics
// (Firebase-Konsole → Crashlytics). Persönliche Inhalte (Nachrichtentexte, Namen,
// E-Mail) gehören NICHT in Meldungen – nur technische Hinweise.
class AppLogger {
  AppLogger._();

  /// Beim Start aufrufen (nach Firebase.initializeApp): fängt alle unbehandelten Fehler ab.
  static Future<void> init() async {
    // Im Entwicklungsmodus nichts senden, nur ausgeben.
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      !kDebugMode,
    );

    // Fehler im Flutter-Gerüst (z. B. beim Zeichnen).
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };
    // Alle übrigen Fehler (asynchrone Aufrufe, Plugins).
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    // Welches Konto betroffen ist: nur die zufällige ID, nie E-Mail oder Name.
    FirebaseAuth.instance.authStateChanges().listen(
      (user) => FirebaseCrashlytics.instance.setUserIdentifier(user?.uid ?? ''),
    );
  }

  /// Gefangenen Fehler melden, der die App nicht abstürzen lässt.
  /// [where] sagt kurz, wo es passiert ist, z. B. 'Foto senden'.
  static void error(Object error, StackTrace? stack, {String? where}) {
    debugPrint('Fehler${where == null ? '' : ' ($where)'}: $error');
    FirebaseCrashlytics.instance.recordError(
      error,
      stack ?? StackTrace.current,
      reason: where,
    );
  }

  /// Kurze Notiz, die bei einem späteren Absturz im Bericht mitgeschickt wird.
  static void info(String message) {
    if (kDebugMode) debugPrint(message);
    FirebaseCrashlytics.instance.log(message);
  }
}
