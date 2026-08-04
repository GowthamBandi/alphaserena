import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';

/// Which half of My Plans the member is looking at.
///
/// An enum rather than an int index: the two tabs carry DIFFERENT accent
/// colours and different semantics, and `_tabIndex == 1` meaning "diet" is the
/// kind of thing that silently inverts during a refactor.
enum PlanTab { workout, diet }

/// THE MY PLANS SEGMENTED CONTROL.
///
/// Replaces the underline "Current Plans / Previous Plans" text tabs, which
/// were a 2px line under a label — no fill, no motion, a tap target as tall as
/// the text, and no indication that the two halves are different KINDS of
/// thing.
///
/// Design decisions worth defending:
///
///  • **The selected colour is the tab's own identity**, not one global accent.
///    Workout is the brand red, Diet is a deep green, and they are the same two
///    colours Home already uses for the workout and nutrition cards. The
///    control therefore teaches the colour language rather than fighting it.
///  • **The slider is a single animated child**, not a cross-fade of two
///    backgrounds, so it physically travels between the halves. A spring
///    (`Curves.easeOutBack`, lightly damped) makes the travel read as direct
///    manipulation.
///  • **Icons are inside the pill**, so the selected tab is legible as a shape
///    from the corner of the eye — the thing an underline can never do.
///  • **56dp tall**, comfortably past the 48dp minimum, and each half is a full
///    half-width tap target rather than a text-sized one.
class PlanSegmentedControl extends StatelessWidget {
  final PlanTab value;
  final ValueChanged<PlanTab> onChanged;

  const PlanSegmentedControl({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// The selected fill for each tab. Deliberately NOT `p.accent` for diet —
  /// nutrition is green everywhere else in this app.
  static const Color workoutFill = Color(0xFFD50000);
  static const Color dietFill = Color(0xFF1B7F3B);

  static Color fillFor(PlanTab tab) =>
      tab == PlanTab.workout ? workoutFill : dietFill;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // The track. Glass over the page rather than a solid block, so the control
    // sits ON the background instead of cutting a hole in it.
    return Semantics(
      container: true,
      label: 'Plan type',
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: p.isDark
              ? Colors.white.withValues(alpha: 0.05)
              : const Color(0xFFF1F3F7),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: p.isDark
                ? Colors.white.withValues(alpha: 0.07)
                : const Color(0xFFE3E7EE),
          ),
        ),
        padding: const EdgeInsets.all(5),
        // MEASURED INSIDE THE PADDING, which is the whole point of it being
        // here rather than wrapping the Container.
        //
        // The slider lives in the Stack's coordinate space — the padded, inside-
        // the-border box. The geometry used to be derived from the control's
        // OUTER width (`half = maxWidth / 2`, `width: half - 5`), which is a
        // different box: narrower by the 5px padding AND the 1px border on each
        // side. The width came out right by luck and the left edge came out
        // right for the FIRST tab only, so the control was flawless on Workout
        // and, on Diet, started 6px too far right and ended at **-1px** — its
        // pill painting over and past the track's own border, with the inset
        // that frames it everywhere else simply gone.
        //
        // Asymmetric by construction, and invisible until the member touches
        // the second tab. Deriving both numbers from the box the slider is
        // actually positioned in removes the class of bug, not just the
        // instance: there is no longer an outer measurement to drift from.
        child: LayoutBuilder(
          builder: (context, inner) {
            final half = inner.maxWidth / 2;
            final selected = value == PlanTab.workout ? 0.0 : half;

            return Stack(
              children: [
                // ── THE SLIDER ────────────────────────────────────────────
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 380),
                  // Decelerating, not springing. `easeOutBack` overshoots its
                  // target by ~10% of the travel — about 17px here — which on
                  // the Diet side threw the pill clean outside the track for
                  // the middle of the animation. The control cannot clip it
                  // away either: clipping would also cut the pill's glow, which
                  // is drawn deliberately outside its bounds. So the spring
                  // lives where it cannot escape — on the icon's scale, below —
                  // and the travel is a clean decelerating slide.
                  curve: Curves.easeOutCubic,
                  left: selected,
                  top: 0,
                  bottom: 0,
                  width: half,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 380),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      color: fillFor(value),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: fillFor(value).withValues(alpha: 0.38),
                          blurRadius: 18,
                          spreadRadius: -2,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                ),
                // ── THE TWO HALVES ────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _Segment(
                        palette: p,
                        selected: value == PlanTab.workout,
                        icon: Icons.fitness_center_rounded,
                        label: 'Workout Plans',
                        onTap: () => onChanged(PlanTab.workout),
                      ),
                    ),
                    Expanded(
                      child: _Segment(
                        palette: p,
                        selected: value == PlanTab.diet,
                        icon: Icons.restaurant_rounded,
                        label: 'Diet Plans',
                        onTap: () => onChanged(PlanTab.diet),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One half of the control.
///
/// A StatefulWidget purely so the half can respond to being HELD. The pill and
/// the icon both animate on selection, but until the finger lifts nothing
/// acknowledged the touch except a ripple — and on a dark glass surface an
/// ink ripple is nearly invisible. A 3% press-scale is the difference between a
/// control that feels connected to your finger and one that feels like a
/// picture of a control.
class _Segment extends StatefulWidget {
  final AppPalette palette;
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _Segment({
    required this.palette,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _pressed = false;

  void _setPressed(bool v) {
    // The SELECTED half does nothing when tapped, so it must not pretend to.
    if (widget.selected || _pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final isSelected = widget.selected;

    return Semantics(
      button: true,
      selected: isSelected,
      label: widget.label,
      container: true,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          // The whole half is the target, not the text.
          onTap: isSelected ? null : widget.onTap,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            scale: _pressed ? 0.97 : 1.0,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 240),
              style: AppText.label(size: 13.5).copyWith(
                color: isSelected ? Colors.white : p.textMuted,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedScale(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    scale: isSelected ? 1.0 : 0.9,
                    child: Icon(
                      widget.icon,
                      size: 17,
                      color: isSelected ? Colors.white : p.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Ellipsize rather than overflow at large OS text scales. A
                  // segmented control that paints a yellow-and-black stripe over
                  // its own name is worse than one that shortens it.
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
}
