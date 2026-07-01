import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/utils/lifestyle_math.dart';

void main() {
  test('dayKey formats yyyy-MM-dd zero-padded', () {
    expect(dayKey(DateTime(2026, 7, 1)), '2026-07-01');
    expect(dayKey(DateTime(2026, 12, 25)), '2026-12-25');
  });

  group('glasses <-> ml', () {
    test('glassesFor rounds to nearest glass', () {
      expect(glassesFor(1500, 250), 6);
      expect(glassesFor(1400, 250), 6); // 5.6 → 6
      expect(glassesFor(1100, 250), 4); // 4.4 → 4
      expect(glassesFor(0, 250), 0);
    });
    test('glassesFor guards bad glass size', () {
      expect(glassesFor(1000, 0), 0);
    });
    test('mlForGlasses multiplies', () {
      expect(mlForGlasses(8, 250), 2000);
    });
  });

  group('effectiveTarget', () {
    test('uses coach target when > 0, else fallback', () {
      expect(effectiveTarget(3000, 2500), 3000);
      expect(effectiveTarget(null, 2500), 2500);
      expect(effectiveTarget(0, 2500), 2500);
    });
  });

  group('adherenceFor', () {
    test('hitRate + average over logged days only', () {
      final a = adherenceFor([9000, 6000, null, 8000], 8000);
      expect(a.loggedDays, 3);
      expect(a.hitDays, 2);
      expect(a.hitRate, closeTo(2 / 3, 0.0001));
      expect(a.average, closeTo((9000 + 6000 + 8000) / 3, 0.0001));
    });
    test('no logged days → zeros', () {
      final a = adherenceFor([null, null], 8000);
      expect(a.loggedDays, 0);
      expect(a.hitDays, 0);
      expect(a.hitRate, 0);
      expect(a.average, 0);
    });
    test('non-positive target → nothing counts as a hit', () {
      final a = adherenceFor([100, 200], 0);
      expect(a.hitDays, 0);
      expect(a.average, 150);
    });
  });

  group('supplementRate', () {
    test('taken / prescribed', () {
      expect(supplementRate(3, 4), closeTo(0.75, 0.0001));
      expect(supplementRate(0, 0), 0);
      expect(supplementRate(5, 0), 0);
    });
  });
}
