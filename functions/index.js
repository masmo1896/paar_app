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
  if (tokens.empty) return;
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

// Neue Smiley-Reaktion auf eine eigene Nachricht
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
        body: `${emoji} auf: ${preview(after)}`,
        type: 'chat',
      });
    }
  },
);

// Neue Aufgabe, die dir zugewiesen wurde (oder euch beiden)
exports.onTodo = onDocumentCreated(
  { document: 'couples/{coupleId}/todos/{id}', region: REGION },
  async (event) => {
    const t = event.data.data();
    const to = await partnerOf(event.params.coupleId, t.createdBy);
    if (!to || (t.assignee !== to && t.assignee !== 'both')) return;
    await notify(to, {
      title: `${await nameOf(t.createdBy, to)} hat eine Aufgabe für dich`,
      body: shorten(t.title),
      type: 'todo',
    });
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
