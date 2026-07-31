import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/domain/home_workout_card.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/gradient_button.dart';

/// TODAY'S WORKOUT — the execution card.
///
/// The version this replaces led with a 138px artwork banner. It looked
/// expensive and did nothing: a photo answers no question a member has while
/// deciding whether to train, and it pushed the button — the only element on
/// the card that matters — below the fold on a small phone. Atmosphere belongs
/// inside the workout experience, after the member has committed.
///
/// What leads instead is the plan's NAME, set in the display face, because
/// "Upper Body" is the actual answer to "what am I doing today". Underneath it
/// the coach's own words, the four facts that decide whether now is a good
/// time, and one button.
///
/// Pure by design (no controller), so every mode — rest, excused, paused,
/// mid-session, finished, offline — is pinned in a widget test.
class HomeWorkoutCardWidget extends StatelessWidget {
  final HomeWorkoutCard card;

  /// The primary button. Null → it does not render even if the model carries
  /// a label, so a caller can never promise an action it cannot route.
  final VoidCallback? onPrimary;

  /// 'Train anyway' / 'Edit Workout Log'.
  final VoidCallback? onSecondary;

  const HomeWorkoutCardWidget({
    super.key,
    required this.card,
    this.onPrimary,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    final Widget body = switch (card.mode) {
      WorkoutCardMode.loading => _skeleton(p),
      WorkoutCardMode.rest ||
      WorkoutCardMode.excused ||
      WorkoutCardMode.paused ||
      WorkoutCardMode.dormant ||
      WorkoutCardMode.waiting ||
      WorkoutCardMode.unavailable =>
        _statePanel(p),
      _ => _executionPanel(p),
    };

    return Semantics(
      label: card.semanticLabel,
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        decoration: glassCard(p, radius: 20),
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
        child: body,
      ),
    );
  }

  // ══ EXECUTION ════════════════════════════════════════════════════════════

  Widget _executionPanel(AppPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      // Hug the content. A Column defaults to MainAxisSize.max, which makes
      // the card stretch to fill any parent that offers loose height — it
      // survives inside Home's ListView only because unbounded height forces
      // min, and would balloon anywhere else it is reused.
      mainAxisSize: MainAxisSize.min,
      children: [
        _eyebrow(p),
        const SizedBox(height: 7),
        _title(p),
        if (card.subtitle.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            card.subtitle,
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
        ],
        if (card.facts.isNotEmpty) ...[
          const SizedBox(height: 13),
          _facts(p),
        ],
        if (card.coachNote.isNotEmpty) ...[
          const SizedBox(height: 13),
          _coachNote(p),
        ],
        if (card.hasProgress) ...[
          const SizedBox(height: 15),
          _progress(p),
        ],
        if (card.nextUp != null) ...[
          const SizedBox(height: 13),
          _nextUp(p),
        ],
        if (card.results.isNotEmpty) ...[
          const SizedBox(height: 15),
          _results(p),
        ],
        if (card.cta.isNotEmpty && onPrimary != null) ...[
          const SizedBox(height: 16),
          card.isFinished
              ? _outlineButton(p, card.cta, Icons.assignment_outlined,
                  onPrimary!)
              : GradientButton(
                  label: card.cta,
                  showChevron: true,
                  onPressed: onPrimary,
                ),
        ],
        if (card.secondaryCta.isNotEmpty && onSecondary != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: _quietAction(p, card.secondaryCta, onSecondary!),
            ),
          ),
        if (card.disclosure.isNotEmpty) ...[
          const SizedBox(height: 10),
          _disclosure(p),
        ],
      ],
    );
  }

  /// The one label on the card. It changes with state so the member never has
  /// to work out which of three cards they are looking at.
  Widget _eyebrow(AppPalette p) {
    final (String text, Color tint) = switch (card.mode) {
      WorkoutCardMode.inProgress => ('IN PROGRESS', p.accent),
      WorkoutCardMode.completed => ('COMPLETED', p.success),
      WorkoutCardMode.closed => ('SESSION CLOSED', p.textMuted),
      _ => ("TODAY'S WORKOUT", p.accent),
    };
    return Row(
      children: [
        Container(width: 3, height: 12, color: tint),
        const SizedBox(width: 7),
        Text(
          text,
          style: GoogleFonts.poppins(
            color: tint,
            fontSize: 9.5,
            height: 1.2,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  /// The plan name in the display face — the largest thing on the card,
  /// because it is the actual answer to "what am I doing today".
  Widget _title(AppPalette p) => Text(
    card.title,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: AppText.title(size: 27).copyWith(
      color: p.textPrimary,
      height: 1.05,
    ),
  );

  Widget _facts(AppPalette p) => Wrap(
    spacing: 7,
    runSpacing: 7,
    children: [
      for (final f in card.facts)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: p.surfaceAlt.withValues(alpha: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_factIcon(f.kind), size: 12, color: p.textMuted),
              const SizedBox(width: 5),
              Text(
                f.label,
                style: GoogleFonts.poppins(
                  color: p.textSecondary,
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
    ],
  );

  static IconData _factIcon(String kind) => switch (kind) {
    'exercises' => Icons.format_list_numbered_rounded,
    'duration' => Icons.schedule_rounded,
    'difficulty' => Icons.signal_cellular_alt_rounded,
    'equipment' => Icons.fitness_center_rounded,
    _ => Icons.info_outline_rounded,
  };

  /// The coach's words, verbatim and visibly theirs. The single
  /// highest-value element on the card: the only place a member hears their
  /// coach before tapping anything, and the reason the session reads as
  /// prepared rather than generated.
  Widget _coachNote(AppPalette p) => Container(
    padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(11),
      color: p.accent.withValues(alpha: 0.07),
      border: Border(left: BorderSide(color: p.accent, width: 2.5)),
    ),
    child: Text(
      card.coachNote,
      style: AppText.body(size: 12.5)
          .copyWith(color: p.textPrimary, height: 1.4),
    ),
  );

  /// The percentage and the bar, from SessionStats and nothing else.
  Widget _progress(AppPalette p) {
    final finished = card.mode == WorkoutCardMode.completed;
    final tint = finished ? p.success : p.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Larger than the plan name (27pt) BY DESIGN: mid-session the
            // percentage is the headline and the plan name is context. Two
            // near-identical sizes on one card read as indecision.
            Text(
              '${card.progressPercent}',
              style: AppText.title(size: 34)
                  .copyWith(color: tint, height: 0.9),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 3, left: 1),
              child: Text(
                '%',
                style: GoogleFonts.poppins(
                  color: tint,
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),
            if (card.results.isEmpty)
              Text(
                'of today\'s sets',
                style:
                    AppText.body(size: 10.5).copyWith(color: p.textMuted),
              ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: card.progressFraction,
            minHeight: 6,
            backgroundColor: p.surfaceAlt,
            valueColor: AlwaysStoppedAnimation(tint),
          ),
        ),
      ],
    );
  }

  /// THE resume answer. A percentage tells a member they are behind; this
  /// tells them what to pick up. It is the difference between a status and a
  /// coach.
  Widget _nextUp(AppPalette p) {
    final n = card.nextUp!;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: p.surfaceAlt.withValues(alpha: 0.65),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.play_circle_fill_rounded, size: 30, color: p.accent),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NEXT EXERCISE',
                  style: GoogleFonts.poppins(
                    color: p.textMuted,
                    fontSize: 8.5,
                    height: 1.2,
                    letterSpacing: 0.9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  n.exerciseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(size: 14.5)
                      .copyWith(color: p.textPrimary, height: 1.2),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    'Set ${n.setNumber} of ${n.totalSets}',
                    if (n.targetLine.isNotEmpty) n.targetLine,
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A finished session's four figures. Stated flatly — a completed workout
  /// needs no celebration graphics; the numbers are the reward.
  Widget _results(AppPalette p) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      color: p.surfaceAlt.withValues(alpha: 0.55),
    ),
    child: Row(
      children: [
        for (var i = 0; i < card.results.length; i++) ...[
          if (i > 0)
            Container(width: 1, height: 24, color: p.border),
          Expanded(
            child: Column(
              children: [
                Text(
                  card.results[i].value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(size: 14.5)
                      .copyWith(color: p.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  card.results[i].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: p.textMuted,
                    fontSize: 9,
                    height: 1.2,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  Widget _disclosure(AppPalette p) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.info_outline_rounded, size: 12, color: p.textMuted),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          card.disclosure,
          style: AppText.body(size: 10.5).copyWith(color: p.textMuted),
        ),
      ),
    ],
  );

  // ══ A DAY THE COACH DID NOT ASK FOR ══════════════════════════════════════

  IconData get _stateIcon => switch (card.mode) {
    WorkoutCardMode.rest => Icons.self_improvement_rounded,
    WorkoutCardMode.excused => Icons.verified_user_rounded,
    WorkoutCardMode.paused => Icons.pause_circle_outline_rounded,
    WorkoutCardMode.unavailable => Icons.cloud_off_rounded,
    WorkoutCardMode.waiting => Icons.hourglass_empty_rounded,
    _ => Icons.event_available_rounded,
  };

  Widget _statePanel(AppPalette p) {
    // Excused is the one calm state with a positive tint: the coach did
    // something FOR the member, and that should feel like care, not absence.
    final tint =
        card.mode == WorkoutCardMode.excused ? p.success : p.textMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tint.withValues(alpha: 0.10),
                border: Border.all(color: tint.withValues(alpha: 0.28)),
              ),
              child: Icon(_stateIcon, size: 19, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    style: GoogleFonts.poppins(
                      color: p.textPrimary,
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    card.subtitle,
                    style: AppText.body(size: 12.5)
                        .copyWith(color: p.textMuted, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
        // The offer sits under the state and stays quiet: on a rest day the
        // plan IS to rest, and a full-width red button would argue with the
        // coach who wrote it.
        if (card.secondaryCta.isNotEmpty && onSecondary != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 44),
            child: _quietAction(p, card.secondaryCta, onSecondary!),
          ),
        if (card.cta.isNotEmpty && onPrimary != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _outlineButton(p, card.cta, Icons.refresh_rounded,
                onPrimary!),
          ),
      ],
    );
  }

  // ══ SHARED CONTROLS ══════════════════════════════════════════════════════

  /// The finished-session and retry action. Deliberately NOT the red gradient:
  /// the signature CTA means "train now", and spending it on "look at what you
  /// already did" would devalue it everywhere else in the app.
  Widget _outlineButton(
    AppPalette p,
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: p.surfaceAlt.withValues(alpha: 0.6),
              border: Border.all(color: p.border),
            ),
            child: SizedBox(
              height: 48,
              width: double.infinity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 17, color: p.textPrimary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label(size: 14)
                          .copyWith(color: p.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _quietAction(AppPalette p, String label, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            // Clears the 44px minimum target once the row is measured.
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppText.label(size: 12.5).copyWith(color: p.accent),
                ),
                const SizedBox(width: 3),
                Icon(Icons.chevron_right_rounded, size: 16, color: p.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ══ LOADING ══════════════════════════════════════════════════════════════

  Widget _skeleton(AppPalette p) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      _bar(p, 96, 10),
      const SizedBox(height: 11),
      _bar(p, 178, 26),
      const SizedBox(height: 13),
      _bar(p, double.infinity, 26),
      const SizedBox(height: 18),
      _bar(p, double.infinity, 56),
    ],
  );

  Widget _bar(AppPalette p, double w, double h) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: p.surfaceAlt,
      borderRadius: BorderRadius.circular(7),
    ),
  );
}
