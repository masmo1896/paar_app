import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'screens/pairing_screen.dart';
import 'services/couple_service.dart';

// Entscheidet, welcher Bildschirm gezeigt wird:
// nicht eingeloggt -> Login, eingeloggt ohne Paar -> Verbinden, sonst -> Chat.
class AppGate extends StatelessWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _Loading();
        }
        final user = authSnap.data;
        if (user == null) return const AuthScreen();

        return StreamBuilder<String?>(
          stream: CoupleService.instance.coupleIdStream(user.uid),
          builder: (context, coupleSnap) {
            if (!coupleSnap.hasData &&
                coupleSnap.connectionState == ConnectionState.waiting) {
              return const _Loading();
            }
            final coupleId = coupleSnap.data;
            if (coupleId == null) return const PairingScreen();
            return HomeShell(coupleId: coupleId);
          },
        );
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
