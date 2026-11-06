import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:paar_app/services/lantern_service.dart';
import 'package:paar_app/utils/battleship_logic.dart';
import 'package:paar_app/utils/crossword_generator.dart';
import 'package:paar_app/utils/crossword_logic.dart';
import 'package:paar_app/utils/crossword_words.dart';
import 'package:paar_app/utils/crossword_tips.dart';
import 'package:paar_app/utils/crossword_words_expert.dart';

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

    test('Experten- und Gott-Wörter: normalisiert, nirgends doppelt', () {
      final others = {
        for (final (a, _) in [...crosswordWords, ...crosswordWordsHard]) a,
      };
      final seen = <String>{};
      for (final (answer, clue) in [
        ...crosswordWordsExpert,
        ...crosswordWordsGod,
      ]) {
        expect(normalizeAnswer(answer), answer, reason: answer);
        expect(clue.trim(), isNotEmpty, reason: answer);
        expect(seen.add(answer), isTrue, reason: 'doppelt: $answer');
        expect(others.contains(answer), isFalse, reason: 'schon da: $answer');
      }
    });

    test('Jedes Wort hat einen Tipp, der die Lösung nicht verrät', () {
      String plain(String t) => t
          .toUpperCase()
          .replaceAll('Ä', 'AE')
          .replaceAll('Ö', 'OE')
          .replaceAll('Ü', 'UE')
          .replaceAll('ß', 'SS');
      for (final (answer, clue) in [
        ...crosswordWords,
        ...crosswordWordsHard,
        ...crosswordWordsExpert,
        ...crosswordWordsGod,
      ]) {
        final tip = crosswordTipFor(answer);
        expect(tip, isNotNull, reason: 'kein Tipp: $answer');
        expect(tip!.trim(), isNotEmpty, reason: answer);
        expect(tip, isNot(clue), reason: 'Tipp = Hinweis: $answer');
        final words = plain(tip).split(RegExp('[^A-Z]+'));
        // Kurze Lösungen nur als ganzes Wort prüfen (sonst stecken sie zufällig in anderen).
        final leaks = answer.length <= 4
            ? words.contains(answer)
            : plain(tip).replaceAll(RegExp('[^A-Z]'), '').contains(answer);
        expect(
          leaks,
          isFalse,
          reason: 'Tipp verrät die Lösung: $answer – $tip',
        );
      }
    });

    test(
      'Viele Rätsel hintereinander: Wörter wiederholen sich lange nicht',
      () {
        for (final (level, games, maxRepeats) in [
          (CrosswordLevel.medium, 30, 0),
          (CrosswordLevel.hard, 12, 0),
          (CrosswordLevel.expert, 8, 0),
          (CrosswordLevel.god, 8, 6),
        ]) {
          final history = <List<String>>[]; // neuestes Rätsel zuerst
          var repeats = 0;
          for (var g = 0; g < games; g++) {
            final recent = {for (final h in history) ...h}.toList();
            final words = generateForLevel(
              level,
              avoid: recent,
              random: Random(g * 7 + level.index),
            ).puzzle.words.map((w) => w.answer).toList();
            repeats += words.where(recent.contains).length;
            history.insert(0, words);
          }
          // ignore: avoid_print
          print('${level.label}: $games Rätsel, $repeats Wiederholungen');
          expect(repeats, lessThanOrEqualTo(maxRepeats), reason: level.label);
        }
      },
    );

    test('Am längsten nicht gesehene Wörter kommen zuerst wieder', () {
      // Alle Wörter schon gespielt: die ältesten (hinten in der Liste) werden bevorzugt.
      final bank = [
        for (final (a, c) in crosswordWords)
          if (a.length >= 4 && a.length <= 8) (a, c),
      ];
      final avoid = [for (final (a, _) in bank) a];
      final oldest = avoid.sublist(avoid.length ~/ 2).toSet();
      var old = 0, total = 0;
      for (var seed = 0; seed < 20; seed++) {
        final p = generateCrossword(
          bank: bank,
          maxSize: 11,
          target: 10,
          minLength: 4,
          maxLength: 8,
          avoid: avoid,
          random: Random(seed),
        );
        total += p.words.length;
        old += p.words.where((w) => oldest.contains(w.answer)).length;
      }
      expect(old / total, greaterThan(0.8));
    });

    test('Punkte und Sterne', () {
      final words = [
        for (var i = 0; i < 10; i++)
          CrosswordWord(
            id: 'w$i',
            clue: 'c',
            answer: 'ABCDE',
            x: 0,
            y: i,
            across: true,
          ),
      ];
      final perfect = crosswordScore(
        words: words,
        solved: 10,
        attempts: 10,
        hints: 0,
        pointsPerLetter: 10,
      );
      expect(perfect.points, 500);
      expect(perfect.stars, 3);
      final messy = crosswordScore(
        words: words,
        solved: 10,
        attempts: 13,
        hints: 1,
        pointsPerLetter: 10,
      );
      expect(messy.misses, 3);
      expect(messy.points, 500 - 3 * 20 - 1 * 30);
      expect(messy.stars, 2);
      final bad = crosswordScore(
        words: words,
        solved: 10,
        attempts: 40,
        hints: 0,
        pointsPerLetter: 10,
      );
      expect(bad.points, 0);
      expect(bad.stars, 1);
      // Tipps kosten 2× Punkte pro Buchstabe und zählen halb für die Sterne.
      final tipped = crosswordScore(
        words: words,
        solved: 10,
        attempts: 10,
        hints: 0,
        tips: 4,
        pointsPerLetter: 10,
      );
      expect(tipped.points, 500 - 4 * 20);
      expect(tipped.stars, 2);
    });

    test('Stufenleiter wird schwerer', () {
      final levels = CrosswordLevel.values;
      for (var i = 1; i < levels.length; i++) {
        expect(levels[i].maxSize, greaterThanOrEqualTo(levels[i - 1].maxSize));
        expect(
          levels[i].minLength,
          greaterThanOrEqualTo(levels[i - 1].minLength),
        );
        expect(levels[i].maxHints, greaterThan(levels[i - 1].maxHints));
        expect(
          levels[i].pointsPerLetter,
          greaterThan(levels[i - 1].pointsPerLetter),
        );
      }
      expect(CrosswordLevel.veryEasy.stars, 1);
      expect(CrosswordLevel.god.stars, 6);
    });

    test('Zuletzt gespielte Wörter werden gemieden', () {
      for (final level in CrosswordLevel.values) {
        for (var seed = 0; seed < 10; seed++) {
          final first = generateForLevel(level, random: Random(seed)).puzzle;
          final used = {for (final w in first.words) w.answer};
          final next = generateForLevel(
            level,
            avoid: used.toList(),
            random: Random(seed + 100),
          ).puzzle;
          // Ganz ohne Wiederholung geht es nur, wenn genug frische Wörter passen.
          final again = next.words.where((w) => used.contains(w.answer));
          expect(
            again.length,
            lessThanOrEqualTo(2),
            reason: '${level.label} seed $seed',
          );
        }
      }
    });

    for (final (level, minWords) in [
      (CrosswordLevel.veryEasy, 4),
      (CrosswordLevel.easy, 5),
      (CrosswordLevel.medium, 7),
      (CrosswordLevel.hard, 10),
      (CrosswordLevel.expert, 12),
      (CrosswordLevel.god, 12),
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
