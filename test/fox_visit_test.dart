import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paar_app/widgets/fox_visit.dart';

void main() {
  testWidgets('Fuchs-Besuch: jeder Moment an jedem Rand zeichnet fehlerfrei', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    for (var edge = 0; edge < 3; edge++) {
      for (var i = 0; i <= 50; i++) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: FoxVisitFrame(
              edge: edge,
              along: 0.2 + 0.03 * i,
              tilt: (i % 5 - 2) * 0.1,
              progress: i / 50,
            ),
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'Rand $edge, t=${i / 50}',
        );
      }
    }
  });
}
