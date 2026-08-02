/// THE member profile EDITOR domain — vocabulary, validation and the write
/// payload for `clientProfiles/{uid}.profile`, in one pure, testable place.
///
/// Why this exists: the app shipped TWO editors for the same document —
/// `IdentitySetupScreen` (the onboarding wizard) and `EditProfileScreen` — each
/// with its own gender vocabulary, its own bounds, and its own idea of which
/// fields are required. They disagreed, and the disagreements were not
/// cosmetic:
///
///  • Identity Setup wrote `gender: 'Other'`; Edit Profile's dropdown offered
///    `Female / Male / Non-binary / Prefer not to say`. A `DropdownButtonFormField`
///    whose value is absent from its items ASSERTS, so Edit Profile did not
///    build at all for those members — the screen was a red error page.
///  • Identity Setup called height, weight, gender and date of birth OPTIONAL
///    ("You can skip this"). Edit Profile made all of them — plus a goal weight
///    that no other surface in the app has ever collected — mandatory for its
///    Save button to enable. Every member who took Identity Setup at its word
///    arrived at a permanently disabled Save button with no error text saying
///    why.
///  • Identity Setup rejected an impossible height (`BodyUnits.isValidHeightCm`);
///    Edit Profile accepted any number greater than zero, so 3 cm and 9 999 kg
///    could be projected to the member's coach.
///
/// One document must have one rule set. Everything either editor needs to
/// decide — what a field may contain, what a blank field MEANS, and what to
/// write — is decided here and nowhere else.
///
/// Pure by construction: no Flutter, no Firebase. A cleared field is marked
/// with [kClearField] and the persistence layer translates that into the
/// backend's delete sentinel, so this file can be unit-tested with no emulator
/// and no plugin registrant.
library;

import '../utils/body_units.dart';

/// The canonical gender vocabulary. These are the values Identity Setup has
/// always written and therefore the values already in production documents;
/// TrainerHQ reads them through `identity['gender']` and renders them verbatim,
/// so the list is a data contract, not a UI choice.
const List<String> kGenderOptions = ['Male', 'Female', 'Other'];

/// The option list to render for a member whose stored gender is [stored].
///
/// Any stored value not in [kGenderOptions] is ADOPTED into the returned list
/// rather than dropped. A dropdown can therefore never be handed a value it has
/// no item for — which is the assertion that made Edit Profile un-openable —
/// whatever a legacy build, a future build, or TrainerHQ happens to have
/// written. Unknown values sort last so the canonical three stay in place.
List<String> genderOptionsFor(String? stored) {
  final value = (stored ?? '').trim();
  if (value.isEmpty || kGenderOptions.contains(value)) return kGenderOptions;
  return [...kGenderOptions, value];
}

/// A stored gender normalised for a form: `null` when nothing was ever set, so
/// the field reads as "not answered" rather than as an empty selection.
String? normalizeGender(Object? raw) {
  final value = (raw ?? '').toString().trim();
  return value.isEmpty ? null : value;
}

/// Marks a member-owned field the member has CLEARED.
///
/// Blank means two completely different things depending on who is writing.
/// The onboarding wizard does not collect an address, so a blank address there
/// means "not supplied — leave whatever is stored alone". The full editor DOES
/// show the address, so a blank one there means "I deleted this". Conflating
/// the two is why a member could never remove a phone number, an emergency
/// contact or an address once saved: every writer skipped empty values.
///
/// The domain marks the second case with this sentinel; `MemberIdentityService`
/// translates it into `FieldValue.delete()`. Keeping it a sentinel rather than a
/// Firestore type is what lets the payload be asserted in a plain unit test.
const Object kClearField = _ClearField();

class _ClearField {
  const _ClearField();
  @override
  String toString() => '<clear>';
}

/// Field keys for [MemberProfileForm.errors]. Screens bind their inputs to
/// these so an error can never be attached to the wrong field.
abstract final class ProfileFormField {
  static const displayName = 'displayName';
  static const email = 'email';
  static const phone = 'phone';
  static const dob = 'dob';
  static const height = 'height';
  static const weight = 'weight';
  static const goalWeight = 'goalWeight';
  static const emergencyPhone = 'emergencyPhone';
}

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Digits only — a member may type `+91 98765 43210` or `(555) 010-1234`.
String digitsOf(String value) => value.replaceAll(RegExp(r'\D'), '');

bool _validPhone(String value) {
  final digits = digitsOf(value);
  return digits.length >= 7 && digits.length <= 15;
}

/// The age range the platform accepts, matching the onboarding date picker's
/// own bounds. A future date of birth, or one implying an age outside this
/// range, is a typo — and it reaches the coach's roster header through the
/// projection, so it is rejected rather than rendered.
const int kMinAgeYears = 10;
const int kMaxAgeYears = 100;

int ageFromDob(DateTime dob, {DateTime? now}) {
  final today = now ?? DateTime.now();
  var years = today.year - dob.year;
  final hadBirthday = today.month > dob.month ||
      (today.month == dob.month && today.day >= dob.day);
  if (!hadBirthday) years -= 1;
  return years;
}

String _two(int v) => v < 10 ? '0$v' : '$v';

/// `yyyy-MM-dd` — the shape TrainerHQ's `client_identity.dart` parses.
/// Formatted here rather than with `intl` so the wire format is fixed by the
/// domain and cannot drift with a screen's locale.
String formatDob(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// An edit in progress over the member's canonical profile.
///
/// Text stays TEXT: the form holds exactly what the member typed, so a
/// half-typed `1.` is preserved across rebuilds and a parse failure is reported
/// as an error instead of silently becoming null. Canonical metric values are
/// derived on demand ([heightCm] / [weightKg] / [goalWeightKg]).
class MemberProfileForm {
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String? gender;
  final DateTime? dob;

  /// `'cm'` | `'ftin'` — display/entry only. Storage is always centimetres.
  final String heightUnit;
  final String heightCmText;
  final String heightFtText;
  final String heightInText;

  /// `'kg'` | `'lb'` — display/entry only. Storage is always kilograms.
  final String weightUnit;
  final String weightText;
  final String goalWeightText;

  final String emergencyPhone;
  final String address;
  final String city;
  final String state;
  final String country;

  /// The avatar currently attached to the draft: an already-uploaded URL, or
  /// `''` when the member has removed it. Uploading happens outside the form
  /// (it is I/O); the form only records the outcome.
  final String photoUrl;

  const MemberProfileForm({
    this.firstName = '',
    this.lastName = '',
    this.email = '',
    this.phone = '',
    this.gender,
    this.dob,
    this.heightUnit = 'cm',
    this.heightCmText = '',
    this.heightFtText = '',
    this.heightInText = '',
    this.weightUnit = 'kg',
    this.weightText = '',
    this.goalWeightText = '',
    this.emergencyPhone = '',
    this.address = '',
    this.city = '',
    this.state = '',
    this.country = '',
    this.photoUrl = '',
  });

  /// Prefills from the RAW `clientProfiles/{uid}` document.
  ///
  /// Reads each value from the section it is WRITTEN to — the bug that left the
  /// emergency contact permanently blank on reopen was reading it from
  /// `contact` while the service wrote it to `emergencyContact`.
  ///
  /// The fallbacks are for the fields a member can hold before they have ever
  /// opened this form: a name the coach typed on their `clients` record, and
  /// the phone number they signed in with.
  factory MemberProfileForm.fromProfileDoc(
    Map<String, dynamic>? doc, {
    String fallbackName = '',
    String fallbackEmail = '',
    String fallbackPhone = '',
  }) {
    Map<String, dynamic> section(String key) {
      final profile = doc?['profile'];
      if (profile is Map) {
        final s = profile[key];
        if (s is Map) return Map<String, dynamic>.from(s);
      }
      return const <String, dynamic>{};
    }

    String text(Map<String, dynamic> m, String key) =>
        (m[key] ?? '').toString().trim();

    final identity = section('identity');
    final contact = section('contact');
    final body = section('bodyMetrics');
    final location = section('location');
    final emergency = section('emergencyContact');
    final units = section('preferences')['units'];
    final unitMap = units is Map ? Map<String, dynamic>.from(units) : const {};

    final name = () {
      final canonical = text(identity, 'displayName');
      if (canonical.isNotEmpty) return canonical;
      // TrainerHQ's own profile adapter spells this key `name`; accepting both
      // keeps the two apps interoperable without either changing the schema.
      final alt = text(identity, 'name');
      if (alt.isNotEmpty) return alt;
      return fallbackName.trim();
    }();
    final parts = name.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();

    final heightUnit = unitMap['height'] == 'ftin' ? 'ftin' : 'cm';
    final weightUnit = unitMap['weight'] == 'lb' ? 'lb' : 'kg';

    final storedHeight = body['heightCm'];
    var cmText = '';
    var ftText = '';
    var inText = '';
    if (storedHeight is num) {
      if (heightUnit == 'ftin') {
        final (f, i) = BodyUnits.cmToFtIn(storedHeight.toDouble());
        ftText = '$f';
        inText = '$i';
      } else {
        cmText = BodyUnits.trim(storedHeight.toDouble());
      }
    }

    String weightIn(Object? stored) {
      if (stored is! num) return '';
      final kg = stored.toDouble();
      return BodyUnits.trim(
        weightUnit == 'lb' ? BodyUnits.kgToLb(kg) : kg,
      );
    }

    final email = text(contact, 'email').isNotEmpty
        ? text(contact, 'email')
        : fallbackEmail.trim();
    final phone = text(contact, 'phone').isNotEmpty
        ? text(contact, 'phone')
        : fallbackPhone.trim();

    return MemberProfileForm(
      firstName: parts.isEmpty ? '' : parts.first,
      lastName: parts.length > 1 ? parts.sublist(1).join(' ') : '',
      email: email,
      phone: phone,
      gender: normalizeGender(identity['gender']),
      dob: DateTime.tryParse(text(identity, 'dob')),
      heightUnit: heightUnit,
      heightCmText: cmText,
      heightFtText: ftText,
      heightInText: inText,
      weightUnit: weightUnit,
      weightText: weightIn(body['weightKg']),
      goalWeightText: weightIn(body['goalWeightKg']),
      emergencyPhone: text(emergency, 'phone'),
      address: text(location, 'address'),
      city: text(location, 'city'),
      state: text(location, 'state'),
      country: text(location, 'country'),
      photoUrl: text(identity, 'photoUrl'),
    );
  }

  MemberProfileForm copyWith({
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    Object? gender = _unset,
    Object? dob = _unset,
    String? heightUnit,
    String? heightCmText,
    String? heightFtText,
    String? heightInText,
    String? weightUnit,
    String? weightText,
    String? goalWeightText,
    String? emergencyPhone,
    String? address,
    String? city,
    String? state,
    String? country,
    String? photoUrl,
  }) {
    return MemberProfileForm(
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      gender: identical(gender, _unset) ? this.gender : gender as String?,
      dob: identical(dob, _unset) ? this.dob : dob as DateTime?,
      heightUnit: heightUnit ?? this.heightUnit,
      heightCmText: heightCmText ?? this.heightCmText,
      heightFtText: heightFtText ?? this.heightFtText,
      heightInText: heightInText ?? this.heightInText,
      weightUnit: weightUnit ?? this.weightUnit,
      weightText: weightText ?? this.weightText,
      goalWeightText: goalWeightText ?? this.goalWeightText,
      emergencyPhone: emergencyPhone ?? this.emergencyPhone,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }

  static const Object _unset = Object();

  /// Switches height units, CONVERTING whatever is already typed so a member
  /// never has to re-enter a value to change how it is displayed.
  MemberProfileForm withHeightUnit(String unit) {
    if (unit == heightUnit) return this;
    if (unit == 'ftin') {
      final cm = double.tryParse(heightCmText.trim());
      if (cm == null) return copyWith(heightUnit: unit);
      final (f, i) = BodyUnits.cmToFtIn(cm);
      return copyWith(heightUnit: unit, heightFtText: '$f', heightInText: '$i');
    }
    final f = int.tryParse(heightFtText.trim());
    final i = int.tryParse(heightInText.trim());
    if (f == null && i == null) return copyWith(heightUnit: unit);
    return copyWith(
      heightUnit: unit,
      heightCmText: BodyUnits.trim(BodyUnits.ftInToCm(f ?? 0, i ?? 0)),
    );
  }

  MemberProfileForm withWeightUnit(String unit) {
    if (unit == weightUnit) return this;
    String convert(String text) {
      final v = double.tryParse(text.trim());
      if (v == null) return text;
      return BodyUnits.trim(
        unit == 'lb' ? BodyUnits.kgToLb(v) : BodyUnits.lbToKg(v),
      );
    }

    return copyWith(
      weightUnit: unit,
      weightText: convert(weightText),
      goalWeightText: convert(goalWeightText),
    );
  }

  String get displayName =>
      [firstName.trim(), lastName.trim()].where((s) => s.isNotEmpty).join(' ');

  bool get heightBlank => heightUnit == 'ftin'
      ? heightFtText.trim().isEmpty && heightInText.trim().isEmpty
      : heightCmText.trim().isEmpty;

  /// Canonical centimetres, or null when blank OR unparseable. Callers must
  /// consult [errors] to tell those apart — a null from a typo must never be
  /// written as "cleared".
  double? get heightCm {
    if (heightBlank) return null;
    if (heightUnit == 'ftin') {
      final f = int.tryParse(heightFtText.trim());
      final i = int.tryParse(heightInText.trim());
      if (f == null && i == null) return null;
      if (heightFtText.trim().isNotEmpty && f == null) return null;
      if (heightInText.trim().isNotEmpty && i == null) return null;
      return BodyUnits.ftInToCm(f ?? 0, i ?? 0);
    }
    return double.tryParse(heightCmText.trim());
  }

  double? _kg(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return null;
    return weightUnit == 'lb' ? BodyUnits.lbToKg(v) : v;
  }

  double? get weightKg => _kg(weightText);
  double? get goalWeightKg => _kg(goalWeightText);

  /// THE validation rule set for this document.
  ///
  /// Only the display name is required — exactly what the onboarding wizard
  /// tells the member, and what the section registry says (`identity` is the
  /// one `required` member-owned section). Every other field is optional and,
  /// when supplied, must be plausible. Making optional fields mandatory here is
  /// what silently disabled Save for every member who had skipped them.
  Map<String, String> get errors {
    final out = <String, String>{};

    if (displayName.length < 2) {
      out[ProfileFormField.displayName] =
          'Enter your name so your coach knows who they are training.';
    }

    final mail = email.trim();
    if (mail.isNotEmpty && !_emailPattern.hasMatch(mail)) {
      out[ProfileFormField.email] = 'That email does not look right.';
    }

    if (phone.trim().isNotEmpty && !_validPhone(phone)) {
      out[ProfileFormField.phone] = 'Enter a valid phone number (7–15 digits).';
    }

    if (emergencyPhone.trim().isNotEmpty && !_validPhone(emergencyPhone)) {
      out[ProfileFormField.emergencyPhone] =
          'Enter a valid phone number (7–15 digits).';
    }

    final birthday = dob;
    if (birthday != null) {
      final age = ageFromDob(birthday);
      if (age < kMinAgeYears || age > kMaxAgeYears) {
        out[ProfileFormField.dob] =
            'Check your date of birth — it reads as $age years old.';
      }
    }

    if (!heightBlank) {
      final cm = heightCm;
      if (cm == null || !BodyUnits.isValidHeightCm(cm)) {
        out[ProfileFormField.height] = heightUnit == 'ftin'
            ? 'Height must be between 3 ft 4 in and 8 ft 2 in.'
            : 'Height must be between ${BodyUnits.minHeightCm.round()} and '
                '${BodyUnits.maxHeightCm.round()} cm.';
      }
    }

    String? weightError(String text, double? kg) {
      if (text.trim().isEmpty) return null;
      if (kg == null || !BodyUnits.isValidWeightKg(kg)) {
        return weightUnit == 'lb'
            ? 'Weight must be between 44 and 880 lb.'
            : 'Weight must be between ${BodyUnits.minWeightKg.round()} and '
                '${BodyUnits.maxWeightKg.round()} kg.';
      }
      return null;
    }

    final w = weightError(weightText, weightKg);
    if (w != null) out[ProfileFormField.weight] = w;
    final g = weightError(goalWeightText, goalWeightKg);
    if (g != null) out[ProfileFormField.goalWeight] = g;

    return out;
  }

  bool get isValid => errors.isEmpty;

  /// Whether anything the member can author differs from [other] — the unsaved
  /// changes guard, and the duplicate-save guard. Compared on CANONICAL values
  /// so re-formatting (`68` → `68.0`) or flipping units back and forth is
  /// correctly seen as no change at all.
  bool differsFrom(MemberProfileForm other) {
    bool sameNum(double? a, double? b) {
      if (a == null || b == null) return a == b;
      return (a - b).abs() < 0.05;
    }

    return displayName != other.displayName ||
        email.trim() != other.email.trim() ||
        digitsOf(phone) != digitsOf(other.phone) ||
        (gender ?? '') != (other.gender ?? '') ||
        dob != other.dob ||
        !sameNum(heightCm, other.heightCm) ||
        !sameNum(weightKg, other.weightKg) ||
        !sameNum(goalWeightKg, other.goalWeightKg) ||
        digitsOf(emergencyPhone) != digitsOf(other.emergencyPhone) ||
        address.trim() != other.address.trim() ||
        city.trim() != other.city.trim() ||
        state.trim() != other.state.trim() ||
        country.trim() != other.country.trim() ||
        photoUrl != other.photoUrl ||
        heightUnit != other.heightUnit ||
        weightUnit != other.weightUnit;
  }
}

/// The `clientProfiles/{uid}` patch for a COMPLETE edit of the member's
/// profile — every member-owned field the full editor shows, with blanks
/// meaning DELETE ([kClearField]).
///
/// Written with `SetOptions(merge: true)`, so sections the editor does not own
/// (`medical`, `goals`, `fitness`, the coach's own sections on `clients`) are
/// untouched. The legacy flat mirrors (`clientName` / `height` / `weight`) are
/// dual-written for the UMHIPP P2→P5 transition exactly as the wizard does.
///
/// Throws [StateError] when the form is invalid — a patch must never be built
/// from a draft that has not passed [MemberProfileForm.errors], or a parse
/// failure would be persisted as a deletion.
Map<String, dynamic> buildProfilePatch(MemberProfileForm form) {
  if (!form.isValid) {
    throw StateError('buildProfilePatch called on an invalid form');
  }

  Object textOrClear(String value) =>
      value.trim().isEmpty ? kClearField : value.trim();
  Object numOrClear(String text, double? canonical) =>
      text.trim().isEmpty ? kClearField : canonical!;

  final identity = <String, Object>{
    'displayName': form.displayName,
    'photoUrl': form.photoUrl.isEmpty ? kClearField : form.photoUrl,
    'gender': (form.gender ?? '').isEmpty ? kClearField : form.gender!,
    'dob': form.dob == null ? kClearField : formatDob(form.dob!),
  };

  final contact = <String, Object>{
    'phone': textOrClear(form.phone),
    'email': textOrClear(form.email),
  };

  final bodyMetrics = <String, Object>{
    'heightCm': numOrClear(
      form.heightUnit == 'ftin'
          ? '${form.heightFtText}${form.heightInText}'
          : form.heightCmText,
      form.heightCm,
    ),
    'weightKg': numOrClear(form.weightText, form.weightKg),
    'goalWeightKg': numOrClear(form.goalWeightText, form.goalWeightKg),
  };

  final location = <String, Object>{
    'address': textOrClear(form.address),
    'city': textOrClear(form.city),
    'state': textOrClear(form.state),
    'country': textOrClear(form.country),
  };

  // Its OWN section, never a `contact` field: the section registry gives
  // `emergencyContact` a visibility of `emergency`, which the coach projection
  // drops. Folding it into `contact` — which IS projected — would share a
  // member's emergency number with their coach against the platform's own
  // privacy model.
  final emergency = form.emergencyPhone.trim().isEmpty
      ? kClearField
      : <String, Object>{'phone': form.emergencyPhone.trim()};

  return <String, dynamic>{
    'profile': <String, dynamic>{
      'identity': identity,
      'contact': contact,
      'bodyMetrics': bodyMetrics,
      'location': location,
      'emergencyContact': emergency,
      'preferences': <String, dynamic>{
        'units': <String, Object>{
          'height': form.heightUnit,
          'weight': form.weightUnit,
        },
      },
    },
    // Transitional dual-write (removed in P5): today's consumers read these.
    'clientName': form.displayName,
    'email': textOrClear(form.email),
    'height': bodyMetrics['heightCm']!,
    'weight': bodyMetrics['weightKg']!,
  };
}
