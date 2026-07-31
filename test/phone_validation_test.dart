import 'package:alphaserena/core/utils/phone_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PhoneValidation — India (+91)', () {
    test('accepts a valid 10-digit mobile starting 6-9', () {
      expect(PhoneValidation.validate('9876543210', phoneCode: '91'), isNull);
      expect(PhoneValidation.validate('6000000000', phoneCode: '91'), isNull);
    });

    test('rejects wrong length', () {
      expect(PhoneValidation.validate('98765', phoneCode: '91'), isNotNull);
      expect(
        PhoneValidation.validate('98765432101', phoneCode: '91'),
        isNotNull,
      );
    });

    test('rejects invalid leading digit', () {
      expect(
        PhoneValidation.validate('1234567890', phoneCode: '91'),
        isNotNull,
      );
      expect(
        PhoneValidation.validate('5876543210', phoneCode: '91'),
        isNotNull,
      );
    });
  });

  group('PhoneValidation — other countries', () {
    test('accepts typical US number (10 digits)', () {
      expect(PhoneValidation.validate('4155552671', phoneCode: '1'), isNull);
    });

    test('accepts typical UK number', () {
      expect(PhoneValidation.validate('7911123456', phoneCode: '44'), isNull);
    });

    test('rejects too short and beyond the E.164 cap', () {
      expect(PhoneValidation.validate('12345', phoneCode: '1'), isNotNull);
      expect(
        PhoneValidation.validate('1234567890123456', phoneCode: '44'),
        isNotNull,
      );
    });

    test('rejects empty input', () {
      expect(PhoneValidation.validate('', phoneCode: '1'), isNotNull);
    });
  });
}
