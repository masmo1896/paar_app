// Liebesbriefe: wann soll die Erinnerung "Ein Brief wartet auf dich" rausgehen?
// Reine Logik ohne Firebase, damit sie sich mit `node --test` prüfen lässt.

const TZ = 'Europe/Zurich';
const HOUR = 60 * 60 * 1000;

const clock = new Intl.DateTimeFormat('de-CH', {
  timeZone: TZ,
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
});

/** Uhrzeit in Zürich als {hour, minute}. */
function zurichClock(ms) {
  const parts = Object.fromEntries(clock.formatToParts(new Date(ms)).map((p) => [p.type, p.value]));
  return { hour: Number(parts.hour), minute: Number(parts.minute) };
}

/** "22:00" in Zürcher Zeit. */
function clockText(ms) {
  const { hour, minute } = zurichClock(ms);
  return `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
}

/** Briefe mit Uhrzeit melden sich zu dieser Zeit, ältere (Mitternacht) um 8 Uhr. */
function reminderTime(openAtMs) {
  const { hour, minute } = zurichClock(openAtMs);
  return hour === 0 && minute === 0 ? openAtMs + 8 * HOUR : openAtMs;
}

/** Ist die Erinnerung jetzt fällig? Nur innerhalb von 24 Stunden nach dem Zeitpunkt. */
function reminderDue(openAtMs, nowMs) {
  const at = reminderTime(openAtMs);
  return nowMs >= at && nowMs - at <= 24 * HOUR;
}

module.exports = { clockText, reminderTime, reminderDue };
