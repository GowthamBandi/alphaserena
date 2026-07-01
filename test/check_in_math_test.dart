import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/utils/check_in_math.dart';

void main() {
  group('hasSubmittableContent', () {
    test('empty everything → false', () {
      expect(hasSubmittableContent(note: '  ', ratings: {}, weightKg: null),
          isFalse);
    });
    test('any one of note / rating / weight → true', () {
      expect(hasSubmittableContent(note: 'hi', ratings: {}, weightKg: null),
          isTrue);
      expect(
          hasSubmittableContent(note: '', ratings: {'energy': 4}, weightKg: null),
          isTrue);
      expect(hasSubmittableContent(note: '', ratings: {}, weightKg: 74.0), isTrue);
    });
  });

  test('periodLabel formats "Week of D MMM"', () {
    expect(periodLabel(DateTime(2026, 6, 29)), 'Week of 29 Jun');
    expect(periodLabel(DateTime(2026, 1, 3)), 'Week of 3 Jan');
  });
}
