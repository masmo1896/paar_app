#!/bin/bash
# Startet die Firebase-Emulatoren und prüft firestore.rules + storage.rules.
# Braucht Java (JAVA_HOME) und Node. Aufruf im Ordner paar_app:  ./rules_test/run.sh
set -e
cd "$(dirname "$0")/.."
export NODE_BIN="$(command -v node)"   # die Firebase-CLI bringt ein eigenes, altes Node mit
firebase emulators:exec --only firestore,storage --project demo-wirzwei \
  'cd rules_test && "$NODE_BIN" --test rules.test.mjs'
