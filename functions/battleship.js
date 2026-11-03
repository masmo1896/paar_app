// Schiffe versenken: reine Spiellogik ohne Firebase, damit sie sich mit
// `node --test` prüfen lässt. Die Cloud Functions in index.js benutzen sie.

const SIZE = 10;

// Die Flotte: genau diese fünf Schiffe.
const FLEET = { s5: 5, s4: 4, s3a: 3, s3b: 3, s2: 2 };

const key = (x, y) => `${x}_${y}`;
const isCoord = (v) => Number.isInteger(v) && v >= 0 && v < SIZE;

/** Alle Felder eines Schiffs als [{x, y}]. */
function cellsOf(ship) {
  const cells = [];
  for (let i = 0; i < ship.len; i++) {
    cells.push(ship.vertical ? { x: ship.x, y: ship.y + i } : { x: ship.x + i, y: ship.y });
  }
  return cells;
}

/** Prüft eine Flotte. Gibt null zurück, wenn alles stimmt, sonst den Grund. */
function validateFleet(ships) {
  if (!Array.isArray(ships) || ships.length !== Object.keys(FLEET).length) {
    return 'Es braucht genau 5 Schiffe';
  }
  const seenIds = new Set();
  const taken = new Set();
  for (const s of ships) {
    if (!s || typeof s !== 'object') return 'Ungültiges Schiff';
    if (!(s.id in FLEET) || seenIds.has(s.id)) return `Ungültige Schiff-ID ${s.id}`;
    seenIds.add(s.id);
    if (s.len !== FLEET[s.id]) return `Falsche Länge für ${s.id}`;
    if (typeof s.vertical !== 'boolean') return `Richtung fehlt bei ${s.id}`;
    if (!isCoord(s.x) || !isCoord(s.y)) return `${s.id} liegt ausserhalb`;
    for (const c of cellsOf(s)) {
      if (!isCoord(c.x) || !isCoord(c.y)) return `${s.id} liegt ausserhalb`;
      if (taken.has(key(c.x, c.y))) return `${s.id} überlappt`;
      taken.add(key(c.x, c.y));
    }
  }
  return null;
}

/**
 * Wertet einen Schuss auf [x, y] aus. [previousHits] sind die bisherigen
 * Treffer des Schützen auf diese Flotte als [{x, y}].
 * Ergebnis: { result: 'miss'|'hit'|'sunk', shipId, shipLen } (bei Wasser null).
 */
function resolveShot(fleet, previousHits, x, y) {
  const hit = new Set((previousHits || []).map((h) => key(h.x, h.y)));
  hit.add(key(x, y));
  for (const ship of fleet) {
    const cells = cellsOf(ship);
    if (!cells.some((c) => c.x === x && c.y === y)) continue;
    const sunk = cells.every((c) => hit.has(key(c.x, c.y)));
    return { result: sunk ? 'sunk' : 'hit', shipId: ship.id, shipLen: ship.len };
  }
  return { result: 'miss', shipId: null, shipLen: null };
}

/** Sind mit diesen Treffern ([{x, y}]) alle Schiffe versenkt? */
function allSunk(fleet, hits) {
  const hit = new Set((hits || []).map((h) => key(h.x, h.y)));
  return fleet.every((ship) => cellsOf(ship).every((c) => hit.has(key(c.x, c.y))));
}

/** Punkte für einen Schuss: Treffer 10, Versenkt 10 + 20, Sieg zusätzlich 50. */
const POINTS = { hit: 10, sunkBonus: 20, win: 50 };
function pointsFor(result, won) {
  if (result === 'miss') return 0;
  return POINTS.hit + (result === 'sunk' ? POINTS.sunkBonus : 0) + (won ? POINTS.win : 0);
}

module.exports = { SIZE, FLEET, POINTS, cellsOf, validateFleet, resolveShot, allSunk, pointsFor };
