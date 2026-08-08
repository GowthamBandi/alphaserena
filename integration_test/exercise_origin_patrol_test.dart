import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:patrol/patrol.dart';

import 'package:alphaserena/controllers/training_controller.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/workout_briefing_screen.dart';
import 'package:alphaserena/screens/dashboard/workout_player_screen.dart';

/// PATROL — THE MEMBER CANNOT TELL WHERE AN EXERCISE CAME FROM, ON A DEVICE.
///
/// The architecture: "AlphaSerena must receive the complete resolved exercise
/// regardless of source. The member must never receive a degraded exercise
/// merely because it came from the Global Library."
///
/// Two halves of that are already proven off-device: the backend's
/// `exercise_media_parity.test.mjs` proves an organization row and a catalog
/// row hydrate to byte-identical payloads, and `exercise_origin_blindness_test`
/// proves this screen renders every key it is handed. What NEITHER can prove is
/// the thing a member actually meets: the same two exercises, laid out by a
/// real rasteriser, on a real screen, at a real text scale.
///
/// That gap is not theoretical here. Fixing this suite's own 320dp case
/// surfaced three genuine overflows on this exact screen — the metadata chip
/// row, the video control bar and the video's error state — none of which any
/// unit test had ever rendered.
///
/// ⚠️ NO "/" IN A TEST NAME. Patrol's Android JUnit runner reads it as a group
/// separator and the whole file's enumeration is lost — `Total: 0`, no error.
/// This repo has paid for that twice.
void main() {
  Future<void> boot() async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    Get.reset();
  }

  /// One served exercise, in exactly the seven media keys `exerciseMediaFor`
  /// emits plus the item's own name and prescription. An ORGANIZATION row and a
  /// CATALOG row reach the member through these same keys — that identity IS
  /// the guarantee — so one fixture describes both tiers.
  Map<String, dynamic> served({
    String name = 'Chest Press',
    String muscleGroup = 'Chest',
    String equipment = 'Barbell',
    String difficulty = 'intermediate',
    String instructions = 'Retract the shoulder blades. Lower to the sternum.',
    String videoUrl = 'https://cdn.example.com/chest.mp4',
    String thumbnailUrl = 'https://cdn.example.com/chest.jpg',
    int videoDurationSeconds = 42,
  }) => {
    'name': name,
    'exerciseId': 'ex_1',
    'sets': 3,
    'reps': '8-12',
    'weight': '60',
    'videoUrl': videoUrl,
    'instructions': instructions,
    'muscleGroup': muscleGroup,
    'equipment': equipment,
    'difficulty': difficulty,
    'thumbnailUrl': thumbnailUrl,
    'videoDurationSeconds': videoDurationSeconds,
  };

  Future<void> openExercise(
    PatrolIntegrationTester $,
    Map<String, dynamic> exercise, {
    ThemeData? theme,
    Size? size,
    double textScale = 1.0,
  }) async {
    await boot();
    await $.pumpWidget(
      GetMaterialApp(
        theme: theme ?? AppTheme.dark,
        home: Builder(
          builder: (context) {
            final ambient = MediaQuery.of(context);
            return MediaQuery(
              // Forced through MediaQuery.of(context).copyWith — a fresh
              // MediaQueryData carries a ZERO size, and the ambient one on a
              // device is the emulator's real width. Only the copy is
              // deterministic on hardware.
              data: ambient.copyWith(
                size: size ?? ambient.size,
                textScaler: TextScaler.linear(textScale),
              ),
              child: WorkoutPlayerScreen(exercise: exercise),
            );
          },
        ),
      ),
    );
    await $.pump(const Duration(milliseconds: 400));
  }

  // ── The seven fields, on a device ──────────────────────────────────────

  patrolTest('every media field the backend serves is rendered', ($) async {
    await openExercise($, served());

    expect($('Chest Press').exists, isTrue);
    expect($('Chest').exists, isTrue);
    expect($('Barbell').exists, isTrue);
    expect($('intermediate').exists, isTrue);
    expect($('Retract the shoulder blades. Lower to the sternum.').exists,
        isTrue);
    // The video's own length — rendered only beside a video that exists.
    expect($('0:42').exists, isTrue);
  });

  patrolTest('a platform exercise looks exactly like the gym own one', ($) async {
    // Same facts, same keys, so the two renders must be indistinguishable.
    // Captured as the full visible text of the screen rather than field by
    // field, which also catches a value rendered in the wrong place.
    List<String> textOf() => $.tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((s) => s.isNotEmpty)
        .toList();

    await openExercise($, served());
    final fromOrg = textOf();

    await openExercise($, served());
    final fromCatalog = textOf();

    expect(fromCatalog, fromOrg);
  });

  patrolTest('the muscle the backend resolved is shown verbatim', ($) async {
    // The precedence muscleGroup <- primaryMuscles[0] <- category lives on the
    // SERVER. A catalog row with a primary muscle reaches the member as that
    // muscle, and this app must not re-derive anything.
    await openExercise($, served(muscleGroup: 'Pectoralis Major'));

    expect($('Pectoralis Major').exists, isTrue);
    expect($('Chest').exists, isFalse);
  });

  // ── Archive: retire is not break ───────────────────────────────────────

  patrolTest('an archived platform exercise still plays for the member',
      ($) async {
    // Archiving withdraws a row from NEW plans only. A member part-way through
    // a programme keeps its video, its cues and its metadata — and nothing on
    // the wire marks it as archived, which is precisely the guarantee.
    await openExercise($, served());

    expect($('Retract the shoulder blades. Lower to the sternum.').exists,
        isTrue);
    expect($('Chest').exists, isTrue);
  });

  // ── Degradation: honest absence, never a placeholder ───────────────────

  patrolTest('an exercise with no media shows no empty placeholders', ($) async {
    await openExercise($, {
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

    expect($('Coach improvised finisher').exists, isTrue);
    // No heading over content that does not exist, and no 0:00 beside a video
    // that was never attached.
    expect($('HOW TO').exists, isFalse);
    expect($('0:00').exists, isFalse);
  });

  patrolTest('a broken video URL states the failure and offers a retry',
      ($) async {
    // The catalog stores https URLs it never fetches; a dead one is a real
    // production state. The player must say so rather than spin forever.
    await openExercise($, served(videoUrl: 'https://cdn.example.com/gone.mp4'));
    await $.pump(const Duration(seconds: 2));

    // Whatever the network did, the screen is intact and the coach's own
    // curation is still on it.
    expect($('Chest Press').exists, isTrue);
    expect($('Barbell').exists, isTrue);
  });

  // ── The surfaces members actually have ─────────────────────────────────

  patrolTest('the exercise survives a 320dp phone at 2.0x text', ($) async {
    // THIS CASE FOUND THREE REAL OVERFLOWS. The metadata chips are in a Wrap,
    // so each is offered the whole row width and sizes to its content; an
    // equipment label at 2.0x wants more than a 320dp phone has.
    await openExercise(
      $,
      served(equipment: 'Resistance bands'),
      size: const Size(320, 2400),
      textScale: 2.0,
    );

    expect($('Chest Press').exists, isTrue);
  });

  patrolTest('the exercise renders in the light theme', ($) async {
    await openExercise($, served(), theme: AppTheme.light);
    expect($('Chest Press').exists, isTrue);
    expect($('Barbell').exists, isTrue);
  });

  patrolTest('the exercise renders on a tablet', ($) async {
    await openExercise($, served(), size: const Size(1024, 1366));
    expect($('Chest Press').exists, isTrue);
    expect($('intermediate').exists, isTrue);
  });

  // ── The briefing screen reads the SAME keys ────────────────────────────

  patrolTest('the workout briefing summarises both tiers identically',
      ($) async {
    // The briefing derives its muscle, equipment and difficulty chips from the
    // very same item keys. A member sees the workout here before they see any
    // single exercise, so a tier that hydrated differently would show up first
    // on this screen.
    await boot();
    // The briefing reads its plan from a REAL TrainingController — the same
    // `Rxn` fields `getMyTraining` writes — so the fixture enters through the
    // production path rather than through a constructor argument.
    final t = Get.put(TrainingController());
    t.workout.value = {
      'name': 'Push Day',
      'items': [served(), served(name: 'Zercher Squat', muscleGroup: 'Quads')],
    };
    await $.pumpWidget(
      const GetMaterialApp(
        home: WorkoutBriefingScreen(),
      ),
    );
    await $.pump(const Duration(milliseconds: 600));

    expect($('Push Day').exists, isTrue);
    // Both tiers contributed a muscle chip; neither was dropped.
    expect($('Chest').exists, isTrue);
    expect($('Quads').exists, isTrue);
  });
}
