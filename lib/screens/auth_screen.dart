import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

// Login und Registrierung mit E-Mail und Passwort.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isRegister = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = FirebaseAuth.instance;
    try {
      if (_isRegister) {
        final cred = await auth.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
        await FirebaseFirestore.instance
            .collection('users')
            .doc(cred.user!.uid)
            .set({
              'email': _email.text.trim(),
              'name': _name.text.trim(),
            }, SetOptions(merge: true));
      } else {
        await auth.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
      // Kein Navigieren nötig: AppGate reagiert automatisch auf den Login.
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _message(e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(String code) => switch (code) {
    'invalid-email' => 'Ungültige E-Mail-Adresse.',
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' => 'E-Mail oder Passwort falsch.',
    'email-already-in-use' => 'Diese E-Mail ist schon registriert.',
    'weak-password' => 'Passwort zu schwach (mind. 6 Zeichen).',
    _ => 'Fehler: $code',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Eingabefelder wie im Mockup: nur eine cremefarbene Linie unten.
    const line = UnderlineInputBorder(
      borderSide: BorderSide(color: Kitsune.paper, width: 1.5),
    );
    InputDecoration field(String label) => InputDecoration(
      labelText: label.toUpperCase(),
      labelStyle: AppTheme.label(),
      floatingLabelStyle: AppTheme.label(),
      filled: false,
      contentPadding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      border: line,
      enabledBorder: line,
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Kitsune.aqua, width: 2),
      ),
    );
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Weisser Fuchs am roten Tor unter dem Vollmond.
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 390 / 400,
                  child: SvgPicture.asset(
                    KitsuneArt.fox.asset,
                    fit: BoxFit.cover,
                    alignment: Alignment.bottomCenter,
                    semanticsLabel: 'Ein weisser Fuchs neben einem roten Tor unter dem Vollmond',
                  ),
                ),
                // Senkrechte Zeile wie im Mockup: "Der Mond ist schön, nicht wahr?"
                Positioned(
                  left: 18,
                  top: MediaQuery.paddingOf(context).top + 18,
                  child: ExcludeSemantics(
                    child: Column(
                      children: [
                        for (final c in '月が綺麗ですね'.split(''))
                          Text(
                            c,
                            style: AppTheme.serif(
                              size: 13,
                              weight: FontWeight.w600,
                              color: Kitsune.paper.withValues(alpha: 0.75),
                              height: 1.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'ふたり',
                    textAlign: TextAlign.center,
                    style: AppTheme.serif(
                      size: 12,
                      weight: FontWeight.w600,
                      color: Kitsune.aqua,
                    ).copyWith(letterSpacing: 4.8),
                  ),
                  Text(
                    'Wir zwei',
                    textAlign: TextAlign.center,
                    style: AppTheme.serif(size: 34).copyWith(letterSpacing: 2),
                  ),
                  const Text(
                    'Nur ihr zwei, unter demselben Mond.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Kitsune.mist, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  if (_isRegister) ...[
                    TextField(
                      controller: _name,
                      decoration: field('Dein Name'),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _email,
                    decoration: field('E-Mail'),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    decoration: field('Passwort'),
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_isRegister ? 'Registrieren' : 'Anmelden'),
                              const SizedBox(width: 10),
                              const Hanko('入', size: 22),
                            ],
                          ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _isRegister = !_isRegister),
                    child: Text(
                      _isRegister
                          ? 'Schon ein Konto? Einloggen'
                          : 'Noch kein Konto? Registrieren',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
