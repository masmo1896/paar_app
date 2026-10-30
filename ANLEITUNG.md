# Wir zwei – Einrichtung (Schritt 1: Login + Chat)

Diese Schritte machst du **einmal**. Danach startest du die App nur noch mit `flutter run`.

## 0. Terminal vorbereiten

Flutter liegt in `~/development/flutter`. Damit der Befehl `flutter` überall funktioniert,
steht er in deiner `~/.zshrc`. Öffne nach der Installation ein **neues** Terminalfenster
(oder führe `source ~/.zshrc` aus) und prüfe:

```bash
flutter doctor
```

`flutter doctor` zeigt mit ✓ / ✗, was noch fehlt. Bei dir waren das (Stand 29.10.2026):

- **iOS-Simulator fehlt:** Xcode öffnen → *Einstellungen → Components* → bei **iOS** auf *Get* klicken (ca. 8 GB).
- **Android cmdline-tools fehlen:** Android Studio öffnen → *Settings → Languages & Frameworks →
  Android SDK* → Reiter *SDK Tools* → Haken bei **Android SDK Command-line Tools** → *Apply*.
- **Android-Lizenzen:** danach im Terminal `flutter doctor --android-licenses` und jede Frage mit `y` bestätigen.

Danach `flutter doctor` erneut ausführen – die Punkte sollten ✓ zeigen.

## 1. Firebase-Projekt anlegen (im Browser)

1. Öffne <https://console.firebase.google.com> und melde dich mit deinem Google-Konto an.
2. **Projekt hinzufügen** → Name z. B. `wir-zwei` → Google Analytics kannst du ausschalten.
3. Links **Build → Authentication → Jetzt starten** → Reiter **Anmeldemethode** →
   **E-Mail/Passwort** aktivieren → Speichern.
4. Links **Build → Firestore Database → Datenbank erstellen** →
   Standort `europe-west6 (Zürich)` → **Produktionsmodus** → Erstellen.
5. In Firestore den Reiter **Regeln** öffnen, alles löschen, den Inhalt der Datei
   `firestore.rules` aus diesem Projekt einfügen → **Veröffentlichen**.
   *Warum?* Die Regeln sorgen dafür, dass nur ihr zwei eure Nachrichten lesen könnt.

## 2. Die App mit Firebase verbinden (im Terminal)

```bash
curl -sL https://firebase.tools | bash
```
Installiert das Firebase-Kommandozeilenwerkzeug (offizielles Installationsskript von Google).

```bash
firebase login
```
Öffnet den Browser, du meldest dich mit demselben Google-Konto an.

```bash
dart pub global activate flutterfire_cli
```
Installiert `flutterfire`, das die Konfigurationsdateien für iOS und Android erzeugt.

Dann im Projektordner `paar_app`:

```bash
flutterfire configure
```
Wähle dein Projekt `wir-zwei` und die Plattformen **android** und **ios**.
Das überschreibt `lib/firebase_options.dart` mit deinen echten Schlüsseln.

## 3. Starten

Simulator/Emulator öffnen (iOS: `open -a Simulator`, Android: in Android Studio den
*Device Manager*), dann im Ordner `paar_app`:

```bash
flutter run
```

## 4. Ausprobieren

1. Registriere dich mit deiner E-Mail → **Code erstellen** → du siehst einen 6-stelligen Code.
2. Auf einem zweiten Gerät/Simulator registrierst du ein Test-Konto (oder später deine Freundin) → **Code eingeben**.
3. Schreibt euch – die Nachrichten erscheinen sofort auf beiden Geräten.

## Wie die App aufgebaut ist

| Datei | Aufgabe |
|---|---|
| `lib/main.dart` | Startet Firebase und die App, Hell/Dunkel nach Systemeinstellung |
| `lib/theme.dart` | Farben und Formen (ein Ort für das ganze Design) |
| `lib/app_gate.dart` | Entscheidet: Login → Verbinden → Chat |
| `lib/screens/auth_screen.dart` | Einloggen / Registrieren |
| `lib/screens/pairing_screen.dart` | Code erstellen oder eingeben |
| `lib/screens/chat_screen.dart` | Chat mit Echtzeit-Nachrichten |
| `lib/services/couple_service.dart` | Alle Firestore-Zugriffe an einem Ort |
| `firestore.rules` | Sicherheitsregeln für die Datenbank |

## Nächste Ausbaustufen

1. Lesebestätigungen ✓✓
2. Fotos im Chat senden (Firebase Storage)
3. Sprachnachrichten (gedrückt halten zum Aufnehmen)
4. Videobotschaften (aufnehmen oder aus der Galerie)
5. Push-Benachrichtigungen (Firebase Cloud Messaging)
6. Gemeinsame To-do-Liste
7. Gemeinsamer Kalender
8. Countdowns
9. Fotoalben
