// Testet firestore.rules und storage.rules im Emulator.
// Start:  cd paar_app && ./rules_test/run.sh
import { test, before, after, beforeEach } from 'node:test';
import fs from 'node:fs';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, addDoc,
  Timestamp, serverTimestamp, arrayUnion,
} from 'firebase/firestore';
import { ref, uploadBytes, getBytes, deleteObject } from 'firebase/storage';

const ME = 'marc', LOVE = 'billie', STRANGER = 'fremd', C = 'c1';
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-wirzwei',
    firestore: { rules: fs.readFileSync('../firestore.rules', 'utf8'), host: '127.0.0.1', port: 8080 },
    storage: { rules: fs.readFileSync('../storage.rules', 'utf8'), host: '127.0.0.1', port: 9199 },
  });
});
after(() => env.cleanup());

// Ausgangslage: Paar c1 mit marc + billie, Fremde in eigenem Paar.
beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'couples', C), { members: [ME, LOVE], inviteCode: 'ABC234' });
    await setDoc(doc(db, 'couples', 'c2'), { members: [STRANGER], inviteCode: 'ZZZ999' });
    await setDoc(doc(db, 'users', ME), { name: 'Marc', coupleId: C });
    await setDoc(doc(db, 'users', LOVE), { name: 'Billie', coupleId: C });
    await setDoc(doc(db, 'users', STRANGER), { name: 'X', coupleId: 'c2' });
    await setDoc(doc(db, 'couples', C, 'messages', 'm1'), {
      type: 'text', text: 'hi', senderId: LOVE, createdAt: Timestamp.now(), read: false,
    });
    await setDoc(doc(db, 'couples', C, 'letters', 'l1'), {
      from: LOVE, to: ME, openAt: Timestamp.fromMillis(Date.now() + 86400000), createdAt: Timestamp.now(),
    });
    await setDoc(doc(db, 'couples', C, 'letters', 'l1', 'content', 'text'), { text: 'geheim' });
    await setDoc(doc(db, 'couples', C, 'days', 'd1', 'answers', LOVE), { text: 'antwort', at: Timestamp.now() });
    await setDoc(doc(db, 'invites', 'ABC234'), { coupleId: C });
  });
});

const db = (uid) => (uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore());
const st = (uid) => (uid ? env.authenticatedContext(uid).storage() : env.unauthenticatedContext().storage());

// ---------- Firestore ----------
test('ohne Login: nichts lesen, nichts schreiben', async () => {
  await assertFails(getDoc(doc(db(null), 'couples', C)));
  await assertFails(getDoc(doc(db(null), 'couples', C, 'messages', 'm1')));
  await assertFails(setDoc(doc(db(null), 'users', 'x'), { name: 'x' }));
  await assertFails(getDoc(doc(db(null), 'invites', 'ABC234')));
});

test('Fremde: kein Zugriff auf euer Paar', async () => {
  const d = db(STRANGER);
  await assertFails(getDoc(doc(d, 'couples', C)));
  await assertFails(getDoc(doc(d, 'couples', C, 'messages', 'm1')));
  await assertFails(getDoc(doc(d, 'users', ME)));
  await assertFails(addDoc(collection(d, 'couples', C, 'messages'), { type: 'text', text: 'x', senderId: STRANGER }));
  await assertFails(getDoc(doc(d, 'couples', C, 'letters', 'l1')));
});

test('Fremde: können euer volles Paar nicht betreten', async () => {
  await assertFails(updateDoc(doc(db(STRANGER), 'couples', C), { members: arrayUnion(STRANGER) }));
  await assertFails(updateDoc(doc(db(STRANGER), 'couples', C), { members: [ME, LOVE, STRANGER] }));
});

test('Ihr zwei: Nachrichten lesen und schreiben', async () => {
  await assertSucceeds(getDoc(doc(db(ME), 'couples', C, 'messages', 'm1')));
  await assertSucceeds(addDoc(collection(db(ME), 'couples', C, 'messages'), {
    type: 'text', text: 'hallo', senderId: ME, createdAt: serverTimestamp(), read: false,
  }));
});

test('Nachricht nicht unter fremdem Namen senden', async () => {
  await assertFails(addDoc(collection(db(ME), 'couples', C, 'messages'), {
    type: 'text', text: 'hallo', senderId: LOVE, createdAt: serverTimestamp(), read: false,
  }));
});

test('Nachricht: Link nur auf Firebase Storage/GIPHY erlaubt', async () => {
  await assertFails(addDoc(collection(db(ME), 'couples', C, 'messages'), {
    type: 'image', imageUrl: 'https://evil.example/x.png', senderId: ME,
  }));
  await assertSucceeds(addDoc(collection(db(ME), 'couples', C, 'messages'), {
    type: 'image', imageUrl: 'https://firebasestorage.googleapis.com/v0/b/x/o/y', senderId: ME,
  }));
});

test('fremde Nachricht nicht bearbeiten, nur "gelesen" setzen', async () => {
  const m = doc(db(ME), 'couples', C, 'messages', 'm1');
  await assertFails(updateDoc(m, { text: 'manipuliert', editedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(m, { read: true, readAt: serverTimestamp() }));
});

test('Nachrichten können nicht hart gelöscht werden', async () => {
  await assertFails(deleteDoc(doc(db(LOVE), 'couples', C, 'messages', 'm1')));
});

test('Paar anlegen: nur mit korrekten Feldern', async () => {
  const d = db('neu');
  await assertFails(setDoc(doc(d, 'couples', 'c9'), { members: ['neu'], inviteCode: 'AAAAAA', admin: true }));
  await assertFails(setDoc(doc(d, 'couples', 'c9'), { members: ['neu', 'anderer'], inviteCode: 'AAAAAA' }));
  await assertSucceeds(setDoc(doc(d, 'couples', 'c9'), { members: ['neu'], inviteCode: 'AAAAAA', createdAt: serverTimestamp() }));
});

test('Beitreten: eine Person kommt zu einem einzelnen Paar dazu', async () => {
  await assertSucceeds(updateDoc(doc(db('neu'), 'couples', 'c2'), { members: arrayUnion('neu') }));
  // danach ist es voll
  await assertFails(updateDoc(doc(db('noch'), 'couples', 'c2'), { members: [STRANGER, 'neu', 'noch'] }));
});

test('Profil: nur das eigene schreiben; kein fremdes Paar eintragen', async () => {
  await assertFails(setDoc(doc(db(STRANGER), 'users', ME), { name: 'hack' }));
  await assertFails(setDoc(doc(db(STRANGER), 'users', STRANGER), { coupleId: C }, { merge: true }));
  await assertSucceeds(setDoc(doc(db(ME), 'users', ME), { name: 'Marc2' }, { merge: true }));
  await assertSucceeds(getDoc(doc(db(LOVE), 'users', ME)));
});

test('Liebesbrief: Text vor openAt gesperrt für Empfänger, offen für Schreiber', async () => {
  const content = (u) => doc(db(u), 'couples', C, 'letters', 'l1', 'content', 'text');
  await assertFails(getDoc(content(ME)));
  await assertSucceeds(getDoc(content(LOVE)));
  await assertFails(getDoc(content(STRANGER)));
  await assertFails(updateDoc(doc(db(ME), 'couples', C, 'letters', 'l1'), { openedAt: serverTimestamp() }));
});

test('Frage des Tages: Antwort des Schatzes erst nach eigener Antwort', async () => {
  const theirs = doc(db(ME), 'couples', C, 'days', 'd1', 'answers', LOVE);
  await assertFails(getDoc(theirs));
  await assertSucceeds(setDoc(doc(db(ME), 'couples', C, 'days', 'd1', 'answers', ME), { text: 'meine', at: serverTimestamp() }));
  await assertSucceeds(getDoc(theirs));
  await assertFails(setDoc(doc(db(ME), 'couples', C, 'days', 'd1', 'answers', LOVE), { text: 'gefälscht', at: serverTimestamp() }));
});

test('Laternen: nur eigene senden, nicht ändern', async () => {
  const col = collection(db(ME), 'couples', C, 'lanterns');
  await assertFails(addDoc(col, { from: LOVE, createdAt: serverTimestamp() }));
  const r = await assertSucceeds(addDoc(col, { from: ME, createdAt: serverTimestamp() }));
  await assertFails(deleteDoc(r));
});

test('Alles andere ist standardmässig verboten', async () => {
  await assertFails(setDoc(doc(db(ME), 'irgendwas', 'x'), { a: 1 }));
  await assertFails(setDoc(doc(db(ME), 'couples', C, 'geheim', 'x'), { a: 1 }));
});

// ---------- Storage ----------
const bytes = (n) => new Uint8Array(n);
const png = { contentType: 'image/png' };

test('Storage: Fremde und Anonyme sehen/laden nichts', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(ref(ctx.storage(), `couples/${C}/images/a.png`), bytes(10), png);
  });
  await assertFails(getBytes(ref(st(STRANGER), `couples/${C}/images/a.png`)));
  await assertFails(getBytes(ref(st(null), `couples/${C}/images/a.png`)));
  await assertFails(uploadBytes(ref(st(STRANGER), `couples/${C}/images/b.png`), bytes(10), png));
  await assertFails(uploadBytes(ref(st(null), `couples/${C}/images/b.png`), bytes(10), png));
});

test('Storage: ihr zwei dürft Bilder hochladen und lesen', async () => {
  await assertSucceeds(uploadBytes(ref(st(ME), `couples/${C}/images/b.png`), bytes(10), png));
  await assertSucceeds(getBytes(ref(st(LOVE), `couples/${C}/images/b.png`)));
});

test('Storage: falscher Typ und zu gross werden abgelehnt', async () => {
  await assertFails(uploadBytes(ref(st(ME), `couples/${C}/images/c.exe`), bytes(10), { contentType: 'application/x-msdownload' }));
  await assertFails(uploadBytes(ref(st(ME), `couples/${C}/audio/c.m4a`), bytes(10), png));
  await assertFails(uploadBytes(ref(st(ME), `couples/${C}/images/big.png`), bytes(16 * 1024 * 1024), png));
});

test('Storage: Datei-Ordner erlaubt PDF bis 25 MB, nicht darüber', async () => {
  const pdf = { contentType: 'application/pdf' };
  await assertSucceeds(uploadBytes(ref(st(ME), `couples/${C}/files/f1/ticket.pdf`), bytes(1000), pdf));
  await assertFails(uploadBytes(ref(st(ME), `couples/${C}/files/f1/riesig.pdf`), bytes(26 * 1024 * 1024), pdf));
});

test('Storage: Profilbild nur im eigenen Ordner; Fremde sehen es nicht', async () => {
  await assertFails(uploadBytes(ref(st(STRANGER), `users/${ME}/p.png`), bytes(10), png));
  await assertSucceeds(uploadBytes(ref(st(ME), `users/${ME}/p.png`), bytes(10), png));
  await assertSucceeds(getBytes(ref(st(LOVE), `users/${ME}/p.png`)));
  await assertFails(getBytes(ref(st(STRANGER), `users/${ME}/p.png`)));
});

test('Storage: nicht überschreiben und Fremde löschen nichts', async () => {
  await assertSucceeds(uploadBytes(ref(st(ME), `couples/${C}/images/o.png`), bytes(10), png));
  await assertFails(uploadBytes(ref(st(ME), `couples/${C}/images/o.png`), bytes(20), png));
  await assertFails(deleteObject(ref(st(STRANGER), `couples/${C}/images/o.png`)));
});

test('Storage: unbekannte Pfade verboten', async () => {
  await assertFails(uploadBytes(ref(st(ME), `irgendwo/x.png`), bytes(10), png));
});
