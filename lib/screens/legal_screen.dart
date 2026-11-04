import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/app_logger.dart';
import '../services/push_service.dart';
import '../theme.dart';
import '../utils/shared_stream.dart';

// Rechtliches: Datenschutzerklärung, Lizenzen und "Konto löschen".

/// Wer die App betreibt und erreichbar ist (steht in der Datenschutzerklärung).
const _operator = 'Marc';
const _contact = 'marc.d@gmx.ch';

/// Datenschutzerklärung als eigene Seite (Einstellungen → Datenschutz).
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: kitsuneAppBar(
      art: KitsuneArt.lanterns,
      kana: 'プライバシー',
      titleText: 'Datenschutz',
      height: 96,
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        for (final (title, text) in _privacyText) ...[
          Text(
            title,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: Kitsune.aqua,
            ),
          ),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(fontSize: 14, height: 1.45)),
          const SizedBox(height: 18),
        ],
      ],
    ),
  );
}

const _privacyText = [
  (
    'Kurz gesagt',
    'SchmiegiHOME ist ein privater Messenger für Paare. Deine Inhalte sehen '
        'nur du und dein Schatz. Es gibt keine Werbung, kein Tracking, und '
        'nichts wird verkauft.',
  ),
  (
    'Verantwortlich',
    '$_operator\nKontakt: $_contact\n'
        'Es gilt das Schweizer Datenschutzgesetz (DSG), für Personen in der '
        'EU zusätzlich die DSGVO.',
  ),
  (
    'Welche Daten gespeichert werden',
    '• Konto: E-Mail-Adresse, Passwort (nur verschlüsselt bei Firebase), '
        'Name, Profilbild.\n'
        '• Gemeinsamer Bereich: Nachrichten, Fotos, Videos, Sprachnachrichten, '
        'Dateien, Reaktionen, Termine, To-dos, Countdowns, Alben, Briefe, '
        'Antworten auf die Frage des Tages, Laternen und Spielstände.\n'
        '• Technisches: Adresse für Push-Benachrichtigungen pro Gerät, '
        'Einstellungen (z. B. Benachrichtigungen an/aus).',
  ),
  (
    'Wo die Daten liegen',
    'Die App nutzt Google Firebase (Google Ireland Ltd. / Google LLC). '
        'Datenbank und Server-Funktionen laufen in Zürich. Anmeldung, '
        'Dateispeicher, Push-Benachrichtigungen und Absturzberichte können '
        'auch in anderen Ländern, z. B. den USA, verarbeitet werden. Google '
        'ist dabei an seine Auftragsverarbeitungs-Bedingungen und die '
        'Standardvertragsklauseln gebunden.',
  ),
  (
    'Weitere Dienste',
    '• Push-Benachrichtigungen laufen über Apple bzw. Google.\n'
        '• GIF-Suche: Suchbegriffe und deine IP-Adresse gehen an GIPHY, '
        'nur wenn du die Suche benutzt.\n'
        '• Absturzberichte (Firebase Crashlytics): Gerätetyp, '
        'Systemversion, App-Version und die Fehlerstelle – keine Nachrichten '
        'oder Fotos. Sie werden nach 90 Tagen gelöscht.\n'
        '• App Check prüft, dass Anfragen von der echten App kommen.',
  ),
  (
    'Berechtigungen',
    'Kamera, Mikrofon, Fotos und Dateien werden nur benutzt, wenn du selbst '
        'etwas aufnimmst oder auswählst. Face ID bzw. Fingerabdruck für die '
        'App-Sperre prüft dein Gerät – davon verlässt nichts das Handy.',
  ),
  (
    'Wie lange',
    'Die Daten bleiben, bis ihr sie löscht oder ein Konto gelöscht wird. '
        'Gelöschte Nachrichten und Dateien werden sofort entfernt.',
  ),
  (
    'Konto löschen',
    'Unter Einstellungen → Konto löschen. Dabei werden dein Profil und der '
        'ganze gemeinsame Bereich mit allen Dateien gelöscht – auch für '
        'deinen Schatz. Dein Schatz behält das eigene Konto.',
  ),
  (
    'Deine Rechte',
    'Du kannst jederzeit Auskunft über deine Daten verlangen, sie '
        'berichtigen oder löschen lassen. Schreib dafür an $_contact. '
        'Beschweren kannst du dich beim EDÖB (edoeb.admin.ch) bzw. bei der '
        'Datenschutzbehörde deines Landes.',
  ),
  ('Stand', 'November 2026'),
];

/// Lizenzen der verwendeten Open-Source-Pakete (fertige Flutter-Seite).
void showLicenses(BuildContext context) =>
    showLicensePage(context: context, applicationName: 'SchmiegiHOME');

/// Fragt nach dem Passwort und löscht dann das Konto samt gemeinsamem Bereich
/// (Cloud Function deleteAccount). Danach landet man auf der Login-Seite.
Future<void> confirmDeleteAccount(BuildContext context) async {
  final controller = TextEditingController();
  final password = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Konto löschen?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dein Konto und euer ganzer gemeinsamer Bereich werden für immer '
            'gelöscht – Chat, Fotos, Videos, Termine, Briefe und Spiele, '
            'auch für deinen Schatz.\n\nZur Sicherheit: dein Passwort.',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Passwort'),
            onSubmitted: (v) => Navigator.pop(dialogContext, v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 40),
            backgroundColor: Kitsune.lantern,
          ),
          child: const Text('Endgültig löschen'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (password == null || password.isEmpty || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || user.email == null) return;
  try {
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: user.email!, password: password),
    );
  } on FirebaseAuthException {
    messenger.showSnackBar(
      const SnackBar(content: Text('Das Passwort stimmt nicht.')),
    );
    return;
  }

  try {
    await PushService.instance.stop();
    await FirebaseFunctions.instanceFor(region: 'europe-west6')
        .httpsCallable('deleteAccount')
        .call<void>();
  } catch (e, st) {
    AppLogger.error(e, st, where: 'Konto löschen');
    await PushService.instance.startIfEnabled();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Löschen hat nicht geklappt. Bitte später nochmal.'),
      ),
    );
    return;
  }
  SharedStreams.clear(); // alte Verbindungen schliessen
  await FirebaseAuth.instance.signOut();
  navigator.popUntil((route) => route.isFirst);
}
