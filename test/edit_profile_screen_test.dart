import 'package:alphaserena/core/domain/member_profile_form.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/profile/edit_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// The Edit Profile screen, rendered.
///
/// Every one of these is a regression guard for a defect that made the screen
/// unusable in production. The first one is the important one: this screen
/// THREW at build time for any member whose stored gender was `'Other'` — the
/// value the onboarding wizard writes — because a `DropdownButtonFormField`
/// asserts when its value is absent from its items. No unit test could have
/// caught that. It has to be built and looked at.
void main() {
  // Tall enough that the whole form lays out: a ListView does not build what
  // is below the fold, and an unbuilt field can neither be tapped nor asserted.
  Future<void> open(
    WidgetTester tester,
    MemberProfileForm form, {
    Size size = const Size(900, 2600),
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.dark,
        home: EditProfileScreen(initialForm: form),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    final button = find.widgetWithText(ElevatedButton, 'SAVE CHANGES');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    // Drain the GetX snackbar's own 3 s timer, or the binding reports a pending
    // timer at teardown and masks whatever the test was actually asserting.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  /// What a field actually contains, read off its controller rather than by
  /// matching loose text that could belong to any label on the screen.
  String fieldText(WidgetTester tester, String label) {
    final field = tester.widget<TextField>(
      find
          .ancestor(of: find.text(label), matching: find.byType(TextField))
          .first,
    );
    return field.controller!.text;
  }

  const named = MemberProfileForm(firstName: 'Asha', lastName: 'Rao');

  group('it builds for every profile a member can actually have', () {
    testWidgets('an empty profile', (tester) async {
      await open(tester, const MemberProfileForm());
      expect(tester.takeException(), isNull);
      expect(find.text('Edit Profile'), findsOneWidget);
    });

    // THE bug. 'Other' is what IdentitySetupScreen writes.
    testWidgets('a gender the old dropdown had no item for', (tester) async {
      await open(tester, named.copyWith(gender: 'Other'));
      expect(tester.takeException(), isNull);
      expect(find.text('Other'), findsWidgets);
    });

    testWidgets('a gender no build in this app has ever written', (
      tester,
    ) async {
      await open(tester, named.copyWith(gender: 'genderqueer'));
      expect(tester.takeException(), isNull);
      expect(find.text('genderqueer'), findsWidgets);
    });

    testWidgets('every canonical gender option', (tester) async {
      for (final g in kGenderOptions) {
        await open(tester, named.copyWith(gender: g));
        expect(tester.takeException(), isNull, reason: 'gender "$g" threw');
      }
    });

    testWidgets('a fully populated profile', (tester) async {
      await open(
        tester,
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
      expect(tester.takeException(), isNull);
      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('172'), findsOneWidget);
      expect(find.text('02 Apr 1995'), findsOneWidget);
    });

    testWidgets('a profile stored in imperial units', (tester) async {
      await open(
        tester,
        named.copyWith(
          heightUnit: 'ftin',
          heightFtText: '5',
          heightInText: '8',
          weightUnit: 'lb',
          weightText: '150',
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Feet'), findsOneWidget);
      expect(find.text('Current weight (lb)'), findsOneWidget);
    });
  });

  group('the save button is never a dead end', () {
    // It used to be DISABLED whenever height, weight, goal weight, phone or
    // date of birth were blank — all of which the wizard calls optional — so a
    // member met an unresponsive button and no explanation.
    testWidgets('is enabled with only a name filled in', (tester) async {
      await open(tester, named);
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'SAVE CHANGES'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('is enabled even when the form is invalid', (tester) async {
      await open(tester, const MemberProfileForm());
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'SAVE CHANGES'),
      );
      expect(
        button.onPressed,
        isNotNull,
        reason: 'a disabled button can never explain itself',
      );
    });

    testWidgets('tapping it with an invalid form REPORTS the field', (
      tester,
    ) async {
      await open(tester, const MemberProfileForm());
      await tapSave(tester);
      expect(
        find.textContaining('Enter your name'),
        findsWidgets,
        reason: 'the blocking field must name itself',
      );
    });

    testWidgets('errors stay hidden until the member asks to save', (
      tester,
    ) async {
      await open(tester, const MemberProfileForm());
      expect(find.textContaining('Enter your name'), findsNothing);
    });

    testWidgets('an out-of-range height is reported on the field', (
      tester,
    ) async {
      await open(tester, named.copyWith(heightCmText: '3'));
      await tapSave(tester);
      expect(find.textContaining('Height must be between'), findsWidgets);
    });
  });

  group('editing', () {
    testWidgets('typing a name clears the blocking error', (tester) async {
      await open(tester, const MemberProfileForm());
      await tapSave(tester);
      expect(find.textContaining('Enter your name'), findsWidgets);

      await tester.enterText(
        find.widgetWithText(TextField, 'First name'),
        'Asha',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter your name'), findsNothing);
    });

    testWidgets('switching height units converts what is already typed', (
      tester,
    ) async {
      await open(tester, named.copyWith(heightCmText: '172'));
      await tester.tap(find.text('ft/in'));
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'Feet'), '5');
      expect(fieldText(tester, 'Inches'), '8');
    });

    testWidgets('switching weight units relabels and converts both fields', (
      tester,
    ) async {
      await open(
        tester,
        named.copyWith(weightText: '68', goalWeightText: '62'),
      );
      await tester.tap(find.text('lb'));
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'Current weight (lb)'), '149.9');
      expect(fieldText(tester, 'Goal weight (lb)'), '136.7');
    });

    testWidgets('the date of birth can be cleared', (tester) async {
      await open(tester, named.copyWith(dob: DateTime(1995, 4, 2)));
      expect(find.text('02 Apr 1995'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear date of birth'));
      await tester.pumpAndSettle();
      expect(find.text('Select date'), findsOneWidget);
    });
  });

  group('leaving the screen', () {
    testWidgets('an untouched form pops without a prompt', (tester) async {
      await open(tester, named);
      final popped = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(popped, isFalse); // nothing below it — the route simply allowed it
      expect(find.text('Discard changes?'), findsNothing);
    });

    testWidgets('an edited form asks before discarding', (tester) async {
      await open(tester, named);
      await tester.enterText(
        find.widgetWithText(TextField, 'First name'),
        'Meera',
      );
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('Meera'), findsOneWidget);
    });
  });

  group('accessibility', () {
    testWidgets('the avatar and unit switches are labelled for a screen '
        'reader', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, named);
      expect(find.bySemanticsLabel('Add profile photo'), findsOneWidget);
      expect(find.bySemanticsLabel('Height unit cm'), findsOneWidget);
      expect(find.bySemanticsLabel('Weight unit kg'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the date row announces its own error text', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, named.copyWith(dob: DateTime(2024, 1, 1)));
      await tapSave(tester);
      // The decorator's error is what a screen reader reads. A custom Semantics
      // label on the row would have replaced it with a static sentence.
      expect(find.textContaining('Check your date of birth'), findsWidgets);
      handle.dispose();
    });

    testWidgets('the date row opens a picker', (tester) async {
      await open(tester, named);
      await tester.tap(find.text('Select date'));
      await tester.pumpAndSettle();
      expect(find.text('Select your date of birth'), findsOneWidget);
    });

    testWidgets('renders at the largest OS font scale without overflowing', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(900, 2600);
      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: 2.0,
            maxScaleFactor: 2.0,
            child: child!,
          ),
          home: EditProfileScreen(
            initialForm: named.copyWith(
              gender: 'Other',
              dob: DateTime(1995, 4, 2),
              heightCmText: '172',
              weightText: '68',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('layout', () {
    testWidgets('renders on a phone, a tablet and in landscape', (
      tester,
    ) async {
      for (final size in const [
        Size(360, 690), // compact phone
        Size(834, 1112), // tablet portrait
        Size(896, 414), // phone landscape
      ]) {
        await open(tester, named.copyWith(gender: 'Other'), size: size);
        expect(tester.takeException(), isNull, reason: 'failed at $size');
      }
    });
  });
}
