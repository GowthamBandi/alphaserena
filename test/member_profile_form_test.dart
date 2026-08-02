import 'package:alphaserena/core/domain/member_profile_form.dart';
import 'package:flutter_test/flutter_test.dart';

/// The member profile editor's rule set. Every case here is a defect that
/// actually shipped, or the invariant that keeps it from coming back.
void main() {
  Map<String, dynamic> doc({
    Map<String, dynamic>? identity,
    Map<String, dynamic>? contact,
    Map<String, dynamic>? bodyMetrics,
    Map<String, dynamic>? location,
    Map<String, dynamic>? emergencyContact,
    Map<String, dynamic>? units,
  }) => {
    'profile': {
      'identity': ?identity,
      'contact': ?contact,
      'bodyMetrics': ?bodyMetrics,
      'location': ?location,
      'emergencyContact': ?emergencyContact,
      if (units != null) 'preferences': {'units': units},
    },
  };

  MemberProfileForm named([String first = 'Asha', String last = 'Rao']) =>
      MemberProfileForm(firstName: first, lastName: last);

  group('gender vocabulary', () {
    // THE crash. The wizard writes 'Other'; the editor's dropdown offered
    // Female/Male/Non-binary/Prefer-not-to-say, and a DropdownButtonFormField
    // whose value is absent from its items ASSERTS — so the screen did not
    // build at all for those members.
    test('adopts a stored value that is not one of the canonical options', () {
      expect(genderOptionsFor('Other'), contains('Other'));
      expect(genderOptionsFor('Non-binary'), contains('Non-binary'));
      expect(genderOptionsFor('genderqueer'), contains('genderqueer'));
    });

    test('every canonical option is renderable without duplication', () {
      for (final option in kGenderOptions) {
        final options = genderOptionsFor(option);
        expect(options.where((o) => o == option).length, 1);
      }
    });

    test('no stored value can ever be missing from the option list', () {
      for (final stored in ['Male', 'Female', 'Other', 'X', '']) {
        final form = MemberProfileForm.fromProfileDoc(
          doc(identity: {'displayName': 'A', 'gender': stored}),
        );
        if (form.gender == null) continue;
        expect(
          genderOptionsFor(form.gender),
          contains(form.gender),
          reason: 'stored gender "$stored" would crash the dropdown',
        );
      }
    });

    test('an unset gender reads as null, not an empty selection', () {
      expect(normalizeGender(null), isNull);
      expect(normalizeGender(''), isNull);
      expect(normalizeGender('  '), isNull);
      expect(normalizeGender(' Male '), 'Male');
    });
  });

  group('validation — only the name is required', () {
    // THE dead end. Height, weight, date of birth, phone AND a goal weight
    // nothing else in the app collects were all mandatory, so a member who took
    // the wizard at its word ("optional, you can skip this") met a permanently
    // disabled Save button with no error text saying why.
    test('a name alone is a valid profile', () {
      expect(named().errors, isEmpty);
      expect(named().isValid, isTrue);
    });

    test('every optional field may be blank', () {
      const form = MemberProfileForm(firstName: 'Asha');
      expect(form.errors, isEmpty);
    });

    test('a missing name is the one blocking error', () {
      expect(
        const MemberProfileForm().errors.keys,
        [ProfileFormField.displayName],
      );
      expect(
        const MemberProfileForm(firstName: 'A').errors,
        contains(ProfileFormField.displayName),
      );
    });

    test('goal weight alone never blocks a save', () {
      expect(named().copyWith(goalWeightText: '').errors, isEmpty);
    });
  });

  group('validation — bounds match the wizard, not "greater than zero"', () {
    test('an impossible height is rejected in cm', () {
      expect(
        named().copyWith(heightCmText: '3').errors,
        contains(ProfileFormField.height),
      );
      expect(
        named().copyWith(heightCmText: '900').errors,
        contains(ProfileFormField.height),
      );
      expect(named().copyWith(heightCmText: '172').errors, isEmpty);
    });

    test('an impossible weight is rejected', () {
      expect(
        named().copyWith(weightText: '9999').errors,
        contains(ProfileFormField.weight),
      );
      expect(
        named().copyWith(goalWeightText: '2').errors,
        contains(ProfileFormField.goalWeight),
      );
      expect(named().copyWith(weightText: '68').errors, isEmpty);
    });

    test('bounds apply in the member\'s own units', () {
      final lb = named().copyWith(weightUnit: 'lb', weightText: '150');
      expect(lb.errors, isEmpty);
      expect(lb.weightKg, closeTo(68.04, 0.01));

      final tooLight = named().copyWith(weightUnit: 'lb', weightText: '30');
      expect(tooLight.errors, contains(ProfileFormField.weight));
    });

    test('unparseable text is an error, never a silent null', () {
      final form = named().copyWith(heightCmText: '..');
      expect(form.heightCm, isNull);
      expect(form.errors, contains(ProfileFormField.height));
    });

    test('a phone is checked only when supplied', () {
      expect(named().copyWith(phone: '').errors, isEmpty);
      expect(
        named().copyWith(phone: '123').errors,
        contains(ProfileFormField.phone),
      );
      expect(named().copyWith(phone: '+91 98765 43210').errors, isEmpty);
    });

    test('an emergency contact is validated like a phone', () {
      expect(
        named().copyWith(emergencyPhone: '12').errors,
        contains(ProfileFormField.emergencyPhone),
      );
      expect(named().copyWith(emergencyPhone: '').errors, isEmpty);
    });

    test('an email is checked only when supplied', () {
      expect(named().copyWith(email: '').errors, isEmpty);
      expect(
        named().copyWith(email: 'nope').errors,
        contains(ProfileFormField.email),
      );
      expect(named().copyWith(email: 'a@b.co').errors, isEmpty);
    });

    test('a date of birth outside the accepted range is rejected', () {
      final now = DateTime.now();
      expect(
        named().copyWith(dob: DateTime(now.year - 2)).errors,
        contains(ProfileFormField.dob),
      );
      expect(
        named().copyWith(dob: DateTime(now.year - 200)).errors,
        contains(ProfileFormField.dob),
      );
      expect(named().copyWith(dob: DateTime(now.year - 30)).errors, isEmpty);
    });

    test('a future date of birth is rejected', () {
      final future = DateTime.now().add(const Duration(days: 400));
      expect(
        named().copyWith(dob: future).errors,
        contains(ProfileFormField.dob),
      );
    });
  });

  group('prefill reads from the section each value is WRITTEN to', () {
    test('emergency contact comes from its own section, not contact', () {
      final form = MemberProfileForm.fromProfileDoc(
        doc(
          identity: {'displayName': 'Asha Rao'},
          contact: {'phone': '+911111111111'},
          emergencyContact: {'phone': '+912222222222'},
        ),
      );
      expect(form.emergencyPhone, '+912222222222');
      expect(form.phone, '+911111111111');
    });

    test('splits a stored display name into first and last', () {
      final form = MemberProfileForm.fromProfileDoc(
        doc(identity: {'displayName': 'Asha  Devi Rao'}),
      );
      expect(form.firstName, 'Asha');
      expect(form.lastName, 'Devi Rao');
      expect(form.displayName, 'Asha Devi Rao');
    });

    test('accepts TrainerHQ\'s `name` spelling of the identity key', () {
      final form = MemberProfileForm.fromProfileDoc(
        doc(identity: {'name': 'Asha Rao'}),
      );
      expect(form.displayName, 'Asha Rao');
    });

    test('falls back to the coach record name and the sign-in phone', () {
      final form = MemberProfileForm.fromProfileDoc(
        null,
        fallbackName: 'Asha Rao',
        fallbackPhone: '+919876543210',
        fallbackEmail: 'a@b.co',
      );
      expect(form.displayName, 'Asha Rao');
      expect(form.phone, '+919876543210');
      expect(form.email, 'a@b.co');
      expect(form.errors, isEmpty);
    });

    test('renders stored metric values in the member\'s saved units', () {
      final form = MemberProfileForm.fromProfileDoc(
        doc(
          identity: {'displayName': 'Asha'},
          bodyMetrics: {'heightCm': 172.72, 'weightKg': 68.0},
          units: {'height': 'ftin', 'weight': 'lb'},
        ),
      );
      expect(form.heightUnit, 'ftin');
      expect(form.heightFtText, '5');
      expect(form.heightInText, '8');
      expect(form.weightUnit, 'lb');
      expect(form.weightText, '149.9');
      expect(form.weightKg, closeTo(68.0, 0.05));
    });

    test('an empty document produces an editable, invalid-until-named form', () {
      final form = MemberProfileForm.fromProfileDoc(null);
      expect(form.displayName, '');
      expect(form.errors.keys, [ProfileFormField.displayName]);
      expect(form.heightUnit, 'cm');
      expect(form.weightUnit, 'kg');
    });
  });

  group('unit switching is lossless', () {
    test('cm → ft/in → cm round-trips within a rounding inch', () {
      final start = named().copyWith(heightCmText: '172');
      final ftin = start.withHeightUnit('ftin');
      expect(ftin.heightFtText, '5');
      expect(ftin.heightInText, '8');
      final back = ftin.withHeightUnit('cm');
      expect(back.heightCm, closeTo(172, 1.5));
    });

    test('kg → lb converts both weight fields', () {
      final lb = named()
          .copyWith(weightText: '68', goalWeightText: '62')
          .withWeightUnit('lb');
      expect(double.parse(lb.weightText), closeTo(149.9, 0.2));
      expect(double.parse(lb.goalWeightText), closeTo(136.7, 0.2));
      expect(lb.weightKg, closeTo(68, 0.1));
    });

    test('switching units is not treated as an edit', () {
      final start = named().copyWith(weightText: '68');
      final flipped = start.withWeightUnit('lb').withWeightUnit('kg');
      expect(flipped.differsFrom(start), isFalse);
    });
  });

  group('change detection', () {
    test('reformatting the same value is not a change', () {
      final a = named().copyWith(weightText: '68');
      final b = named().copyWith(weightText: '68.0');
      expect(b.differsFrom(a), isFalse);
    });

    test('a differently formatted phone is not a change', () {
      final a = named().copyWith(phone: '+91 98765 43210');
      final b = named().copyWith(phone: '+919876543210');
      expect(b.differsFrom(a), isFalse);
    });

    test('a real edit is a change', () {
      final a = named();
      expect(a.copyWith(firstName: 'Meera').differsFrom(a), isTrue);
      expect(a.copyWith(photoUrl: 'https://x/y.jpg').differsFrom(a), isTrue);
      expect(a.copyWith(gender: 'Other').differsFrom(a), isTrue);
      expect(a.copyWith(dob: DateTime(1995, 4, 2)).differsFrom(a), isTrue);
    });

    test('clearing a stored value is a change', () {
      final stored = MemberProfileForm.fromProfileDoc(
        doc(
          identity: {'displayName': 'Asha'},
          location: {'city': 'Rajahmundry'},
        ),
      );
      expect(stored.copyWith(city: '').differsFrom(stored), isTrue);
    });
  });

  group('the write payload', () {
    test('refuses to build from an invalid form', () {
      expect(
        () => buildProfilePatch(const MemberProfileForm()),
        throwsStateError,
      );
      expect(
        () => buildProfilePatch(named().copyWith(heightCmText: '3')),
        throwsStateError,
      );
    });

    test('writes canonical metric regardless of the entry unit', () {
      final patch = buildProfilePatch(
        named().copyWith(
          weightUnit: 'lb',
          weightText: '150',
          heightUnit: 'ftin',
          heightFtText: '5',
          heightInText: '8',
        ),
      );
      final body =
          (patch['profile'] as Map)['bodyMetrics'] as Map<String, Object>;
      expect(body['weightKg'] as double, closeTo(68.04, 0.05));
      expect(body['heightCm'] as double, closeTo(172.72, 0.05));
    });

    // Blank USED to be skipped by every writer, so a member could never remove
    // a phone number, an emergency contact, an address or their photo: the
    // deletion was discarded and the stale value kept flowing to their coach.
    test('a cleared field is marked for deletion, not skipped', () {
      final patch = buildProfilePatch(named());
      final profile = patch['profile'] as Map;
      expect((profile['identity'] as Map)['photoUrl'], same(kClearField));
      expect((profile['identity'] as Map)['gender'], same(kClearField));
      expect((profile['identity'] as Map)['dob'], same(kClearField));
      expect((profile['contact'] as Map)['phone'], same(kClearField));
      expect((profile['contact'] as Map)['email'], same(kClearField));
      expect((profile['location'] as Map)['city'], same(kClearField));
      expect(profile['emergencyContact'], same(kClearField));
      expect(
        (profile['bodyMetrics'] as Map)['heightCm'],
        same(kClearField),
      );
    });

    test('a supplied field is written verbatim', () {
      final patch = buildProfilePatch(
        named().copyWith(
          phone: '+919876543210',
          email: 'asha@example.com',
          gender: 'Other',
          dob: DateTime(1995, 4, 2),
          city: 'Rajahmundry',
          emergencyPhone: '+911234567890',
          photoUrl: 'https://x/y.jpg',
        ),
      );
      final profile = patch['profile'] as Map;
      final identity = profile['identity'] as Map;
      expect(identity['displayName'], 'Asha Rao');
      expect(identity['gender'], 'Other');
      expect(identity['dob'], '1995-04-02');
      expect(identity['photoUrl'], 'https://x/y.jpg');
      expect((profile['contact'] as Map)['phone'], '+919876543210');
      expect((profile['location'] as Map)['city'], 'Rajahmundry');
      expect(
        (profile['emergencyContact'] as Map)['phone'],
        '+911234567890',
      );
    });

    // `emergencyContact` carries a visibility of `emergency`, which the coach
    // projection drops. `contact` is projected. Folding one into the other
    // would share a member's emergency number with their coach.
    test('the emergency contact never lands in the coach-visible section', () {
      final patch = buildProfilePatch(
        named().copyWith(emergencyPhone: '+911234567890'),
      );
      final contact = (patch['profile'] as Map)['contact'] as Map;
      expect(contact.values, isNot(contains('+911234567890')));
    });

    test('the transitional flat mirrors stay in step with the sections', () {
      final patch = buildProfilePatch(
        named().copyWith(
          heightCmText: '172',
          weightText: '68',
          email: 'asha@example.com',
        ),
      );
      final body = (patch['profile'] as Map)['bodyMetrics'] as Map;
      expect(patch['clientName'], 'Asha Rao');
      expect(patch['height'], body['heightCm']);
      expect(patch['weight'], body['weightKg']);
      expect(patch['email'], 'asha@example.com');
    });

    test('only sections this editor owns are present', () {
      final profile = buildProfilePatch(named())['profile'] as Map;
      // medical / documents / goals / fitness / privacy belong to other
      // surfaces; a merge-write must never mention them.
      expect(
        profile.keys.toSet(),
        {
          'identity',
          'contact',
          'bodyMetrics',
          'location',
          'emergencyContact',
          'preferences',
        },
      );
    });

    test('the date of birth is written in the shape TrainerHQ parses', () {
      expect(formatDob(DateTime(1995, 4, 2)), '1995-04-02');
      expect(formatDob(DateTime(2000, 12, 31)), '2000-12-31');
      expect(DateTime.tryParse(formatDob(DateTime(1988, 1, 9))), isNotNull);
    });
  });

  group('round trip', () {
    test('save then reopen yields an identical, unchanged form', () {
      final original = named().copyWith(
        phone: '+919876543210',
        email: 'asha@example.com',
        gender: 'Other',
        dob: DateTime(1995, 4, 2),
        heightCmText: '172',
        weightText: '68',
        goalWeightText: '62',
        emergencyPhone: '+911234567890',
        address: '4-1-2 Main Rd',
        city: 'Rajahmundry',
        state: 'Andhra Pradesh',
        country: 'India',
        photoUrl: 'https://x/y.jpg',
      );

      // What Firestore would hold after the patch is merged in.
      final patch = buildProfilePatch(original);
      final stored = {
        'profile': (patch['profile'] as Map).map(
          (k, v) => MapEntry(
            k.toString(),
            v is Map
                ? Map<String, dynamic>.fromEntries(
                    v.entries
                        .where((e) => !identical(e.value, kClearField))
                        .map((e) => MapEntry(e.key.toString(), e.value)),
                  )
                : v,
          ),
        ),
      };

      final reopened = MemberProfileForm.fromProfileDoc(stored);
      expect(reopened.differsFrom(original), isFalse);
      expect(reopened.displayName, original.displayName);
      expect(reopened.gender, 'Other');
      expect(reopened.dob, DateTime(1995, 4, 2));
      expect(reopened.emergencyPhone, '+911234567890');
      expect(reopened.city, 'Rajahmundry');
      expect(reopened.photoUrl, 'https://x/y.jpg');
    });
  });
}
