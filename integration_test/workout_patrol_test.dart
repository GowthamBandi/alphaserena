import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:patrol/patrol.dart';

import 'package:alphaserena/controllers/training_controller.dart';
import 'package:alphaserena/controllers/workout_history_controller.dart';
import 'package:alphaserena/core/domain/home_workout_card.dart';
import 'package:alphaserena/core/domain/prescription.dart' show ExpectationKind;
import 'package:alphaserena/core/domain/today_expectation.dart';
import 'package:alphaserena/core/domain/workout_history.dart';
import 'package:alphaserena/core/domain/workout_session.dart';
import 'package:alphaserena/core/services/workout_draft_store.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/core/widgets/premium_video_player.dart';
import 'package:alphaserena/screens/dashboard/home/home_workout_card_widget.dart';
import 'package:alphaserena/screens/dashboard/plans/workout_history_screen.dart';
import 'package:alphaserena/screens/dashboard/workout_briefing_screen.dart';
import 'package:alphaserena/screens/dashboard/workout_rest_overlay.dart';
import 'package:alphaserena/screens/dashboard/workout_session_screen.dart';
import 'package:alphaserena/screens/dashboard/workout_summary_screen.dart';

/// PATROL — THE WORKOUT DOMAIN, ON A REAL DEVICE.
///
/// ── HOW THESE JOURNEYS RUN WITHOUT AN ACCOUNT ─────────────────────────────
/// Phone-OTP auth is externally blocked on this Firebase project, so no
/// member session exists on the emulator. These journeys therefore run the
/// REAL screens against a REAL `TrainingController` whose served plan is a
/// deterministic fixture injected after registration (its `Rxn` fields are
/// the same ones `getMyTraining` writes). Every fixture is a shape the
/// backend genuinely serves. No manual setup, no manual data.
///
/// What that buys, honestly stated:
///  • The full guided session — complete/skip/undo sets, skip/unskip
///    exercise, rest timer, back guard, DRAFT RESUME — runs end-to-end on
///    device through the production code paths, including real
///    SharedPreferences persistence.
///  • Remote persistence runs the real code path too, and FAILS (no member is
///    linked) — which is itself a certified state: the failure banner, the
///    Retry, and Finish refusing to discard unsynced work are all asserted.
///  • What can NOT run here: a successful Firestore write (needs a linked
///    member) — so the finish→summary handoff is certified by unit tests plus
///    a direct summary mount, and the save-success path stays covered by the
///    663-test suite.
void main() {
  // ── Boot: deterministic, per test ───────────────────────────────────────
  Future<void> boot() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    Get.reset();
    // One draft slot exists on the device; a leftover from a previous journey
    // would turn "fresh session" tests into resume tests.
    await WorkoutDraftStore().clear();
  }

  /// One served exercise item, exactly as `getMyTraining` shapes it.
  Map<String, dynamic> item(
    String name, {
    List<Map<String, String>> setRows = const [
      {'reps': '10', 'weight': '40', 'rest': ''},
      {'reps': '10', 'weight': '40', 'rest': ''},
    ],
    String muscle = 'Chest',
    String videoUrl = '',
    String instructions = '',
  }) => {
    'name': name,
    'sets': setRows.length,
    'reps': setRows.isEmpty ? '' : setRows.first['reps'],
    'weight': setRows.isEmpty ? '' : setRows.first['weight'],
    'setRows': setRows,
    'videoUrl': videoUrl,
    'instructions': instructions,
    'muscleGroup': muscle,
  };

  /// Registers a real TrainingController and injects the served plan.
  TrainingController plan(
    List<Map<String, dynamic>> items, {
    String name = 'Upper Body',
    String coachNote = '',
  }) {
    final t = Get.isRegistered<TrainingController>()
        ? Get.find<TrainingController>()
        : Get.put(TrainingController());
    t.workout.value = {'name': name, 'items': items};
    if (coachNote.isNotEmpty) {
      t.expectations.value = TodayExpectations(
        date: localDayKey(DateTime.now()),
        workout: ServedExpectation(
          kind: ExpectationKind.required,
          note: coachNote,
          prescribed: true,
        ),
      );
    }
    return t;
  }

  Widget host(Widget home, {double textScale = 1.0, bool dark = true}) =>
      GetMaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: home,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      );

  /// Pumps until [marker] exists — a settle would hang on the boot spinner's
  /// infinite animation. NOTE: in the live on-device binding `pump(Duration)`
  /// advances SIMULATED time, not wall-clock, so the loop must also wait in
  /// real time or it exhausts its tries before an async boot (SharedPreferences
  /// et al.) has had a single wall-clock millisecond to resolve.
  Future<void> pumpUntil(PatrolIntegrationTester $, Finder marker,
      {int tries = 60}) async {
    for (var i = 0; i < tries; i++) {
      if (marker.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await $.tester.pump();
    }
  }

  /// Mounts the session and waits for boot to finish.
  Future<void> mountSession(PatrolIntegrationTester $,
      {double textScale = 1.0}) async {
    await $.tester.pumpWidget(host(
      const WorkoutSessionScreen(),
      textScale: textScale,
    ));
    await pumpUntil($, find.textContaining('Exercise'));
    await $.tester.pump(const Duration(milliseconds: 100));
  }

  Finder inOverlay(Finder f) =>
      find.descendant(of: find.byType(RestOverlay), matching: f);

  // ══ J1/J2 — HAPPY PATH: guided completion ═══════════════════════════════

  patrolTest('guided flow: prefill, complete sets, exercise done, advance',
      ($) async {
    await boot();
    plan([
      item('Bench Press'),
      item('Incline Row', muscle: 'Back'),
    ]);
    await mountSession($);

    // Where am I? Exercise 1 of 2, set 1 of 2, coach target visible.
    expect(find.text('Exercise 1 of 2'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('SET 1 OF 2'), findsOneWidget);
    expect(find.text('10 reps  ×  40 kg'), findsOneWidget);

    // The coach's numbers are PREFILLED — confirming is one tap, not typing.
    expect(find.widgetWithText(TextField, '10'), findsOneWidget);
    expect(find.widgetWithText(TextField, '40'), findsOneWidget);

    await $.tester.tap(find.text('Complete Set 1'));
    await $.tester.pumpAndSettle();
    expect(find.text('SET 2 OF 2'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget); // strip row 1

    await $.tester.tap(find.text('Complete Set 2'));
    await $.tester.pump(const Duration(milliseconds: 500));
    await $.tester.pumpAndSettle();

    // Exercise done card, honest count, one CTA forward.
    expect(find.text('Bench Press done'), findsOneWidget);
    expect(find.text('2 of 2 sets completed'), findsOneWidget);

    await $.tester.tap(find.text('Next Exercise').first);
    await $.tester.pumpAndSettle();
    expect(find.text('Exercise 2 of 2'), findsOneWidget);
    expect(find.text('Incline Row'), findsOneWidget);
  });

  // ══ REST TIMER — wall-clock, pausable, extendable, skippable ════════════

  patrolTest('rest timer: opens on completion, pauses, +30s, skips', ($) async {
    await boot();
    plan([
      item('Squat', setRows: const [
        {'reps': '8', 'weight': '60', 'rest': '60'},
        {'reps': '8', 'weight': '60', 'rest': '60'},
      ]),
    ]);
    await mountSession($);

    await $.tester.tap(find.text('Complete Set 1'));
    await $.tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Rest'), findsOneWidget);
    expect(find.text('Next: Set 2'), findsOneWidget);

    // Pause freezes against the wall clock, and says so.
    await $.tester.tap(inOverlay(find.text('Pause')));
    await $.tester.pump(const Duration(milliseconds: 250));
    expect(find.text('paused'), findsOneWidget);
    expect(inOverlay(find.text('Resume')), findsOneWidget);

    // The member outranks the clock: +30s, then skip entirely.
    await $.tester.tap(inOverlay(find.text('30s')));
    await $.tester.pump(const Duration(milliseconds: 250));

    await $.tester.tap(inOverlay(find.text('Skip')));
    await $.tester.pump(const Duration(milliseconds: 400));
    await $.tester.pumpAndSettle();
    expect(find.text('Rest'), findsNothing);
    expect(find.text('SET 2 OF 2'), findsOneWidget);
  });

  // ══ J27 — RAPID TAPS: the double-complete regression ════════════════════

  patrolTest('a double-tap completes exactly ONE set, never two', ($) async {
    await boot();
    plan([item('Deadlift', setRows: const [
      {'reps': '5', 'weight': '100', 'rest': ''},
      {'reps': '5', 'weight': '100', 'rest': ''},
      {'reps': '5', 'weight': '100', 'rest': ''},
    ])]);
    await mountSession($);

    // No prescribed rest → no overlay barrier → the second tap lands on the
    // NEXT set's freshly-prefilled button. Before the cooldown fix this
    // logged a set that never happened.
    await $.tester.tap(find.text('Complete Set 1'));
    await $.tester.pump(const Duration(milliseconds: 60));
    await $.tester.tap(find.text('Complete Set 2'), warnIfMissed: false);
    await $.tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('SET 2 OF 3'), findsOneWidget);
  });

  // ══ J13 — SKIP A SET ════════════════════════════════════════════════════

  patrolTest('skipping a set is explicit and moves focus on', ($) async {
    await boot();
    plan([item('Press')]);
    await mountSession($);

    await $.tester.tap(find.text('Skip this set'));
    await $.tester.pumpAndSettle();
    expect(find.text('skipped'), findsOneWidget);
    expect(find.text('SET 2 OF 2'), findsOneWidget);
  });

  // ══ UNDO — reopen a completed set; the correction is marked ═════════════

  patrolTest('reopening a completed set marks the re-complete as edited',
      ($) async {
    await boot();
    plan([item('Curl')]);
    await mountSession($);

    await $.tester.tap(find.text('Complete Set 1'));
    await $.tester.pumpAndSettle();

    // Tap the resolved strip row to correct it.
    await $.tester.tap(find.text('Set 1'));
    await $.tester.pumpAndSettle();
    expect(find.text('SET 1 OF 2'), findsOneWidget); // focus returned

    await $.tester.tap(find.text('Complete Set 1'));
    await $.tester.pumpAndSettle();
    // The coach sees the number was revised, not logged live.
    expect(find.text('edited'), findsOneWidget);
  });

  // ══ J12 — SKIP AN EXERCISE, WITH A REASON, THEN UNDO ════════════════════

  patrolTest('skip exercise requires a reason; undo restores it', ($) async {
    await boot();
    plan([item('Lunge', muscle: 'Legs'), item('Row', muscle: 'Back')]);
    await mountSession($);

    await $.tester.tap(find.text('Skip'));
    await $.tester.pumpAndSettle();
    expect(find.text('Skip this exercise?'), findsOneWidget);

    await $.tester.tap(find.text('Out of time'));
    await $.tester.pumpAndSettle();

    // Auto-advanced to the next exercise; go back to see the skip state.
    expect(find.text('Exercise 2 of 2'), findsOneWidget);
    await $.tester.tap(find.text('Prev'));
    await $.tester.pumpAndSettle();
    expect(find.text('Exercise skipped'), findsWidgets);

    await $.tester.ensureVisible(find.text('Undo'));
    await $.tester.pumpAndSettle();
    await $.tester.tap(find.text('Undo'));
    await pumpUntil($, find.text('SET 1 OF 2'));
    await $.tester.pumpAndSettle();
    expect(find.text('SET 1 OF 2'), findsOneWidget); // back in play
  });

  // ══ J26 + J3/J5/J25 — BACK GUARD, SAVE & LEAVE, DRAFT RESUME ════════════

  patrolTest('back is guarded; save & leave; a new mount resumes the draft',
      ($) async {
    await boot();
    plan([item('Bench Press')]);

    // A base page underneath, so leaving has somewhere real to land.
    await $.tester.pumpWidget(host(Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => Get.to(() => const WorkoutSessionScreen()),
            child: const Text('OPEN WORKOUT'),
          ),
        ),
      ),
    )));
    await $.tester.pumpAndSettle();
    await $.tester.tap(find.text('OPEN WORKOUT'));
    await $.tester.pump(const Duration(milliseconds: 400));
    await $.tester.pumpAndSettle();

    await $.tester.tap(find.text('Complete Set 1'));
    await $.tester.pumpAndSettle();

    // Back with meaningful work → guarded.
    await $.tester.pageBack();
    await $.tester.pumpAndSettle();
    expect(find.text('Leave workout?'), findsOneWidget);
    await $.tester.tap(find.text('Keep training'));
    await $.tester.pumpAndSettle();
    expect(find.text('SET 2 OF 2'), findsOneWidget); // still here

    await $.tester.pageBack();
    await $.tester.pumpAndSettle();
    await $.tester.tap(find.text('Save & leave'));
    await $.tester.pumpAndSettle();
    expect(find.text('OPEN WORKOUT'), findsOneWidget); // landed home

    // Re-open: the draft restores the EXACT position — same code path a
    // process kill takes (draft → SharedPreferences → bootstrap).
    await $.tester.tap(find.text('OPEN WORKOUT'));
    await $.tester.pump(const Duration(milliseconds: 400));
    await $.tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsOneWidget); // set 1 kept
    expect(find.text('SET 2 OF 2'), findsOneWidget); // focus restored
  });

  // ══ J6/J7 — PERSISTENCE FAILURE IS HONEST, WORK IS NEVER LOST ═══════════

  patrolTest('a failed save shows the truth and Finish refuses to lose work',
      ($) async {
    await boot();
    plan([item('Press', setRows: const [
      {'reps': '10', 'weight': '40', 'rest': ''},
    ])]);
    await mountSession($);

    await $.tester.tap(find.text('Complete Set 1'));
    await $.tester.pumpAndSettle();

    // No linked member on this device → the remote save genuinely fails.
    // The member is told, offered a Retry, and the work stays on device.
    expect(find.textContaining("Couldn't save your last set"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    // Finish must NOT navigate to a celebratory summary over a failed save.
    await $.tester.tap(find.text('Finish Workout').last);
    await $.tester.pump(const Duration(seconds: 1));
    await $.tester.pumpAndSettle();
    expect(find.text('Workout complete'), findsNothing);
    expect(find.textContaining("Couldn't save"), findsOneWidget);
  });

  // ══ EMPTY / NULL PAYLOAD ════════════════════════════════════════════════

  patrolTest('no served workout is an honest empty state, not a crash',
      ($) async {
    await boot();
    plan(const []);
    await $.tester.pumpWidget(host(const WorkoutSessionScreen()));
    await pumpUntil($, find.text('No workout to start'));
    expect(find.text('No workout to start'), findsOneWidget);
    expect(find.textContaining("hasn't assigned"), findsOneWidget);
  });

  // ══ J14/J28 — 100-EXERCISE STRESS + VERY LONG NAMES ═════════════════════

  patrolTest('100 exercises and very long names hold up', ($) async {
    await boot();
    plan([
      for (var i = 1; i <= 100; i++)
        item(
          i == 1
              ? 'Single-Arm Bulgarian Split Squat with Contralateral '
                  'Kettlebell Front-Rack Hold'
              : 'Exercise $i',
          setRows: const [
            {'reps': '10', 'weight': '', 'rest': ''},
          ],
        ),
    ]);
    await mountSession($);

    expect(find.text('Exercise 1 of 100'), findsOneWidget);
    expect(find.textContaining('Bulgarian Split Squat'), findsOneWidget);

    // Only the current exercise is built — navigation must stay instant.
    for (var i = 0; i < 3; i++) {
      await $.tester.tap(find.text('Skip to next'));
      await $.tester.pump(const Duration(milliseconds: 120));
    }
    await $.tester.pumpAndSettle();
    expect(find.text('Exercise 4 of 100'), findsOneWidget);
  });

  // ══ J15/J16 — SINGLE EXERCISE · SINGLE SET · BODYWEIGHT ═════════════════

  patrolTest('a one-set bodyweight workout reads honestly to the end',
      ($) async {
    await boot();
    plan([
      item('Push-Up', muscle: 'Chest', setRows: const [
        {'reps': '15', 'weight': '', 'rest': ''},
      ]),
    ]);
    await mountSession($);

    // No fabricated "× 0 kg" — the coach's target line is reps alone.
    expect(find.text('15 reps'), findsOneWidget);
    expect(find.textContaining('× 0'), findsNothing);
    expect(find.textContaining('0 kg'), findsNothing);

    await $.tester.tap(find.text('Complete Set 1'));
    await $.tester.pumpAndSettle();
    expect(find.text('Push-Up done'), findsOneWidget);
    expect(find.text('1 of 1 sets completed'), findsOneWidget);
    expect(find.text('Finish Workout'), findsWidgets); // isLast
  });

  // ══ J19 — BRIEFING: FACTS, A VERY LONG COACH NOTE, DRAFT-AWARE CTA ══════

  patrolTest('briefing states real facts, carries a long coach note verbatim',
      ($) async {
    await boot();
    final longNote = 'Deload context for this week: keep every working set '
        'two reps shy of failure, slow the eccentric to a strict three-count, '
        'rest fully between sets even if the gym is busy, and if the left '
        'shoulder pinches at all on pressing, stop that movement and message '
        'me — we will swap it, not push through it. Hydrate before you start.';
    plan(
      [item('Bench Press'), item('Row', muscle: 'Back')],
      name: 'Push Day A',
      coachNote: longNote,
    );

    await $.tester.pumpWidget(host(const WorkoutBriefingScreen()));
    await $.tester.pump(const Duration(milliseconds: 350));
    await $.tester.pumpAndSettle();

    expect(find.text('Push Day A'), findsOneWidget);
    expect(find.text('2'), findsWidgets); // exercises fact
    expect(find.textContaining('≈'), findsOneWidget); // labelled estimate
    expect(find.textContaining('two reps shy of failure'), findsOneWidget);
    expect(find.text('Begin Workout'), findsOneWidget);

    // With a meaningful draft on device, the CTA becomes a resume.
    final draft = WorkoutDraft(
      sessionId: 'ws_probe_${localDayKey(DateTime.now())}',
      dayKey: localDayKey(DateTime.now()),
      planName: 'Push Day A',
      exercises: [
        ExerciseLog(name: 'Bench Press', exerciseId: '', sets: [
          SetLog(
              pReps: '10',
              pWeight: '40',
              pRest: '',
              actualReps: '10',
              actualWeight: '40',
              state: SetLogState.completed),
        ]),
      ],
    );
    await WorkoutDraftStore().save(draft);
    // Tear the tree down first: a second `const WorkoutBriefingScreen()`
    // would REUSE the existing State and never re-run initState's draft
    // check — the classic const-widget test trap.
    await $.tester.pumpWidget(host(const SizedBox.shrink()));
    await $.tester.pump(const Duration(milliseconds: 80));
    await $.tester.pumpWidget(host(WorkoutBriefingScreen(key: UniqueKey())));
    await pumpUntil($, find.text('Resume Workout'));
    await $.tester.pumpAndSettle();
    expect(find.text('Resume Workout'), findsOneWidget);
    expect(find.textContaining('unfinished session'), findsOneWidget);
  });

  // ══ PHASE 5 — SUMMARY: COMPLETE · PARTIAL · QUEUED ══════════════════════

  patrolTest('summary states repository truth for every finish shape',
      ($) async {
    await boot();
    const complete = SessionStats(
      completedSets: 9,
      skippedSets: 0,
      totalSets: 9,
      skippedExercises: 0,
      completedExercises: 3,
      volumeKg: 1840,
      targetHitPct: 0.89,
    );
    await $.tester.pumpWidget(host(const WorkoutSummaryScreen(
      sessionId: 's1',
      planName: 'Upper Body',
      stats: complete,
      durationSeconds: 2712,
    )));
    await $.tester.pumpAndSettle();
    expect(find.text('Workout complete'), findsOneWidget);
    expect(find.text('45 min'), findsOneWidget);
    expect(find.text('9/9'), findsOneWidget);
    expect(find.text('1840 kg'), findsOneWidget);
    expect(find.text('89%'), findsOneWidget);

    // A partial finish earns its real fraction, not a congratulation.
    const partial = SessionStats(
      completedSets: 4,
      skippedSets: 2,
      totalSets: 12,
      skippedExercises: 1,
      completedExercises: 1,
      volumeKg: 0,
      targetHitPct: 1,
    );
    await $.tester.pumpWidget(host(const WorkoutSummaryScreen(
      sessionId: 's2',
      planName: 'Upper Body',
      stats: partial,
    )));
    await $.tester.pumpAndSettle();
    expect(find.text('Workout finished — 33% done'), findsOneWidget);
    expect(find.text('2'), findsWidgets); // sets skipped shown, not hidden
    // No recorded clock → an em dash, never a fabricated 0:00.
    expect(find.text('—'), findsOneWidget);
    // Bodyweight-only volume is ABSENT, not "0 kg of effort".
    expect(find.textContaining('kg'), findsNothing);
  });

  // ══ J9/J10/J11 + PROGRESS LADDER — THE HOME CARD'S TRUTH ════════════════

  patrolTest('home card: progress ladder 22→50→75→99 stays IN PROGRESS, '
      '100 completes', ($) async {
    await boot();
    for (final pct in [22, 50, 75, 99]) {
      await $.tester.pumpWidget(host(Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: HomeWorkoutCardWidget(
            card: HomeWorkoutCard(
              mode: WorkoutCardMode.inProgress,
              title: 'Upper Body',
              progressPercent: pct,
              cta: 'Resume Workout',
            ),
            onPrimary: () {},
          ),
        ),
      )));
      await $.tester.pumpAndSettle();
      expect(find.text('IN PROGRESS'), findsOneWidget);
      expect(find.text('$pct'), findsOneWidget);
      expect(find.text('Resume Workout'), findsWidgets);
      expect(find.text('Start Workout'), findsNothing);
    }

    await $.tester.pumpWidget(host(Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: HomeWorkoutCardWidget(
          card: const HomeWorkoutCard(
            mode: WorkoutCardMode.completed,
            title: 'Upper Body',
            subtitle: 'Completed',
            progressPercent: 100,
            results: [WorkoutResult('Sets', '12/12')],
            cta: 'Review Workout',
            secondaryCta: 'Edit Workout Log',
          ),
          onPrimary: () {},
          onSecondary: () {},
        ),
      ),
    )));
    await $.tester.pumpAndSettle();
    expect(find.text('COMPLETED'), findsOneWidget);
    expect(find.text('Review Workout'), findsWidgets);
  });

  patrolTest('home card: rest, paused and closed-by-skipping days', ($) async {
    await boot();
    await $.tester.pumpWidget(host(Scaffold(
      body: ListView(padding: const EdgeInsets.all(18), children: [
        HomeWorkoutCardWidget(
          card: const HomeWorkoutCard(
            mode: WorkoutCardMode.rest,
            title: 'Rest day',
            subtitle: 'Recovery is part of the program.',
            secondaryCta: 'Train anyway',
          ),
          onSecondary: () {},
        ),
        const SizedBox(height: 14),
        const HomeWorkoutCardWidget(
          card: HomeWorkoutCard(
            mode: WorkoutCardMode.paused,
            title: 'Coaching paused',
            subtitle: 'Nothing counts against you.',
          ),
        ),
        const SizedBox(height: 14),
        HomeWorkoutCardWidget(
          card: const HomeWorkoutCard(
            mode: WorkoutCardMode.closed,
            title: 'Upper Body',
            subtitle: '8 sets skipped',
            progressPercent: 33,
            cta: 'Review Workout',
          ),
          onPrimary: () {},
        ),
      ]),
    )));
    await $.tester.pumpAndSettle();
    expect(find.text('Rest day'), findsOneWidget);
    expect(find.text('Train anyway'), findsOneWidget);
    expect(find.text('Coaching paused'), findsOneWidget);
    expect(find.text('SESSION CLOSED'), findsOneWidget);
    expect(find.text('33'), findsOneWidget);
  });

  // ══ J17/J18 — MEDIA UNAVAILABLE vs BROKEN ═══════════════════════════════

  patrolTest('no video is calm; a broken video fails loudly with Retry',
      ($) async {
    await boot();
    await $.tester.pumpWidget(host(Scaffold(
      body: ListView(padding: const EdgeInsets.all(18), children: const [
        PremiumVideoPlayer(videoUrl: ''),
        SizedBox(height: 16),
        PremiumVideoPlayer(videoUrl: 'not-a-real-url'),
      ]),
    )));
    await $.tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No demo video'), findsOneWidget);
    expect(find.text("Video couldn't load"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  // ══ J20/J21 — ACCESSIBILITY SCALE + LANDSCAPE ═══════════════════════════

  patrolTest('the session survives 1.6x accessibility text', ($) async {
    await boot();
    plan([item('Bench Press')]);
    await mountSession($, textScale: 1.6);
    // One exercise (of two SETS) — the app bar counts exercises.
    expect(find.text('Exercise 1 of 1'), findsOneWidget);
    expect(find.text('Complete Set 1'), findsOneWidget);
    expect($.tester.takeException(), isNull);
  });

  patrolTest('the rest overlay survives a small landscape viewport',
      ($) async {
    await boot();
    plan([item('Squat', setRows: const [
      {'reps': '8', 'weight': '60', 'rest': '90'},
      {'reps': '8', 'weight': '60', 'rest': '90'},
    ])]);
    await mountSession($);
    await $.tester.tap(find.text('Complete Set 1'));
    await $.tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Rest'), findsOneWidget);
    // The overlay is a scrollable column sized off shortestSide — it must
    // not overflow whatever the window is.
    expect($.tester.takeException(), isNull);
    await $.tester.tap(inOverlay(find.text('Skip')));
    await $.tester.pump(const Duration(milliseconds: 400));
    await $.tester.pumpAndSettle();
  });

  // ══ ACTIVE TRAINING TIME, ON REAL HARDWARE ══════════════════════════════
  //
  // "Duration" used to be `finishedAt - startedAt` — pure wall clock, with no
  // pause control anywhere. An interrupted session recorded the whole
  // interruption as training, in the member's history, on Home, as the sole
  // input to the calorie estimate, and in the COACH's app, which renders the
  // same `durationSeconds` field. The audited member's own 3 August session
  // records 2 h 7 m for three sets of ten reps at 12 kg.
  //
  // The arithmetic — the five-minute idle cap, the backwards-clock guard, the
  // real 3 August reconstruction — is pinned exhaustively and deterministically
  // in `test/workout_active_time_test.dart`, because a device test cannot wait
  // five real minutes to cross the cap.
  //
  // What ONLY a device can prove, and what these two cover, is the PLUMBING:
  // that the real screen accrues active time against real wall-clock intervals
  // and real SharedPreferences, and that the total SURVIVES the draft — the
  // same path a killed process, a locked phone and a backgrounded app all take.
  // A regression that reset the total on resume would credit a member only for
  // the work done after their last interruption, which is the opposite error
  // from wall clock and just as wrong.

  patrolTest('active time accrues from real intervals between sets',
      ($) async {
    await boot();
    plan([
      item('Bench Press', setRows: const [
        {'reps': '10', 'weight': '40', 'rest': ''},
        {'reps': '10', 'weight': '40', 'rest': ''},
      ]),
    ]);
    await mountSession($);

    // A fresh session has banked nothing: the FIRST mark closes no interval.
    await $.tester.tap(find.text('Complete Set 1'));
    await $.tester.pump(const Duration(milliseconds: 400));
    await $.tester.pumpAndSettle();
    final afterFirst = await WorkoutDraftStore().load();
    expect(afterFirst, isNotNull);
    expect(afterFirst!.activeMillis, 0,
        reason: 'the first activity mark has no preceding interval to bank');

    // A real wall-clock gap — `pump(Duration)` advances SIMULATED time, so the
    // wait has to be a real one for the accumulator to see anything.
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    await $.tester.tap(find.text('Complete Set 2'));
    await $.tester.pump(const Duration(milliseconds: 400));
    await $.tester.pumpAndSettle();

    final afterSecond = await WorkoutDraftStore().load();
    expect(afterSecond!.activeMillis, greaterThanOrEqualTo(1000),
        reason: 'the interval between the two sets must be banked');
    // And bounded — it cannot have invented time it did not observe.
    expect(afterSecond.activeMillis, lessThan(kMaxIdleGapSeconds * 1000));
  });

  patrolTest('the accumulated total SURVIVES leaving and resuming the session',
      ($) async {
    await boot();
    plan([
      item('Bench Press', setRows: const [
        {'reps': '10', 'weight': '40', 'rest': ''},
        {'reps': '10', 'weight': '40', 'rest': ''},
        {'reps': '10', 'weight': '40', 'rest': ''},
      ]),
    ]);

    await $.tester.pumpWidget(host(Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => Get.to(() => const WorkoutSessionScreen()),
            child: const Text('OPEN WORKOUT'),
          ),
        ),
      ),
    )));
    await $.tester.pumpAndSettle();
    await $.tester.tap(find.text('OPEN WORKOUT'));
    await $.tester.pump(const Duration(milliseconds: 400));
    await $.tester.pumpAndSettle();

    await $.tester.tap(find.text('Complete Set 1'));
    await $.tester.pump(const Duration(milliseconds: 400));
    await $.tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await $.tester.tap(find.text('Complete Set 2'));
    await $.tester.pump(const Duration(milliseconds: 400));
    await $.tester.pumpAndSettle();

    final banked = (await WorkoutDraftStore().load())!.activeMillis;
    expect(banked, greaterThanOrEqualTo(1000));

    // Leave — the same persistence path a process kill takes.
    await $.tester.pageBack();
    await $.tester.pumpAndSettle();
    await $.tester.tap(find.text('Save & leave'));
    await $.tester.pumpAndSettle();
    expect(find.text('OPEN WORKOUT'), findsOneWidget);

    // Away for a while. This interval must NOT be credited: the clock restarts
    // at the next real activity, never at the resume.
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    await $.tester.tap(find.text('OPEN WORKOUT'));
    await $.tester.pump(const Duration(milliseconds: 400));
    await $.tester.pumpAndSettle();

    // Resumed, and the total came back with it.
    final onResume = (await WorkoutDraftStore().load())!.activeMillis;
    expect(onResume, banked,
        reason: 'resuming must restore the total, not restart it');

    // The next set banks only the interval since THAT set — the time spent
    // away from the session is not in the total.
    await $.tester.tap(find.text('Complete Set 3'));
    await $.tester.pump(const Duration(milliseconds: 400));
    await $.tester.pumpAndSettle();

    final afterThird = (await WorkoutDraftStore().load())!.activeMillis;
    expect(afterThird, greaterThanOrEqualTo(banked),
        reason: 'the total only ever grows');
    expect(afterThird - banked, lessThan(1500),
        reason: 'the 1.5s spent AWAY from the session must not be credited');
  });

  // ══ WORKOUT HISTORY — THE TIMELINE CENTRES ON A COLD OPEN ═══════════════
  //
  // The strip is centred by a single post-frame callback fired from
  // `initState`. On a cold open the screen has just CREATED its controller,
  // `isLoading` is true for the whole of that frame, the body is the skeleton,
  // and there is no attached ScrollController for the callback to move — so it
  // returned silently and nothing ever re-centred. And because GetX disposes a
  // route-scoped controller on pop, every entry to History is a cold entry:
  // the strip never centred at all, leaving a member late in the month looking
  // at the 1st while the panel below described the 28th.
  //
  // It survived because both screens have a test group literally named "the
  // timeline centres the day the member came to see" in which every test
  // asserts `selectedIndex` — the SELECTION — and not one reads the OFFSET.
  // This one reads the offset, on real hardware.
  patrolTest('workout history centres the selected day on a cold open',
      ($) async {
    await boot();
    final month = DateTime(2026, 8, 1);
    final controller = _FakeHistory([
      for (var d = 1; d <= 31; d++)
        WorkoutHistoryDay(
          date: DateTime(month.year, month.month, d),
          state: WorkoutDayState.unknown,
        ),
    ]);
    Get.put<WorkoutHistoryController>(controller);
    controller.selectedDay.value = DateTime(2026, 8, 28);

    await $.tester.pumpWidget(host(const WorkoutHistoryScreen()));
    // The production sequence: skeleton first, days after.
    await $.tester.pump();
    controller.isLoading.value = false;
    await $.tester.pumpAndSettle();

    ScrollController? strip;
    for (final l in $.tester.widgetList<ListView>(find.byType(ListView))) {
      if (l.scrollDirection == Axis.horizontal) strip = l.controller;
    }
    expect(strip, isNotNull, reason: 'the day strip must be on screen');
    expect(controller.selectedIndex, 27);
    // Measured at 0.0 before the fix, against a scroll extent of ~1568.
    expect(strip!.offset, greaterThan(1000),
        reason: 'the 28th must be centred, not left at the start of August');
  });
}

/// Overrides only the network read and the composed month — everything below
/// is the REAL controller, so this exercises production code on the device.
class _FakeHistory extends WorkoutHistoryController {
  _FakeHistory(this._days);
  final List<WorkoutHistoryDay> _days;

  @override
  Future<void> load() async {}

  @override
  List<WorkoutHistoryDay> get days => _days;

  @override
  bool get hasPrescription => true;
}
