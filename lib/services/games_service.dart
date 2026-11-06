import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'battleship_service.dart';
import 'crossword_service.dart';
import '../utils/shared_stream.dart';

// Für die Spiele-Kacheln auf Home: Bin ich gerade am Zug?

class GamesService {
  GamesService._();
  static final instance = GamesService._();

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  /// Schiffe versenken: am Zug, oder das Spiel wartet noch auf meine Flotte.
  /// Geteilt: Home baut die Kacheln oft neu, die Verbindung bleibt dieselbe.
  Stream<bool> battleshipMyTurn(String coupleId) =>
      SharedStreams.get('battleTurn/$_uid/$coupleId', () {
        final bs = BattleshipService.instance;
        return bs.current(coupleId).asyncExpand((g) {
          if (g == null || g.isDone) return Stream.value(false);
          if (g.isPlaying) return Stream.value(g.turn == _uid && !g.resolving);
          return bs.myFleet(coupleId, g.id).map((f) => f == null);
        });
      });

  Stream<bool> crosswordMyTurn(String coupleId) => SharedStreams.get(
    'crosswordTurn/$_uid/$coupleId',
    () => CrosswordService.instance
        .current(coupleId)
        .map((g) => g != null && !g.isDone && g.turn == _uid),
  );
}
