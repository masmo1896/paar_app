import 'dart:math' as math;

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
      if (mounted) setState(() => _error = _message(e.code));
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

  /// Schickt eine E-Mail zum Zurücksetzen des Passworts an die eingetragene Adresse.
  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Gib zuerst oben deine E-Mail-Adresse ein.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      setState(() => _error = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Wir haben dir eine E-Mail an $email geschickt. '
            'Darin kannst du ein neues Passwort setzen.',
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _message(e.code));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  // Farben des cremefarbenen Anmelde-Blatts aus dem Mockup.
  static const _ink = Kitsune.night;
  static const _inkSoft = Color(0xFF4A5470);
  static const _line = Color(0x40133174);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Kitsune.deep,
      body: SingleChildScrollView(
        child: Stack(
          children: [
            // Fuchs auf der Klippe vor dem grossen Vollmond.
            SvgPicture.asset(
              KitsuneArt.moonfox.asset,
              width: MediaQuery.sizeOf(context).width,
              fit: BoxFit.fitWidth,
              alignment: Alignment.topCenter,
              semanticsLabel:
                  'Ein Fuchs sitzt auf einer Klippe und blickt zum Vollmond',
            ),
            Positioned(
              left: 24,
              top: top + 40,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SvgPicture.asset(
                          KitsuneArt.foxlogo.asset,
                          width: 26,
                          height: 26,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'WIR ZWEI',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Zwei Herzen,\nein Mond.',
                      style: AppTheme.serif(size: 44, height: 1.04),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Euer Chat, euer Kalender, eure To-dos. Nur für euch zwei.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: Kitsune.mist,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                top: math.max(330.0, MediaQuery.sizeOf(context).height - 470),
              ),
              child: _sheet(context),
            ),
          ],
        ),
      ),
    );
  }

  /// Das cremefarbene Blatt unten mit Reitern, Feldern und Einladungs-Karte.
  Widget _sheet(BuildContext context) {
    InputDecoration field(String label, String hint) => InputDecoration(
      labelText: label,
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: _inkSoft,
        letterSpacing: 0.6,
      ),
      hintStyle: const TextStyle(color: Color(0x994A5470)),
      filled: true,
      fillColor: const Color(0xFFFBF7EC),
      contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _line, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _line, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Kitsune.indigo, width: 1.5),
      ),
    );

    Widget tab(String label, bool register) {
      final on = _isRegister == register;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          child: GestureDetector(
            onTap: () => setState(() {
              _isRegister = register;
              _error = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
                boxShadow: on
                    ? const [
                        BoxShadow(
                          color: Color(0x26133174),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: on ? _ink : _inkSoft,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Theme(
      data: AppTheme.paper,
      child: Container(
        decoration: const BoxDecoration(
          color: Kitsune.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Color(0x73071230),
              blurRadius: 40,
              offset: Offset(0, -18),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(
          22,
          12,
          22,
          26 + MediaQuery.paddingOf(context).bottom,
        ),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: _ink),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _line,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0x14133174),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    tab('Anmelden', false),
                    const SizedBox(width: 4),
                    tab('Konto erstellen', true),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_isRegister) ...[
                TextField(
                  controller: _name,
                  style: const TextStyle(color: _ink, fontSize: 16),
                  decoration: field('Dein Name', 'So sieht dich dein Schatz'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _email,
                style: const TextStyle(color: _ink, fontSize: 16),
                decoration: field('E-Mail', 'du@beispiel.ch'),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                style: const TextStyle(color: _ink, fontSize: 16),
                decoration: field('Passwort', 'mindestens 6 Zeichen'),
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _submit(),
              ),
              if (!_isRegister)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _resetPassword,
                    style: TextButton.styleFrom(
                      foregroundColor: Kitsune.indigo,
                    ),
                    child: const Text('Passwort vergessen, ? Kein Problem'),
                  ),
                )
              else
                const SizedBox(height: 14),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFB0204D)),
                  ),
                ),
              // Hauptknopf: Indigo, grosse runde Ecken wie im Mockup.
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: Kitsune.indigo,
                  foregroundColor: Kitsune.paper,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  elevation: 6,
                  shadowColor: const Color(0x4D133174),
                ),
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Kitsune.paper,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isRegister
                                ? Icons.person_add_alt_rounded
                                : Icons.login_rounded,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(_isRegister ? 'Konto erstellen' : 'Anmelden'),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              // Einladung: zuerst ein Konto erstellen, danach kommt die Code-Eingabe.
              Material(
                color: const Color(0x1AE73162),
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => setState(() {
                    _isRegister = true;
                    _error =
                        'Erstelle zuerst dein Konto. Gleich danach kannst du '
                        'den Code deines Schatzes eingeben.';
                  }),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Kitsune.lantern,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.favorite_rounded,
                            size: 16,
                            color: Kitsune.paper,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Einladung von deinem Schatz?',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Code eingeben und verbinden',
                                style: TextStyle(fontSize: 12, color: _inkSoft),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: _ink),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
