// Testdaten NUR für die lokalen Firebase-Emulatoren (nie gegen das echte Projekt!).
// Zwei Testkonten, ein Paar und eine laufende Partie Schiffe versenken.
// Für die App im Android-Emulator (die echte Projekt-ID, aber alles lokal):
//   firebase emulators:start --only auth,firestore,storage,functions --project wir-zwei-9e599
//   SEED_PROJECT=wir-zwei-9e599 node rules_test/seed_emulator.cjs
process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';

const path = require('path');
const admin = require(path.join(__dirname, '../functions/node_modules/firebase-admin'));

// Testkonten (nur Emulator).
const ACCOUNTS = [
  { uid: 'test-marc', email: 'marc@test.local', password: 'testtest1', name: 'Marc' },
  { uid: 'test-billie', email: 'billie@test.local', password: 'testtest1', name: 'Billie' },
];

admin.initializeApp({ projectId: process.env.SEED_PROJECT || 'demo-wirzwei' });
const db = admin.firestore();
const now = admin.firestore.FieldValue.serverTimestamp();

const fleet = (ships) => ships.map(([id, len, x, y, vertical]) => ({ id, len, x, y, vertical }));
const marcFleet = fleet([
  ['s5', 5, 1, 1, false], ['s4', 4, 8, 2, true], ['s3a', 3, 2, 5, true],
  ['s3b', 3, 5, 7, false], ['s2', 2, 0, 9, false],
]);
const billieFleet = fleet([
  ['s5', 5, 0, 0, true], ['s4', 4, 3, 3, false], ['s3a', 3, 9, 5, true],
  ['s3b', 3, 4, 8, false], ['s2', 2, 6, 0, false],
]);

async function main() {
  for (const a of ACCOUNTS) {
    await admin.auth().deleteUser(a.uid).catch(() => {});
    await admin.auth().createUser({ uid: a.uid, email: a.email, password: a.password, displayName: a.name });
  }
  const [m, b] = ACCOUNTS.map((a) => a.uid);
  await db.doc('couples/c1').set({ members: [m, b], inviteCode: 'TEST42' });
  await db.doc(`users/${m}`).set({ name: 'Marc', email: ACCOUNTS[0].email, coupleId: 'c1' });
  await db.doc(`users/${b}`).set({ name: 'Billie', email: ACCOUNTS[1].email, coupleId: 'c1' });

  const g = db.doc('couples/c1/battleships/g1');
  await g.set({
    status: 'playing', players: [m, b], turn: m, resolving: false, createdBy: b,
    createdAt: now, updatedAt: now, sunk: { [m]: ['s2'], [b]: ['s2'] },
  });
  await g.collection('fleets').doc(m).set({ ships: marcFleet });
  await g.collection('fleets').doc(b).set({ ships: billieFleet });
  const shot = (by, x, y, result, extra = {}) =>
    g.collection('shots').doc(`${by}_${x}_${y}`).set({
      by, x, y, at: admin.firestore.Timestamp.now(), result, ...extra,
    });
  // Billies Schüsse auf Marcs Meer
  await shot(b, 4, 4, 'miss');
  await shot(b, 1, 1, 'hit');
  await shot(b, 0, 9, 'hit');
  await shot(b, 1, 9, 'sunk', { shipLen: 2, shipCells: [{ x: 0, y: 9 }, { x: 1, y: 9 }] });
  await shot(b, 7, 7, 'miss');
  // Marcs Schüsse auf Billies Meer
  await shot(m, 6, 0, 'hit');
  await shot(m, 7, 0, 'sunk', { shipLen: 2, shipCells: [{ x: 6, y: 0 }, { x: 7, y: 0 }] });
  await shot(m, 3, 3, 'hit');
  await shot(m, 5, 5, 'miss');
  await shot(m, 2, 7, 'miss');
  console.log('Testdaten angelegt: Paar c1, Partie g1 (Marc ist dran).');
}

main().then(() => process.exit(0), (e) => { console.error(e); process.exit(1); });
