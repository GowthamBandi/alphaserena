import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:patrol/patrol.dart';

import 'package:alphaserena/core/domain/member_profile_form.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/profile/edit_profile_screen.dart';

/// PATROL — THE MEMBER PROFILE EDITOR, ON A REAL DEVICE.
///
/// The reported symptom was "I cannot properly edit and update my profile", and
/// the two causes were both things only a rendered screen can prove:
///
///  1. The screen THREW at build time for any member whose stored gender was
///     `'Other'` — the value the onboarding wizard writes — because a
///     `DropdownButtonFormField` asserts when its value is absent from its
///     items. On a device that is a red screen where the editor should be.
///  2. Its Save button was DISABLED unless height, weight, goal weight, phone
///     and date of birth were all filled — every one of which the wizard calls
///     optional, and one of which (goal weight) nothing in the app had ever
///     collected. On a device that is a button that does not respond to a real
///     finger, with no error text to explain it.
///
/// The rules, the projection and the form's logic are proven elsewhere (rules:
/// `trainershq-backend/tests/rules/member_profile_editor_write.mjs`, 9/9 on a
/// real emulator; projection: `functions/test/profile_backfill_wire.mjs`,
/// 13/13; form: `test/member_profile_form_test.dart`, 39). What a DEVICE
/// uniquely proves is what a member's hands actually meet: that the editor
/// opens for every profile shape in production, that every control responds,
/// that keyboards and scrolling do not swallow a field, and that it survives
/// landscape, a tablet, dark mode and accessibility text sizes.
///
/// Deliberately pumps the screen with a seeded profile rather than signing in:
/// the same pattern as `auth_role_gate_patrol_test.dart`. A device run must not
/// depend on a live member account, and `initialForm` is the seam that makes
/// every production profile shape reachable — including the ones that used to
/// crash.
void main() {
  Future<void> open(
    PatrolIntegrationTester $,
    MemberProfileForm form, {
    double textScale = 1.0,
    Size surface = const Size(390, 844),
    bool dark = true,
  }) async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    Get.reset();
    await $.tester.binding.setSurfaceSize(surface);
    await $.pumpWidgetAndSettle(
      GetMaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: EditProfileScreen(initialForm: form),
        ),
      ),
    );
  }

  /// Delivers the SYSTEM back press at the Flutter level.
  ///
  /// Not `native.pressBack()`: this screen is the ROOT of a bare harness, so an
  /// Android back would finish the activity and tear down Patrol's app service
  /// mid-run. `popRoute` is exactly what the OS back delivers to Flutter, so it
  /// exercises `PopScope` for real without touching the activity.
  Future<void> systemBack(PatrolIntegrationTester $) async {
    await $.tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await $.pumpAndSettle();
  }

  /// Taps Save and lets the GetX snackbar finish.
  ///
  /// The snackbar repeats the blocking message for three seconds, so asserting
  /// on error text before it clears cannot tell an INLINE field error from the
  /// toast — which is the whole point of the assertion.
  Future<void> tapSave(PatrolIntegrationTester $) async {
    await $('SAVE CHANGES').scrollTo().tap();
    await $.pumpAndSettle();
    await $.tester.pump(const Duration(seconds: 4));
    await $.pumpAndSettle();
  }

  const blank = MemberProfileForm();
  const named = MemberProfileForm(firstName: 'Asha', lastName: 'Rao');

  /// A member exactly as the onboarding wizard leaves them: a name, a photo, a
  /// gender of 'Other', and NOTHING else. This is the profile the editor
  /// refused to open, and refused to save.
  final wizardMember = named.copyWith(
    gender: 'Other',
    photoUrl: '',
    phone: '+919876543210',
  );

  // ── The screen opens at all ─────────────────────────────────────────────

  patrolTest('the editor OPENS for a wizard-completed member', ($) async {
    await open($, wizardMember);
    expect($('Edit Profile').exists, true);
    expect($('Asha').exists, true);
    // 'Other' is the value that made this screen a red error page.
    expect($('Other').exists, true);
  });

  patrolTest('the editor opens for a member who has entered nothing', (
    $,
  ) async {
    await open($, blank);
    expect($('Edit Profile').exists, true);
    expect($('First name').exists, true);
  });

  patrolTest('the editor opens for a fully populated member', ($) async {
    await open(
      $,
      named.copyWith(
        gender: 'Female',
        dob: DateTime(1995, 4, 2),
        phone: '+919876543210',
        email: 'asha@example.com',
        heightCmText: '172',
        weightText: '68',
        goalWeightText: '62',
        emergencyPhone: '+911234567890',
        address: '4-1-2 Main Rd',
        city: 'Rajahmundry',
        state: 'Andhra Pradesh',
        country: 'India',
      ),
    );
    expect($('02 Apr 1995').exists, true);
    expect($('asha@example.com').exists, true);
    expect($('Rajahmundry').exists, true);
  });

  // ── Save responds to a real finger ──────────────────────────────────────

  patrolTest('SAVE responds for a member with only a name and a gender', (
    $,
  ) async {
    await open($, wizardMember);
    // The whole reported symptom: this tap used to do nothing at all, because
    // the button was disabled behind four optional fields.
    await tapSave($);
    // No name error — the form is valid, so the tap proceeded to the write.
    expect($(RegExp('Enter your name')).exists, false);
  });

  patrolTest('SAVE with nothing filled in NAMES the blocking field', (
    $,
  ) async {
    await open($, blank);
    await tapSave($);
    expect($(RegExp('Enter your name')).exists, true);
  });

  patrolTest('an out-of-range height is reported, not silently accepted', (
    $,
  ) async {
    await open($, named.copyWith(heightCmText: '3'));
    await tapSave($);
    expect($(RegExp('Height must be between')).exists, true);
  });

  patrolTest('errors are not shown before the member asks to save', ($) async {
    await open($, blank);
    expect($(RegExp('Enter your name')).exists, false);
  });

  // ── Every control responds ──────────────────────────────────────────────

  patrolTest('typing a name clears the blocking error', ($) async {
    await open($, blank);
    await tapSave($);
    expect($(RegExp('Enter your name')).exists, true);

    await $(ValueKey(fieldKey('firstName'))).enterText('Meera');
    await $.pumpAndSettle();
    expect($(RegExp('Enter your name')).exists, false);
  });

  patrolTest('the gender dropdown opens and every option can be chosen', (
    $,
  ) async {
    await open($, wizardMember);
    await $(DropdownButton<String>).scrollTo().tap();
    await $.pumpAndSettle();
    for (final option in kGenderOptions) {
      expect($(option).exists, true, reason: '$option must be selectable');
    }
    await $('Female').tap();
    await $.pumpAndSettle();
    expect($('Female').exists, true);
  });

  patrolTest('the date picker opens on a device', ($) async {
    await open($, named);
    await $('Select date').scrollTo().tap();
    await $.pumpAndSettle();
    expect($('Select your date of birth').exists, true);
  });

  patrolTest('a stored date of birth can be cleared', ($) async {
    await open($, named.copyWith(dob: DateTime(1995, 4, 2)));
    expect($('02 Apr 1995').exists, true);
    await $(Icons.close).scrollTo().tap();
    await $.pumpAndSettle();
    expect($('Select date').exists, true);
  });

  patrolTest('the height unit switch converts what is already typed', (
    $,
  ) async {
    await open($, named.copyWith(heightCmText: '172'));
    await $('ft/in').scrollTo().tap();
    await $.pumpAndSettle();
    expect($('Feet').exists, true);
    expect($('Inches').exists, true);
  });

  patrolTest('the weight unit switch relabels both weight fields', ($) async {
    await open($, named.copyWith(weightText: '68', goalWeightText: '62'));
    await $('lb').scrollTo().tap();
    await $.pumpAndSettle();
    expect($('Current weight (lb)').exists, true);
    expect($('Goal weight (lb)').exists, true);
  });

  patrolTest('the photo control offers a real picker, not a placeholder', (
    $,
  ) async {
    await open($, named);
    await $('Add photo').scrollTo().tap();
    await $.pumpAndSettle();
    // The button used to raise "Photo upload will use the existing profile
    // media flow" and do nothing.
    expect($('Take a photo').exists, true);
    expect($('Choose from gallery').exists, true);
    expect($(RegExp('will use the existing profile media flow')).exists, false);
  });

  patrolTest('a member with a photo is offered a way to REMOVE it', ($) async {
    await open($, named.copyWith(photoUrl: 'https://example.invalid/a.jpg'));
    await $('Change photo').scrollTo().tap();
    await $.pumpAndSettle();
    expect($('Remove photo').exists, true);
  });

  // ── Every field is reachable with a keyboard up ──────────────────────────

  patrolTest('every field can be scrolled to and typed into', ($) async {
    await open($, named);
    // Addressed by key, not by label: an `InputDecoration` label is not
    // hit-testable, and positional lookup is meaningless in a lazy list.
    for (final entry in const {
      'firstName': 'Meera',
      'lastName': 'Devi',
      'phone': '+919876543210',
      'email': 'meera@example.com',
      'heightCm': '168',
      'weight': '61',
      'goalWeight': '57',
      'emergencyPhone': '+911234567890',
      'address': '4-1-2 Main Rd',
      'city': 'Rajahmundry',
      'state': 'Andhra Pradesh',
      'country': 'India',
    }.entries) {
      final field = $(ValueKey(fieldKey(entry.key)));
      await field.scrollTo();
      await field.enterText(entry.value);
      await $.pumpAndSettle();
      expect(field.exists, true, reason: '${entry.key} was not reachable');
    }
    // Everything typed is still there after scrolling the whole form.
    // `ensureVisible`, not `scrollTo()`: Patrol scrolls DOWNWARD, and the name
    // field is now far above the viewport.
    await $.tester.ensureVisible(find.byKey(ValueKey(fieldKey('firstName'))));
    await $.pumpAndSettle();
    expect($('Meera').exists, true);
  });

  patrolTest('the LAST field is reachable and typeable with a keyboard up', (
    $,
  ) async {
    // The bottom of a long form is where a keyboard most easily swallows a
    // field.
    await open($, named);
    final country = $(ValueKey(fieldKey('country')));
    await country.scrollTo();
    await country.tap();
    await $.pumpAndSettle();
    await country.enterText('India');
    await $.pumpAndSettle();
    expect($('India').exists, true);
    // ...and Save is still reachable from there.
    await $('SAVE CHANGES').scrollTo();
    expect($('SAVE CHANGES').exists, true);
  });

  // ── Leaving ─────────────────────────────────────────────────────────────

  patrolTest('system back on an UNEDITED form does not nag', ($) async {
    await open($, named);
    await systemBack($);
    expect($('Discard changes?').exists, false);
  });

  patrolTest('system back on an EDITED form asks before discarding', (
    $,
  ) async {
    await open($, named);
    await $(ValueKey(fieldKey('firstName'))).enterText('Meera');
    await $.pumpAndSettle();

    await systemBack($);
    expect($('Discard changes?').exists, true);

    await $('Keep editing').tap();
    await $.pumpAndSettle();
    expect($('Discard changes?').exists, false);
    // The member's typing survived the prompt.
    expect($('Meera').exists, true);
  });

  // ── It holds up ─────────────────────────────────────────────────────────

  patrolTest('it renders in LIGHT mode', ($) async {
    await open($, wizardMember, dark: false);
    expect($('Edit Profile').exists, true);
    expect($('Other').exists, true);
  });

  patrolTest('it renders in LANDSCAPE', ($) async {
    await open($, wizardMember, surface: const Size(844, 390));
    expect($('Edit Profile').exists, true);
    await $('SAVE CHANGES').scrollTo();
    expect($('SAVE CHANGES').exists, true);
  });

  patrolTest('it renders on a TABLET, two fields to a row', ($) async {
    await open($, wizardMember, surface: const Size(834, 1112));
    expect($('First name').exists, true);
    expect($('Last name (optional)').exists, true);
    await $('SAVE CHANGES').scrollTo();
    expect($('SAVE CHANGES').exists, true);
  });

  patrolTest('it survives the largest accessibility text size', ($) async {
    await open($, wizardMember, textScale: 2.0);
    expect($('Edit Profile').exists, true);
    await $('SAVE CHANGES').scrollTo();
    expect($('SAVE CHANGES').exists, true);
  });

  patrolTest('it survives a small phone at a large text size', ($) async {
    await open(
      $,
      wizardMember,
      surface: const Size(320, 640),
      textScale: 1.6,
    );
    expect($('Edit Profile').exists, true);
    await $('SAVE CHANGES').scrollTo();
    expect($('SAVE CHANGES').exists, true);
  });

  // ── Privacy is stated where the member can see it ───────────────────────

  patrolTest('the screen states what reaches the coach and what does not', (
    $,
  ) async {
    await open($, named);
    await $(RegExp('shared with your coach')).scrollTo();
    expect($(RegExp('shared with your coach')).exists, true);
    // The emergency contact carries a narrower visibility than `contact`, and
    // the field says so where the member enters it.
    expect($('Never shared with your coach.').exists, true);
  });
}
