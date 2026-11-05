// Tests für die Brief-Erinnerung: `node --test` im Ordner functions.
const test = require('node:test');
const assert = require('node:assert/strict');
const { clockText, reminderTime, reminderDue } = require('./letters');

// 5. November 2026 (Winterzeit, UTC+1)
const at = (h, m = 0) => Date.UTC(2026, 10, 5, h - 1, m);

test('Uhrzeit in Schweizer Zeit', () => {
  assert.equal(clockText(at(22)), '22:00');
  assert.equal(clockText(at(7, 5)), '07:05');
  // Sommerzeit (UTC+2)
  assert.equal(clockText(Date.UTC(2026, 6, 1, 20, 30)), '22:30');
});

test('Brief mit Uhrzeit: Erinnerung zur Uhrzeit', () => {
  assert.equal(reminderTime(at(22)), at(22));
  assert.equal(reminderDue(at(22), at(21, 59)), false);
  assert.equal(reminderDue(at(22), at(22, 0)), true);
  assert.equal(reminderDue(at(22), at(22, 14)), true);
});

test('Alter Brief (Mitternacht): Erinnerung um 8 Uhr', () => {
  assert.equal(reminderTime(at(0)), at(8));
  assert.equal(reminderDue(at(0), at(3)), false);
  assert.equal(reminderDue(at(0), at(8)), true);
});

test('Nach 24 Stunden keine Erinnerung mehr', () => {
  assert.equal(reminderDue(at(22), at(22) + 25 * 3600 * 1000), false);
});
