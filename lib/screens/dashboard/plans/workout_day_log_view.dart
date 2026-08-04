import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/domain/workout_history.dart';
import '../../../core/domain/workout_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/glass_card.dart';

/// ONE DAY'S WORKOUT, EXACTLY AS IT WAS LOGGED.
///
/// Renders a single `client_workout_sessions` document: the plan it belonged
/// to, every exercise, every set, the reps and weight prescribed and the reps
/// and weight performed, the prescribed rest, the session's duration, its
/// volume, its completion, and any note attached to it.
///
/// ── THE RULE THIS WIDGET IS BUILT AROUND ──────────────────────────────────
///
/// **Nothing here is computed to fill a gap.** Every string comes from a field
/// on that document, or from `computeSessionStats` over its own sets. A
/// dimension the coach left blank is absent. A set that was never reached shows
/// its target and no result — never a dash, which reads as "recorded nothing"
/// when the truth is "not reached". A session with no recorded clock states no
/// duration rather than "0m". A bodyweight session states no volume rather
/// than "0 kg".
///
/// The one number on this screen nobody measured — the calorie estimate — is
/// deliberately NOT here. It belongs to the completion card, where it can be
/// explained in a sentence; a history entry is a record, and a record should
/// contain only what was recorded.
class WorkoutDayLogView extends StatelessWidget {
  final WorkoutDayLog log;

  /// Today, injected so the "left unfinished" derivation is testable without
  /// waiting for tomorrow.
  final DateTime today;

  /// Opens the editor. Null for a day that is not editable — see the caller.
  final VoidCallback? onEdit;

  const WorkoutDayLogView({
    super.key,
    required this.log,
    required this.today,
    this.onEdit,
  });

  static const Color _done = Color(0xFF2EBD59);
  static const Color _skip = Color(0xFFE0A106);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final stats = log.stats;
    final abandoned = log.wasAbandonedOn(today);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _summary(p, stats, abandoned),
        if (log.memberNote.isNotEmpty) ...[
          const SizedBox(height: 12),
          _note(
            p,
            // The member's own message, attached to this session and read by
            // their coach beside the sets it refers to.
            label: 'YOUR NOTE',
            body: log.memberNote,
            icon: Icons.chat_bubble_outline_rounded,
          ),
        ],
        const SizedBox(height: 16),
        Text('EXERCISES',
            style: AppText.label(size: 11)
                .copyWith(color: p.textMuted, letterSpacing: 1.0)),
        const SizedBox(height: 10),
        if (log.exercises.isEmpty)
          _empty(p)
        else
          for (final ex in log.exercises) _exercise(p, ex),
        if (onEdit != null) ...[
          const SizedBox(height: 6),
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
    );
  }

  Widget _summary(AppPalette p, SessionStats stats, bool abandoned) {
    final accent = stats.isComplete ? _done : p.accent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: glassCard(p, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  // The plan name STORED ON THE SESSION, not the plan the
                  // member happens to be on today: a session logged under
                  // "Push Day" in March must not be relabelled because the
                  // coach has since assigned "Upper A".
                  log.planName.isEmpty ? 'Workout' : log.planName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.cardTitle(size: 15)
                      .copyWith(color: p.textPrimary),
                ),
              ),
              const SizedBox(width: 8),
              Text('${stats.progressPercent}%',
                  style: AppText.display(size: 22).copyWith(color: accent)),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            _timeLine(abandoned),
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _stat(p, 'Sets', '${stats.completedSets}/${stats.totalSets}'),
              if (stats.skippedSets > 0)
                _stat(p, 'Skipped', '${stats.skippedSets}'),
              _stat(p, 'Exercises',
                  '${stats.completedExercises}/${log.exercises.length}'),
              if (log.durationSeconds != null && log.durationSeconds! > 0)
                _stat(p, 'Duration', _duration(log.durationSeconds!)),
              if (stats.hasVolume)
                _stat(p, 'Volume', '${stats.volumeKg.round()} kg'),
              if (stats.targetHitPct != null)
                _stat(p, 'On target',
                    '${(stats.targetHitPct! * 100).round()}%'),
            ],
          ),
        ],
      ),
    );
  }

  /// When the session happened, stated only as precisely as the document
  /// allows. A session with neither a start nor a finish says only its date.
  String _timeLine(bool abandoned) {
    final date = DateFormat('EEEE, d MMMM y').format(log.date);
    if (abandoned) return '$date  ·  left unfinished';
    final started = log.startedAt;
    final finished = log.finishedAt;
    if (started != null && finished != null) {
      return '$date  ·  ${DateFormat('h:mm a').format(started)} – '
          '${DateFormat('h:mm a').format(finished)}';
    }
    if (finished != null) {
      return '$date  ·  finished ${DateFormat('h:mm a').format(finished)}';
    }
    return date;
  }

  Widget _stat(AppPalette p, String label, String value) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppText.body(size: 10.5).copyWith(color: p.textMuted)),
          const SizedBox(height: 1),
          Text(value,
              style: AppText.cardTitle(size: 14).copyWith(color: p.textPrimary)),
        ],
      );

  Widget _exercise(AppPalette p, ExerciseLog ex) {
    final done = ex.sets.where((s) => s.state == SetLogState.completed).length;
    final allDone = !ex.skipped && ex.sets.isNotEmpty && done == ex.sets.length;
    final color = ex.skipped
        ? _skip
        : allDone
            ? _done
            : p.textMuted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: glassCard(p, radius: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                  child: Text(
                    ex.name.isEmpty ? 'Exercise' : ex.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.cardTitle(size: 14)
                        .copyWith(color: p.textPrimary),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  ex.skipped ? 'Skipped' : '$done/${ex.sets.length}',
                  style: AppText.label(size: 12).copyWith(color: color),
                ),
              ],
            ),
            if (ex.skipped && ex.skipReason.isNotEmpty) ...[
              const SizedBox(height: 7),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Text(ex.skipReason,
                    style: AppText.body(size: 12).copyWith(color: p.textMuted)),
              ),
            ],
            // A coach's note on this exercise, when the wire carries one.
            // History is where a member goes to understand a past session, so
            // it is the one surface that must not drop it.
            if (ex.note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: _note(
                  p,
                  label: 'COACH NOTE',
                  body: ex.note,
                  icon: Icons.format_quote_rounded,
                ),
              ),
            ],
            // HISTORY DOES NOT COLLAPSE.
            //
            // Today's section hides finished exercises because its job is to
            // guide a member to their next set. History has no next set: it is
            // a record, and a record the member has to tap eleven times to read
            // is a record that does not answer the question they opened it for.
            if (ex.sets.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (var i = 0; i < ex.sets.length; i++)
                _set(p, i + 1, ex.sets[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _set(AppPalette p, int number, SetLog s) {
    final target = _pair(s.pReps, s.pWeight);
    final actual = _pair(s.actualReps, s.actualWeight);
    final rest = _rest(s.pRest);
    final color = switch (s.state) {
      SetLogState.completed => _done,
      SetLogState.skipped => _skip,
      SetLogState.pending => p.textMuted,
    };

    return Padding(
      padding: const EdgeInsets.only(left: 26, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: Text('Set $number',
                style: AppText.body(size: 11.5).copyWith(color: p.textMuted)),
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
                if (rest.isNotEmpty)
                  Text(rest,
                      style:
                          AppText.body(size: 10.5).copyWith(color: p.textMuted)),
                if (s.edited)
                  Text('edited',
                      style:
                          AppText.body(size: 10.5).copyWith(color: p.textMuted)),
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

  Widget _note(
    AppPalette p, {
    required String label,
    required String body,
    required IconData icon,
  }) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: p.isDark
              ? Colors.white.withValues(alpha: 0.04)
              : const Color(0xFFF5F6F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: p.textMuted),
                const SizedBox(width: 6),
                Text(label,
                    style: AppText.label(size: 10)
                        .copyWith(color: p.textMuted, letterSpacing: 1.0)),
              ],
            ),
            const SizedBox(height: 5),
            Text(body,
                style:
                    AppText.body(size: 12.5).copyWith(color: p.textSecondary)),
          ],
        ),
      );

  Widget _empty(AppPalette p) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: glassCard(p, radius: 14),
        child: Text(
          // A saved session with no readable entries. Rare, and the honest
          // answer is to say so rather than render an empty list that looks
          // like a rendering bug.
          'This session was saved without any exercise detail.',
          textAlign: TextAlign.center,
          style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
        ),
      );

  static String _duration(int seconds) => formatWorkoutDuration(seconds);

  /// "rest 90s" — the same label every other workout surface prints, and the
  /// same reason: `rest` is free text and often a bare number, while every
  /// timer in this app counts it in SECONDS. No digits at all → no label.
  static String _rest(String raw) {
    final m = RegExp(r'\d+').firstMatch(raw);
    return m == null ? '' : 'rest ${m.group(0)}s';
  }

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
