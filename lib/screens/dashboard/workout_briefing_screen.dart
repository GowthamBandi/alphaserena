import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/home_controller.dart';
import '../../controllers/performance_controller.dart';
import '../../controllers/training_controller.dart';
import '../../core/domain/today_expectation.dart' show localDayKey;
import '../../core/domain/workout_session.dart';
import '../../core/services/workout_draft_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/gradient_button.dart';
import 'workout_session_screen.dart';

/// THE BRIEFING — the 15 seconds before a workout starts.
///
/// A real coach does not hand you a form; they tell you what today is, why,
/// and what it will take. This screen is that moment: plan, coach's own words
/// for today, what the session contains, what you need, and where it sits in
/// your week — then one button.
///
/// EVERY FIGURE IS REAL OR LABELLED:
///  • coach note = the prescription's note for today (their words, verbatim);
///  • muscles / equipment / difficulty = the exercise library's own metadata
///    (served all along, never shown until now);
///  • week progress = the Prescription Engine's week verdict;
///  • duration is the ONE estimate, and it always wears "≈" plus its basis.
///    Nothing here is invented to fill a slot: absent data is absent.
class WorkoutBriefingScreen extends StatefulWidget {
  const WorkoutBriefingScreen({super.key});

  @override
  State<WorkoutBriefingScreen> createState() => _WorkoutBriefingScreenState();
}

class _WorkoutBriefingScreenState extends State<WorkoutBriefingScreen> {
  final TrainingController _training = Get.isRegistered<TrainingController>()
      ? Get.find<TrainingController>()
      : Get.put(TrainingController());
  final WorkoutDraftStore _drafts = WorkoutDraftStore();

  bool _hasDraft = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkDraft();
  }

  Future<void> _checkDraft() async {
    final draft = await _drafts.load();
    if (!mounted) return;
    setState(() {
      _hasDraft = draft != null &&
          draft.dayKey == localDayKey(DateTime.now()) &&
          hasMeaningfulActivity(draft.exercises);
      _checking = false;
    });
  }

  String get _coachLabel {
    final h = Get.isRegistered<HomeController>()
        ? Get.find<HomeController>()
        : null;
    if (h == null) return 'Your coach';
    return h.hasCoachName ? h.coachName : 'Your coach';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = _training.workoutItems;
    final planName =
        _training.workout.value?['name']?.toString() ?? 'Workout';
    final exercises = exercisesFromServedItems(items);
    final totalSets =
        exercises.fold<int>(0, (sum, e) => sum + e.sets.length);
    final minutes = estimatedMinutes(exercises);
    final muscles =
        distinctLabels(items.map((e) => (e['muscleGroup'] ?? '').toString()));
    final equipment =
        distinctLabels(items.map((e) => (e['equipment'] ?? '').toString()));
    final difficulty =
        distinctLabels(items.map((e) => (e['difficulty'] ?? '').toString()));
    final note = _training.workoutExpectation?.note ?? '';
    // The coach's PLAN description — authored in the TrainerHQ builder since
    // V1 and, until this serving change, delivered to nobody. Distinct from
    // [note], which is the prescription-level message ("deload week"): this
    // is about the PLAN ("focus on slow negatives all block").
    final planDescription =
        (_training.workout.value?['description'] ?? '').toString().trim();

    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        elevation: 0,
        iconTheme: IconThemeData(color: p.textPrimary),
        title: Text("Today's session",
            style: AppText.cardTitle(size: 16).copyWith(color: p.textPrimary)),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  Text(
                    planName,
                    style:
                        AppText.title(size: 26).copyWith(color: p.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Prepared for you by $_coachLabel',
                    style:
                        AppText.body(size: 13).copyWith(color: p.textMuted),
                  ),
                  const SizedBox(height: 16),
                  _facts(p, exercises.length, totalSets, minutes),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _coachNote(p, note),
                  ],
                  if (planDescription.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _planDescription(p, planDescription),
                  ],
                  const SizedBox(height: 14),
                  _weekProgress(p),
                  if (muscles.isNotEmpty || equipment.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _chipsCard(p, muscles, equipment, difficulty),
                  ],
                  const SizedBox(height: 18),
                  Text('WHAT YOU\'LL DO',
                      style: AppText.label(size: 11.5)
                          .copyWith(color: p.textMuted, letterSpacing: 1.6)),
                  const SizedBox(height: 10),
                  _exerciseList(p, exercises, items),
                ],
              ),
            ),
            _bottomBar(p, exercises.isEmpty),
          ],
        ),
      ),
    );
  }

  /// The three facts a member wants before starting. Duration is the only
  /// estimate on the screen and says so.
  Widget _facts(AppPalette p, int exercises, int sets, int? minutes) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: glassCard(p, radius: 16),
      child: Row(
        children: [
          _fact(p, '$exercises', exercises == 1 ? 'exercise' : 'exercises'),
          _divider(p),
          _fact(p, '$sets', sets == 1 ? 'set' : 'sets'),
          _divider(p),
          _fact(
            p,
            minutes == null ? '—' : '≈$minutes',
            minutes == null ? 'duration' : 'min (est.)',
          ),
        ],
      ),
    );
  }

  Widget _fact(AppPalette p, String value, String label) => Expanded(
        child: Column(
          children: [
            Text(value,
                style:
                    AppText.title(size: 20).copyWith(color: p.textPrimary)),
            const SizedBox(height: 2),
            Text(label,
                style: AppText.body(size: 11).copyWith(color: p.textMuted)),
          ],
        ),
      );

  Widget _divider(AppPalette p) =>
      Container(width: 1, height: 28, color: p.border);

  /// The coach's word for today — verbatim, never paraphrased or generated.
  Widget _coachNote(AppPalette p, String note) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: AppRadii.cardR,
        color: p.accent.withValues(alpha: 0.08),
        border: Border.all(color: p.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.format_quote_rounded, size: 18, color: p.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('From $_coachLabel',
                    style: AppText.label(size: 11.5)
                        .copyWith(color: p.accent)),
                const SizedBox(height: 3),
                Text(note,
                    style: AppText.body(size: 13)
                        .copyWith(color: p.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The coach's plan-level description — their own authored words about THIS
  /// plan, rendered verbatim. Quieter treatment than [_coachNote] (the
  /// prescription message), which is the more time-sensitive of the two.
  Widget _planDescription(AppPalette p, String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: glassCard(p, radius: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.notes_rounded, size: 18, color: p.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('About this plan',
                    style:
                        AppText.label(size: 11.5).copyWith(color: p.textMuted)),
                const SizedBox(height: 3),
                Text(text,
                    style: AppText.body(size: 13)
                        .copyWith(color: p.textSecondary, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Where today sits in the coach's week — the Prescription Engine's own
  /// verdict, so it can never disagree with Home or the performance screen.
  Widget _weekProgress(AppPalette p) {
    if (!Get.isRegistered<PerformanceController>()) {
      return const SizedBox.shrink();
    }
    final perf = Get.find<PerformanceController>();
    final w = perf.weekOf(isWorkout: true);
    if (w.unknown || w.paused || w.expected == 0) return const SizedBox.shrink();
    final done = w.done.clamp(0, w.expected);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: glassCard(p, radius: 14),
      child: Row(
        children: [
          Icon(Icons.calendar_month_rounded, size: 17, color: p.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              w.isFrequency
                  ? 'Session ${done + 1} of ${w.expected} this week'
                  : '$done of ${w.expected} days done this week',
              style: AppText.body(size: 12.5).copyWith(color: p.textSecondary),
            ),
          ),
          SizedBox(
            width: 56,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (done / w.expected).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: p.surfaceAlt,
                valueColor: AlwaysStoppedAnimation(p.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipsCard(
    AppPalette p,
    List<String> muscles,
    List<String> equipment,
    List<String> difficulty,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: glassCard(p, radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (muscles.isNotEmpty) ...[
            _chipRowLabel(p, 'You\'ll train'),
            const SizedBox(height: 7),
            _chips(p, muscles, p.accent),
          ],
          if (equipment.isNotEmpty) ...[
            if (muscles.isNotEmpty) const SizedBox(height: 12),
            _chipRowLabel(p, 'You\'ll need'),
            const SizedBox(height: 7),
            _chips(p, equipment, p.textMuted),
          ],
          if (difficulty.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Level: ${difficulty.join(' · ')}',
              style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chipRowLabel(AppPalette p, String text) => Text(
        text,
        style: AppText.label(size: 11.5).copyWith(color: p.textMuted),
      );

  Widget _chips(AppPalette p, List<String> values, Color tint) => Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (final v in values)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: tint.withValues(alpha: 0.10),
                border: Border.all(color: tint.withValues(alpha: 0.32)),
              ),
              child: Text(v,
                  style: AppText.label(size: 11)
                      .copyWith(color: p.textSecondary)),
            ),
        ],
      );

  Widget _exerciseList(
    AppPalette p,
    List<ExerciseLog> exercises,
    List<Map<String, dynamic>> items,
  ) {
    if (exercises.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: glassCard(p, radius: 14),
        child: Text('No exercises in this plan yet.',
            style: AppText.body(size: 13).copyWith(color: p.textMuted)),
      );
    }
    return Container(
      decoration: glassCard(p, radius: 14),
      child: Column(
        children: [
          for (var i = 0; i < exercises.length; i++) ...[
            if (i > 0)
              Divider(height: 1, indent: 46, color: p.border.withValues(alpha: 0.6)),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: Text('${i + 1}',
                        style: AppText.label(size: 13)
                            .copyWith(color: p.textMuted)),
                  ),
                  // The library THUMBNAIL, served since Foundation V2 and
                  // rendered nowhere until now. Absent → no placeholder box;
                  // the row simply stays text-first (nothing fabricated).
                  if (i < items.length &&
                      (items[i]['thumbnailUrl'] ?? '')
                          .toString()
                          .isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: items[i]['thumbnailUrl'].toString(),
                        width: 38,
                        height: 38,
                        fit: BoxFit.cover,
                        // A broken thumbnail vanishes rather than leaving a
                        // broken-image glyph on a premium briefing.
                        errorWidget: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(exercises[i].name,
                            style: AppText.label(size: 13.5)
                                .copyWith(color: p.textPrimary)),
                        if (i < items.length &&
                            (items[i]['muscleGroup'] ?? '')
                                .toString()
                                .isNotEmpty)
                          Text(
                            (items[i]['muscleGroup']).toString(),
                            style: AppText.body(size: 11)
                                .copyWith(color: p.textMuted),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    exercises[i].sets.length == 1
                        ? '1 set'
                        : '${exercises[i].sets.length} sets',
                    style:
                        AppText.body(size: 12).copyWith(color: p.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bottomBar(AppPalette p, bool empty) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_hasDraft && !_checking)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, size: 15, color: p.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You have an unfinished session from today — you\'ll '
                      'resume exactly where you stopped.',
                      style: AppText.body(size: 11.5)
                          .copyWith(color: p.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          GradientButton(
            label: _hasDraft ? 'Resume Workout' : 'Begin Workout',
            showChevron: true,
            onPressed: empty
                ? null
                : () => Get.off(() => const WorkoutSessionScreen()),
          ),
        ],
      ),
    );
  }
}
