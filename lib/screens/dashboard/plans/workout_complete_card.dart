import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/domain/workout_history.dart';
import '../../../core/domain/workout_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/glass_card.dart';

/// THE FINISHED SESSION, ON THE SCREEN THE MEMBER IS ALREADY LOOKING AT.
///
/// ── THE PROBLEM THIS SOLVES ───────────────────────────────────────────────
///
/// Finishing a workout used to make My Plans go quiet. The hero card's CTA
/// turned into the words "Workout complete" with nothing to tap, the section
/// header below it said "Workout complete" a second time, and that was the
/// whole of it: no finishing time, no duration in the eye-line, and — the part
/// members actually asked for — **no way back into the numbers**. The one
/// screen whose job is "what have I completed today?" answered it and then
/// went dead.
///
/// So the completion state becomes a real card: what was done, when it ended,
/// what it cost, and one obvious action.
///
/// ── EVERY FIGURE'S PROVENANCE, STATED ─────────────────────────────────────
///
///  • **Completed at** — the session's own `finishedAt`, and absent entirely
///    when the clock was never recorded. Never `updatedAt`, which moves every
///    time anything is corrected and would re-date a workout the member
///    finished this morning to whenever they last fixed a typo.
///  • **Duration** — the recorded `durationSeconds`. Absent, not "0m", when
///    unknown.
///  • **Volume** — `SessionStats.volumeKg`, Σ(reps × weight) over completed
///    sets, byte-identical to the coach app's `totalVolume`. Absent for
///    bodyweight work, because volume is a LOAD metric and a zero there would
///    read as zero effort.
///  • **Calories** — the only MODELLED number on this card, and the only one
///    with a "≈". Nobody counted them: no sensor, no coach, no member. It is
///    computed from the recorded duration and the member's own body weight by
///    [estimatedWorkoutCalories], and when either is missing it does not
///    render at all rather than being derived from an assumed stranger.
class WorkoutCompleteCard extends StatelessWidget {
  final SessionStats stats;

  /// When the member finished. Null when the session carries no `finishedAt` —
  /// legacy sessions, and sessions the member walked away from.
  final DateTime? finishedAt;

  final int? durationSeconds;

  /// The member's own recorded weight, for the calorie model. Null when they
  /// have never entered one, which is why the calorie tile is conditional.
  final double? bodyWeightKg;

  /// Opens the log editor. Null renders no action — a card that offers an
  /// action it cannot perform is the dead affordance this card replaces.
  final VoidCallback? onEdit;

  /// The session was left `inProgress` and its day has ended. The coach's app
  /// derives exactly this and calls it abandoned; the member's app must not
  /// dress it up as a finish.
  final bool abandoned;

  const WorkoutCompleteCard({
    super.key,
    required this.stats,
    this.finishedAt,
    this.durationSeconds,
    this.bodyWeightKg,
    this.onEdit,
    this.abandoned = false,
  });

  static const Color _done = Color(0xFF2EBD59);

  bool get _isComplete => stats.isComplete;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final accent = _isComplete ? _done : p.accent;
    final calories = estimatedWorkoutCalories(
      durationSeconds: durationSeconds,
      bodyWeightKg: bodyWeightKg,
    );

    final tiles = <({String label, String value, bool estimated})>[
      if (durationSeconds != null && durationSeconds! > 0)
        (
          label: 'Duration',
          value: _duration(durationSeconds!),
          estimated: false
        ),
      if (stats.hasVolume)
        (
          label: 'Volume',
          value: '${stats.volumeKg.round()} kg',
          estimated: false
        ),
      // ON TARGET — THE FIGURE THAT KEEPS THE TICK HONEST.
      //
      // "Workout Complete" answers whether every prescribed set was CLOSED. It
      // says nothing about whether they were closed at the prescribed reps and
      // weight, and those are different questions: a member who was told 10 and
      // managed 6 on half their sets has finished their session and hit 50% of
      // it. The in-progress header has always shown this (`On target`), so
      // dropping it at the exact moment the card turns green and congratulatory
      // meant the one state that most needed a counterweight was the only one
      // without it — the card flattered precisely when it should not.
      //
      // Null when nothing was completed: there is nothing to judge adherence
      // against, and 0% would read as failure rather than absence.
      if (stats.targetHitPct != null)
        (
          label: 'On target',
          value: '${(stats.targetHitPct! * 100).round()}%',
          estimated: false
        ),
      if (calories != null)
        (label: 'Calories', value: '${calories.round()}', estimated: true),
    ];

    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: glassCard(p, radius: 18).copyWith(
          border: Border.all(color: accent.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // The tick is EARNED. A partly-finished session gets a flag,
                // not a check — the same rule the summary screen applies, and
                // the reason a member can trust the tick when they see it.
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    abandoned
                        ? Icons.pause_circle_outline_rounded
                        : _isComplete
                            ? Icons.check_rounded
                            : Icons.flag_rounded,
                    size: 20,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        abandoned
                            ? 'Workout left unfinished'
                            : _isComplete
                                ? 'Workout Complete'
                                : 'Workout finished — '
                                    '${stats.progressPercent}% done',
                        style: AppText.title(size: 19)
                            .copyWith(color: p.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(),
                        style: AppText.body(size: 12.5)
                            .copyWith(color: p.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (tiles.isNotEmpty) ...[
              const SizedBox(height: 16),
              // Wrap, not Row: three tiles at 2.0x accessibility text on a
              // 320dp phone do not fit on one line, and a stat that overflows
              // its own card is worse than one that wraps to the next.
              Wrap(
                spacing: 26,
                runSpacing: 14,
                children: [
                  for (final t in tiles)
                    _tile(p, t.label, t.value, estimated: t.estimated),
                ],
              ),
            ],
            if (calories != null) ...[
              const SizedBox(height: 12),
              _estimateDisclosure(p),
            ],
            if (onEdit != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.textPrimary,
                    side: BorderSide(color: p.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  // The label SHRINKS rather than clipping. Measured: at 2.0x
                  // accessibility text on a 320dp phone "Edit Workout Log"
                  // plus its icon wants 12px more than the card can give, and
                  // a primary action that paints an overflow stripe over its
                  // own name is not a primary action.
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Edit Workout Log',
                        maxLines: 1,
                        style: AppText.label(size: 13.5)
                            .copyWith(color: p.textPrimary)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final at = finishedAt;
    if (abandoned) {
      return '${stats.completedSets} of ${stats.totalSets} sets logged';
    }
    final sets = '${stats.completedSets} of ${stats.totalSets} sets';
    // No `finishedAt` → no claim about when. A session finished before the
    // lifecycle fields existed is old, not mysterious, and inventing a time
    // for it would be the one dishonest number on an otherwise sourced card.
    if (at == null) return sets;
    return 'Completed at ${DateFormat('h:mm a').format(at)}  ·  $sets';
  }

  Widget _tile(
    AppPalette p,
    String label,
    String value, {
    required bool estimated,
  }) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ONE PARAGRAPH, not a Row of two Texts.
          //
          // "Calories" beside "est." in a Row is two boxes that cannot wrap
          // between them, and at 2.0x accessibility text on a 320dp phone the
          // pair overflowed its tile by 12px. A single `Text.rich` is the same
          // two type sizes and wraps like the prose it is.
          Text.rich(
            TextSpan(
              text: label,
              style: AppText.body(size: 11).copyWith(color: p.textMuted),
              children: estimated
                  ? [
                      TextSpan(
                        text: ' est.',
                        style: AppText.body(size: 9.5)
                            .copyWith(color: p.textMuted),
                      ),
                    ]
                  : const [],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            estimated ? '≈$value' : value,
            style: AppText.title(size: 20).copyWith(color: p.textPrimary),
          ),
        ],
      );

  /// The estimate says so, in words, where the number is.
  ///
  /// A "≈" alone is a symbol a member can miss; this card is the one place in
  /// the module showing a figure nobody measured, so it explains itself rather
  /// than relying on punctuation to carry the honesty.
  Widget _estimateDisclosure(AppPalette p) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 12.5, color: p.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Calories are an estimate from this session’s length and '
              'your body weight — not a measurement.',
              style: AppText.body(size: 11).copyWith(color: p.textMuted),
            ),
          ),
        ],
      );

  static String _duration(int seconds) => formatWorkoutDuration(seconds);
}
