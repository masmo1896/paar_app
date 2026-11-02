import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/dates.dart';

import '../utils/shared_stream.dart';

/// Wer ist zuständig / betroffen: eine Person (uid) oder beide.
const both = 'both';

// Datenmodell in Firestore:
//   couples/{coupleId}/todos/{id}   -> { title, assignee, due?, done, doneAt?, createdBy, createdAt }
//   couples/{coupleId}/countdowns/{id} -> { title, date, emoji, yearly, createdBy, createdAt }
//   couples/{coupleId}/events/{id}  -> { title, who, startDate, endDate, startTime?, endTime?,
//                                        note?, createdBy, createdAt, updatedBy?, updatedAt? }
// Tage sind Texte wie "2026-11-06", Zeiten wie "07:40" (siehe utils/dates.dart).

class Todo {
  const Todo({
    required this.id,
    required this.title,
    required this.assignee,
    required this.due,
    required this.done,
    this.doneAt,
    this.list = todoList,
  });

  factory Todo.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Todo(
      id: doc.id,
      title: d['title'] as String? ?? '',
      assignee: d['assignee'] as String? ?? both,
      due: parseDayKey(d['due'] as String?),
      done: d['done'] as bool? ?? false,
      doneAt: (d['doneAt'] as Timestamp?)?.toDate(),
      list: d['list'] as String? ?? todoList,
    );
  }

  final String id;
  final String title;
  final String assignee; // uid oder 'both'
  final DateTime? due;
  final bool done;
  final DateTime? doneAt;
  final String list; // 'todo' oder 'shopping' (Einkaufsliste)

  bool get isShopping => list == shoppingList;
}

/// Die zwei Listen: To-dos und Einkaufsliste liegen in derselben Sammlung.
const todoList = 'todo';
const shoppingList = 'shopping';

class CalEvent {
  const CalEvent({
    required this.id,
    required this.title,
    required this.who,
    required this.start,
    required this.end,
    required this.startTime,
    required this.endTime,
    required this.note,
  });

  factory CalEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final start = parseDayKey(d['startDate'] as String?) ?? today();
    return CalEvent(
      id: doc.id,
      title: d['title'] as String? ?? '',
      who: d['who'] as String? ?? both,
      start: start,
      end: parseDayKey(d['endDate'] as String?) ?? start,
      startTime: parseTimeKey(d['startTime'] as String?),
      endTime: parseTimeKey(d['endTime'] as String?),
      note: d['note'] as String? ?? '',
    );
  }

  final String id;
  final String title;
  final String who; // uid oder 'both'
  final DateTime start; // erster Tag
  final DateTime end; // letzter Tag (gleich start bei eintägigen Terminen)
  final TimeOfDay? startTime; // null = ganztägig
  final TimeOfDay? endTime;
  final String note;

  bool get allDay => startTime == null;
  bool get multiDay => !sameDay(start, end);

  /// Liegt dieser Tag im Zeitraum des Termins?
  bool occursOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }
}

/// Countdown zu einem Datum, z. B. Urlaub oder Jahrestag.
class Countdown {
  const Countdown({
    required this.id,
    required this.title,
    required this.date,
    required this.emoji,
    required this.yearly,
  });

  factory Countdown.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Countdown(
      id: doc.id,
      title: d['title'] as String? ?? '',
      date: parseDayKey(d['date'] as String?) ?? today(),
      emoji: d['emoji'] as String? ?? '❤️',
      yearly: d['yearly'] as bool? ?? false,
    );
  }

  final String id;
  final String title;
  final DateTime date; // das ursprüngliche Datum (bei Jahrestagen der erste)
  final String emoji;
  final bool yearly; // jedes Jahr wiederholen

  /// Das Datum, auf das heruntergezählt wird: bei Jahrestagen das nächste Mal.
  DateTime get next {
    if (!yearly) return date;
    final t = today();
    final thisYear = DateTime(t.year, date.month, date.day);
    return thisYear.isBefore(t)
        ? DateTime(t.year + 1, date.month, date.day)
        : thisYear;
  }

  /// Tage bis [next]; negativ, wenn es vorbei ist (nur bei einmaligen möglich).
  int get daysLeft => daysBetween(today(), next);

  /// Tage seit dem ursprünglichen Datum (null, wenn es noch nicht passiert ist).
  int? get daysSince {
    final n = daysBetween(date, today());
    return n > 0 ? n : null;
  }
}

/// To-dos und Termine des Paares.
class PlannerService {
  PlannerService._();
  static final instance = PlannerService._();

  final _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> _todos(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('todos');
  CollectionReference<Map<String, dynamic>> _events(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('events');

  // --- To-dos -----------------------------------------------------------

  /// Geteilt: alle Bildschirme nutzen dieselbe Verbindung (siehe SharedStreams).
  Stream<List<Todo>> todos(String coupleId) =>
      SharedStreams.get('todos/$coupleId', () => _todosLive(coupleId));

  Stream<List<Todo>> _todosLive(String coupleId) =>
      _todos(coupleId)
          .snapshots()
          .map((s) => s.docs.map(Todo.fromDoc).toList());

  Future<void> saveTodo(
    String coupleId, {
    String? id,
    required String title,
    required String assignee,
    DateTime? due,
    String list = todoList,
  }) {
    final data = {
      'title': title,
      'assignee': assignee,
      'due': due == null ? null : dayKey(due),
    };
    if (id != null) return _todos(coupleId).doc(id).update(data);
    return _todos(coupleId).add({
      ...data,
      'list': list,
      'done': false,
      'createdBy': _uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setTodoDone(String coupleId, String id, bool done) =>
      _todos(coupleId).doc(id).update({
        'done': done,
        'doneAt': done ? FieldValue.serverTimestamp() : FieldValue.delete(),
      });

  Future<void> deleteTodo(String coupleId, String id) =>
      _todos(coupleId).doc(id).delete();

  // --- Countdowns -------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _countdowns(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('countdowns');

  /// Geteilt: alle Bildschirme nutzen dieselbe Verbindung (siehe SharedStreams).
  Stream<List<Countdown>> countdowns(String coupleId) => SharedStreams.get(
    'countdowns/$coupleId',
    () => _countdownsLive(coupleId),
  );

  Stream<List<Countdown>> _countdownsLive(String coupleId) =>
      _countdowns(coupleId)
          .snapshots()
          .map((s) => s.docs.map(Countdown.fromDoc).toList());

  Future<void> saveCountdown(
    String coupleId, {
    String? id,
    required String title,
    required DateTime date,
    required String emoji,
    required bool yearly,
  }) {
    final data = {
      'title': title,
      'date': dayKey(date),
      'emoji': emoji,
      'yearly': yearly,
    };
    if (id != null) return _countdowns(coupleId).doc(id).update(data);
    return _countdowns(coupleId).add({
      ...data,
      'createdBy': _uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteCountdown(String coupleId, String id) =>
      _countdowns(coupleId).doc(id).delete();

  // --- Termine ----------------------------------------------------------

  /// Geteilt: alle Bildschirme nutzen dieselbe Verbindung (siehe SharedStreams).
  Stream<List<CalEvent>> events(String coupleId) =>
      SharedStreams.get('events/$coupleId', () => _eventsLive(coupleId));

  Stream<List<CalEvent>> _eventsLive(String coupleId) =>
      _events(coupleId)
          .snapshots()
          .map((s) => s.docs.map(CalEvent.fromDoc).toList());

  Future<void> saveEvent(
    String coupleId, {
    String? id,
    required String title,
    required String who,
    required DateTime start,
    required DateTime end,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    String note = '',
  }) {
    final data = {
      'title': title,
      'who': who,
      'startDate': dayKey(start),
      'endDate': dayKey(end),
      'startTime': startTime == null ? null : timeKey(startTime),
      'endTime': startTime == null || endTime == null ? null : timeKey(endTime),
      'note': note,
    };
    // Beim Ändern merken, wer es war – dann benachrichtigt die Cloud-Funktion
    // die andere Person ("Marc hat einen Termin geändert").
    if (id != null) {
      return _events(coupleId).doc(id).update({
        ...data,
        'updatedBy': _uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    return _events(coupleId).add({
      ...data,
      'createdBy': _uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteEvent(String coupleId, String id) =>
      _events(coupleId).doc(id).delete();
}
