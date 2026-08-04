import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../controllers/progress_analytics_controller.dart';
import '../../../core/analytics/progress_analytics.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_text.dart';

/// The Progress module's shared vocabulary.
///
/// Every section is built from these, so the screen reads as ONE surface rather
/// than eight cards that each invented their own header rhythm, corner radius
/// and touch feedback. The old Progress screen had a private `_card` helper and
/// no shared header at all, which is how a "Progress" title at 24pt ended up
/// beside section titles at 16, 17 and 19.

/// "Met the goal" green — the SAME token the consistency cards, the check-in
/// surface and the Home progress cards already use. A fourth green would make
/// one product look like two.
const Color kProgressGreen = Color(0xFF2EBD59);

/// The amber this app reserves for "needs attention, nothing is broken" — the
/// unfinished-upload banner already uses it.
const Color kProgressAmber = Color(0xFFE0A020);

/// Colour for a direction, in a module where direction is the whole point.
///
/// ⚠️ NEVER use this for WEIGHT. Whether a weight going up is good depends on a
/// goal weight NO collection in this platform stores, so weight movement is
/// rendered in the neutral text colour and described with a word, never a hue.
Color directionColor(AppPalette p, ProgressDirection d) => switch (d) {
  ProgressDirection.improving => kProgressGreen,
  ProgressDirection.declining => kProgressAmber,
  ProgressDirection.steady => p.textSecondary,
  ProgressDirection.unknown => p.textMuted,
};

IconData directionIcon(ProgressDirection d) => switch (d) {
  ProgressDirection.improving => Icons.trending_up_rounded,
  ProgressDirection.declining => Icons.trending_down_rounded,
  ProgressDirection.steady => Icons.trending_flat_rounded,
  ProgressDirection.unknown => Icons.remove_rounded,
};

/// The member-facing word for a direction. The enum name is NEVER rendered.
String directionWord(ProgressDirection d) => switch (d) {
  ProgressDirection.improving => 'improving',
  ProgressDirection.declining => 'slipping',
  ProgressDirection.steady => 'steady',
  ProgressDirection.unknown => 'not enough data',
};

/// The module's card. One radius, one border, one padding rhythm.
class ProgressCard extends StatelessWidget {
  const ProgressCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.accent = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;

  /// Draws the accent border. Reserved for the ONE card that is the answer to
  /// the screen's question; a second accented card makes neither primary.
  final bool accent;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final body = Padding(padding: padding, child: child);
    final decorated = Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.cardR,
        side: BorderSide(
          color: accent ? p.accent.withValues(alpha: .42) : p.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? body
          // InkWell inside Material, never a decorated Container in front of
          // it: painting a background ahead of the Material swallows every
          // splash, which is how the transformation timeline shipped with a
          // primary interaction that gave no feedback at all.
          : InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap!();
              },
              child: body,
            ),
    );
    return decorated;
  }
}

/// A section header: title, optional subtitle, optional trailing action.
class ProgressSectionHeader extends StatelessWidget {
  const ProgressSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppText.title(size: 17).copyWith(color: p.textPrimary),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: AppText.body(size: 12).copyWith(color: p.textMuted),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          // `container: true` so the action is announced as its OWN control.
          // Without it a screen reader reads "Progress, 82%, See all" as one
          // sentence and the button is unreachable as a button.
          Semantics(
            container: true,
            button: true,
            child: TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionLabel!,
                style: AppText.label(size: 12.5).copyWith(color: p.accent),
              ),
            ),
          ),
      ],
    );
  }
}

/// The range selector. Week / Month / 3 Months / Year.
///
/// A fixed set, not a date picker: every option maps to a bounded read, so no
/// selection a member can make turns into an unbounded query.
class ProgressRangeBar extends StatelessWidget {
  const ProgressRangeBar({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ProgressRange value;
  final ValueChanged<ProgressRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      container: true,
      label: 'Time range',
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: p.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.border),
        ),
        child: Row(
          children: [
            for (final r in ProgressRange.values)
              Expanded(
                child: Semantics(
                  container: true,
                  button: true,
                  selected: r == value,
                  label: r.label,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (r == value) return;
                      HapticFeedback.selectionClick();
                      onChanged(r);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      // 40dp of height plus the outer padding clears the 44dp
                      // touch target on the narrowest phone this app supports.
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: r == value ? p.surface : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: r == value ? p.border : Colors.transparent,
                        ),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            r.label,
                            maxLines: 1,
                            style: AppText.label(size: 12).copyWith(
                              color: r == value ? p.textPrimary : p.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One number with its label. The module's atom.
class ProgressStat extends StatelessWidget {
  const ProgressStat({
    super.key,
    required this.value,
    required this.label,
    this.caption,
    this.valueColor,
    this.icon,
  });

  /// Already formatted. A stat NEVER formats its own number — the section owns
  /// the unit, so "82%" and "4,840 kg·reps" cannot disagree about precision.
  final String value;
  final String label;
  final String? caption;
  final Color? valueColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      container: true,
      label: '$label: $value${caption == null ? '' : ', $caption'}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: valueColor ?? p.accent),
                const SizedBox(width: 5),
              ],
              // Flexible + FittedBox: at 2.0x text scale on a 320dp phone a
              // four-across stat band cannot fit its numbers, and a truncated
              // figure is worse than a smaller one.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: AppText.title(
                      size: 20,
                    ).copyWith(color: valueColor ?? p.textPrimary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
          ),
          if (caption != null) ...[
            const SizedBox(height: 1),
            Text(
              caption!,
              style: AppText.body(size: 10.5).copyWith(color: p.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// The "not enough data yet" state for a single metric inside a card.
///
/// It states WHY, because "no data" and "not enough data to be honest about"
/// are different, and only one of them is the member's fault to fix.
class ProgressUnavailable extends StatelessWidget {
  const ProgressUnavailable({
    super.key,
    required this.title,
    required this.reason,
    this.compact = false,
  });

  final String title;
  final String reason;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 10 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppText.label(size: 13).copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            reason,
            style: AppText.body(
              size: 12,
            ).copyWith(color: p.textMuted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// A quiet, honest banner naming the sources that failed.
///
/// It is a BANNER and not a full-screen error on purpose: with five sources, a
/// single failing one must not blank a screen that can still answer most of the
/// member's question. What it must never do is stay silent, which would make a
/// short view look complete.
class ProgressPartialBanner extends StatelessWidget {
  const ProgressPartialBanner({
    super.key,
    required this.sources,
    required this.onRetry,
  });

  final List<String> sources;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final names = sources.length == 1
        ? sources.single
        : '${sources.take(sources.length - 1).join(", ")} and ${sources.last}';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: kProgressAmber.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kProgressAmber.withValues(alpha: .40)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: kProgressAmber, size: 19),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              '$names could not be loaded. Everything else on this screen is '
              'up to date.',
              style: AppText.body(
                size: 12,
              ).copyWith(color: p.textPrimary, height: 1.35),
            ),
          ),
          Semantics(
            container: true,
            button: true,
            child: TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(
                'Retry',
                style: AppText.label(
                  size: 12.5,
                ).copyWith(color: kProgressAmber),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
