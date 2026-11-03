import 'dart:math';

// Kleine Überraschungen, die sich jeden Tag ändern. Alles hier ist reine Logik
// (ohne Firebase) und für euch beide gleich, weil es nur vom Datum und eurer
// Paar-ID abhängt.

/// Tages-Schlüssel wie '2026-11-03' (lokales Datum).
String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Stabile Zufallszahl aus einem Text (FNV-1a) – gleich auf jedem Handy.
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

int _daySeed(DateTime d, [String salt = '']) =>
    stableHash('${dayKey(d)}|$salt');

// ---- 1. Echte Mondphase ------------------------------------------------------

/// Mondphase 0–1: 0 = Neumond, 0.25 = zunehmender Halbmond, 0.5 = Vollmond,
/// 0.75 = abnehmender Halbmond. Gerechnet ab einem bekannten Neumond.
double moonPhase(DateTime t) {
  const synodic = 29.530588853; // Tage von Neumond zu Neumond
  final ref = DateTime.utc(2000, 1, 6, 18, 14);
  final days = t.toUtc().difference(ref).inSeconds / 86400;
  final p = (days / synodic) % 1;
  return p < 0 ? p + 1 : p;
}

/// Beleuchteter Anteil 0–1.
double moonIllumination(DateTime t) => (1 - cos(2 * pi * moonPhase(t))) / 2;

bool isFullMoon(DateTime t) => (moonPhase(t) - 0.5).abs() < 0.034;

String moonName(DateTime t) {
  final p = moonPhase(t);
  if (p < 0.034 || p > 0.966) return 'Neumond';
  if (isFullMoon(t)) return 'Vollmond';
  if ((p - 0.25).abs() < 0.034) return 'zunehmender Halbmond';
  if ((p - 0.75).abs() < 0.034) return 'abnehmender Halbmond';
  return p < 0.5 ? 'zunehmender Mond' : 'abnehmender Mond';
}

// ---- 2. Fuchs des Tages ------------------------------------------------------

enum FoxOutfit {
  scarf('einen Schal'),
  sunglasses('eine Sonnenbrille'),
  flowers('einen Blumenkranz'),
  partyHat('einen Partyhut'),
  santaHat('eine Weihnachtsmütze');

  const FoxOutfit(this.label);

  /// Für Sätze wie «Heute trage ich …».
  final String label;
}

/// Was der Fuchs heute trägt: an Feiertagen Passendes, sonst wechselnd.
FoxOutfit foxOutfitFor(DateTime d) {
  if (d.month == 12 && d.day >= 24 && d.day <= 26) return FoxOutfit.santaHat;
  if ((d.month == 12 && d.day == 31) || (d.month == 1 && d.day == 1)) {
    return FoxOutfit.partyHat;
  }
  if (d.month == 2 && d.day == 14) return FoxOutfit.flowers;
  const rotation = [
    FoxOutfit.scarf,
    FoxOutfit.sunglasses,
    FoxOutfit.flowers,
    FoxOutfit.partyHat,
  ];
  // Tag für Tag der Reihe nach, damit es sicher jeden Tag wechselt.
  final dayNumber = DateTime.utc(
    d.year,
    d.month,
    d.day,
  ).difference(DateTime.utc(2026)).inDays;
  return rotation[dayNumber % rotation.length];
}

// ---- 3. Sternschnuppe --------------------------------------------------------

/// Heute ab dieser Zeit fliegt eure Sternschnuppe (zwischen 17 und 23 Uhr,
/// für euch beide gleich). Danach kommt sie immer wieder, bis jemand sie fängt.
DateTime shootingStarTime(DateTime day, String coupleId) {
  final minutes = 17 * 60 + _daySeed(day, 'stern|$coupleId') % (6 * 60);
  return DateTime(day.year, day.month, day.day).add(Duration(minutes: minutes));
}

// ---- 4. Goldene Laterne ------------------------------------------------------

/// Etwa jede 50. Laterne ist golden – aus ihrer ID, also für euch beide gleich.
bool isGoldenLantern(String id) => stableHash('gold|$id') % 50 == 0;

// ---- 5. Monatstag ------------------------------------------------------------

/// Ist heute euer Monatstag? Dann die Anzahl Monate seit [since], sonst null.
/// Hat ein Monat den Tag nicht (z. B. der 31.), zählt der letzte Tag des Monats.
int? monthiversary(DateTime since, DateTime today) {
  final lastDay = DateTime(today.year, today.month + 1, 0).day;
  if (today.day != min(since.day, lastDay)) return null;
  final months = (today.year - since.year) * 12 + today.month - since.month;
  return months > 0 ? months : null;
}

// ---- 6. Verstecktes Kanji ----------------------------------------------------

const _kanji = ['福', '愛', '縁', '幸', '夢', '星', '月', '桜', '狐', '光', '和', '絆'];
const kanjiMeanings = {
  '福': 'Glück',
  '愛': 'Liebe',
  '縁': 'Schicksalsband',
  '幸': 'Freude',
  '夢': 'Traum',
  '星': 'Stern',
  '月': 'Mond',
  '桜': 'Kirschblüte',
  '狐': 'Fuchs',
  '光': 'Licht',
  '和': 'Harmonie',
  '絆': 'Verbundenheit',
};

/// Heutiges Versteck: welches Zeichen, in welchem Bereich (0 Home, 1 Chat,
/// 2 Kalender, 3 To-dos, 4 Wir) und wo (Anteil von Breite/Höhe).
({String char, int tab, double x, double y}) hiddenKanji(
  DateTime day,
  String coupleId,
) {
  final h = _daySeed(day, 'kanji|$coupleId');
  return (
    char: _kanji[h % _kanji.length],
    tab: (h ~/ 13) % 5,
    x: 0.08 + ((h ~/ 97) % 1000) / 1000 * 0.8,
    y: 0.2 + ((h ~/ 7919) % 1000) / 1000 * 0.55,
  );
}
