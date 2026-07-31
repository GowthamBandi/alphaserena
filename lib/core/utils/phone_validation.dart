/// Pure phone-number validation shared by the auth screens — kept out of
/// widget state so it is unit-testable and consistent everywhere.
class PhoneValidation {
  PhoneValidation._();

  /// Validates [digits] (numbers only, no country code) for the country with
  /// dial code [phoneCode]. Returns a human error message, or null when valid.
  ///
  /// India (+91) mobiles are exactly 10 digits starting 6–9; every other
  /// country gets a sane generic length check (E.164 caps national numbers
  /// at 15 digits; nothing real is shorter than 6).
  static String? validate(String digits, {required String phoneCode}) {
    if (phoneCode == '91') {
      if (digits.length != 10 || !RegExp(r'^[6-9]').hasMatch(digits)) {
        return 'Enter a valid 10-digit Indian mobile number.';
      }
      return null;
    }
    if (digits.length < 6 || digits.length > 15) {
      return 'Enter a valid phone number.';
    }
    return null;
  }
}
