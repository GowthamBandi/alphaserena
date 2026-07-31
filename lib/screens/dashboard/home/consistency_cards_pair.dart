import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/domain/consistency_pair.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/glass_card.dart';

/// "Done today" green — the same token nutrition and check-in already use.
const Color kLoggedGreen = Color(0xFF2EBD59);

/// Hero tags for the streak → detail transition. Public so the detail screen
/// binds to the same tag without either side guessing a string.
const String kWorkoutStreakHeroTag = 'consistency-streak-workout';
const String kNutritionStreakHeroTag = 'consistency-streak-nutrition';

/// CONSISTENCY ON HOME — two cards, one job each: make a member feel they are
/// someone who trains.
///
/// The version this replaces packed six data points into a 172px column:
/// streak, week rail, week line, a "Today" row with a bar, a "Next" row with a
/// bar, and a status chip. Every number was true and the card read as a
/// dashboard — which is the failure mode this redesign exists to fix. A member
/// glancing at Home is not auditing their adherence; they are asking *am I
/// doing well?* and that question is answered by ONE number and ONE sentence.
///
/// ── WHAT PREMIUM PRODUCTS ACTUALLY DO ──────────────────────────────────────
/// Apple Fitness, Whoop and Garmin all resolve to a single dominant figure per
/// card with everything else subordinate by an order of magnitude. None of them
/// stack two labelled progress bars in a summary tile — bars are for detail
/// views, where a member has opted into reading. The pattern is not the visual
/// style; it is the RATIO: one thing 4× larger than everything near it.
///
/// So: flame · number · unit · one line · seven circles · one affordance.
/// Nothing else earns the space.
class ConsistencyCardsPair extends StatelessWidget {
  final ConsistencyCard workout;
  final ConsistencyCard nutrition;

  /// Null → that card stays inert rather than promising a destination.
  final VoidCallback? onWorkoutTap;
  final VoidCallback? onNutritionTap;

  const ConsistencyCardsPair({
    super.key,
    required this.workout,
    required this.nutrition,
    this.onWorkoutTap,
    this.onNutritionTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _TrackCard(
              card: workout,
              palette: p,
              tint: p.accent,
              icon: Icons.fitness_center_rounded,
              heroTag: kWorkoutStreakHeroTag,
              onTap: onWorkoutTap,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _TrackCard(
              card: nutrition,
              palette: p,
              tint: kLoggedGreen,
              icon: Icons.restaurant_rounded,
              heroTag: kNutritionStreakHeroTag,
              onTap: onNutritionTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackCard extends StatefulWidget {
  final ConsistencyCard card;
  final AppPalette palette;
  final Color tint;
  final IconData icon;
  final String heroTag;
  final VoidCallback? onTap;

  const _TrackCard({
    required this.card,
    required this.palette,
    required this.tint,
    required this.icon,
    required this.heroTag,
    this.onTap,
  });

  @override
  State<_TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<_TrackCard> {
  /// A press scale, not a ripple. A ripple spreads across a 172px card and
  /// reads as a smear; a 2% shrink reads as the card acknowledging the touch —
  /// which is the entire difference between "responsive" and "premium".
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final card = widget.card;
    final tappable = widget.onTap != null;

    return Semantics(
      button: tappable,
      label: tappable
          ? '${card.semanticLabel}. Open full history'
          : card.semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: tappable ? (_) => _setPressed(true) : null,
        onTapCancel: tappable ? () => _setPressed(false) : null,
        onTapUp: tappable ? (_) => _setPressed(false) : null,
        onTap: tappable
            ? () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _pressed ? 0.978 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: Container(
            decoration: glassCard(p, radius: 20),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: card.state == ConsistencyCardState.loading
                ? _skeleton(p)
                : _content(p, card),
          ),
        ),
      ),
    );
  }

  Widget _content(AppPalette p, ConsistencyCard card) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _title(p, card),
        const SizedBox(height: 14),
        _streak(p, card),
        const SizedBox(height: 8),
        _motivation(p, card),
        const SizedBox(height: 16),
        if (card.week.length == 7) _circles(p, card),
        const SizedBox(height: 14),
        if (widget.onTap != null) _tapHint(p),
      ],
    );
  }

  // ── Identity ───────────────────────────────────────────────────────────

  Widget _title(AppPalette p, ConsistencyCard card) => Row(
    children: [
      Icon(widget.icon, size: 13, color: widget.tint),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          card.track == ConsistencyTrack.workout ? 'Workout' : 'Nutrition',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
            color: p.textSecondary,
            fontSize: 12,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );

  // ── The number ─────────────────────────────────────────────────────────

  /// The flame, the figure and its unit. This block is the card: everything
  /// above and below it is subordinate by at least 3×, which is what makes the
  /// eye land here first and makes the streak feel like a possession rather
  /// than a statistic.
  Widget _streak(AppPalette p, ConsistencyCard card) {
    final lit = card.isReal && card.streak > 0;
    return Hero(
      tag: widget.heroTag,
      // The flight is a bare number on a transparent surface, so it reads as
      // the SAME object moving rather than a card morphing into a screen.
      flightShuttleBuilder: (_, _, _, _, _) => Material(
        color: Colors.transparent,
        child: Text(
          card.streakValue,
          style: AppText.title(size: 48)
              .copyWith(color: lit ? widget.tint : p.textMuted, height: 0.9),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    card.streakValue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title(size: 48).copyWith(
                      color: lit ? p.textPrimary : p.textMuted,
                      height: 0.88,
                    ),
                  ),
                ),
                // The flame is EARNED — it lights only for a live streak. A
                // permanently lit icon is decoration, and decoration that
                // looks like status is a small lie told every single day.
                if (lit) ...[
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Icon(
                      Icons.local_fire_department_rounded,
                      size: 19,
                      color: widget.tint,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _unit(card),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                color: p.textMuted,
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _unit(ConsistencyCard card) {
    if (card.weekUnit) {
      return card.streak == 1 ? 'Week on plan' : 'Weeks on plan';
    }
    return 'Day Streak';
  }

  Widget _motivation(AppPalette p, ConsistencyCard card) => SizedBox(
    // Reserved height so a one-line and a two-line message do not change the
    // card's height — two cards side by side must never disagree by a row.
    height: 30,
    child: Text(
      card.motivation,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.poppins(
        color: p.textSecondary,
        fontSize: 11.5,
        height: 1.3,
        fontWeight: FontWeight.w500,
      ),
    ),
  );

  // ── The week ───────────────────────────────────────────────────────────

  /// Seven circles, this week only.
  ///
  /// Home draws them at LOW fidelity on purpose — filled for done, a soft dot
  /// for a day the coach did not ask for, a ring for everything else. A glance
  /// should answer "how is my week going", not "what exactly happened on
  /// Tuesday"; that question has a whole screen one tap away.
  ///
  /// The one distinction Home keeps is rest-vs-open, because a member who
  /// rested exactly as prescribed must never see the same empty ring as a
  /// member who missed.
  Widget _circles(AppPalette p, ConsistencyCard card) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      for (var i = 0; i < 7; i++)
        _circle(p, card.week[i], isToday: i == card.todayIndex),
    ],
  );

  Widget _circle(AppPalette p, TodayMark m, {required bool isToday}) {
    final done = m == TodayMark.done;
    final notAsked = m == TodayMark.rest ||
        m == TodayMark.excused ||
        m == TodayMark.paused;
    final faint = m == TodayMark.future || m == TodayMark.unknown;

    return Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? widget.tint
            : (notAsked ? p.textMuted.withValues(alpha: 0.28) : null),
        border: done || notAsked
            ? null
            : Border.all(
                color: p.textMuted.withValues(alpha: faint ? 0.22 : 0.45),
                width: isToday ? 2 : 1.3,
              ),
      ),
      // Today, unlogged, gets a centre dot so the eye finds the day that can
      // still be acted on without needing a colour to say so.
      child: isToday && !done && !notAsked
          ? Center(
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.tint,
                ),
              ),
            )
          : null,
    );
  }

  // ── The affordance ─────────────────────────────────────────────────────

  Widget _tapHint(AppPalette p) => Row(
    children: [
      Text(
        'Tap to view',
        style: GoogleFonts.poppins(
          color: p.textMuted,
          fontSize: 10.5,
          height: 1.2,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(width: 2),
      Icon(Icons.arrow_forward_rounded, size: 11, color: p.textMuted),
    ],
  );

  Widget _skeleton(AppPalette p) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      _bar(p, 62, 12),
      const SizedBox(height: 16),
      _bar(p, 54, 34),
      const SizedBox(height: 10),
      _bar(p, double.infinity, 11),
      const SizedBox(height: 6),
      _bar(p, 88, 11),
      const SizedBox(height: 18),
      _bar(p, double.infinity, 13),
      const SizedBox(height: 18),
      _bar(p, 66, 10),
    ],
  );

  Widget _bar(AppPalette p, double w, double h) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: p.surfaceAlt,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}
