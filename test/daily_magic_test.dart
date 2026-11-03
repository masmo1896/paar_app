import 'package:flutter_test/flutter_test.dart';
import 'package:paar_app/utils/daily_magic.dart';

void main() {
  test('Mondphase: bekannte Voll- und Neumonde', () {
    // Vollmond 5. November 2025 (14:19 MEZ), Neumond 20. Oktober 2025.
    expect(isFullMoon(DateTime(2025, 11, 5, 14)), isTrue);
    expect(moonName(DateTime(2025, 10, 21, 12)), 'Neumond');
    expect(moonIllumination(DateTime(2025, 11, 5, 14)), greaterThan(0.98));
    expect(moonIllumination(DateTime(2025, 10, 21, 12)), lessThan(0.02));
  });

  test('Fuchs: Feiertage und täglicher Wechsel', () {
    expect(foxOutfitFor(DateTime(2026, 12, 24)), FoxOutfit.santaHat);
    expect(foxOutfitFor(DateTime(2026, 12, 31)), FoxOutfit.partyHat);
    expect(foxOutfitFor(DateTime(2027, 2, 14)), FoxOutfit.flowers);
    for (var i = 0; i < 60; i++) {
      final a = DateTime(2026, 3, 1).add(Duration(days: i));
      final b = a.add(const Duration(days: 1));
      expect(foxOutfitFor(a), isNot(foxOutfitFor(b)), reason: '$a');
    }
  });

  test('Sternschnuppe: zwischen 17 und 23 Uhr, für beide gleich', () {
    for (var i = 0; i < 100; i++) {
      final d = DateTime(2026, 1, 1).add(Duration(days: i));
      final t = shootingStarTime(d, 'c1');
      expect(t.hour, inInclusiveRange(17, 22));
      expect(dayKey(t), dayKey(d));
      expect(shootingStarTime(d, 'c1'), t);
    }
  });

  test('Goldene Laterne: etwa 1 von 50', () {
    var gold = 0;
    for (var i = 0; i < 20000; i++) {
      if (isGoldenLantern('lantern$i')) gold++;
    }
    expect(gold, inInclusiveRange(300, 500));
  });

  test('Monatstag', () {
    final since = DateTime(2024, 3, 15);
    expect(monthiversary(since, DateTime(2026, 11, 15)), 32);
    expect(monthiversary(since, DateTime(2026, 11, 14)), isNull);
    expect(monthiversary(since, DateTime(2024, 3, 15)), isNull);
    // Der 31. fällt im November auf den 30.
    expect(monthiversary(DateTime(2024, 1, 31), DateTime(2026, 11, 30)), 34);
    expect(monthiversary(DateTime(2024, 1, 31), DateTime(2026, 2, 28)), 25);
  });

  test('Verstecktes Kanji: täglich anders, im sichtbaren Bereich', () {
    final spots = <String>{};
    for (var i = 0; i < 30; i++) {
      final d = DateTime(2026, 11, 1).add(Duration(days: i));
      final k = hiddenKanji(d, 'c1');
      expect(k.tab, inInclusiveRange(0, 4));
      expect(k.x, inInclusiveRange(0.08, 0.88));
      expect(k.y, inInclusiveRange(0.2, 0.75));
      expect(kanjiMeanings.containsKey(k.char), isTrue);
      spots.add('${k.tab}-${k.char}');
    }
    expect(spots.length, greaterThan(15));
  });
}
