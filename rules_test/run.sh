#!/bin/bash
# Startet die Firebase-Emulatoren und prüft firestore.rules + storage.rules
# sowie eine ganze Spielpartie mit den Cloud Functions.
# Braucht Java (JAVA_HOME) und Node. Aufruf im Ordner paar_app:  ./rules_test/run.sh
set -e
cd "$(dirname "$0")/.."
export NODE_BIN="$(command -v node)"   # die Firebase-CLI bringt ein eigenes, altes Node mit
firebase emulators:exec --only firestore,storage,functions --project demo-wirzwei \
  'cd rules_test && "$NODE_BIN" --test --test-concurrency=1 rules.test.mjs game_flow.test.mjs'
