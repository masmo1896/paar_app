import 'package:flutter/material.dart';

// Datums-Hilfen auf Deutsch. Tage werden als "2026-11-06" gespeichert (ohne Zeitzone),
// damit ein Termin in Lissabon nicht plötzlich auf einen anderen Tag rutscht.

const weekdaysShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const weekdaysLong = [
  'Montag',
  'Dienstag',
  'Mittwoch',
  'Donnerstag',
  'Freitag',
  'Samstag',
  'Sonntag',
];
const monthsLong = [
  'Januar',
  'Februar',
  'März',
  'April',
  'Mai',
  'Juni',
  'Juli',
  'August',
  'September',
  'Oktober',
  'November',
  'Dezember',
];
const monthsShort = [
  'Jan.',
  'Feb.',
  'März',
  'Apr.',
  'Mai',
  'Juni',
  'Juli',
  'Aug.',
  'Sep.',
  'Okt.',
  'Nov.',
  'Dez.',
];

/// Heute um Mitternacht.
DateTime today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "2026-11-06"
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime? parseDayKey(String? s) {
  if (s == null) return null;
  final parts = s.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]),
      m = int.tryParse(parts[1]),
      d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

/// "07:40"
String timeKey(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay? parseTimeKey(String? s) {
  if (s == null) return null;
  final parts = s.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return TimeOfDay(hour: h, minute: m);
}

/// "Fr, 6. Nov." (mit Jahr, wenn es nicht das aktuelle ist)
String shortDay(DateTime d) {
  final base =
      '${weekdaysShort[d.weekday - 1]}, ${d.day}. ${monthsShort[d.month - 1]}';
  return d.year == DateTime.now().year ? base : '$base ${d.year}';
}

/// "Freitag, 6. November"
String longDay(DateTime d) =>
    '${weekdaysLong[d.weekday - 1]}, ${d.day}. ${monthsLong[d.month - 1]}';

/// Ganze Tage von [from] bis [to] (negativ, wenn [to] davor liegt).
/// Über UTC gerechnet: bei der Zeitumstellung ist ein Tag sonst 23 oder 25 Stunden lang.
int daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// "Heute", "Morgen", "Gestern" oder z. B. "Fr, 6. Nov."
String relativeDay(DateTime d) {
  final diff = daysBetween(today(), d);
  return switch (diff) {
    0 => 'Heute',
    1 => 'Morgen',
    -1 => 'Gestern',
    _ => shortDay(d),
  };
}
