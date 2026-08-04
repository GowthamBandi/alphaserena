import 'package:flutter/material.dart';

import '../../../core/domain/workout_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/glass_card.dart';

/// TODAY'S WORKOUT — what the member ACTUALLY performed, set by set.
///
/// The companion to the assigned-plan hero card above it: that card answers
/// "what did my coach ask for", this one answers "what have I done about it".
///
/// ── WHY IT COLLAPSES ──────────────────────────────────────────────────────
/// The first version rendered every exercise with every set always open. On the
/// one-exercise plan it was built against that read fine; on a real 8-exercise
/// session it is a 40-row wall in which the one thing a returning member needs —
/// *where do I continue* — is indistinguishable from everything else.
///
/// So: one card per exercise, collapsed to a status line and a progress bar,
/// and the exercise holding the NEXT SET opens itself. Finished and skipped
/// exercises stay shut, because they are answered. Every card is still tappable,
/// so nothing is hidden — it is ranked.
///
/// **Every value comes from the session document the coach reads.** There is no
/// second computation here: [SessionStats] is passed in from the one engine
/// (`computeSessionStats`), and each row renders `SetLog` fields verbatim. A
/// dimension the coach left blank is absent, never a zero; an unfinished set
/// states its target and no result, never a fabricated one.
class TodayWorkoutSection extends StatefulWidget {
  /// Today's session, exercise by exercise.
  final List<ExerciseLog> exercises;

  /// Computed by the caller from [exercises] with the shared engine, so this
  /// widget cannot introduce a second definition of "done".
  final SessionStats stats;

  /// Recorded session length. Null when the clock was never recorded — the
  /// header then states no duration rather than "0m".
  final int? durationSeconds;

  /// Where the session resumes. Null once nothing is left.
  final NextUp? nextUp;

  /// The SERVED plan items (`getMyTraining`'s `workout.items[]`).
  ///
  /// The session log carries what the member DID; the library facts a coach
  /// curated — muscle group, equipment — live only on the served item, and were
  /// previously shown on the prescription list that this section replaces once a
  /// session exists. Matched by `exerciseId`, which the backend carries end to
  /// end for exactly this purpose, falling back to the name for freehand items.
  /// Empty is fine: every chip is omitted rather than guessed.
  final List<Map<String, dynamic>> items;

  const TodayWorkoutSection({
    super.key,
    required this.exercises,
    required this.stats,
    required this.durationSeconds,
    required this.nextUp,
    this.items = const [],
  });

  static const Color _done = Color(0xFF2EBD59);
  static const Color _skip = Color(0xFFE0A106);

  @override
  State<TodayWorkoutSection> createState() => _TodayWorkoutSectionState();
}

class _TodayWorkoutSectionState extends State<TodayWorkoutSection> {
  /// Exercises the member has explicitly toggled. Anything absent follows the
  /// default rule (open the one that is next), so the section keeps guiding as
  /// sets are logged — but never re-closes a card the member opened themselves.
  final Map<int, bool> _overrides = {};

  bool _isOpen(int index, ExerciseLog ex) {
    final forced = _overrides[index];
    if (forced != null) return forced;
    return index == widget.nextUp?.exerciseIndex;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(p),
        const SizedBox(height: 12),
        for (var i = 0; i < widget.exercises.length; i++)
          _exercise(p, i, widget.exercises[i]),
      ],
    );
  }

  // ── HEADER — the session's own summary ───────────────────────────────────

  Widget _header(AppPalette p) {
    final stats = widget.stats;
    final complete = stats.isComplete;
    final accent = complete ? TodayWorkoutSection._done : p.accent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: glassCard(p, radius: 16).copyWith(
        // A finished session earns a border. It is the one moment this screen
        // is allowed to congratulate rather than instruct.
        border: complete
            ? Border.all(
                color: TodayWorkoutSection._done.withValues(alpha: 0.45))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (complete) ...[
                const Icon(Icons.verified_rounded,
                    size: 20, color: TodayWorkoutSection._done),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  complete
                      ? 'Workout complete'
                      : stats.isFullyResolved
                          ? 'Workout closed'
                          : 'In progress',
                  style:
                      AppText.cardTitle(size: 15).copyWith(color: p.textPrimary),
                ),
              ),
              Text(
                // Floored, from the one engine — 17 of 18 sets never rounds up
                // to a 100% the member did not earn.
                '${stats.progressPercent}%',
                style: AppText.display(size: 22).copyWith(color: accent),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              // Animates from where it was, so logging a set advances the bar
              // rather than snapping it.
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOutCubic,
              tween: Tween(begin: 0, end: stats.progressFraction),
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: p.isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : const Color(0xFFE8EBF0),
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _stat(p, 'Sets', '${stats.completedSets}/${stats.totalSets}'),
              if (stats.skippedSets > 0)
                _stat(p, 'Skipped', '${stats.skippedSets}'),
              _stat(p, 'Exercises',
                  '${stats.completedExercises}/${widget.exercises.length}'),
              if (widget.durationSeconds != null && widget.durationSeconds! > 0)
                _stat(p, 'Duration', _duration(widget.durationSeconds!)),
              // Only when something was completed — there is nothing to judge
              // adherence against otherwise.
              if (stats.targetHitPct != null)
                _stat(p, 'On target',
                    '${(stats.targetHitPct! * 100).round()}%'),
              // Volume is a LOAD metric: zero for bodyweight work, and the
              // coach's weights are free text, so it appears only when the
              // logged numbers actually produced one.
              if (stats.hasVolume)
                _stat(p, 'Volume', '${stats.volumeKg.round()} kg'),
            ],
          ),
          if (widget.nextUp != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                children: [
                  Icon(Icons.play_circle_outline_rounded,
                      size: 15, color: p.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Next: ${widget.nextUp!.exerciseName} · set '
                      '${widget.nextUp!.setNumber} of ${widget.nextUp!.totalSets}'
                      '${widget.nextUp!.targetLine.isEmpty ? '' : ' · ${widget.nextUp!.targetLine}'}',
                      style: AppText.body(size: 12.5)
                          .copyWith(color: p.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(AppPalette p, String label, String value) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppText.body(size: 10.5).copyWith(color: p.textMuted)),
          const SizedBox(height: 1),
          Text(value,
              style:
                  AppText.cardTitle(size: 14).copyWith(color: p.textPrimary)),
        ],
      );

  static String _duration(int seconds) {
    final m = seconds ~/ 60;
    if (m >= 60) return '${m ~/ 60}h ${m % 60}m';
    return m > 0 ? '${m}m' : '${seconds}s';
  }

  /// The served plan item for a logged exercise, or null.
  ///
  /// `exerciseId` first — the referential key the backend carries end to end.
  /// Name is the fallback for freehand/legacy items, which have no id.
  Map<String, dynamic>? _servedFor(ExerciseLog ex) {
    for (final it in widget.items) {
      final id = (it['exerciseId'] ?? '').toString();
      if (ex.exerciseId.isNotEmpty && id == ex.exerciseId) return it;
    }
    for (final it in widget.items) {
      if ((it['name'] ?? '').toString() == ex.name) return it;
    }
    return null;
  }

  // ── ONE EXERCISE ─────────────────────────────────────────────────────────

  Widget _exercise(AppPalette p, int index, ExerciseLog ex) {
    final done = ex.sets.where((s) => s.state == SetLogState.completed).length;
    final total = ex.sets.length;
    final allDone = !ex.skipped && total > 0 && done == total;
    final open = _isOpen(index, ex);
    final isNext = index == widget.nextUp?.exerciseIndex;

    final color = ex.skipped
        ? TodayWorkoutSection._skip
        : allDone
            ? TodayWorkoutSection._done
            : p.textMuted;

    final served = _servedFor(ex);
    final meta = <String>[
      if ((served?['muscleGroup'] ?? '').toString().trim().isNotEmpty)
        served!['muscleGroup'].toString().trim(),
      if ((served?['equipment'] ?? '').toString().trim().isNotEmpty)
        served!['equipment'].toString().trim(),
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: '${ex.name}, '
            '${ex.skipped ? 'skipped' : '$done of $total sets done'}'
            '${open ? '' : '. Tap to expand'}',
        container: true,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _overrides[index] = !open),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: glassCard(p, radius: 14).copyWith(
                // The exercise the member is on is the only one that gets a
                // border. On an 8-exercise session that single cue is the
                // difference between a list and a guide.
                border: isNext && !allDone && !ex.skipped
                    ? Border.all(color: p.accent.withValues(alpha: 0.42))
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        ex.skipped
                            ? Icons.remove_circle_outline_rounded
                            : allDone
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                        size: 17,
                        color: color,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ex.name.isEmpty ? 'Exercise' : ex.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.cardTitle(size: 14)
                                  .copyWith(color: p.textPrimary),
                            ),
                            if (meta.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.body(size: 11.5)
                                    .copyWith(color: p.textMuted),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        ex.skipped ? 'Skipped' : '$done/$total',
                        style: AppText.label(size: 12).copyWith(color: color),
                      ),
                      const SizedBox(width: 4),
                      // Rotates rather than swaps: the same affordance moving,
                      // not two icons trading places.
                      AnimatedRotation(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        turns: open ? 0.5 : 0,
                        child: Icon(Icons.keyboard_arrow_down_rounded,
                            size: 20, color: p.textMuted),
                      ),
                    ],
                  ),
                  // The collapsed card still carries its progress — the member
                  // sees how far through each exercise is without opening it.
                  if (!ex.skipped && total > 0) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: TweenAnimationBuilder<double>(
                        duration: const Duration(milliseconds: 460),
                        curve: Curves.easeOutCubic,
                        tween: Tween(begin: 0, end: done / total),
                        builder: (_, v, _) => LinearProgressIndicator(
                          value: v,
                          minHeight: 4,
                          backgroundColor: p.isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : const Color(0xFFECEFF4),
                          valueColor: AlwaysStoppedAnimation(
                            allDone ? TodayWorkoutSection._done : p.accent,
                          ),
                        ),
                      ),
                    ),
                  ],
                  // The member's own words for a skip, shown whether or not the
                  // card is open — it is one line and it is the coach's next
                  // conversation.
                  if (ex.skipped && ex.skipReason.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 26),
                      child: Text(
                        ex.skipReason,
                        style:
                            AppText.body(size: 12).copyWith(color: p.textMuted),
                      ),
                    ),
                  ],
                  AnimatedSize(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: (open && !ex.skipped && ex.sets.isNotEmpty)
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 12),
                              for (var i = 0; i < ex.sets.length; i++)
                                _set(
                                  p,
                                  i + 1,
                                  ex.sets[i],
                                  isNextSet: isNext &&
                                      widget.nextUp?.setNumber == i + 1,
                                ),
                            ],
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One set: what was asked, what was done. A pending set shows its target and
  /// leaves the result column EMPTY — writing a dash there reads as "recorded
  /// nothing", when the truth is "not reached yet".
  Widget _set(
    AppPalette p,
    int number,
    SetLog s, {
    bool isNextSet = false,
  }) {
    final target = _pair(s.pReps, s.pWeight);
    final actual = _pair(s.actualReps, s.actualWeight);
    final rest = _rest(s.pRest);
    final color = switch (s.state) {
      SetLogState.completed => TodayWorkoutSection._done,
      SetLogState.skipped => TodayWorkoutSection._skip,
      SetLogState.pending => p.textMuted,
    };

    return Container(
      margin: const EdgeInsets.only(left: 26, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: isNextSet
          ? BoxDecoration(
              color: p.accent.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: Text('Set $number',
                style: AppText.body(size: 11.5).copyWith(
                  color: isNextSet ? p.accent : p.textMuted,
                  fontWeight: isNextSet ? FontWeight.w600 : null,
                )),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (target.isNotEmpty)
                  Text(target,
                      style:
                          AppText.body(size: 12).copyWith(color: p.textMuted)),
                if (s.state == SetLogState.completed && actual.isNotEmpty) ...[
                  Icon(Icons.arrow_right_alt_rounded,
                      size: 14, color: p.textMuted),
                  Text(actual,
                      style: AppText.label(size: 12.5)
                          .copyWith(color: p.textPrimary)),
                ],
                // The coach's prescribed rest — served on every setRow and
                // shown nowhere until now.
                if (rest.isNotEmpty)
                  Text(rest,
                      style: AppText.body(size: 10.5)
                          .copyWith(color: p.textMuted)),
                // A member who corrected a set after logging it: honest, and
                // the coach is told so rather than reading it as live data.
                if (s.edited)
                  Text('edited',
                      style: AppText.body(size: 10.5)
                          .copyWith(color: p.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            switch (s.state) {
              SetLogState.completed => Icons.check_rounded,
              SetLogState.skipped => Icons.remove_rounded,
              SetLogState.pending => Icons.circle_outlined,
            },
            size: 14,
            color: color,
          ),
        ],
      ),
    );
  }

  /// "rest 90s" — the same label the session screen prints.
  ///
  /// `setRows[].rest` is a free-text String and is often a bare number. Rest is
  /// SECONDS everywhere in this app — the rest overlay counts the value in
  /// seconds and `workout_session_screen` renders `'rest ${digits}s'` — so a
  /// bare "90" rendered as "rest 90" left the member reading an ambiguous
  /// number that every other surface qualifies. This is not inventing a unit;
  /// it is stating the one the timer already uses. No digits at all → no label.
  static String _rest(String raw) {
    final m = RegExp(r'\d+').firstMatch(raw);
    return m == null ? '' : 'rest ${m.group(0)}s';
  }

  /// "10 reps × 20 kg" — the coach's words verbatim, never parsed into a number
  /// nobody wrote, and never suffixed twice when the weight carries its unit.
  static String _pair(String reps, String weight) {
    final r = reps.trim();
    final w = weight.trim();
    final hasUnit = w.isEmpty || RegExp(r'[a-zA-Z]').hasMatch(w);
    return [
      if (r.isNotEmpty) '$r reps',
      if (w.isNotEmpty) hasUnit ? w : '$w kg',
    ].join(' × ');
  }
}
