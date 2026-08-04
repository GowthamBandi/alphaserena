import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/serena/premium_states.dart';

/// The pieces the two Home progress cards SHARE.
///
/// Nutrition and Lifestyle no longer share a layout — a calorie ring and a
/// tile grid answer different questions and should not be forced into one
/// widget. What they must never differ on is the smaller vocabulary: the
/// header rhythm, the shape of a progress bar, and the way a card
/// acknowledges a touch. Those live here, once.

/// "Done today" green — the same token the consistency cards and check-in use.
const Color kMetGreen = Color(0xFF2EBD59);

/// The horizontal progress bar used by BOTH cards.
///
/// Animated on every change, so a logged meal visibly moves the bar rather
/// than teleporting it. A null progress draws the track ALONE — a bar against
/// no target, or against nothing logged, must not draw a filled sliver.
class MetricBar extends StatelessWidget {
  final double? progress;
  final Color tint;
  final AppPalette palette;
  final double height;

  const MetricBar({
    super.key,
    required this.progress,
    required this.tint,
    required this.palette,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: p.isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : const Color(0xFFE8EBF0),
              ),
            ),
            if (progress != null && progress! > 0)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress!.clamp(0.0, 1.0)),
                duration: kCountUp,
                curve: kCountCurve,
                builder: (context, t, _) => FractionallySizedBox(
                  widthFactor: t.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(height / 2),
                      gradient: LinearGradient(
                        colors: [tint.withValues(alpha: 0.75), tint],
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

/// The shared card header: identity on the left, one optional action on the
/// right.
class ProgressCardHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final AppPalette palette;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  /// Shown at the far right when there is no action — the "this whole card
  /// opens something" affordance.
  final bool showChevron;

  const ProgressCardHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.palette,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.showChevron = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final hasAction = actionLabel != null && onAction != null;
    // At large accessibility sizes the pill alone can be wider than the row it
    // shares with the title. Dropping to an icon would cost the label exactly
    // the member who needs it most, so the action moves to its OWN line
    // instead — the same affordance, still named.
    final stackAction = hasAction && scale > 1.3;

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: p.accent.withValues(alpha: 0.12),
          ),
          child: Icon(icon, size: 16, color: p.accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.cardTitle(size: 14.5)
                    .copyWith(color: p.textPrimary, height: 1.15),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(size: 11.5)
                    .copyWith(color: p.textMuted, height: 1.25),
              ),
            ],
          ),
        ),
        if (hasAction && !stackAction) ...[
          const SizedBox(width: 8),
          Flexible(
            child: ActionPill(
              label: actionLabel!,
              icon: actionIcon,
              palette: p,
              onTap: onAction!,
            ),
          ),
        ] else if (!hasAction && showChevron) ...[
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(Icons.chevron_right_rounded,
                size: 20, color: p.textMuted),
          ),
        ],
      ],
    );

    if (!stackAction) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        const SizedBox(height: 10),
        ActionPill(
          label: actionLabel!,
          icon: actionIcon,
          palette: p,
          onTap: onAction!,
        ),
      ],
    );
  }
}

/// A compact accent pill — the header action. Quieter than a filled button
/// (this is a dashboard, not a form) and louder than a bare text link.
class ActionPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final AppPalette palette;
  final VoidCallback onTap;

  const ActionPill({
    super.key,
    required this.label,
    required this.palette,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: p.accent.withValues(alpha: p.isDark ? 0.16 : 0.10),
              border: Border.all(color: p.accent.withValues(alpha: 0.32)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: p.accent),
                  const SizedBox(width: 3),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label(size: 11.5).copyWith(color: p.accent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A press SCALE, not a ripple.
///
/// A ripple spreads across a full-width card and reads as a smear; a 1.5%
/// shrink reads as the card acknowledging the touch. Same touch language as
/// the consistency pair, so every premium surface on Home behaves alike.
class PressableCard extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  /// Announced by a screen reader in place of the card's contents' own nodes.
  final String? semanticLabel;

  const PressableCard({
    super.key,
    required this.onTap,
    required this.child,
    this.semanticLabel,
  });

  @override
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTapDown: (_) => _set(true),
        onTapCancel: () => _set(false),
        onTapUp: (_) => _set(false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
