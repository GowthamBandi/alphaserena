import 'package:alphaserena/core/utils/body_units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BodyUnits conversions', () {
    test('172 cm → 5 ft 8 in', () {
      expect(BodyUnits.cmToFtIn(172), (5, 8));
    });

    test('inch carry never produces 12 inches', () {
      // 182.9 cm ≈ 72.0 in → 6 ft 0 in (not 5 ft 12).
      final (ft, inches) = BodyUnits.cmToFtIn(182.9);
      expect(ft, 6);
      expect(inches, 0);
    });

    test('ft/in → cm round-trips within one inch', () {
      final cm = BodyUnits.ftInToCm(5, 8);
      expect(cm, closeTo(172.7, 0.1));
      expect(BodyUnits.cmToFtIn(cm), (5, 8));
    });

    test('68 kg → 149.9 lb and back', () {
      expect(BodyUnits.trim(BodyUnits.kgToLb(68)), '149.9');
      expect(BodyUnits.lbToKg(BodyUnits.kgToLb(68)), closeTo(68, 0.001));
    });
  });

  group('BodyUnits validation', () {
    test('height bounds', () {
      expect(BodyUnits.isValidHeightCm(99.9), isFalse);
      expect(BodyUnits.isValidHeightCm(100), isTrue);
      expect(BodyUnits.isValidHeightCm(250), isTrue);
      expect(BodyUnits.isValidHeightCm(250.1), isFalse);
    });

    test('weight bounds', () {
      expect(BodyUnits.isValidWeightKg(19.9), isFalse);
      expect(BodyUnits.isValidWeightKg(20), isTrue);
      expect(BodyUnits.isValidWeightKg(400), isTrue);
      expect(BodyUnits.isValidWeightKg(401), isFalse);
    });

    test('imperial extremes map inside the metric bounds', () {
      // 3 ft 4 in ≈ 101.6 cm and 8 ft 2 in ≈ 248.9 cm — both valid.
      expect(BodyUnits.isValidHeightCm(BodyUnits.ftInToCm(3, 4)), isTrue);
      expect(BodyUnits.isValidHeightCm(BodyUnits.ftInToCm(8, 2)), isTrue);
      // 44 lb ≈ 20 kg, 880 lb ≈ 399.2 kg.
      expect(BodyUnits.isValidWeightKg(BodyUnits.lbToKg(44.1)), isTrue);
      expect(BodyUnits.isValidWeightKg(BodyUnits.lbToKg(880)), isTrue);
    });

    test('trim formatting', () {
      expect(BodyUnits.trim(68.0), '68');
      expect(BodyUnits.trim(149.91), '149.9');
    });
  });
}
