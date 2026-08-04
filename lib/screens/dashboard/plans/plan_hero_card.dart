import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/glass_card.dart';
import 'plan_segmented_control.dart';

/// One fact about an assigned plan, ready to render.
///
/// A record rather than free-form widgets so the hero card cannot grow a row
/// whose value was assembled inline from something the backend never served —
/// which is exactly how `Duration: 'Ongoing'` and a bundled stock photo ended
/// up on the old screen presented as the member's own plan data.
typedef PlanFact = ({IconData icon, String label, String value});

/// THE ASSIGNED-PLAN HERO CARD — "my coach assigned this".
///
/// Shared by both tabs so a workout plan and a diet plan cannot describe
/// themselves in two different visual languages; the accent is the only
/// difference, and it comes from [PlanSegmentedControl.fillFor].
///
/// **Every row is caller-supplied and every row is backed.** The card has no
/// opinion about difficulty, duration, frequency, start date or a hero image,
/// because `getMyTraining` serves none of those — see
/// `MY_PLANS_FIELD_INVENTORY.md`. It renders what it is given and nothing else.
class PlanHeroCard extends StatelessWidget {
  final PlanTab tab;

  /// The plan's own name, e.g. "Workout Plan 11".
  final String planName;

  /// Who prescribed it, and for which organization. Either may be empty.
  final String coachName;
  final String orgName;

  /// One line about TODAY, e.g. "Rest day" or "3 exercises". Never invented:
  /// the caller passes null when the backend said nothing.
  final String? todayLine;

  /// Backed facts only. See [PlanFact].
  final List<PlanFact> facts;

  /// The single primary action. Label changes with completion state.
  final String ctaLabel;
  final IconData ctaIcon;

  /// Null disables the CTA (e.g. a rest day with nothing to start).
  final VoidCallback? onCta;

  /// True once today's work is done — flips the CTA to a calm confirmation
  /// rather than a call to action.
  final bool completedToday;

  const PlanHeroCard({
    super.key,
    required this.tab,
    required this.planName,
    required this.coachName,
    required this.orgName,
    required this.facts,
    required this.ctaLabel,
    required this.ctaIcon,
    required this.onCta,
    this.todayLine,
    this.completedToday = false,
  });

  static const Color _done = Color(0xFF2EBD59);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final accent = PlanSegmentedControl.fillFor(tab);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: glassCard(p, radius: 20).copyWith(
        // A hairline of the tab's colour, so the card belongs to the tab that
        // opened it without shouting.
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  tab == PlanTab.workout
                      ? Icons.fitness_center_rounded
                      : Icons.restaurant_rounded,
                  color: accent,
                  size: 21,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ASSIGNED BY YOUR COACH',
                      style: AppText.label(size: 10).copyWith(
                        color: accent,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      planName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.cardTitle(size: 18)
                          .copyWith(color: p.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_attribution.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.person_outline_rounded,
                    size: 14, color: p.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _attribution,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(size: 12.5)
                        .copyWith(color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          if (todayLine != null && todayLine!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: (completedToday ? _done : accent)
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    completedToday
                        ? Icons.check_circle_rounded
                        : Icons.today_rounded,
                    size: 15,
                    color: completedToday ? _done : accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      todayLine!,
                      style: AppText.body(size: 12.5)
                          .copyWith(color: p.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [for (final f in facts) _fact(p, f)],
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: _cta(p, accent),
          ),
        ],
      ),
    );
  }

  /// "ORG Name · Coach Name", collapsing cleanly when either is missing.
  String get _attribution {
    final parts = [orgName.trim(), coachName.trim()]
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.join('  ·  ');
  }

  Widget _cta(AppPalette p, Color accent) {
    if (completedToday) {
      // NOT a button styled green — a statement. There is nothing left to do,
      // so offering a primary action would be inviting a pointless tap.
      return Container(
        decoration: BoxDecoration(
          color: _done.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _done.withValues(alpha: 0.42)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_rounded, color: _done, size: 19),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                ctaLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(size: 14.5).copyWith(color: _done),
              ),
            ),
          ],
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: onCta,
      icon: Icon(ctaIcon, size: 19, color: Colors.white),
      label: Text(
        ctaLabel,
        style: AppText.label(size: 14.5).copyWith(color: Colors.white),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        disabledBackgroundColor: p.isDark
            ? Colors.white.withValues(alpha: 0.07)
            : const Color(0xFFE8EBF0),
        disabledForegroundColor: p.textMuted,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  Widget _fact(AppPalette p, PlanFact f) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: p.isDark
              ? Colors.white.withValues(alpha: 0.04)
              : const Color(0xFFF4F6FA),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(f.icon, size: 13, color: p.textMuted),
            const SizedBox(width: 7),
            // Both halves shrink rather than overflow. A Wrap hands its child
            // the full line width as a MAX, so `Flexible` here resolves to
            // min(content, available) — which is what stops a long fact chip
            // from running off a 320dp screen at 2.0x text.
            Flexible(
              child: Text(
                '${f.label}  ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(size: 11).copyWith(color: p.textMuted),
              ),
            ),
            Flexible(
              child: Text(
                f.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(size: 12).copyWith(color: p.textPrimary),
              ),
            ),
          ],
        ),
      );

}
