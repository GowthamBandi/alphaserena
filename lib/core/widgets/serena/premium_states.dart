import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../glass_card.dart';

/// PREMIUM STATE PRIMITIVES — the shared vocabulary for "the app is working",
/// "there is nothing here yet" and "the refresh failed but your data is fine".
///
/// These exist because the same three moments were being re-implemented per
/// screen, and every re-implementation drifted: one screen faded, another
/// popped; one said "Loading", another showed a bare grey box; one replaced a
/// member's data with an error, another kept it. A member reads the whole app
/// as one product, so these moments have to be one implementation.
///
/// THE RULE THE WHOLE FILE SERVES (see [SerenaSkeleton]): a skeleton is a
/// FIRST-LOAD affordance only. Once the member has seen real content, a
/// refresh never takes it away — it stays on screen and [SyncWhisper] says
/// what is happening.

// ── MOTION ──────────────────────────────────────────────────────────────────

/// One duration for every state transition in the app, so a fade on Home and a
/// fade on My Plans are recognisably the same gesture.
const Duration kStateSwap = Duration(milliseconds: 260);

/// One duration for every VALUE that travels — a counting number, a ring
/// sweeping to a new percentage, a macro bar filling.
///
/// These three were 900 ms, 900 ms and 750 ms, which meant that on a single
/// card the bars finished 150 ms before the ring they belong to. Nobody can
/// name that gap, and everybody feels it: the card stops arriving twice. A
/// value is a value, so it moves at one speed.
const Duration kCountUp = Duration(milliseconds: 900);

/// Fast out, settle in. A counter that decelerates reads as landing on its
/// figure; a linear one reads as a loading bar that happens to have digits.
const Curve kCountCurve = Curves.easeOutCubic;

/// Whether the platform has asked for reduced motion.
///
/// Every animation here is decorative — a shimmer, a fade, a counting number —
/// so all of them are answers to a question the member may have already said
/// no to at the OS level. Honouring it is not optional for an accessibility
/// setting whose entire purpose is to stop exactly this kind of movement.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

// ── SKELETON ────────────────────────────────────────────────────────────────

/// A first-load placeholder with a slow shimmer sweep.
///
/// The sweep is the entire difference between "this app is loading" and "this
/// app is broken": a static grey rectangle is indistinguishable from a card
/// that failed to render, which is precisely how a half-finished build looks.
///
/// ⚠️ Only ever render this when NOTHING has loaded yet. If the member has
/// already seen content, showing this instead is a regression — it destroys
/// information they had a moment ago to tell them something they can be told
/// with [SyncWhisper] instead.
class SerenaSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const SerenaSkeleton({
    super.key,
    this.width,
    required this.height,
    this.radius = 12,
  });

  @override
  State<SerenaSkeleton> createState() => _SerenaSkeletonState();
}

class _SerenaSkeletonState extends State<SerenaSkeleton>
    with SingleTickerProviderStateMixin {
  // ⚠️ NULLABLE AND CREATED IN `build`, NOT `late final`.
  //
  // This was `late final … = AnimationController(…)..repeat()`, which is
  // initialised on FIRST ACCESS. Under reduced motion `build` returns the
  // static box before ever touching it, so the first access was `dispose()`
  // itself — constructing an AnimationController, and therefore a Ticker,
  // against an element that had already been deactivated. That throws
  // "Looking up a deactivated widget's ancestor is unsafe" and takes down the
  // frame.
  //
  // It reproduced for every member with the OS "reduce motion" setting on,
  // every time a skeleton left the tree — which is to say on every screen in
  // the app, on the single code path chosen by an accessibility preference.
  // Creating it in `build` means it exists exactly when it is used, and
  // `dispose` can only ever release something already constructed.
  AnimationController? _c;

  AnimationController get _shimmer =>
      _c ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      )..repeat();

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final base = p.surfaceAlt;
    // The highlight has to survive both themes: on near-black a white wash
    // reads, on white it does not — there it is the SHADOW that moves.
    final highlight = p.isDark
        ? Colors.white.withValues(alpha: 0.055)
        : Colors.white.withValues(alpha: 0.85);

    final box = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    );

    if (reduceMotion(context)) {
      // If the setting was turned ON while a skeleton was already sweeping,
      // stop the ticker rather than leaving it repeating behind a static box.
      _c?.stop();
      return box;
    }

    final shimmer = _shimmer;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: AnimatedBuilder(
        animation: shimmer,
        builder: (context, _) {
          // -1 → 2 rather than 0 → 1 so the band is fully off-screen at both
          // ends; sweeping 0 → 1 leaves it parked at the edge between cycles,
          // which reads as a flicker rather than a pass.
          final t = shimmer.value * 3 - 1;
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Colors.transparent, highlight, Colors.transparent],
              stops: [
                (t - 0.28).clamp(0.0, 1.0),
                t.clamp(0.0, 1.0),
                (t + 0.28).clamp(0.0, 1.0),
              ],
            ).createShader(rect),
            child: box,
          );
        },
      ),
    );
  }
}

// ── SYNC WHISPER ────────────────────────────────────────────────────────────

/// The "something is happening, nothing is wrong" line.
///
/// A 12px spinner and a short verb, shown OVER content the member is already
/// reading. Deliberately quiet: it is an answer to a question they have not
/// asked yet, so it must never compete with the data it sits beside.
///
/// Always occupies its slot ([height]) whether visible or not, so arming it
/// cannot push the page down — a layout jump during a background refresh is
/// the exact "the app is doing something to me" feeling this removes.
class SyncWhisper extends StatelessWidget {
  final bool visible;
  final String label;

  /// The reserved slot height. Matches the row so nothing moves.
  static const double height = 18;

  const SyncWhisper({
    super.key,
    required this.visible,
    this.label = 'Updating',
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: height,
      // ⚠️ THE SPINNER IS BUILT ONLY WHILE IT IS VISIBLE.
      //
      // An earlier version kept the row mounted at opacity 0 so the fade could
      // run both ways. A `CircularProgressIndicator` drives a repeating ticker
      // for as long as it EXISTS, not for as long as it can be seen — so an
      // invisible one on Home, My Plans and Diet meant three permanently
      // animating widgets requesting frames on an idle screen. It also hung
      // every `pumpAndSettle` in the widget suite, which is the same fact
      // reported by a different observer.
      child: AnimatedSwitcher(
        duration: kStateSwap,
        switchInCurve: Curves.easeOut,
        child: !visible
            ? const SizedBox.shrink()
            : Row(
                key: const ValueKey('busy'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: p.textMuted,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style:
                        AppText.body(size: 11.5).copyWith(color: p.textMuted),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── STALE BANNER ────────────────────────────────────────────────────────────

/// A refresh failed while the member already had good data.
///
/// The data STAYS. This says so, and offers the retry — because the failure is
/// about the network, and replacing a member's plan with an error page over a
/// dropped packet tells them they have lost something they have not lost.
class StaleDataBanner extends StatelessWidget {
  final VoidCallback? onRetry;
  final String message;

  const StaleDataBanner({
    super.key,
    this.onRetry,
    this.message = "Couldn't refresh. Showing your last synced information.",
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: p.textMuted.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.textMuted.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 15, color: p.textMuted),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: AppText.body(size: 12).copyWith(color: p.textSecondary),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: p.accent,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Retry', style: AppText.label(size: 12.5)),
            ),
        ],
      ),
    );
  }
}

// ── EMPTY STATE ─────────────────────────────────────────────────────────────

/// A premium empty state: what this screen is waiting for, and how to start it.
///
/// "No data" describes the DATABASE. This describes the MEMBER's situation —
/// which of the two they are in ("you haven't started yet" vs "your coach
/// hasn't sent this yet") decides whether an action button belongs here at all.
/// An empty state with a button the member cannot act on is worse than none.
class SerenaEmptyState extends StatelessWidget {
  /// A glyph, not an icon — an emoji carries warmth a monochrome outline does
  /// not, and these are the screens where a first-time member decides whether
  /// the product feels alive.
  final String glyph;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Whether to draw the card surface. False when the caller already provides
  /// one (a section inside an existing card).
  final bool boxed;

  const SerenaEmptyState({
    super.key,
    required this.glyph,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.boxed = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(glyph, style: const TextStyle(fontSize: 34)),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppText.cardTitle(size: 15.5).copyWith(color: p.textPrimary),
        ),
        const SizedBox(height: 7),
        Text(
          body,
          textAlign: TextAlign.center,
          style: AppText.body(size: 13)
              .copyWith(color: p.textMuted, height: 1.45),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: onAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              actionLabel!,
              style: AppText.label(size: 13.5).copyWith(color: Colors.white),
            ),
          ),
        ],
      ],
    );

    if (!boxed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        child: content,
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 22),
      decoration: glassCard(p, radius: 18),
      child: content,
    );
  }
}

// ── COUNTING NUMBERS ────────────────────────────────────────────────────────

/// A number that TRAVELS to its new value instead of teleporting to it.
///
/// ── WHY THIS EXISTS ────────────────────────────────────────────────────────
/// Every ring and bar in this app already animates. Not one NUMBER did. So
/// logging a 300 kcal lunch played a 900 ms sweep around a ring whose centre
/// had already snapped from 165 to 465 on the first frame — the two halves of
/// one object disagreeing about whether anything moved. The snap is what reads
/// as "a value was replaced"; the count is what reads as "you did that".
///
/// It is deliberately a BUILDER rather than a Text: the figure is almost never
/// alone. It sits inside "165 / 1800 kcal", inside a ring, beside a unit — and
/// only the current value may move. Animating the whole composed string would
/// count the TARGET up from zero too, which is a number the member did not
/// change and must never appear to.
///
/// Null is not zero. A metric with nothing logged renders its em dash with no
/// animation at all, because counting to a value that does not exist would be
/// the card inventing data for the length of the tween.
class AnimatedCount extends StatelessWidget {
  /// The destination. Null renders [builder] once, unanimated.
  final double? value;

  /// Rebuilt on every frame with the intermediate figure.
  final Widget Function(BuildContext context, double? shown) builder;

  /// Whether the FIRST appearance counts up from zero, or simply arrives at
  /// its figure. Later changes always animate either way.
  ///
  /// ⚠️ THIS IS NOT A STYLE PREFERENCE. A counter on its way up displays every
  /// number below its destination, including zero — so "count on appear" is
  /// only honest where something ELSE on screen is making the same claim at
  /// the same time. The calorie ring sweeps from empty, so its centre counting
  /// from 0 is the two halves of one object agreeing.
  ///
  /// A streak has no such partner. Counting it up would put "0 Day Streak"
  /// under a member's eyes for 900 ms on every single app open — a false and
  /// specifically demoralising statement, told daily, to say nothing new. It
  /// arrives at 5 and animates only when it BECOMES 6.
  final bool animateOnAppear;

  final Duration duration;
  final Curve curve;

  const AnimatedCount({
    super.key,
    required this.value,
    required this.builder,
    this.animateOnAppear = true,
    this.duration = kCountUp,
    this.curve = kCountCurve,
  });

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v == null || reduceMotion(context)) return builder(context, v);

    // TweenAnimationBuilder reads `begin` on the FIRST build only; on every
    // rebuild it re-targets from wherever the value currently IS to the new
    // `end`. So beginning at `v` costs the arrival animation and nothing else
    // — a later change still departs from the figure already on screen.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: animateOnAppear ? 0 : v, end: v),
      duration: duration,
      curve: curve,
      builder: (context, shown, _) => builder(context, shown),
    );
  }
}

/// Tabular (fixed-width) digits.
///
/// Proportional digits are different widths — a 1 is half a 0 in most faces —
/// so a counter running through 111 → 222 visibly breathes, and one inside a
/// [FittedBox] re-scales the whole block while it does. This is the single
/// detail that separates a counter that looks engineered from one that looks
/// like text being rewritten very fast.
const List<FontFeature> kTabularFigures = [FontFeature.tabularFigures()];

// ── STATE SWAP ──────────────────────────────────────────────────────────────

/// Crossfades between the states of one region (skeleton → content → empty).
///
/// The swap is the moment a screen most often looks cheap: content appearing
/// instantly at full opacity reads as a jump-cut, and it is what makes a fast
/// load feel abrupt rather than smooth. A short fade with a 2% rise costs
/// nothing and is the difference every flagship app is trading on here.
class StateSwap extends StatelessWidget {
  final Widget child;

  /// Distinguishes the states. Two different states MUST have different keys
  /// or no transition runs at all.
  final Object stateKey;

  const StateSwap({super.key, required this.stateKey, required this.child});

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    return AnimatedSwitcher(
      duration: kStateSwap,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      // The default layout builder stacks children CENTRED, which visibly
      // shifts a tall skeleton against short content mid-transition. Top
      // alignment keeps both pinned to the same origin, so the swap reads as a
      // dissolve rather than a slide.
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(stateKey), child: child),
    );
  }
}
