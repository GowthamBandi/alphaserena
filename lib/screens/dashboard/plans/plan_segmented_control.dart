import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

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
/// Design decisions worth defending:
///
///  • **The selected colour is the tab's own identity**, not one global accent.
///    Workout is the brand red, Diet is a deep green, and they are the same two
///    colours Home already uses for the workout and nutrition cards. The
///    control therefore teaches the colour language rather than fighting it.
///  • **The pill is a single travelling child**, not a cross-fade of two
///    backgrounds, so it physically moves between the halves.
///  • **Icons are inside the pill**, so the selected tab is legible as a shape
///    from the corner of the eye — the thing an underline can never do.
///  • **56dp tall at 1.0× and taller with the OS text scale**, comfortably past
///    the 48dp minimum, and each half is a full half-width tap target.
///
/// ── WHY THERE IS NO GEOMETRY ARITHMETIC LEFT ─────────────────────────────
///
/// The previous build positioned the pill with numbers: `half = maxWidth / 2`,
/// `left: 0 | half`, `width: half`. Those numbers were derived from the wrong
/// box once already, which put the pill **1px outside its own track** on the
/// Diet tab and nowhere else — flawless on the first tab, wrong on the second,
/// which is exactly why it survived a 16-test suite and a review. Moving the
/// `LayoutBuilder` inside the padding fixed that instance.
///
/// This build removes the CLASS. `Positioned.fill → AnimatedAlign →
/// FractionallySizedBox(widthFactor: 0.5)` states the same intent —
/// *exactly half the inner box, pinned to one end* — with **no measurement at
/// all**. There is no width to compute, no origin to drift from, and the two
/// positions are mirror images because `centerLeft` and `centerRight` are. A
/// pixel of asymmetry is now unrepresentable rather than merely tested for.
/// (The geometry suite still measures the rendered rectangles at four widths;
/// it just cannot fail any more, which is the point.)
///
/// ── TWO ANIMATIONS, NOT ONE ──────────────────────────────────────────────
///
/// [AnimatedAlign] owns the TRAVEL and [AnimatedContainer] owns only the
/// COLOUR, at different durations, because they are different events. One
/// `AnimatedContainer` doing both blended brand red into deep green across the
/// whole 360 ms slide, and the midpoint of that blend is a muddy brown that
/// belongs to neither tab. The colour now resolves in 200 ms — the pill is
/// already the destination's colour for the back half of its journey — while
/// the travel keeps the long, calm settle that makes the motion read as
/// premium rather than hurried.
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

  /// The base height at 1.0× text. Grows with the OS text scale (see [build]).
  static const double baseHeight = 56;

  /// Inset from the track's outer edge to the pill: 5px of padding plus the
  /// 1px the border draws. Public so the geometry suite states the contract
  /// rather than restating a magic number.
  static const double trackInset = 6;

  /// A long, decelerating settle with **no overshoot** — the curve Linear and
  /// Arc use for exactly this control.
  ///
  /// `easeOutBack`, the previous travel curve, overshoots its target by ~10%
  /// of the travel: on the Diet side that threw the pill clean outside the
  /// track for the middle of the animation, and it cannot be clipped away
  /// because clipping would also cut the pill's glow, which is drawn
  /// deliberately outside its bounds. The spring now lives on the ICON's
  /// scale, where escaping the track is not a thing it can do.
  static const Curve travelCurve = Cubic(0.16, 1, 0.3, 1);
  static const Duration travelDuration = Duration(milliseconds: 360);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // RESPONSIVE HEIGHT, CLAMPED.
    //
    // A fixed 56 clipped its own label at large accessibility text sizes; an
    // unclamped one let the control eat a third of a 320dp screen. 1.35× is
    // where the 17px icon and the label stop fitting on one line.
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.35);
    final selected = value == PlanTab.workout;

    return Semantics(
      container: true,
      label: 'Plan type',
      child: Container(
        height: baseHeight * scale,
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
        padding: const EdgeInsets.all(trackInset - 1),
        child: Stack(
          children: [
            // ── THE PILL ──────────────────────────────────────────────────
            // Exactly half the inner box, pinned to one end. No arithmetic.
            Positioned.fill(
              child: AnimatedAlign(
                duration: travelDuration,
                curve: travelCurve,
                alignment:
                    selected ? Alignment.centerLeft : Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  heightFactor: 1,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    decoration: _pillDecoration(p, fillFor(value)),
                  ),
                ),
              ),
            ),
            // ── THE TWO HALVES ────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _Segment(
                    palette: p,
                    selected: selected,
                    icon: Icons.fitness_center_rounded,
                    // SHORT LABELS, deliberately.
                    //
                    // "Workout Plans" / "Diet Plans" restated the screen title
                    // ("My Plans", two lines above) inside every half, and at
                    // 2.0× accessibility text on a 320dp phone the longer one
                    // ellipsized to "Workou…" — a control painting a truncated
                    // version of its own name. One word per half fits at every
                    // scale this app supports, and the two words are close
                    // enough in width that the halves read as balanced rather
                    // than as one crowded and one empty.
                    label: 'Workout',
                    onTap: () => _select(PlanTab.workout),
                  ),
                ),
                Expanded(
                  child: _Segment(
                    palette: p,
                    selected: !selected,
                    icon: Icons.restaurant_rounded,
                    label: 'Diet',
                    onTap: () => _select(PlanTab.diet),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _select(PlanTab tab) {
    if (tab == value) return;
    // The same tick a native segmented control gives. It fires on the STATE
    // CHANGE, not on touch-down, so a tap that lands on the already-selected
    // half stays silent — buzzing for a no-op teaches the member to distrust
    // the feedback.
    HapticFeedback.selectionClick();
    onChanged(tab);
  }

  /// The pill as a physical object rather than a coloured rectangle.
  ///
  /// Three cues, all subtle enough to be felt rather than seen: a vertical
  /// gradient (light strikes the top), a hairline lit edge, and TWO shadows —
  /// a wide ambient one that lifts the pill off the track and a tight key one
  /// that keeps it anchored to it. A single blurred shadow reads as a glow
  /// (which is what the previous build had, and it made the pill float rather
  /// than sit).
  static BoxDecoration _pillDecoration(AppPalette p, Color fill) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(fill, Colors.white, 0.13)!,
          fill,
        ],
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
      boxShadow: [
        // Ambient — the lift.
        BoxShadow(
          color: fill.withValues(alpha: p.isDark ? 0.34 : 0.28),
          blurRadius: 16,
          spreadRadius: -3,
          offset: const Offset(0, 6),
        ),
        // Key — the contact.
        BoxShadow(
          color: fill.withValues(alpha: 0.22),
          blurRadius: 4,
          spreadRadius: -1,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }
}

/// One half of the control.
///
/// A StatefulWidget purely so the half can respond to being HELD. The pill and
/// the icon both animate on selection, but until the finger lifts nothing
/// acknowledged the touch except a ripple — and on a dark glass surface an
/// ink ripple is nearly invisible. A press-scale is the difference between a
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
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.35);
    // BALANCED SPACING AT EVERY TEXT SIZE. A fixed 8dp gap that stays 8dp while
    // the glyphs beside it grow by a third reads as the icon crowding the word.
    final gap = 8 * scale;
    // Never `textMuted` (#757575 on the light track = 4.0:1, under WCAG AA for
    // body text). The unselected half is still a label a member has to read.
    final restColor = p.isDark ? const Color(0xFFCFCFCF) : p.textSecondary;

    return Semantics(
      button: true,
      selected: isSelected,
      // A segmented control is a one-of-N choice, and saying so is what lets a
      // screen reader announce "1 of 2" rather than two unrelated buttons that
      // happen to both be toggles.
      inMutuallyExclusiveGroup: true,
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
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            scale: _pressed ? 0.96 : 1.0,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 240),
              style: AppText.label(size: 13.5).copyWith(
                color: isSelected ? Colors.white : restColor,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                // The selected weight is heavier than the resting one, so the
                // label's WIDTH changes on selection. Tabular figures do not
                // help letters; a hair of tracking on the lighter weight keeps
                // the two optical widths close enough that the word does not
                // visibly re-centre as the pill arrives under it.
                letterSpacing: isSelected ? 0 : 0.15,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedScale(
                    duration: const Duration(milliseconds: 300),
                    // The spring lives HERE, where overshooting is a flourish
                    // rather than a pill leaving its track.
                    curve: Curves.easeOutBack,
                    scale: isSelected ? 1.0 : 0.9,
                    child: Icon(
                      widget.icon,
                      size: 17,
                      color: isSelected ? Colors.white : restColor,
                    ),
                  ),
                  SizedBox(width: gap),
                  // SHRINK THE WORD, NEVER CUT IT.
                  //
                  // One word per half is not enough on its own: measured at
                  // 2.0x accessibility text on a 320dp phone, "Workout" wants
                  // 196px and each half offers 127. Ellipsis would answer that
                  // with "Workou…" — the member who most needs to read the
                  // label being the one who cannot. `BoxFit.scaleDown` honours
                  // the OS preference right up to the point where it physically
                  // stops fitting and only then gives ground, so the word stays
                  // WHOLE at every size (and at 2.0x still renders around 1.3x
                  // the default, well above where it started).
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                      ),
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
