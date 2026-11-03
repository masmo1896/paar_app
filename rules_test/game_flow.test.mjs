// Ganze Partie Schiffe versenken gegen Firestore- + Functions-Emulator.
// Start:  cd paar_app && ./rules_test/run.sh   (läuft mit den Regel-Tests)
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, addDoc, collection, writeBatch, serverTimestamp, Timestamp,
} from 'firebase/firestore';

const ME = 'marc', LOVE = 'billie', C = 'c1';
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-wirzwei',
    firestore: { rules: fs.readFileSync('../firestore.rules', 'utf8'), host: '127.0.0.1', port: 8080 },
  });
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'couples', C), { members: [ME, LOVE], inviteCode: 'ABC234' });
  });
});
after(() => env.cleanup());

const dbs = {};
const db = (u) => (dbs[u] ??= env.authenticatedContext(u).firestore());
const fleetOf = (row) => [
  { id: 's5', len: 5, x: 0, y: row, vertical: false },
  { id: 's4', len: 4, x: 0, y: row + 1, vertical: false },
  { id: 's3a', len: 3, x: 0, y: row + 2, vertical: false },
  { id: 's3b', len: 3, x: 0, y: row + 3, vertical: false },
  { id: 's2', len: 2, x: 0, y: row + 4, vertical: false },
];

// Wartet, bis die Cloud Function etwas geschrieben hat.
async function until(read, ok, what) {
  for (let i = 0; i < 100; i++) {
    const v = await read();
    if (ok(v)) return v;
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error(`Zeitüberschreitung: ${what}`);
}

test('ganze Partie: aufstellen, treffen, verfehlen, versenken, gewinnen', async () => {
  const ref = await addDoc(collection(db(ME), 'couples', C, 'battleships'), {
    status: 'setup', players: [ME, LOVE], turn: null, resolving: false, createdBy: ME,
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(), sunk: {},
  });
  const g = (u = ME) => doc(db(u), 'couples', C, 'battleships', ref.id);
  const read = async () => (await getDoc(g())).data();

  // Ungültige Flotte (Überlappung) wird von der Function gelöscht.
  const bad = fleetOf(0).map((s) => ({ ...s, y: 0 }));
  await setDoc(doc(g(LOVE), 'fleets', LOVE), { ships: bad });
  await until(async () => (await getDoc(doc(g(LOVE), 'fleets', LOVE))).exists(), (e) => !e, 'ungültige Flotte gelöscht');

  await setDoc(doc(g(ME), 'fleets', ME), { ships: fleetOf(0) });
  await setDoc(doc(g(LOVE), 'fleets', LOVE), { ships: fleetOf(5) });
  let game = await until(read, (d) => d.status === 'playing', 'Spielstart');
  assert.equal(game.turn, LOVE, 'wer nicht gestartet hat, beginnt');

  const shoot = async (u, x, y) => {
    const d = db(u);
    const b = writeBatch(d);
    b.set(doc(g(u), 'shots', `${u}_${x}_${y}`), { by: u, x, y, at: serverTimestamp() });
    b.update(g(u), { resolving: true });
    await b.commit();
    const shot = await until(
      async () => (await getDoc(doc(g(u), 'shots', `${u}_${x}_${y}`))).data(),
      (s) => s && s.result, `Auswertung ${x},${y}`,
    );
    await until(read, (d) => d.resolving === false, 'Sperre gelöst');
    return shot;
  };

  // Wasser → Zug wechselt
  assert.equal((await shoot(LOVE, 9, 9)).result, 'miss');
  assert.equal((await read()).turn, ME);
  // Treffer → nochmal dran
  assert.equal((await shoot(ME, 0, 9)).result, 'hit');
  assert.equal((await read()).turn, ME);
  // Papierboot (2) bei LOVE: Zeile 9, x 0–1 → versenkt mit Feldern
  const sunk = await shoot(ME, 1, 9);
  assert.equal(sunk.result, 'sunk');
  assert.equal(sunk.shipLen, 2);
  assert.deepEqual(sunk.shipCells, [{ x: 0, y: 9 }, { x: 1, y: 9 }]);
  assert.deepEqual((await read()).sunk[LOVE], ['s2']);

  // Rest der Flotte von LOVE (Zeilen 5–8) versenken → Sieg
  for (const s of fleetOf(5).filter((s) => s.id !== 's2')) {
    for (let i = 0; i < s.len; i++) await shoot(ME, s.x + i, s.y);
  }
  game = await read();
  assert.equal(game.status, 'done');
  assert.equal(game.winner, ME);
  assert.equal(game.turn, null);
  assert.equal(game.revealed[LOVE].length, 5);
  assert.equal(game.revealed[ME].length, 5);
  // Punkte: 17 Treffer à 10, 5× Versenkt +20, Sieg +50 = 320; Billie nur Wasser.
  assert.equal(game.scores[ME], 320);
  assert.equal(game.scores[LOVE], undefined);
});

test('Kreuzwort: abwechselnd raten bis gelöst', async () => {
  const words = ['EINS', 'ZWEI', 'DREI', 'VIER'].map((a, i) =>
    ({ id: `w${i + 1}`, clue: 'c', answer: a, x: 0, y: i * 2, across: true }));
  const ref = await addDoc(collection(db(ME), 'couples', C, 'crosswords'), {
    status: 'playing', turn: ME, createdBy: ME, createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(), size: 9, words, solved: {}, attempts: 0, hintsUsed: 0, revealed: [],
  });
  const k = (u) => doc(db(u), 'couples', C, 'crosswords', ref.id);
  const { updateDoc, increment } = await import('firebase/firestore');
  const turns = [ME, LOVE, ME, LOVE];
  for (let i = 0; i < 4; i++) {
    const u = turns[i];
    await updateDoc(k(u), {
      [`solved.w${i + 1}`]: u, attempts: increment(1), turn: u === ME ? LOVE : ME,
      ...(i === 3 ? { status: 'done' } : {}), updatedAt: serverTimestamp(),
    });
  }
  const d = (await getDoc(k(ME))).data();
  assert.equal(d.status, 'done');
  assert.equal(Object.keys(d.solved).length, 4);
  assert.ok(Timestamp);
});
