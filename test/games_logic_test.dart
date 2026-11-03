import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:paar_app/services/lantern_service.dart';
import 'package:paar_app/utils/battleship_logic.dart';
import 'package:paar_app/utils/crossword_generator.dart';
import 'package:paar_app/utils/crossword_logic.dart';
import 'package:paar_app/utils/crossword_words.dart';

void main() {
  group('Kreuzwort', () {
    test('Wortliste: Lösungen sind schon normalisiert und nicht doppelt', () {
      final seen = <String>{};
      for (final (answer, clue) in crosswordWords) {
        expect(normalizeAnswer(answer), answer, reason: answer);
        expect(clue.trim(), isNotEmpty, reason: answer);
        expect(seen.add(answer), isTrue, reason: 'doppelt: $answer');
      }
      expect(crosswordWords.length, greaterThanOrEqualTo(200));
    });

    test('Eingabe wird grosszügig verglichen', () {
      expect(normalizeAnswer(' hello kitty! '), 'HELLOKITTY');
      expect(normalizeAnswer('Strauß'), 'STRAUSS');
    });

    test('Generator: gültige, sich kreuzende Rätsel', () {
      for (var seed = 0; seed < 50; seed++) {
        final p = generateCrossword(random: Random(seed));
        expect(p.words.length, greaterThanOrEqualTo(7), reason: 'seed $seed');
        expect(p.size, lessThanOrEqualTo(11));
        final grid = <Point<int>, String>{};
        for (final w in p.words) {
          for (var i = 0; i < w.answer.length; i++) {
            final c = w.cells[i];
            expect(c.x, inInclusiveRange(0, p.size - 1));
            expect(c.y, inInclusiveRange(0, p.size - 1));
            final prev = grid[c];
            if (prev != null) expect(prev, w.answer[i], reason: 'seed $seed');
            grid[c] = w.answer[i];
          }
        }
        // Jedes Wort kreuzt mindestens ein anderes.
        for (final w in p.words) {
          final others = p.words
              .where((o) => o != w)
              .expand((o) => o.cells)
              .toSet();
          expect(
            w.cells.any(others.contains),
            isTrue,
            reason: '${w.answer} seed $seed',
          );
        }
        expect(p.words.map((w) => w.id).toSet().length, p.words.length);
      }
    });
  });

  group('Kreuzwort-Stufen', () {
    test('Schwere Wörter: normalisiert und nicht doppelt', () {
      final seen = <String>{};
      for (final (answer, clue) in crosswordWordsHard) {
        expect(normalizeAnswer(answer), answer, reason: answer);
        expect(clue.trim(), isNotEmpty, reason: answer);
        expect(seen.add(answer), isTrue, reason: 'doppelt: $answer');
      }
    });

    for (final (level, minWords) in [
      (CrosswordLevel.easy, 5),
      (CrosswordLevel.medium, 7),
      (CrosswordLevel.hard, 10),
    ]) {
      test('${level.label}: Grösse, Wortanzahl, Wortlänge, alles kreuzt', () {
        var total = 0;
        for (var seed = 0; seed < 40; seed++) {
          final r = generateForLevel(level, random: Random(seed));
          final p = r.puzzle;
          total += p.words.length;
          expect(p.size, lessThanOrEqualTo(level.maxSize));
          expect(
            p.words.length,
            greaterThanOrEqualTo(minWords),
            reason: 'seed $seed',
          );
          expect(r.revealed.length, level.giftedLetters);
          final grid = <Point<int>, String>{};
          for (final w in p.words) {
            expect(
              w.answer.length,
              inInclusiveRange(level.minLength, level.maxLength),
            );
            for (var i = 0; i < w.answer.length; i++) {
              final c = w.cells[i];
              expect(c.x, inInclusiveRange(0, p.size - 1));
              expect(c.y, inInclusiveRange(0, p.size - 1));
              final prev = grid[c];
              if (prev != null) expect(prev, w.answer[i]);
              grid[c] = w.answer[i];
            }
          }
          for (final w in p.words) {
            final others = p.words
                .where((o) => o != w)
                .expand((o) => o.cells)
                .toSet();
            expect(
              w.cells.any(others.contains),
              isTrue,
              reason: '${w.answer} seed $seed',
            );
          }
          for (final i in r.revealed) {
            expect(grid.containsKey(Point(i % p.size, i ~/ p.size)), isTrue);
          }
        }
        // ignore: avoid_print
        print(
          '${level.label}: im Schnitt ${(total / 40).toStringAsFixed(1)} Wörter',
        );
      });
    }
  });

  group('Laternen gleichzeitig', () {
    final t0 = DateTime(2026, 11, 3, 20);
    Lantern l(String id, String from, int minutes) => Lantern(
      id: id,
      from: from,
      at: t0.add(Duration(minutes: minutes)),
    );

    test('Billie zuerst, ich 3 Min. später: neuer Moment', () {
      expect(
        LanternService.addsSyncMoment([l('b1', 'B', 0)], [l('m1', 'M', 3)]),
        isTrue,
      );
    });
    test(
      'Ich zuerst, Billie 4 Min. später (Fuchs bringt sie): neuer Moment',
      () {
        expect(
          LanternService.addsSyncMoment([l('m1', 'M', 0)], [l('b1', 'B', 4)]),
          isTrue,
        );
      },
    );
    test('Mehr als 5 Min. auseinander: kein Moment', () {
      expect(
        LanternService.addsSyncMoment([l('b1', 'B', 0)], [l('m1', 'M', 6)]),
        isFalse,
      );
    });
    test('Eigene Laternen untereinander zählen nicht', () {
      expect(
        LanternService.addsSyncMoment([l('m1', 'M', 0)], [l('m2', 'M', 1)]),
        isFalse,
      );
    });
    test('Derselbe Moment wird nur einmal gefeiert', () {
      final before = [l('b1', 'B', 0), l('m1', 'M', 1)];
      expect(LanternService.addsSyncMoment(before, [l('m2', 'M', 2)]), isFalse);
      expect(LanternService.addsSyncMoment(before, [l('b2', 'B', 3)]), isFalse);
    });
    test('Später ein neuer Moment wird wieder gefeiert', () {
      final before = [l('b1', 'B', 0), l('m1', 'M', 1)];
      expect(
        LanternService.addsSyncMoment(before, [
          l('b2', 'B', 30),
          l('m2', 'M', 32),
        ]),
        isTrue,
      );
      expect(
        LanternService.syncMoments([
          ...before,
          l('b2', 'B', 30),
          l('m2', 'M', 32),
        ]),
        2,
      );
    });
  });

  group('Schiffe versenken', () {
    test('Zufallsflotte ist immer gültig', () {
      for (var seed = 0; seed < 200; seed++) {
        expect(isValidFleet(randomFleet(Random(seed))), isTrue);
      }
    });

    test('Ungültig: Überlappung, ausserhalb, falsche Flotte', () {
      final ok = randomFleet(Random(1));
      final s5 = ok.firstWhere((s) => s.id == 's5');
      final overlap = [
        for (final s in ok)
          s.id == 's2'
              ? s.copyWith(x: s5.x, y: s5.y, vertical: s5.vertical)
              : s,
      ];
      expect(isValidFleet(overlap), isFalse);
      expect(invalidShips(overlap), containsAll(['s2', 's5']));
      final outside = [
        for (final s in ok)
          s.id == 's5' ? s.copyWith(x: 8, y: 0, vertical: false) : s,
      ];
      expect(isValidFleet(outside), isFalse);
      expect(isValidFleet(ok.take(4).toList()), isFalse);
    });
  });
}
