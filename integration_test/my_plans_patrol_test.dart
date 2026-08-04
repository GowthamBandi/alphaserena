import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
// `PatrolTester` (the `patrolWidgetTest` callback type) lives in patrol_finders;
// `package:patrol` re-exports the test function but not the tester type.
// ignore: depend_on_referenced_packages
import 'package:patrol_finders/patrol_finders.dart';

import 'package:alphaserena/controllers/food_log_controller.dart';
import 'package:alphaserena/controllers/member_controller.dart';
import 'package:alphaserena/controllers/membership_controller.dart';
import 'package:alphaserena/controllers/streak_controller.dart';
import 'package:alphaserena/controllers/training_controller.dart';
import 'package:alphaserena/core/domain/prescription.dart' show ExpectationKind;
import 'package:alphaserena/core/domain/today_expectation.dart';
import 'package:alphaserena/core/domain/workout_session.dart';
import 'package:alphaserena/core/models/nutrition_day_model.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/consistency_detail_screen.dart';
import 'package:alphaserena/screens/dashboard/nutrition/add_food_screen.dart';
import 'package:alphaserena/screens/dashboard/plans/my_plans_screen.dart';
import 'package:alphaserena/screens/dashboard/workout_briefing_screen.dart';

/// PATROL — MY PLANS, ON A REAL DEVICE.
///
/// My Plans exists to answer exactly two questions:
///   1. What has my trainer assigned me?
///   2. What have I completed today?
///
/// Every journey below certifies one of those, or certifies that the screen
/// refuses to answer a question it has no data for.
///
/// ── HOW THESE RUN ─────────────────────────────────────────────────────────
/// The real screen is mounted against real controllers whose served state is a
/// deterministic fixture written into the same `Rxn` fields `getMyTraining`
/// writes. Every fixture is a shape the backend genuinely serves — the wire
/// shapes were read out of `functions/src/members.ts` (`buildWorkout`,
/// `buildDiet`) and `nutrition_day_model.dart`, not invented.
///
/// ── WHAT THIS SUITE EXISTS TO PREVENT ─────────────────────────────────────
/// Before this pass, verified on `emulator-5554` against the live backend:
///   • the Workout tab's PRIMARY CTA raised a snackbar reading "Open it from
///     Home → Start Workout" — a sign pointing at another screen;
///   • the calendar button did the same;
///   • the screen ignored the served expectation entirely, so on an excused or
///     paused day it said "Start Workout · 3 exercises" while Home correctly
///     said "Today is excused";
///   • the Diet tab reported a NETWORK FAILURE as "No diet plan right now —
///     your coach will assign one";
///   • nothing on the screen said what the member had done today.
/// Each of those has a journey here.

// ── FIXTURE CONTROLLERS ────────────────────────────────────────────────────

class _Member extends MemberController {
  _Member({this.linked = true, this.membershipActive = true}) {
    isLinked.value = linked;
    client.value = {
      'adminId': 'admin1',
      'membershipActive': membershipActive,
      'membershipFrozen': false,
      // `_parseExpiry` accepts Timestamp | DateTime | String — NOT a number.
      // An epoch-millis fixture parses to null, which reads as EXPIRED and
      // puts the whole screen behind the "Membership inactive" blocker.
      'membershipExpiry':
          DateTime.now().add(const Duration(days: 90)).toIso8601String(),
    };
    profile.value = {'gymName': 'ORG Name', 'linkedClientId': 'c1'};
    isLoading.value = false;
  }

  final bool linked;
  final bool membershipActive;

  @override
  String? get linkedClientId => 'c1';

  @override
  String get trainerName => 'Coach Ravi';

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> claim() async {}
}

class _Training extends TrainingController {
  _Training({
    Map<String, dynamic>? workoutValue,
    Map<String, dynamic>? dietValue,
    ServedExpectation? workoutExpect,
    String errorText = '',
  }) {
    workout.value = workoutValue;
    diet.value = dietValue;
    servedTargets.value = {
      'calories': 2000.0,
      'protein': 150.0,
      'carbs': 200.0,
      'fat': 60.0,
      'fiber': 30.0,
      'source': 'coach',
    };
    coach.value = {'name': 'Coach Ravi'};
    if (workoutExpect != null) {
      expectations.value = TodayExpectations(
        date: '2026-08-03',
        workout: workoutExpect,
        diet: null,
      );
    }
    error.value = errorText;
    isLoading.value = false;
  }

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> load() async {}

  @override
  Future<void> ensureFreshDay() async {}
}

class _Log extends FoodLogController {
  _Log({Map<String, FoodEntry> entries = const {}}) {
    day.value = NutritionDayModel(
      id: 'c1_2026-08-03',
      dateKey: '2026-08-03',
      adminId: 'admin1',
      entries: entries,
    );
    isLoading.value = false;
    loadError.value = false;
  }

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  void ensureFreshDay() {}
}

class _Streak extends StreakController {
  _Streak({List<ExerciseLog>? exercises, int? duration}) {
    workoutDays.value = <String>{};
    dietDays.value = <String>{};
    isLoading.value = false;
    if (exercises != null) {
      markWorkoutToday(
        stats: computeSessionStats(exercises),
        nextUp: nextUpFrom(exercises),
        exercises: exercises,
        trained: hasCompletedWork(exercises),
      );
      _duration = duration;
    }
  }

  int? _duration;

  @override
  int? get todayDurationSeconds => _duration;

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> load() async {}

  @override
  Future<void> ensureFreshDay() async {}
}

/// The real controller opens a Firestore listener on the org's membership
/// plans and leaves `isLoading` TRUE until it answers. This test process has no
/// signed-in session, so that listener neither completes nor errors within a
/// `pumpAndSettle` — the screen sits in its loading skeleton and every
/// assertion about content fails. Entitlement itself is still decided by the
/// REAL `isActive` rule, reading the fake member's clients document.
class _Membership extends MembershipController {
  _Membership() {
    isLoading.value = false;
  }

  @override
  // ignore: must_call_super
  void onInit() {}
}

// ── WIRE-SHAPED FIXTURES ───────────────────────────────────────────────────

/// `buildWorkout`'s served item shape, verbatim.
Map<String, dynamic> _item(String name) => {
      'name': name,
      'exerciseId': 'ex_${name.hashCode}',
      'sets': 3,
      'reps': '10',
      'weight': '40',
      'setRows': const [
        {'reps': '10', 'weight': '40', 'rest': '60s'},
        {'reps': '10', 'weight': '40', 'rest': '60s'},
        {'reps': '10', 'weight': '40', 'rest': '60s'},
      ],
      'videoUrl': '',
      'instructions': '',
      'muscleGroup': 'Chest',
      'equipment': 'Dumbbell',
      'difficulty': 'Beginner',
      'thumbnailUrl': '',
      'videoDurationSeconds': 0,
    };

Map<String, dynamic> _workout({bool restDay = false}) => {
      'name': 'Workout Plan 11',
      'items': restDay ? const [] : [_item('Dumbbell Chest Press')],
      if (restDay) 'restDay': true,
    };

Map<String, dynamic> _diet() => {
      'name': 'Test Diet Plan',
      'items': [
        {
          'name': 'Boiled Egg',
          'foodId': 'food_egg',
          'meal': 'Breakfast',
          'calories': 116.0,
          'protein': 11.0,
          'carbs': 1.0,
          'fat': 8.0,
        },
        {
          'name': 'Whole Cow Milk',
          'foodId': 'food_milk',
          'meal': 'Breakfast',
          'calories': 73.0,
          'protein': 3.0,
          'carbs': 5.0,
          'fat': 4.0,
        },
      ],
      'targetCalories': 2000.0,
      'targetProtein': 150.0,
      'targetCarbs': 200.0,
      'targetFat': 60.0,
      'targetFiber': 30.0,
    };

FoodEntry _entry(String name, String meal, double kcal) => FoodEntry(
      entryId: name.toLowerCase().replaceAll(' ', '_'),
      source: FoodEntrySource.search,
      foodName: name,
      foodTier: FoodTier.global,
      mealSlot: meal,
      quantity: 1,
      unit: 'katori',
      grams: 150,
      loggedAt: DateTime(2026, 8, 3, 13, 30).millisecondsSinceEpoch,
      consumed: ConsumedSnapshot(calories: kcal, protein: 20),
    );

ExerciseLog _session({
  int completed = 1,
  int skipped = 0,
  int total = 3,
}) {
  final sets = <SetLog>[];
  for (var i = 0; i < total; i++) {
    sets.add(SetLog(
      pReps: '10',
      pWeight: '40',
      pRest: '60s',
      actualReps: i < completed ? '10' : '',
      actualWeight: i < completed ? '42' : '',
      state: i < completed
          ? SetLogState.completed
          : (i < completed + skipped
              ? SetLogState.skipped
              : SetLogState.pending),
    ));
  }
  return ExerciseLog(
    name: 'Dumbbell Chest Press',
    exerciseId: 'ex1',
    sets: sets,
  );
}

void main() {
  Future<void> boot() async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    Get.reset();
  }

  Future<void> mount(
    PatrolTester $, {
    _Training? training,
    _Log? log,
    _Streak? streak,
    _Member? member,
    Size? size,
    double textScale = 1.0,
    ThemeData? theme,
  }) async {
    await boot();
    Get.put<MemberController>(member ?? _Member());
    Get.put<TrainingController>(
      training ?? _Training(workoutValue: _workout(), dietValue: _diet()),
    );
    Get.put<FoodLogController>(log ?? _Log());
    Get.put<StreakController>(streak ?? _Streak());
    Get.put<MembershipController>(_Membership());

    if (size != null) {
      $.tester.view.physicalSize = size;
      $.tester.view.devicePixelRatio = 1.0;
      addTearDown($.tester.view.reset);
    }

    await $.pumpWidget(
      GetMaterialApp(
        theme: theme ?? AppTheme.dark,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const MyPlansScreen(),
        ),
      ),
    );
    await $.pumpAndSettle();
  }

  // ── 0. WARM-UP ──────────────────────────────────────────────────────────
  //
  // The FIRST `patrolWidgetTest` in a bundle pays for `Firebase.initializeApp`
  // and the Patrol binding's own first-run setup. Every subsequent test in the
  // same bundle runs clean, so the cost lands here — on a test that asserts
  // only that the screen mounts — rather than on a real assertion, where it
  // would be read as a product failure.
  //
  // ── THE FIRST-TEST FAILURE, DIAGNOSED (2026-08-04) ─────────────────────
  //
  // It was previously recorded here as "a null-messaged `AssertionError` from
  // the JUnit runner". That is only the SYMPTOM as the native side reports it.
  // The actual Dart-side assertion, read off logcat, is:
  //
  //     A SemanticsHandle was active at the end of the test.
  //     WidgetTester._verifySemanticsHandlesWereDisposed
  //
  // It fires AFTER the body has already passed — Patrol's own tearDown logs
  // this test as `success`, and only the post-body verification throws. Patrol
  // carries a workaround for the same family of bug in this exact code path,
  // citing https://github.com/leancodepl/patrol/issues/1474 ("tests failing on
  // iOS and (from Flutter 3.29.0) on Android").
  //
  // TWO CAUSES TESTED AND REFUTED, by experiment rather than assumption:
  //   1. The emulator's `accessibility_enabled` secure setting. Toggled to 0
  //      and the whole suite re-run: the failure reproduced identically.
  //   2. `semanticsEnabled: false` on this test, which is what decides whether
  //      `testWidgets` itself holds a handle. Also reproduced identically —
  //      so the handle is held by the PatrolBinding, not by the test.
  //
  // It is therefore an upstream harness artifact with no app-side fix, and it
  // lands here by design. Every one of the 34 real tests below passes.
  patrolWidgetTest('warm-up — the screen mounts', ($) async {
    await mount($);
    expect($.tester.takeException(), isNull);
  });

  // ── 1. WHAT MY TRAINER ASSIGNED ─────────────────────────────────────────

  group('question 1 — what has my trainer assigned me', () {
    patrolWidgetTest('the workout plan, its coach, and today', ($) async {
      await mount($);
      expect($('ASSIGNED BY YOUR COACH').exists, true);
      expect($('Workout Plan 11').exists, true);
      // The attribution is one Text — "ORG Name  ·  Coach Ravi" — so this is a
      // substring match, not an exact one.
      expect(find.textContaining('Coach Ravi'), findsOneWidget);
      expect(find.textContaining('ORG Name'), findsOneWidget);
      expect($('Dumbbell Chest Press').exists, true);
    });

    patrolWidgetTest('the diet plan, on its own tab', ($) async {
      await mount($);
      await $('Diet').tap();
      await $.pumpAndSettle();
      expect($('Test Diet Plan').exists, true);
    });

    patrolWidgetTest('the FOODS the coach prescribed — not just a count',
        ($) async {
      // This tab used to answer "what has my trainer assigned me?" with two
      // number chips while the prescribed foods lived on another screen.
      await mount($);
      await $('Diet').tap();
      await $.pumpAndSettle();

      expect($("YOUR COACH'S PLAN").exists, true);
      expect($('BREAKFAST').exists, true);
      expect($('Boiled Egg').exists, true);
      expect($('Whole Cow Milk').exists, true);
    });

    patrolWidgetTest("the coach's WORKOUT note, which nothing used to render",
        ($) async {
      // `buildWorkout` has served `description` since Workout Plans V1. The
      // Diet tab showed its equivalent; this one dropped it.
      await mount(
        $,
        training: _Training(
          workoutValue: {
            ..._workout(),
            'description': 'Leave one rep in reserve on every set.',
          },
          dietValue: _diet(),
        ),
      );
      expect($('Leave one rep in reserve on every set.').exists, true);
    });

    patrolWidgetTest('and NO note is invented when the coach wrote none',
        ($) async {
      await mount($);
      expect($(Icons.format_quote_rounded).exists, false);
    });

    patrolWidgetTest(
        'NO fabricated plan fields — duration, difficulty, image, status',
        ($) async {
      // `getMyTraining` serves none of these at plan level. The screen this
      // replaced printed a hardcoded `Duration: Ongoing` and a bundled stock
      // photo as though both were the member's own plan data.
      await mount($);
      expect($('Ongoing').exists, false);
      expect($('Duration').exists, false);
      expect($('Not set').exists, false);
      expect($('Active').exists, false);
      expect($(Image).exists, false);
    });
  });

  // ── 2. WHAT I COMPLETED TODAY ───────────────────────────────────────────

  group('question 2 — what have I completed today', () {
    patrolWidgetTest('a part-done session states progress, set by set',
        ($) async {
      await mount($, streak: _Streak(exercises: [_session(completed: 1)]));

      expect($("TODAY'S WORKOUT").exists, true);
      expect($('In progress').exists, true);
      expect($('33%').exists, true);
      expect($('1/3').exists, true);
      // The member's own numbers, beside the coach's.
      expect($('10 reps × 42 kg').exists, true);
      expect($(RegExp(r'Next: Dumbbell Chest Press · set 2 of 3')).exists, true);
    });

    patrolWidgetTest('a PENDING set states its target and no result', ($) async {
      await mount($, streak: _Streak(exercises: [_session(completed: 1)]));
      expect($('Set 3').exists, true);
      // Three prescription labels (one per set) and exactly one result.
      expect($('10 reps × 42 kg').exists, true);
      expect($('0 reps').exists, false);
    });

    patrolWidgetTest('a finished session is a STATEMENT, not a button',
        ($) async {
      await mount(
        $,
        streak: _Streak(exercises: [_session(completed: 3)], duration: 2700),
      );
      expect($('Workout complete').exists, true);
      expect($('100%').exists, true);
      expect($('45m').exists, true);
      // Nothing left to do, so nothing invites a tap.
      expect($(ElevatedButton).exists, false);
    });

    patrolWidgetTest('skipped sets close the session WITHOUT completing it',
        ($) async {
      await mount(
        $,
        streak: _Streak(exercises: [_session(completed: 1, skipped: 2)]),
      );
      expect($('Workout closed').exists, true);
      expect($('Workout complete').exists, false);
      expect($('Review Workout').exists, true);
    });

    patrolWidgetTest("today's meals, grouped, with times", ($) async {
      await mount(
        $,
        log: _Log(entries: {
          'boiled_egg': _entry('Boiled Egg', 'breakfast', 155),
          'paneer': _entry('Paneer', 'lunch', 387),
        }),
      );
      await $('Diet').tap();
      await $.pumpAndSettle();

      expect($("TODAY'S MEALS").exists, true);
      expect($('BREAKFAST').exists, true);
      expect($('LUNCH').exists, true);
      expect($('Paneer').exists, true);
      expect($('387 kcal').exists, true);
    });

    patrolWidgetTest('the totals are stated ONCE, by the nutrition card',
        ($) async {
      await mount(
        $,
        log: _Log(entries: {'paneer': _entry('Paneer', 'lunch', 387)}),
      );
      await $('Diet').tap();
      await $.pumpAndSettle();
      // The food log's own totals card is suppressed here; the ring above
      // already states every macro AGAINST the coach's target.
      expect($('Logged today').exists, false);
      expect($('kcal from 1 item').exists, false);
    });
  });

  // ── 3. NO DEAD ENDS ─────────────────────────────────────────────────────

  group('every control goes somewhere real', () {
    patrolWidgetTest('the workout CTA opens the session briefing', ($) async {
      await mount($);
      await $(ElevatedButton).tap();
      await $.pumpAndSettle();
      // Previously: a snackbar reading "Open it from Home → Start Workout".
      expect($(WorkoutBriefingScreen).exists, true);
      expect($(RegExp('Open it from Home')).exists, false);
    });

    patrolWidgetTest('the diet CTA opens Add Food', ($) async {
      await mount($);
      await $('Diet').tap();
      await $.pumpAndSettle();
      await $('Add Food').tap();
      await $.pumpAndSettle();
      expect($(AddFoodScreen).exists, true);
    });

    patrolWidgetTest('the header button opens the workout history calendar',
        ($) async {
      await mount($);
      await $(find.byIcon(Icons.calendar_today_outlined)).tap();
      await $.pumpAndSettle();
      expect($(ConsistencyDetailScreen).exists, true);
      expect($(RegExp('Open it from Home')).exists, false);
    });
  });

  // ── 4. THE SCREEN NEVER CONTRADICTS HOME ────────────────────────────────

  group('one served expectation, one answer', () {
    patrolWidgetTest('an EXCUSED day never says "Start Workout"', ($) async {
      await mount(
        $,
        training: _Training(
          workoutValue: _workout(),
          dietValue: _diet(),
          workoutExpect: const ServedExpectation(
            kind: ExpectationKind.rest,
            excusedToday: true,
          ),
        ),
      );
      expect($('Today is excused').exists, true);
      expect($('Start Full Workout').exists, false);
    });

    patrolWidgetTest('PAUSED coaching offers nothing to start', ($) async {
      await mount(
        $,
        training: _Training(
          workoutValue: _workout(),
          dietValue: _diet(),
          workoutExpect:
              const ServedExpectation(kind: ExpectationKind.paused),
        ),
      );
      expect($('Coaching paused').exists, true);
      expect($('Start Full Workout').exists, false);
    });

    patrolWidgetTest('a REST day is a positive state, not an empty screen',
        ($) async {
      await mount(
        $,
        training: _Training(
          workoutValue: _workout(),
          dietValue: _diet(),
          workoutExpect: const ServedExpectation(kind: ExpectationKind.rest),
        ),
      );
      expect($('Rest day').exists, true);
    });
  });

  // ── 5. HONEST FAILURE ───────────────────────────────────────────────────

  group('a network failure is never reported as a coach doing nothing', () {
    patrolWidgetTest('the WORKOUT tab says so', ($) async {
      await mount(
        $,
        training: _Training(errorText: 'Could not load your training.'),
      );
      expect($("Couldn't load your plans").exists, true);
      expect($('No workout plan right now').exists, false);
      expect($('Try again').exists, true);
    });

    patrolWidgetTest('the DIET tab says so too — it used to lie', ($) async {
      // This branch had no error check at all: a failed load rendered as
      // "No diet plan right now — your coach will assign one soon", telling
      // the member their coach had done nothing.
      await mount(
        $,
        training: _Training(errorText: 'Could not load your training.'),
      );
      await $('Diet').tap();
      await $.pumpAndSettle();
      expect($("Couldn't load your plans").exists, true);
      expect($('No diet plan right now').exists, false);
    });

    patrolWidgetTest('an unlinked member is told what to do', ($) async {
      await mount($, member: _Member(linked: false));
      expect($('No coach linked yet').exists, true);
      // A blocker that names a remedy must OFFER it — this used to be a dead
      // end that told the member what to do and gave them nothing to do it with.
      expect($('Find a coach').exists, true);
    });

    patrolWidgetTest('an inactive membership blocks with a reason', ($) async {
      await mount($, member: _Member(membershipActive: false));
      expect($('Membership inactive').exists, true);
      expect($('Renew membership').exists, true);
    });
  });

  // ── 6. RESPONSIVE + ACCESSIBLE ──────────────────────────────────────────

  group('the screen holds up', () {
    patrolWidgetTest('320dp at 2.0x text, both tabs, no overflow', ($) async {
      await mount(
        $,
        streak: _Streak(exercises: [_session(completed: 2)]),
        log: _Log(entries: {'paneer': _entry('Paneer', 'lunch', 387)}),
        size: const Size(320, 3000),
        textScale: 2.0,
      );
      expect($.tester.takeException(), isNull);
      await $('Diet').tap();
      await $.pumpAndSettle();
      expect($.tester.takeException(), isNull);
    });

    patrolWidgetTest('tablet', ($) async {
      await mount($, size: const Size(1024, 1366));
      expect($.tester.takeException(), isNull);
      expect($('Workout Plan 11').exists, true);
    });

    patrolWidgetTest('landscape', ($) async {
      await mount($, size: const Size(900, 420));
      expect($.tester.takeException(), isNull);
    });

    patrolWidgetTest('light theme', ($) async {
      await mount($, theme: AppTheme.light);
      expect($.tester.takeException(), isNull);
      expect($('Workout Plan 11').exists, true);
    });
  });

  // ── 7. PREMIUM POLISH ───────────────────────────────────────────────────

  group('the session is ranked, not dumped', () {
    patrolWidgetTest('a finished exercise stays COLLAPSED', ($) async {
      await mount(
        $,
        streak: _Streak(exercises: [_session(completed: 3)], duration: 2700),
      );
      // It is answered, so it does not spend screen height restating itself.
      expect($('Dumbbell Chest Press').exists, true);
      expect($('Set 1').exists, false);
    });

    patrolWidgetTest('the exercise holding the next set opens itself',
        ($) async {
      await mount($, streak: _Streak(exercises: [_session(completed: 1)]));
      expect($('Set 1').exists, true);
      expect($('Set 3').exists, true);
    });

    patrolWidgetTest('and any card can be opened by hand', ($) async {
      await mount(
        $,
        streak: _Streak(exercises: [_session(completed: 3)], duration: 2700),
      );
      expect($('Set 1').exists, false);
      await $('Dumbbell Chest Press').tap();
      await $.pumpAndSettle();
      expect($('Set 1').exists, true);
    });

    patrolWidgetTest("the coach's prescribed REST reaches the member", ($) async {
      await mount($, streak: _Streak(exercises: [_session(completed: 1)]));
      expect($('rest 60s').exists, true);
    });
  });

  group("what I still need", () {
    patrolWidgetTest('a prescribed food the member already logged is marked',
        ($) async {
      await mount(
        $,
        log: _Log(entries: {
          // Same foodId as the plan's Boiled Egg.
          'egg': FoodEntry(
            entryId: 'egg',
            source: FoodEntrySource.search,
            foodId: 'food_egg',
            foodName: 'Boiled Egg',
            foodTier: FoodTier.global,
            mealSlot: 'breakfast',
            quantity: 1,
            unit: 'egg',
            grams: 50,
            loggedAt: DateTime(2026, 8, 3, 8).millisecondsSinceEpoch,
            consumed: const ConsumedSnapshot(calories: 78),
          ),
        }),
      );
      await $('Diet').tap();
      await $.pumpAndSettle();
      // One of the two prescribed breakfast foods is logged.
      expect($('1 of 2 logged').exists, true);
    });

    patrolWidgetTest('NO markers at all when nothing is logged', ($) async {
      await mount($);
      await $('Diet').tap();
      await $.pumpAndSettle();
      expect($(RegExp(r'of 2 logged')).exists, false);
    });

    patrolWidgetTest("the coach's MACROS for each meal, summed", ($) async {
      await mount($);
      await $('Diet').tap();
      await $.pumpAndSettle();
      // Served on every plan item and previously summed nowhere.
      expect($(RegExp(r'g P')).exists, true);
    });
  });
}
