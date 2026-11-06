import 'dart:math';

import 'crossword_logic.dart';
import 'crossword_words.dart';
import 'crossword_words_expert.dart';

/// Ein fertiges Rätsel: quadratisches Feld der Kantenlänge [size].
typedef CrosswordPuzzle = ({int size, List<CrosswordWord> words});

/// Schwierigkeit: Grösse, Wortanzahl, Wortlänge und aufgedeckte Startbuchstaben.
enum CrosswordLevel {
  veryEasy(
    'Sehr leicht',
    '7×7 · 5 kurze Wörter · 4 Buchstaben geschenkt · 3 Hinweise',
  ),
  easy('Einfach', '9×9 · kurze Wörter · 2 Buchstaben geschenkt · 5 Hinweise'),
  medium('Mittel', '11×11 · 10 Wörter · 8 Hinweise'),
  hard('Schwer', '13×13 · lange, knifflige Wörter · 12 Hinweise'),
  expert('Experte', '15×15 · seltene Wörter · 16 Hinweise'),
  god('Gott', '15×15 · extrem schwer · Fachwörter · 20 Hinweise');

  const CrosswordLevel(this.label, this.description);
  final String label;
  final String description;

  /// Sterne in der Auswahl: 1 (sehr leicht) bis 6 (Gott).
  int get stars => index + 1;

  /// So oft darf man einen Buchstaben aufdecken – je schwerer, desto öfter.
  int get maxHints => switch (this) {
    veryEasy => 3,
    easy => 5,
    medium => 8,
    hard => 12,
    expert => 16,
    god => 20,
  };

  /// Wie viel ein Wort wert ist (Punkte pro Buchstabe).
  int get pointsPerLetter => switch (this) {
    veryEasy => 5,
    easy => 8,
    medium => 12,
    hard => 20,
    expert => 30,
    god => 50,
  };

  int get maxSize => switch (this) {
    veryEasy => 7,
    easy => 9,
    medium => 11,
    hard => 13,
    expert => 15,
    god => 15,
  };
  int get target => switch (this) {
    veryEasy => 5,
    easy => 7,
    medium => 10,
    hard => 14,
    expert => 17,
    god => 20,
  };
  int get minLength => switch (this) {
    veryEasy => 3,
    easy => 3,
    medium => 3,
    hard => 5,
    expert => 6,
    god => 7,
  };
  int get maxLength => switch (this) {
    veryEasy => 5,
    easy => 6,
    medium => 10,
    hard => 12,
    expert => 13,
    god => 14,
  };

  /// So viele Buchstaben sind zu Beginn schon aufgedeckt.
  int get giftedLetters => switch (this) {
    veryEasy => 4,
    easy => 2,
    _ => 0,
  };

  List<(String, String)> get bank => switch (this) {
    veryEasy || easy || medium => crosswordWords,
    hard => [...crosswordWordsHard, ...crosswordWords],
    expert => [
      ...crosswordWordsExpert,
      ...crosswordWordsHard,
      ...crosswordWords,
    ],
    god => [
      ...crosswordWordsGod,
      ...crosswordWordsExpert,
      ...crosswordWordsHard,
    ],
  };

  static CrosswordLevel fromName(String? name) =>
      values.firstWhere((l) => l.name == name, orElse: () => medium);
}

/// Rätsel für eine Stufe; bei «Einfach» mit [CrosswordLevel.giftedLetters]
/// zufällig aufgedeckten Feldern (als Feld-Nummern, siehe [cellIndex]).
/// [avoid]: zuletzt gespielte Wörter, das neueste zuerst. Sie kommen nur vor, wenn es
/// sonst nicht reicht – und dann die am längsten nicht mehr gesehenen zuerst.
({CrosswordPuzzle puzzle, List<int> revealed}) generateForLevel(
  CrosswordLevel level, {
  List<String> avoid = const [],
  Random? random,
}) {
  final rnd = random ?? Random();
  final puzzle = generateCrossword(
    bank: level.bank,
    maxSize: level.maxSize,
    target: level.target,
    minLength: level.minLength,
    maxLength: level.maxLength,
    avoid: avoid,
    random: rnd,
  );
  final cells = {
    for (final w in puzzle.words)
      for (final c in w.cells) cellIndex(c, puzzle.size),
  }.toList()..shuffle(rnd);
  return (puzzle: puzzle, revealed: cells.take(level.giftedLetters).toList());
}

/// Baut ein Kreuzworträtsel mit bis zu [target] sich kreuzenden Wörtern.
/// Probiert [attempts] Varianten und nimmt die mit den meisten Wörtern und Kreuzungen.
CrosswordPuzzle generateCrossword({
  List<(String, String)> bank = crosswordWords,
  int maxSize = 11,
  int target = 10,
  int attempts = 30,
  int minLength = 3,
  int maxLength = 10,
  List<String> avoid = const [],
  Random? random,
}) {
  final rnd = random ?? Random();
  final seen = <String>{};
  final usable = [
    for (final (answer, clue) in bank)
      if (answer.length >= minLength &&
          answer.length <= min(maxLength, maxSize - 1) &&
          seen.add(normalizeAnswer(answer)))
        (normalizeAnswer(answer), clue),
  ];

  _Layout? best;
  for (var i = 0; i < attempts; i++) {
    final layout = _Layout(maxSize)..build(usable, target, avoid, rnd);
    if (best == null || layout.score > best.score) best = layout;
  }
  return best!.trimmed();
}

class _Placed {
  _Placed(this.answer, this.clue, this.x, this.y, this.across);
  final String answer;
  final String clue;
  final int x;
  final int y;
  final bool across;
}

class _Layout {
  _Layout(this.size);

  final int size;
  final _grid = <Point<int>, String>{};
  // Felder, in denen schon ein Wort in dieser Richtung liegt.
  final _usedAcross = <Point<int>>{};
  final _usedDown = <Point<int>>{};
  final placed = <_Placed>[];
  var crossings = 0;
  // Wörter, die ihr schon einmal gespielt habt (machen eine Variante schlechter).
  var repeats = 0;

  int get score => placed.length * 10 + crossings - repeats * 8;

  void build(
    List<(String, String)> bank,
    int target,
    List<String> avoid,
    Random rnd,
  ) {
    // Gemischt; zuerst nie gespielte Wörter, danach die am längsten nicht
    // mehr gesehenen (bei Gleichstand bleibt die Zufallsreihenfolge).
    final seen = {for (var i = 0; i < avoid.length; i++) avoid[i]: i};
    final shuffled = [...bank]..shuffle(rnd);
    final stale =
        [
          for (var i = 0; i < shuffled.length; i++)
            if (seen.containsKey(shuffled[i].$1)) (word: shuffled[i], pos: i),
        ]..sort((a, b) {
          final age = seen[b.word.$1]! - seen[a.word.$1]!;
          return age != 0 ? age : a.pos - b.pos;
        });
    final words = [
      ...shuffled.where((w) => !seen.containsKey(w.$1)),
      for (final s in stale) s.word,
    ];
    // Erstes Wort: lang, waagrecht in die Mitte.
    final first = words.firstWhere(
      (w) => w.$1.length >= 6,
      orElse: () => words.first,
    );
    _place(
      _Placed(
        first.$1,
        first.$2,
        (size - first.$1.length) ~/ 2,
        size ~/ 2,
        true,
      ),
    );
    final used = {first.$1};
    if (seen.containsKey(first.$1)) repeats++;

    for (final (answer, clue) in words) {
      if (placed.length >= target) break;
      if (used.contains(answer)) continue;
      final spot = _bestSpot(answer, rnd);
      if (spot == null) continue;
      _place(_Placed(answer, clue, spot.x, spot.y, spot.across));
      crossings += spot.crosses;
      if (seen.containsKey(answer)) repeats++;
      used.add(answer);
    }
  }

  ({int x, int y, bool across, int crosses})? _bestSpot(
    String word,
    Random rnd,
  ) {
    ({int x, int y, bool across, int crosses})? best;
    for (final entry in _grid.entries) {
      for (var i = 0; i < word.length; i++) {
        if (word[i] != entry.value) continue;
        for (final across in const [true, false]) {
          final x = across ? entry.key.x - i : entry.key.x;
          final y = across ? entry.key.y : entry.key.y - i;
          final crosses = _fits(word, x, y, across);
          if (crosses == null || crosses == 0) continue;
          if (best == null ||
              crosses > best.crosses ||
              (crosses == best.crosses && rnd.nextBool())) {
            best = (x: x, y: y, across: across, crosses: crosses);
          }
        }
      }
    }
    return best;
  }

  /// Anzahl Kreuzungen, oder null, wenn das Wort dort nicht passt.
  int? _fits(String word, int x, int y, bool across) {
    final dx = across ? 1 : 0, dy = across ? 0 : 1;
    final endX = x + dx * (word.length - 1), endY = y + dy * (word.length - 1);
    if (x < 0 || y < 0 || endX >= size || endY >= size) return null;
    // Vor dem Anfang und nach dem Ende muss frei sein.
    if (_grid.containsKey(Point(x - dx, y - dy))) return null;
    if (_grid.containsKey(Point(endX + dx, endY + dy))) return null;

    var crosses = 0;
    for (var i = 0; i < word.length; i++) {
      final p = Point(x + dx * i, y + dy * i);
      final existing = _grid[p];
      if (existing != null) {
        if (existing != word[i]) return null;
        if ((across ? _usedAcross : _usedDown).contains(p)) return null;
        crosses++;
      } else {
        // Keine Nachbarn quer dazu, sonst entstehen ungewollte Wörter.
        if (_grid.containsKey(Point(p.x + dy, p.y + dx)) ||
            _grid.containsKey(Point(p.x - dy, p.y - dx))) {
          return null;
        }
      }
    }
    return crosses;
  }

  void _place(_Placed w) {
    placed.add(w);
    for (var i = 0; i < w.answer.length; i++) {
      final p = w.across ? Point(w.x + i, w.y) : Point(w.x, w.y + i);
      _grid[p] = w.answer[i];
      (w.across ? _usedAcross : _usedDown).add(p);
    }
  }

  /// Leeren Rand abschneiden und Wörter von oben links nach unten rechts nummerieren.
  CrosswordPuzzle trimmed() {
    final xs = _grid.keys.map((p) => p.x), ys = _grid.keys.map((p) => p.y);
    final minX = xs.reduce(min), minY = ys.reduce(min);
    final width = xs.reduce(max) - minX + 1, height = ys.reduce(max) - minY + 1;
    final sorted = [...placed]
      ..sort((a, b) => a.y != b.y ? a.y - b.y : a.x - b.x);
    return (
      size: max(width, height),
      words: [
        for (var i = 0; i < sorted.length; i++)
          CrosswordWord(
            id: 'w${i + 1}',
            clue: sorted[i].clue,
            answer: sorted[i].answer,
            x: sorted[i].x - minX,
            y: sorted[i].y - minY,
            across: sorted[i].across,
          ),
      ],
    );
  }
}
