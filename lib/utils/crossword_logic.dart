import 'dart:math';

// Kreuzworträtsel ohne Firebase: Wörter, Felder, Eingabe vergleichen.

class CrosswordWord {
  const CrosswordWord({
    required this.id,
    required this.clue,
    required this.answer,
    required this.x,
    required this.y,
    required this.across,
  });

  factory CrosswordWord.fromMap(Map<String, dynamic> m) => CrosswordWord(
    id: m['id'] as String? ?? '',
    clue: m['clue'] as String? ?? '',
    answer: m['answer'] as String? ?? '',
    x: (m['x'] as num?)?.toInt() ?? 0,
    y: (m['y'] as num?)?.toInt() ?? 0,
    across: m['across'] as bool? ?? true,
  );

  final String id;
  final String clue;

  /// Nur Grossbuchstaben A–Z und ÄÖÜ (siehe [normalizeAnswer]).
  final String answer;
  final int x;
  final int y;

  /// true = waagrecht, false = senkrecht.
  final bool across;

  Map<String, dynamic> toMap() => {
    'id': id,
    'clue': clue,
    'answer': answer,
    'x': x,
    'y': y,
    'across': across,
  };

  List<Point<int>> get cells => [
    for (var i = 0; i < answer.length; i++)
      across ? Point(x + i, y) : Point(x, y + i),
  ];
}

/// Eingabe vergleichbar machen: Grossbuchstaben, ß → SS, ohne Leer- und Sonderzeichen.
String normalizeAnswer(String s) => s
    .toUpperCase()
    .replaceAll('ß', 'SS')
    .replaceAll('ẞ', 'SS')
    .replaceAll(RegExp(r'[^A-ZÄÖÜ]'), '');

/// Feld-Nummer für die Liste "revealed" (Hinweise).
int cellIndex(Point<int> p, int size) => p.y * size + p.x;

/// Buchstabe je Feld: aus der Lösung.
Map<Point<int>, String> solutionGrid(List<CrosswordWord> words) => {
  for (final w in words)
    for (var i = 0; i < w.answer.length; i++) w.cells[i]: w.answer[i],
};

/// Nummern an den Wortanfängen (1, 2, 3 … von oben links nach unten rechts).
Map<Point<int>, int> clueNumbers(List<CrosswordWord> words) {
  final starts = {for (final w in words) Point(w.x, w.y)}.toList()
    ..sort((a, b) => a.y != b.y ? a.y - b.y : a.x - b.x);
  return {for (var i = 0; i < starts.length; i++) starts[i]: i + 1};
}
