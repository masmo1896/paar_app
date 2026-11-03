import 'dart:math';

// Regeln von Schiffe versenken, ohne Firebase (in test/ geprüft).
// Die gleichen Regeln prüft die Cloud Function functions/battleship.js.

const boardSize = 10;

/// Die Flotte: id und Länge. Reihenfolge = Reihenfolge beim Platzieren.
const fleetSpec = [
  (id: 's5', len: 5, name: 'Kitsune-Flaggschiff'),
  (id: 's4', len: 4, name: 'Mondsegler'),
  (id: 's3a', len: 3, name: 'Laternenboot'),
  (id: 's3b', len: 3, name: 'Koi-Kutter'),
  (id: 's2', len: 2, name: 'Papierboot'),
];

String shipName(String id) =>
    fleetSpec.firstWhere((s) => s.id == id, orElse: () => fleetSpec.last).name;

class Ship {
  const Ship({
    required this.id,
    required this.len,
    required this.x,
    required this.y,
    required this.vertical,
  });

  factory Ship.fromMap(Map<String, dynamic> m) => Ship(
    id: m['id'] as String? ?? '',
    len: (m['len'] as num?)?.toInt() ?? 0,
    x: (m['x'] as num?)?.toInt() ?? 0,
    y: (m['y'] as num?)?.toInt() ?? 0,
    vertical: m['vertical'] as bool? ?? false,
  );

  final String id;
  final int len;
  final int x;
  final int y;
  final bool vertical;

  Map<String, dynamic> toMap() => {
    'id': id,
    'len': len,
    'x': x,
    'y': y,
    'vertical': vertical,
  };

  Ship copyWith({int? x, int? y, bool? vertical}) => Ship(
    id: id,
    len: len,
    x: x ?? this.x,
    y: y ?? this.y,
    vertical: vertical ?? this.vertical,
  );

  /// Alle Felder des Schiffs als (x, y).
  List<Point<int>> get cells => [
    for (var i = 0; i < len; i++) vertical ? Point(x, y + i) : Point(x + i, y),
  ];

  bool get inBounds => cells.every(
    (c) => c.x >= 0 && c.y >= 0 && c.x < boardSize && c.y < boardSize,
  );
}

/// Schiffe, die ausserhalb liegen oder sich überlappen (für die rote Markierung).
Set<String> invalidShips(List<Ship> ships) {
  final bad = <String>{};
  final owner = <Point<int>, String>{};
  for (final s in ships) {
    if (!s.inBounds) bad.add(s.id);
    for (final c in s.cells) {
      final other = owner[c];
      if (other != null) {
        bad
          ..add(s.id)
          ..add(other);
      } else {
        owner[c] = s.id;
      }
    }
  }
  return bad;
}

/// Gültig = genau die Flotte aus [fleetSpec], im Feld, ohne Überlappung.
bool isValidFleet(List<Ship> ships) {
  if (ships.length != fleetSpec.length) return false;
  for (final spec in fleetSpec) {
    final s = ships.where((s) => s.id == spec.id);
    if (s.length != 1 || s.first.len != spec.len) return false;
  }
  return invalidShips(ships).isEmpty;
}

/// Zufällige gültige Aufstellung.
List<Ship> randomFleet([Random? rnd]) {
  final r = rnd ?? Random();
  while (true) {
    final ships = <Ship>[];
    var ok = true;
    for (final spec in fleetSpec) {
      Ship? placed;
      for (var tries = 0; tries < 200 && placed == null; tries++) {
        final vertical = r.nextBool();
        final s = Ship(
          id: spec.id,
          len: spec.len,
          x: r.nextInt(vertical ? boardSize : boardSize - spec.len + 1),
          y: r.nextInt(vertical ? boardSize - spec.len + 1 : boardSize),
          vertical: vertical,
        );
        if (invalidShips([...ships, s]).isEmpty) placed = s;
      }
      if (placed == null) {
        ok = false;
        break;
      }
      ships.add(placed);
    }
    if (ok) return ships;
  }
}

/// Ergebnis eines Schusses, wie es die Cloud Function einträgt.
enum ShotResult { pending, miss, hit, sunk }

ShotResult shotResultFrom(String? s) => switch (s) {
  'miss' => ShotResult.miss,
  'hit' => ShotResult.hit,
  'sunk' => ShotResult.sunk,
  _ => ShotResult.pending,
};

class Shot {
  const Shot({
    required this.id,
    required this.by,
    required this.x,
    required this.y,
    required this.at,
    required this.result,
    this.shipLen,
    this.shipCells = const [],
  });

  final String id;
  final String by;
  final int x;
  final int y;
  final DateTime at;
  final ShotResult result;
  final int? shipLen;

  /// Nur beim Versenken: alle Felder des Schiffs (für das brennende Boot).
  final List<Point<int>> shipCells;

  bool get isHit => result == ShotResult.hit || result == ShotResult.sunk;
}
