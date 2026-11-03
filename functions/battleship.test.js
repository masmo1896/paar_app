// Tests für die Schiffe-versenken-Logik: `node --test` im Ordner functions.
const test = require('node:test');
const assert = require('node:assert/strict');
const { cellsOf, validateFleet, resolveShot, allSunk } = require('./battleship');

// Gültige Flotte: Schiffe untereinander, s3b berührt s3a (erlaubt).
const fleet = () => [
  { id: 's5', len: 5, x: 0, y: 0, vertical: false },
  { id: 's4', len: 4, x: 0, y: 1, vertical: false },
  { id: 's3a', len: 3, x: 0, y: 2, vertical: false },
  { id: 's3b', len: 3, x: 3, y: 2, vertical: false },
  { id: 's2', len: 2, x: 9, y: 8, vertical: true },
];

test('cellsOf: waagrecht und senkrecht', () => {
  assert.deepEqual(cellsOf({ len: 2, x: 3, y: 4, vertical: false }), [{ x: 3, y: 4 }, { x: 4, y: 4 }]);
  assert.deepEqual(cellsOf({ len: 2, x: 3, y: 4, vertical: true }), [{ x: 3, y: 4 }, { x: 3, y: 5 }]);
});

test('gültige Flotte wird akzeptiert', () => {
  assert.equal(validateFleet(fleet()), null);
});

test('ungültig: falsche Länge', () => {
  const f = fleet();
  f[0].len = 4;
  assert.notEqual(validateFleet(f), null);
});

test('ungültig: falsche Anzahl oder doppelte ID', () => {
  assert.notEqual(validateFleet(fleet().slice(0, 4)), null);
  const f = fleet();
  f[3] = { ...f[2], y: 5 };
  assert.notEqual(validateFleet(f), null);
  assert.notEqual(validateFleet(null), null);
});

test('ungültig: ausserhalb des Feldes', () => {
  const a = fleet();
  a[0].x = 6; // 6..10 ragt hinaus
  assert.notEqual(validateFleet(a), null);
  const b = fleet();
  b[4].y = 9; // senkrecht 9..10
  assert.notEqual(validateFleet(b), null);
  const c = fleet();
  c[4].x = -1;
  assert.notEqual(validateFleet(c), null);
  const d = fleet();
  d[4].x = 1.5;
  assert.notEqual(validateFleet(d), null);
});

test('ungültig: Überlappung', () => {
  const f = fleet();
  f[4] = { id: 's2', len: 2, x: 2, y: 0, vertical: true }; // kreuzt s5 und s4
  assert.notEqual(validateFleet(f), null);
});

test('Wasser', () => {
  assert.deepEqual(resolveShot(fleet(), [], 5, 5), { result: 'miss', shipId: null, shipLen: null });
});

test('Treffer', () => {
  assert.deepEqual(resolveShot(fleet(), [], 0, 0), { result: 'hit', shipId: 's5', shipLen: 5 });
});

test('Versenkt', () => {
  assert.equal(resolveShot(fleet(), [], 9, 8).result, 'hit');
  assert.deepEqual(resolveShot(fleet(), [{ x: 9, y: 8 }], 9, 9), { result: 'sunk', shipId: 's2', shipLen: 2 });
});

test('Sieg: erst wenn alle Felder getroffen sind', () => {
  const all = fleet().flatMap(cellsOf);
  assert.equal(allSunk(fleet(), all), true);
  assert.equal(allSunk(fleet(), all.slice(1)), false);
  assert.equal(allSunk(fleet(), []), false);
});

test('Punkte: Wasser 0, Treffer 10, Versenkt 30, Sieg +50', () => {
  const { pointsFor } = require('./battleship.js');
  assert.equal(pointsFor('miss', false), 0);
  assert.equal(pointsFor('hit', false), 10);
  assert.equal(pointsFor('sunk', false), 30);
  assert.equal(pointsFor('sunk', true), 80);
});
