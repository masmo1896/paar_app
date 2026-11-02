// Cloud-Funktionen: schicken Push-Benachrichtigungen an die andere Person.
// Sie laufen bei Google (nicht auf dem Handy) und reagieren auf Änderungen in Firestore.
const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();
const db = getFirestore();

// Die Firestore-Datenbank steht in Zürich, die Funktionen müssen in derselben Region laufen.
const REGION = 'europe-west6';

/** Name der Person (für "Anna: Hallo"). Hat [viewer] einen Spitznamen gesetzt, diesen. */
async function nameOf(uid, viewer) {
  if (viewer) {
    const me = await db.collection('users').doc(viewer).get();
    const nick = (me.get('partnerNickname') || '').trim();
    if (nick) return nick;
  }
  const snap = await db.collection('users').doc(uid).get();
  return snap.get('name') || 'Dein Schatz';
}

/** Die andere Person im Paar. */
async function partnerOf(coupleId, uid) {
  const couple = await db.collection('couples').doc(coupleId).get();
  const members = couple.get('members') || [];
  return members.find((m) => m !== uid) || null;
}

/** Schickt an alle Geräte von [uid]; ungültige Adressen werden aufgeräumt. */
async function notify(uid, { title, body, type }) {
  const tokens = await db.collection('users').doc(uid).collection('tokens').get();
  if (tokens.empty) {
    console.log('notify: kein Gerät registriert für', uid);
    return;
  }
  const ids = tokens.docs.map((d) => d.id);
  const res = await getMessaging().sendEachForMulticast({
    tokens: ids,
    notification: { title, body },
    data: { type },
    android: { priority: 'high', notification: { tag: type } },
    apns: { payload: { aps: { sound: 'default' } } },
  });
  const dead = [];
  res.responses.forEach((r, i) => {
    const code = r.error && r.error.code;
    if (code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token') {
      dead.push(tokens.docs[i].ref.delete());
    }
  });
  await Promise.all(dead);
}

function shorten(text, max = 120) {
  const t = String(text || '').replace(/\s+/g, ' ').trim();
  return t.length > max ? `${t.slice(0, max - 1)}…` : t;
}

const preview = (m) => ({
  text: shorten(m.text),
  image: '📷 Foto',
  gif: 'GIF',
  audio: '🎤 Sprachnachricht',
  video: '🎥 Videonachricht',
  file: `📎 ${m.fileName || 'Datei'}`,
}[m.type || 'text'] ?? 'Neue Nachricht');

// Neue Chat-Nachricht
exports.onMessage = onDocumentCreated(
  { document: 'couples/{coupleId}/messages/{id}', region: REGION },
  async (event) => {
    const m = event.data.data();
    const to = await partnerOf(event.params.coupleId, m.senderId);
    if (!to) return;
    await notify(to, { title: await nameOf(m.senderId, to), body: preview(m), type: 'chat' });
  },
);

// Neues Like (❤️) oder andere Smiley-Reaktion auf eine eigene Nachricht
exports.onReaction = onDocumentUpdated(
  { document: 'couples/{coupleId}/messages/{id}', region: REGION },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (after.type === 'deleted') return;
    const was = before.reactions || {};
    const now = after.reactions || {};
    for (const [uid, emoji] of Object.entries(now)) {
      // Nur neue oder geänderte Reaktionen der anderen Person, nicht auf eigene Nachricht
      if (was[uid] === emoji || uid === after.senderId) continue;
      await notify(after.senderId, {
        title: await nameOf(uid, after.senderId),
        body: emoji === '❤️'
          ? `❤️ gefällt deine Nachricht: ${preview(after)}`
          : `hat mit ${emoji} reagiert: ${preview(after)}`,
        type: 'chat',
      });
    }
  },
);

// Neuer Eintrag in To-dos oder Einkaufsliste – die andere Person erfährt es
// immer, der Text sagt, für wen er ist.
exports.onTodo = onDocumentCreated(
  { document: 'couples/{coupleId}/todos/{id}', region: REGION },
  async (event) => {
    const t = event.data.data();
    const to = await partnerOf(event.params.coupleId, t.createdBy);
    if (!to) return;
    const name = await nameOf(t.createdBy, to);
    const title = t.list === 'shopping'
      ? `🛒 ${name} hat etwas auf die Einkaufsliste gesetzt`
      : t.assignee === to
        ? `${name} hat eine Aufgabe für dich`
        : t.assignee === 'both'
          ? `${name} hat eine Aufgabe für euch beide`
          : `${name} hat eine eigene Aufgabe eingetragen`;
    await notify(to, { title, body: shorten(t.title), type: 'todo' });
    console.log('onTodo: Push an', to, '–', title);
  },
);

// Neuer Termin
exports.onEvent = onDocumentCreated(
  { document: 'couples/{coupleId}/events/{id}', region: REGION },
  async (event) => {
    const e = event.data.data();
    const to = await partnerOf(event.params.coupleId, e.createdBy);
    if (!to) return;
    const [, m, d] = e.startDate.split('-');
    await notify(to, {
      title: `${await nameOf(e.createdBy, to)} hat einen Termin eingetragen`,
      body: `${shorten(e.title)} · ${Number(d)}.${Number(m)}.`,
      type: 'event',
    });
  },
);

/** "6.11." oder "6.11. – 9.11.", mit Uhrzeit falls vorhanden: "6.11. 07:40". */
function eventWhen(e) {
  const day = (key) => {
    const [, m, d] = key.split('-');
    return `${Number(d)}.${Number(m)}.`;
  };
  const start = `${day(e.startDate)}${e.startTime ? ` ${e.startTime}` : ''}`;
  return e.endDate && e.endDate !== e.startDate ? `${start} – ${day(e.endDate)}` : start;
}

// Geänderter Termin (Titel, Datum oder Uhrzeit). Wer geändert hat, steht in
// updatedBy; ältere App-Versionen setzen das nicht, dann wird nichts geschickt.
exports.onEventChanged = onDocumentUpdated(
  { document: 'couples/{coupleId}/events/{id}', region: REGION },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    const by = after.updatedBy;
    // Nur echte Bearbeitungen: neuer Zeitstempel und etwas Sichtbares hat sich geändert.
    if (!by || String(before.updatedAt) === String(after.updatedAt)) return;
    const keys = ['title', 'startDate', 'endDate', 'startTime', 'endTime'];
    if (keys.every((k) => (before[k] ?? null) === (after[k] ?? null))) return;
    const to = await partnerOf(event.params.coupleId, by);
    if (!to) return;
    const moved = eventWhen(before) !== eventWhen(after);
    await notify(to, {
      title: `${await nameOf(by, to)} hat einen Termin geändert`,
      body: moved
        ? `${shorten(after.title)} · neu ${eventWhen(after)}`
        : `${shorten(after.title)} · ${eventWhen(after)}`,
      type: 'event',
    });
  },
);

// Neue Laterne im Laternenhimmel ("Ich denk an dich"). Hat die andere Person in
// den letzten 5 Minuten selbst eine geschickt, ist es ein Gleichzeitig-Moment.
exports.onLantern = onDocumentCreated(
  { document: 'couples/{coupleId}/lanterns/{id}', region: REGION },
  async (event) => {
    const l = event.data.data();
    const to = await partnerOf(event.params.coupleId, l.from);
    if (!to) return;
    const name = await nameOf(l.from, to);
    // Ohne Filter in der Abfrage (sonst bräuchte es einen extra Index).
    const recent = await event.data.ref.parent
      .orderBy('createdAt', 'desc').limit(20).get();
    const now = l.createdAt.toMillis();
    const sync = recent.docs.some((d) => d.get('from') === to &&
      Math.abs(now - d.get('createdAt').toMillis()) <= 5 * 60 * 1000);
    await notify(to, sync
      ? { title: '✨ Gleichzeitig!', body: `${name} und du habt im selben Moment aneinander gedacht.`, type: 'lantern' }
      : { title: `🏮 ${name} denkt an dich`, body: 'Eine Laterne ist für dich aufgestiegen.', type: 'lantern' });
  },
);

// Frage des Tages: Schatz hat geantwortet.
exports.onDailyAnswer = onDocumentCreated(
  { document: 'couples/{coupleId}/days/{day}/answers/{uid}', region: REGION },
  async (event) => {
    const { coupleId, day, uid } = event.params;
    const to = await partnerOf(coupleId, uid);
    if (!to) return;
    const name = await nameOf(uid, to);
    const partnerDone = (await db.doc(`couples/${coupleId}/days/${day}/answers/${to}`).get()).exists;
    await notify(to, {
      title: '💬 Frage des Tages',
      body: partnerDone
        ? `${name} hat auch geantwortet – jetzt könnt ihr eure Antworten lesen.`
        : `${name} hat geantwortet – jetzt bist du dran!`,
      type: 'us',
    });
  },
);

/** "24.12.2026" in Schweizer Zeit. */
const swissDate = (ts) => ts.toDate().toLocaleDateString('de-CH', { timeZone: 'Europe/Zurich' });

// Neuer Liebesbrief (der Text bleibt bis zum Datum verschlossen).
exports.onLetter = onDocumentCreated(
  { document: 'couples/{coupleId}/letters/{id}', region: REGION },
  async (event) => {
    const l = event.data.data();
    await notify(l.to, {
      title: `💌 ${await nameOf(l.from, l.to)} hat dir einen Brief geschrieben`,
      body: `Er lässt sich am ${swissDate(l.openAt)} öffnen.`,
      type: 'us',
    });
  },
);

// Jeden Morgen um 8 Uhr: Briefe, die sich seit gestern öffnen lassen.
exports.letterReminder = onSchedule(
  { schedule: 'every day 08:00', timeZone: 'Europe/Zurich', region: REGION },
  async () => {
    const now = Date.now();
    const snap = await db.collectionGroup('letters').get();
    for (const doc of snap.docs) {
      const l = doc.data();
      if (l.openedAt || !l.openAt) continue;
      const openAt = l.openAt.toMillis();
      if (openAt > now || openAt <= now - 24 * 60 * 60 * 1000) continue;
      await notify(l.to, {
        title: '💌 Ein Brief wartet auf dich',
        body: `Heute darfst du den Brief von ${await nameOf(l.from, l.to)} öffnen.`,
        type: 'us',
      });
    }
  },
);

// Jahrestag-Erinnerung: jeden Morgen um 8 Uhr (Schweizer Zeit) alle jährlichen
// Countdowns prüfen und eine Woche vorher, am Vortag und am Tag selbst erinnern.
// Wer auf der Wir-Seite "Jahrestag-Erinnerung" ausschaltet, bekommt nichts.
exports.anniversaryReminder = onSchedule(
  { schedule: 'every day 08:00', timeZone: 'Europe/Zurich', region: REGION },
  async () => {
    // Heutiges Datum in Zürich als "2026-10-31".
    const todayKey = new Date().toLocaleDateString('sv-SE', { timeZone: 'Europe/Zurich' });
    const [ty, tm, td] = todayKey.split('-').map(Number);
    const today = Date.UTC(ty, tm - 1, td);

    // Ohne Filter in der Abfrage (sonst bräuchte es einen extra Index) – es sind nur wenige.
    const snap = await db.collectionGroup('countdowns').get();
    for (const doc of snap.docs) {
      const c = doc.data();
      if (c.yearly !== true || typeof c.date !== 'string') continue;
      const [y, m, d] = c.date.split('-').map(Number);
      let next = Date.UTC(ty, m - 1, d);
      if (next < today) next = Date.UTC(ty + 1, m - 1, d);
      const daysLeft = Math.round((next - today) / 86400000);
      if (![0, 1, 7].includes(daysLeft)) continue;

      const years = new Date(next).getUTCFullYear() - y;
      const title = shorten(c.title, 60);
      const body = {
        0: years > 0 ? `Heute: ${title} – ${years} Jahre ♥` : `Heute: ${title} ♥`,
        1: `Morgen: ${title}`,
        7: `In einer Woche: ${title}`,
      }[daysLeft];

      const coupleRef = doc.ref.parent.parent;
      const couple = await coupleRef.get();
      for (const uid of couple.get('members') || []) {
        const me = await db.collection('users').doc(uid).get();
        if (me.get('anniversaryReminder') === false) continue;
        await notify(uid, { title: `${c.emoji || '♥'} Jahrestag`, body, type: 'chat' });
      }
    }
  },
);
