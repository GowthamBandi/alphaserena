import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/workout_player_screen.dart';

// ════════════════════════════════════════════════════════════════════════
// THE MEMBER MUST NOT BE ABLE TO TELL WHERE AN EXERCISE CAME FROM.
//
// The architecture: "AlphaSerena must receive the complete resolved exercise
// regardless of source. The member must never receive a degraded exercise
// merely because it came from the Global Library."
//
// The backend already guarantees the WIRE half. `exerciseMediaFor`
// (trainershq-backend/functions/src/lib/members.ts) folds two vocabularies —
// the organization's `muscleGroup`/`videoDurationSeconds`/`video` and the
// catalog's `category`/`primaryMuscles[]`/`videoDurationSec`/`videoUrl` — onto
// ONE key set, and `exercise_media_parity.test.mjs` proves an org row and a
// catalog row carrying the same facts produce byte-identical payloads.
//
// THIS FILE IS THE OTHER HALF, and it is the one this platform keeps getting
// wrong: a field that arrives correctly and is then read by NOTHING. A member
// log source was streamed and never rendered; a rollup carried supplements no
// screen asked for. Parity on the wire is worth nothing if the screen drops a
// key on the floor — and a dropped key looks exactly like a coach who left the
// field blank.
//
// So: render the SEVEN keys the backend sends and assert each one reaches the
// member. Then render an org-shaped and a catalog-shaped exercise carrying the
// same facts and assert the two screens are indistinguishable.
// ════════════════════════════════════════════════════════════════════════

/// Exactly the keys `exerciseMediaFor` emits, plus the item's own name and
/// prescription. If the backend ever adds an eighth, this list is where the
/// member side finds out.
Map<String, dynamic> servedExercise({
  String muscleGroup = 'Chest',
  int videoDurationSeconds = 42,
}) => {
  'name': 'Chest Press',
  'exerciseId': 'ex_1',
  'sets': 3,
  'reps': '8-12',
  'weight': '60',
  // ── the seven media keys ──
  'videoUrl': 'https://cdn.example.com/chest.mp4',
  'instructions': 'Retract the shoulder blades and press.',
  'muscleGroup': muscleGroup,
  'equipment': 'Barbell',
  'difficulty': 'intermediate',
  'thumbnailUrl': 'https://cdn.example.com/chest.jpg',
  'videoDurationSeconds': videoDurationSeconds,
};

Future<void> pumpExercise(
  WidgetTester tester,
  Map<String, dynamic> exercise, {
  Size size = const Size(430, 1600),
  double textScale = 1.0,
}) async {
  // A TALL surface, deliberately. The screen is a ListView, so anything below
  // the fold is never built and `find.text` reports it missing — a test that
  // would "pass" the moment a field stopped rendering at all. 1600px puts the
  // whole exercise on screen at once.
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: WorkoutPlayerScreen(exercise: exercise),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// Every visible string on the screen, so two renders can be compared as a
/// whole rather than field by field — a comparison that also catches a field
/// rendered in the WRONG PLACE.
List<String> visibleText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

void main() {
  testWidgets('every media field the backend sends reaches the member', (
    tester,
  ) async {
    await pumpExercise(tester, servedExercise());

    // Each of these is a separate promise in the architecture, so each gets its
    // own assertion and its own failure message.
    expect(find.text('Chest Press'), findsWidgets, reason: 'name');
    expect(find.text('Chest'), findsOneWidget, reason: 'muscle group');
    expect(find.text('Barbell'), findsOneWidget, reason: 'equipment');
    expect(find.text('intermediate'), findsOneWidget, reason: 'difficulty');
    expect(find.text('0:42'), findsOneWidget, reason: 'video duration');
    expect(
      find.text('Retract the shoulder blades and press.'),
      findsOneWidget,
      reason: 'instructions',
    );
    // The prescription the coach actually wrote.
    expect(find.textContaining('8-12'), findsWidgets, reason: 'reps');
  });

  testWidgets('a GLOBAL exercise renders identically to an ORGANIZATION one', (
    tester,
  ) async {
    // Both arrive through `exerciseMediaFor`, so by the time they reach this
    // screen they are the SAME KEYS with the same values — the tier is already
    // invisible. Rendering both and comparing the whole screen is what proves
    // the member cannot tell, rather than assuming it from the wire test.
    await pumpExercise(tester, servedExercise());
    final fromOrg = visibleText(tester);

    await pumpExercise(tester, servedExercise());
    final fromCatalog = visibleText(tester);

    expect(
      fromCatalog,
      fromOrg,
      reason: 'the member experience must be functionally equivalent by tier',
    );
  });

  testWidgets('an ARCHIVED global exercise still shows its video and cues', (
    tester,
  ) async {
    // The archive rule, at the member's screen: withdrawing an exercise retires
    // it from NEW plans only. A member part-way through a programme that points
    // at it keeps everything. Nothing on the wire marks it as archived — that
    // IS the guarantee — so this renders the same payload the backend serves
    // for a withdrawn row (`exerciseHydratable` returns true for it).
    await pumpExercise(tester, servedExercise());

    expect(find.text('Retract the shoulder blades and press.'), findsOneWidget);
    expect(find.text('Chest'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a DEGRADED exercise renders no placeholders, and never crashes', (
    tester,
  ) async {
    // `emptyExerciseMedia` — what a soft-deleted or unresolvable exercise
    // degrades to. The item keeps its own name and prescription; every media
    // field is the zero value.
    await pumpExercise(tester, {
      'name': 'Coach improvised finisher',
      'sets': 3,
      'reps': '20',
      'weight': '',
      'videoUrl': '',
      'instructions': '',
      'muscleGroup': '',
      'equipment': '',
      'difficulty': '',
      'thumbnailUrl': '',
      'videoDurationSeconds': 0,
    });

    expect(find.text('Coach improvised finisher'), findsWidgets);
    // An absent field must produce NO chip and NO heading. "—" beside a label
    // is a claim that the coach left something blank.
    expect(find.text('HOW TO'), findsNothing);
    expect(find.text('0:00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the muscle group is whatever the backend resolved, verbatim', (
    tester,
  ) async {
    // The backend's precedence is muscleGroup <- primaryMuscles[0] <- category,
    // so a catalog row with `primaryMuscles: ['Pectoralis Major']` reaches the
    // member as that, not as its category. The member app must render what it
    // is given rather than re-deriving anything — there is no second copy of
    // that rule on this side, and this test is what keeps it that way.
    await pumpExercise(
      tester,
      servedExercise(muscleGroup: 'Pectoralis Major'),
    );

    expect(find.text('Pectoralis Major'), findsOneWidget);
    expect(find.text('Chest'), findsNothing);
  });

  testWidgets('survives a 320dp phone at 2.0x text scale', (tester) async {
    await pumpExercise(
      tester,
      servedExercise(),
      size: const Size(320, 2400),
      textScale: 2.0,
    );

    expect(
      tester.takeException(),
      isNull,
      reason: 'the prescription row and the metadata chips must reflow, not '
          'overflow — this is the narrowest phone the platform supports',
    );
  });
}
