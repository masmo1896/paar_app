import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'app_logger.dart';

/// Push-Benachrichtigungen (Firebase Cloud Messaging).
///
/// So läuft es: Dieses Gerät meldet sich mit einem "Token" an (eine Art Postfach-Adresse)
/// und speichert ihn unter users/{uid}/tokens. Bei einer neuen Nachricht, Aufgabe oder einem
/// Termin schickt eine Cloud-Funktion (Ordner functions/) eine Benachrichtigung an die Tokens
/// der anderen Person.
class PushService {
  PushService._();
  static final instance = PushService._();

  /// Tab, der geöffnet werden soll, weil jemand eine Benachrichtigung angetippt hat.
  /// 0 = Home (Laternen), 1 = Chat, 2 = Kalender, 3 = To-dos, 4 = Wir. Wer ihn auswertet, setzt ihn wieder auf null.
  final requestedTab = ValueNotifier<int?>(null);

  final _db = FirebaseFirestore.instance;
  final _messaging = FirebaseMessaging.instance;
  bool _started = false;
  String? _token;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  /// Welcher Tab gehört zu einer Benachrichtigung? (Wird in der Cloud-Funktion gesetzt.)
  static int? tabFor(RemoteMessage message) => switch (message.data['type']) {
    'lantern' => 0,
    'chat' => 1,
    'event' => 2,
    'todo' => 3,
    'us' => 4,
    _ => null,
  };

  /// Nach dem Login aufrufen: um Erlaubnis bitten, Token speichern, Antippen auswerten.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      // Android 13+ und iOS fragen den Nutzer hier nach der Erlaubnis.
      final settings = await _messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      await _saveToken(await _messaging.getToken());
      _refreshSub = _messaging.onTokenRefresh.listen(_saveToken);
    } catch (e) {
      // Kein Push-Token (z. B. Erlaubnis fehlt oder Simulator ohne APNs).
      // Die App läuft dann einfach ohne Benachrichtigungen weiter.
      // Nur als Notiz (kein Fehlerbericht), sonst meldet jeder solche Start einen Fehler.
      AppLogger.info('Push nicht verfügbar: ${e.runtimeType}');
    }

    // App war im Hintergrund und wurde über die Benachrichtigung geöffnet ...
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_open);
    // ... oder war ganz beendet.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _open(initial);
  }

  void _open(RemoteMessage message) => requestedTab.value = tabFor(message);

  Future<void> _saveToken(String? token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (token == null || uid == null) return;
    _token = token;
    await _db.collection('users').doc(uid).collection('tokens').doc(token).set({
      'platform': defaultTargetPlatform.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Schalter auf der Wir-Seite. Gespeichert im eigenen Profil (pushOff), damit die
  /// App beim nächsten Start weiss, ob sie sich wieder anmelden soll.
  Future<void> setEnabled(bool on) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).set({
      'pushOff': !on,
    }, SetOptions(merge: true));
    on ? await start() : await stop();
  }

  /// Beim App-Start: nur anmelden, wenn Benachrichtigungen nicht ausgeschaltet sind.
  Future<void> startIfEnabled() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final me = await _db.collection('users').doc(uid).get();
    if (me.data()?['pushOff'] != true) await start();
  }

  /// Vor dem Abmelden: dieses Gerät abmelden, damit es keine Nachrichten mehr bekommt.
  Future<void> stop() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final token = _token;
    await _refreshSub?.cancel();
    await _openedSub?.cancel();
    _started = false;
    _token = null;
    if (uid != null && token != null) {
      await _db
          .collection('users')
          .doc(uid)
          .collection('tokens')
          .doc(token)
          .delete()
          .catchError((_) {});
      await _messaging.deleteToken().catchError((_) {});
    }
  }
}
