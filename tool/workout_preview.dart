// DEV TOOL — not shipped, not referenced by the app.
//
// Renders the workout surfaces with deterministic fixtures on a real device
// so the certification's visual record is a photograph of the production
// widgets with real fonts. Swipe to advance.
//
// Run:  flutter run -t tool/workout_preview.dart -d emulator-5554
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:alphaserena/controllers/training_controller.dart';
import 'package:alphaserena/core/domain/home_workout_card.dart';
import 'package:alphaserena/core/domain/workout_session.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/home/home_workout_card_widget.dart';
import 'package:alphaserena/screens/dashboard/workout_briefing_screen.dart';
import 'package:alphaserena/screens/dashboard/workout_rest_overlay.dart';
import 'package:alphaserena/screens/dashboard/workout_session_screen.dart';
import 'package:alphaserena/screens/dashboard/workout_summary_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final t = Get.put(TrainingController());
  t.workout.value = {
    'name': 'Upper Body',
    'items': [
      {
        'name': 'Bench Press',
        'sets': 3,
        'reps': '10',
        'weight': '40',
        'setRows': [
          {'reps': '10', 'weight': '40', 'rest': '90'},
          {'reps': '10', 'weight': '40', 'rest': '90'},
          {'reps': '8', 'weight': '45', 'rest': '120'},
        ],
        'videoUrl': '',
        'instructions': 'Retract the shoulder blades, control the descent.',
        'muscleGroup': 'Chest',
      },
      {
        'name': 'Incline Row',
        'sets': 3,
        'reps': '12',
        'weight': '30',
        'setRows': [
          {'reps': '12', 'weight': '30', 'rest': '60'},
          {'reps': '12', 'weight': '30', 'rest': '60'},
          {'reps': '12', 'weight': '30', 'rest': '60'},
        ],
        'videoUrl': '',
        'instructions': '',
        'muscleGroup': 'Back',
      },
    ],
  };
  runApp(const _Preview());
}

class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    const completeStats = SessionStats(
      completedSets: 9,
      skippedSets: 0,
      totalSets: 9,
      skippedExercises: 0,
      completedExercises: 3,
      volumeKg: 1840,
      targetHitPct: 0.89,
    );
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: PageView(
        children: [
          const WorkoutSessionScreen(),
          const WorkoutBriefingScreen(),
          Stack(children: [
            Container(color: Colors.black),
            const RestOverlay(
              seconds: 90,
              nextSetNumber: 2,
              accent: Color(0xFFE10600),
              reminder: 'Breathe. Let your heart rate settle before the '
                  'next set.',
            ),
          ]),
          const WorkoutSummaryScreen(
            sessionId: 'preview',
            planName: 'Upper Body',
            stats: completeStats,
            durationSeconds: 2712,
          ),
          Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: HomeWorkoutCardWidget(
                  card: const HomeWorkoutCard(
                    mode: WorkoutCardMode.inProgress,
                    title: 'Upper Body',
                    progressPercent: 44,
                    nextUp: NextUp(
                      exerciseName: 'Incline Row',
                      exerciseIndex: 1,
                      setNumber: 2,
                      totalSets: 3,
                      prescribedReps: '12',
                      prescribedWeight: '30',
                    ),
                    cta: 'Resume Workout',
                  ),
                  onPrimary: _noop,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void _noop() {}
}
