// Erzeugt aus google-services.json und GoogleService-Info.plist (Projekt wir-zwei-9e599).
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => switch (defaultTargetPlatform) {
    TargetPlatform.android => android,
    TargetPlatform.iOS => ios,
    _ => throw UnsupportedError('Diese App läuft nur auf Android und iOS.'),
  };

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCf4_F7FdeiVx9XkSr4IlXhFauvi5DckJo',
    appId: '1:356236633441:android:bd9b22902aadbf630c1120',
    messagingSenderId: '356236633441',
    projectId: 'wir-zwei-9e599',
    storageBucket: 'wir-zwei-9e599.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBTT9MX4wa25nBDKEOCpRaG-pbEqtNYPgw',
    appId: '1:356236633441:ios:9038fbbaccea6e760c1120',
    messagingSenderId: '356236633441',
    projectId: 'wir-zwei-9e599',
    storageBucket: 'wir-zwei-9e599.firebasestorage.app',
    iosBundleId: 'ch.wirzwei.paarApp',
  );
}
