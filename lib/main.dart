import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app_gate.dart';
import 'firebase_options.dart';
import 'theme.dart';

// Einstiegspunkt der App: Firebase starten, dann die Oberfläche zeichnen.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const PaarApp());
}

class PaarApp extends StatelessWidget {
  const PaarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wir zwei',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Folgt automatisch der Systemeinstellung (Hell/Dunkel).
      themeMode: ThemeMode.system,
      home: const AppGate(),
    );
  }
}
