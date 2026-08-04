import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/lifestyle_controller.dart';
import '../../core/models/lifestyle_log_model.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/lifestyle_math.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/progress_ring.dart';
import 'lifestyle_history_screen.dart';

/// TODAY'S TARGETS — the member's daily lifestyle tracker.
///
/// Water (tap a glass), steps, sleep (bedtime → wake time) and the coach's
/// supplement stack.
///
/// Every figure is DERIVED from the day's recorded events — the same
/// derivation the server runs — so what the member sees is what the coach
/// receives. Nothing here reads the legacy projection document, and nothing
/// here computes: the controller owns every number, so Home, this screen and
/// History cannot disagree.
class LifestyleTodayScreen extends StatelessWidget {
  const LifestyleTodayScreen({super.key});

  /// Water's own blue — the same tint the Home lifestyle tile uses, so the
  /// metric keeps one colour across the app.
  static const Color kWater = Color(0xFF29B6F6);
  static const Color kWaterDeep = Color(0xFF0288D1);
  static const Color kSteps = Color(0xFFFB8C00);
  static const Color kSleep = Color(0xFF7C83FF);
  static const Color kSupplements = Color(0xFF2EBD59);

  @override
  Widget build(BuildContext context) {
    final c = Get.isRegistered<LifestyleController>()
        ? Get.find<LifestyleController>()
        : Get.put(LifestyleController());
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: Text("Today's Targets",
            style: AppText.title(size: 20).copyWith(color: p.textPrimary)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: _HistoryPill(palette: p),
          ),
        ],
      ),
      body: Obx(() {
        if (!c.canLog) return _joinPrompt(p);
        if (c.isLoading.value) return _skeleton(p);
        return RefreshIndicator(
          color: p.accent,
          onRefresh: () async => c.ensureFreshDay(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // The controller has always TRACKED these two states; nothing
              // ever showed them, so a member whose write was rejected or
              // queued had no way to know.
              if (c.hasError.value) _banner(p, isError: true),
              if (!c.hasError.value && c.isOffline.value)
                _banner(p, isError: false),
              _summary(c, p),
              const SizedBox(height: 14),
              _WaterCard(controller: c, palette: p),
              const SizedBox(height: 14),
              _StepsCard(controller: c, palette: p),
              const SizedBox(height: 14),
              _SleepCard(controller: c, palette: p),
              const SizedBox(height: 14),
              _supplementsCard(c, p),
            ],
          ),
        );
      }),
    );
  }

  // ── States ───────────────────────────────────────────────────────────────

  Widget _joinPrompt(AppPalette p) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.self_improvement, size: 44, color: p.textMuted),
              const SizedBox(height: 14),
              Text('Join a coach to start tracking your day.',
                  textAlign: TextAlign.center,
                  style:
                      AppText.body(size: 14).copyWith(color: p.textSecondary)),
            ],
          ),
        ),
      );

  Widget _banner(AppPalette p, {required bool isError}) {
    final color = isError ? p.error : p.textMuted;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.cloud_off,
              size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isError
                  ? "That didn't save. Check your connection and try again."
                  : "Saved on this device — it'll sync when you're back online.",
              style: AppText.body(size: 12.5).copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeleton(AppPalette p) {
    Widget block(double height) => Container(
          height: height,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: glassCard(p),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [block(72), block(300), block(120), block(180), block(140)],
    );
  }

  // ── Day summary ──────────────────────────────────────────────────────────

  /// One line answering "how is today going" before any single metric does.
  Widget _summary(LifestyleController c, AppPalette p) {
    final parts = <double>[
      if (c.waterCompletion != null) c.waterCompletion!.clamp(0.0, 1.0),
      if (c.stepsCompletion != null) c.stepsCompletion!.clamp(0.0, 1.0),
      if (c.sleepCompletion != null) c.sleepCompletion!.clamp(0.0, 1.0),
      if (c.supplementCompletion != null)
        c.supplementCompletion!.clamp(0.0, 1.0),
    ];
    final done = parts.where((v) => v >= 1).length;
    final overall =
        parts.isEmpty ? 0.0 : parts.reduce((a, b) => a + b) / parts.length;

    return Container(
      decoration: glassCard(p, radius: 20),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          ProgressRing(
            value: overall,
            palette: p,
            diameter: 56,
            strokeFraction: 0.1,
            colors: const [BrandColors.accent, BrandColors.gradientOrange],
            // A day with nothing logged is not 0% complete — there is
            // nothing yet to be a fraction of. Same rule the rest of the
            // module keeps: an em dash, never a fabricated zero.
            child: Text(
                parts.isEmpty ? '—' : '${(overall * 100).round()}%',
                style: AppText.label(size: 12).copyWith(color: p.textPrimary)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TODAY',
                    style: AppText.label(size: 11)
                        .copyWith(color: p.textMuted, letterSpacing: 1.2)),
                const SizedBox(height: 3),
                Text(
                  parts.isEmpty
                      ? 'Nothing logged yet — start with a glass of water.'
                      : '$done of ${parts.length} goals met',
                  style: AppText.cardTitle(size: 15)
                      .copyWith(color: p.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Supplements ──────────────────────────────────────────────────────────

  Widget _supplementsCard(LifestyleController c, AppPalette p) {
    final list = c.supplementChecklist;
    final taken = list.where((s) => s.taken).length;
    final remaining = list.length - taken;
    return Container(
      decoration: glassCard(p, radius: 20),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            label: 'SUPPLEMENTS',
            icon: Icons.medication_rounded,
            tint: kSupplements,
            palette: p,
            trailing: list.isEmpty
                ? null
                : Text('$taken/${list.length}',
                    style: AppText.label(size: 13).copyWith(
                        color:
                            taken == list.length ? kSupplements : p.textMuted)),
          ),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
              child: Text("Your coach hasn't added supplements yet.",
                  style: AppText.body(size: 12.5).copyWith(color: p.textMuted)),
            )
          else ...[
            const SizedBox(height: 12),
            // Completed / remaining, said plainly — the member should not have
            // to count ticks to know what is left.
            Text(
              remaining == 0
                  ? 'All $taken completed'
                  : '$taken completed · $remaining remaining',
              style: AppText.body(size: 12.5).copyWith(
                  color: remaining == 0 ? kSupplements : p.textSecondary),
            ),
            const SizedBox(height: 4),
            ...list.map((s) => _supplementRow(c, p, s)),
          ],
        ],
      ),
    );
  }

  Widget _supplementRow(
      LifestyleController c, AppPalette p, SupplementIntake s) {
    final doses = c.dosesOf(s.id);
    final label = s.dose == null ? s.name : '${s.name} · ${s.dose}';
    return Semantics(
      checked: s.taken,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          c.toggleSupplement(s.id);
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
          child: Row(
            children: [
              Icon(s.taken ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: s.taken ? kSupplements : p.textMuted, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: AppText.body(size: 14).copyWith(
                        color: s.taken ? p.textPrimary : p.textSecondary)),
              ),
              // A multi-dose protocol is expressible now, so show how many
              // have actually been recorded rather than a bare tick.
              if (doses > 1)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text('×$doses',
                      style:
                          AppText.label(size: 12).copyWith(color: p.textMuted)),
                ),
              if (s.taken)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Record another dose of ${s.name}',
                  onPressed: () => c.addSupplementDose(s.id),
                  icon: Icon(Icons.add_circle_outline,
                      size: 20, color: p.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══ SHARED PARTS ══════════════════════════════════════════════════════════

/// The app-bar action — a premium accent pill, not a bare icon.
class _HistoryPill extends StatelessWidget {
  const _HistoryPill({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Semantics(
      button: true,
      container: true,
      label: 'History',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.selectionClick();
            Get.to(() => const LifestyleHistoryScreen());
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: p.accent.withValues(alpha: p.isDark ? 0.16 : 0.10),
              border: Border.all(color: p.accent.withValues(alpha: 0.32)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history_rounded, size: 15, color: p.accent),
                const SizedBox(width: 5),
                Text('History',
                    style: AppText.label(size: 12).copyWith(color: p.accent)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Every metric card opens the same way: a tinted icon, a label, an optional
/// figure on the right.
class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.label,
    required this.icon,
    required this.tint,
    required this.palette,
    this.trailing,
  });

  final String label;
  final IconData icon;
  final Color tint;
  final AppPalette palette;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: tint.withValues(alpha: p.isDark ? 0.18 : 0.13),
          ),
          child: Icon(icon, size: 15, color: tint),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label(size: 12)
                  .copyWith(color: p.textMuted, letterSpacing: 1.2)),
        ),
        ?trailing,
      ],
    );
  }
}

/// The shared progress bar — one shape for steps and sleep.
class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.tint, required this.palette});

  final double? value;
  final Color tint;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: p.isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : const Color(0xFFE8EBF0),
              ),
            ),
            if (value != null && value! > 0)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value!.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (_, t, _) => FractionallySizedBox(
                  widthFactor: t,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
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

/// An input (or a summary line) beside its primary action — until the text is
/// large enough that "beside" stops working.
///
/// At 1.8x accessibility text the button's own label is wider than half the
/// card, which squeezed the steps field to a stub and wrapped the sleep
/// duration line into a twelve-line column beside it. Above 1.3x the action
/// takes its own full-width row instead, which costs one line of height and
/// keeps both parts usable.
class _FieldAndAction extends StatelessWidget {
  const _FieldAndAction({
    required this.child,
    required this.action,
    required this.palette,
  });

  final Widget child;
  final Widget action;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    if (scale > 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: action),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: child),
        const SizedBox(width: 10),
        action,
      ],
    );
  }
}

/// The primary action on the steps and sleep cards.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.palette,
    required this.onTap,
    this.filled = true,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final AppPalette palette;
  final VoidCallback? onTap;
  final bool filled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final enabled = onTap != null && !busy;
    return Semantics(
      // CONTAINER, deliberately. Without it the annotation merges into
      // whatever node is nearest, and the steps card's Edit button was
      // announced as the tail of one long sentence — "STEPS, 65%, 6,500, goal
      // 10,000, Edit" — with no way for a screen-reader user to reach it as a
      // control. An action is its own node.
      button: true,
      container: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onTap!();
                }
              : null,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: enabled ? 1 : 0.45,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: filled
                    ? const LinearGradient(colors: BrandColors.selectedGradient)
                    : null,
                color: filled ? null : p.accent.withValues(alpha: 0.10),
                border: filled
                    ? null
                    : Border.all(color: p.accent.withValues(alpha: 0.32)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  else
                    Icon(icon,
                        size: 16, color: filled ? Colors.white : p.accent),
                  const SizedBox(width: 7),
                  Text(label,
                      style: AppText.label(size: 13).copyWith(
                          color: filled ? Colors.white : p.accent)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══ WATER ═════════════════════════════════════════════════════════════════

/// WATER — one glass per tap, bounded at both ends.
///
/// The ring, the counter inside it and the millilitre line are three
/// renderings of ONE number: glasses against the coach's glass goal. They were
/// two (millilitres for the ring, glasses for the counter), which is how a
/// member came to see "10 of 10 glasses" inside a ring that stopped at 96%.
class _WaterCard extends StatelessWidget {
  const _WaterCard({required this.controller, required this.palette});

  final LifestyleController controller;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final p = palette;
    final glasses = c.waterGlasses;
    final target = c.waterTargetGlasses;
    final met = c.waterGoalReached;
    final completion = (c.waterCompletion ?? 0).clamp(0.0, 1.0);

    return Container(
      decoration: glassCard(p, radius: 20),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 18),
      child: Column(
        children: [
          _CardHeader(
            label: 'WATER',
            icon: Icons.water_drop_rounded,
            tint: LifestyleTodayScreen.kWater,
            palette: p,
            trailing: c.targets.waterTargetMl == null
                ? Text('suggested goal',
                    style:
                        AppText.body(size: 11).copyWith(color: p.textMuted))
                : null,
          ),
          const SizedBox(height: 18),
          ProgressRing(
            value: completion,
            palette: p,
            diameter: 168,
            colors: met
                ? const [Color(0xFF2EBD59), Color(0xFF7BD97C)]
                : const [
                    LifestyleTodayScreen.kWaterDeep,
                    LifestyleTodayScreen.kWater,
                  ],
            semanticLabel:
                'Water, $glasses of $target glasses, ${(completion * 100).round()}%',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$glasses',
                    style: AppText.title(size: 46)
                        .copyWith(color: p.textPrimary, height: 0.95)),
                const SizedBox(height: 2),
                Text('of $target glasses',
                    style: AppText.body(size: 12).copyWith(color: p.textMuted)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Millilitres, computed from the COACH'S glass size — never a
          // hardcoded 250.
          Text(
            '${_ml(glasses * c.glassSizeMl)} ml / ${_ml(c.waterTargetMl)} ml',
            style: AppText.label(size: 13).copyWith(
                color: met ? const Color(0xFF2EBD59) : p.textSecondary),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _GlassButton(
                icon: Icons.remove_rounded,
                palette: p,
                enabled: c.canRemoveGlass,
                semanticLabel: 'Remove a glass of water',
                onTap: () => c.addGlass(-1),
              ),
              const SizedBox(width: 30),
              _GlassButton(
                icon: Icons.add_rounded,
                palette: p,
                filled: true,
                // NEVER disabled. A goal is a goal, not a ceiling: a member who
                // drinks past it must still be able to record it, or their real
                // intake is truncated here and in their coach's analytics.
                semanticLabel: 'Add a glass of water',
                onTap: () => c.addGlass(1),
              ),
            ],
          ),
          if (met) ...[
            const SizedBox(height: 12),
            Text('Goal reached — nice work.',
                style: AppText.body(size: 12)
                    .copyWith(color: const Color(0xFF2EBD59))),
          ],
        ],
      ),
    );
  }

  static String _ml(double v) {
    final n = v.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < n.length; i++) {
      if (i > 0 && (n.length - i) % 3 == 0) buf.write(',');
      buf.write(n[i]);
    }
    return buf.toString();
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.palette,
    required this.onTap,
    required this.semanticLabel,
    this.filled = false,
    this.enabled = true,
  });

  final IconData icon;
  final AppPalette palette;
  final VoidCallback onTap;
  final String semanticLabel;
  final bool filled;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Semantics(
      button: true,
      container: true,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onTap();
              }
            : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1 : 0.3,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: filled
                  ? const LinearGradient(
                      colors: [
                        LifestyleTodayScreen.kWaterDeep,
                        LifestyleTodayScreen.kWater,
                      ],
                    )
                  : null,
              color: filled ? null : p.surfaceAlt.withValues(alpha: 0.8),
              border: filled
                  ? null
                  : Border.all(color: p.border),
              boxShadow: filled && enabled
                  ? [
                      BoxShadow(
                        color: LifestyleTodayScreen.kWater
                            .withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Icon(icon,
                color: filled ? Colors.white : p.textPrimary, size: 28),
          ),
        ),
      ),
    );
  }
}

// ═══ STEPS ═════════════════════════════════════════════════════════════════

/// STEPS — enter, save, then edit.
///
/// A manual entry is an ABSOLUTE daily figure (the server takes the latest),
/// so saving again corrects the day rather than adding a second entry. The
/// affordance now says so: once a figure exists the field is replaced by the
/// figure and an Edit button that loads it back.
class _StepsCard extends StatefulWidget {
  const _StepsCard({required this.controller, required this.palette});

  final LifestyleController controller;
  final AppPalette palette;

  @override
  State<_StepsCard> createState() => _StepsCardState();
}

class _StepsCardState extends State<_StepsCard> {
  final TextEditingController _field = TextEditingController();
  bool _editing = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _startEdit() {
    final current = widget.controller.steps;
    _field.text = current == null ? '' : current.toString();
    _field.selection =
        TextSelection.collapsed(offset: _field.text.length);
    setState(() {
      _editing = true;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    final text = _field.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Enter your step count.');
      return;
    }
    final invalid = validateStepsEntry(text);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.controller.setSteps(double.parse(text));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = ok ? null : "That didn't save. Try again.";
      if (ok) _editing = false;
    });
    if (ok && mounted) FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final p = widget.palette;
    final steps = c.steps;
    final target = c.targets.stepsTarget;
    final completion = c.stepsCompletion;
    final met = (completion ?? 0) >= 1;
    final showField = _editing || !c.hasStepsRecord;

    return Container(
      decoration: glassCard(p, radius: 20),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            label: 'STEPS',
            icon: Icons.directions_walk_rounded,
            tint: LifestyleTodayScreen.kSteps,
            palette: p,
            trailing: completion == null
                ? null
                : Text('${(completion * 100).round()}%',
                    style: AppText.label(size: 13).copyWith(
                        color: met
                            ? const Color(0xFF2EBD59)
                            : LifestyleTodayScreen.kSteps)),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  steps == null ? '—' : _thousands(steps.toDouble()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.title(size: 30).copyWith(
                      color: steps == null ? p.textMuted : p.textPrimary),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  // 🔴 CONTRADICTION. `stepsCompletion` scores against the
                  // coach's target OR the platform default, so a member with
                  // no coach goal was shown "no goal set" beside a live
                  // percentage computed from a goal of 8 000 nobody had
                  // mentioned. Water already said "suggested"; so do these.
                  target == null
                      ? 'goal ${_thousands(LifestyleDefaults.steps.toDouble())}'
                          ' · suggested'
                      : 'goal ${_thousands(target.toDouble())}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          _Bar(
            value: completion,
            tint: met
                ? const Color(0xFF2EBD59)
                : LifestyleTodayScreen.kSteps,
            palette: p,
          ),
          const SizedBox(height: 14),
          if (showField)
            _FieldAndAction(
              palette: p,
              action: _ActionButton(
                label: 'Save',
                icon: Icons.check_rounded,
                palette: p,
                busy: _busy,
                onTap: _save,
              ),
              child: TextField(
                    controller: _field,
                    enabled: !_busy,
                    autofocus: _editing,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    style:
                        AppText.body(size: 15).copyWith(color: p.textPrimary),
                    decoration: InputDecoration(
                      hintText: "Today's steps",
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      hintStyle:
                          AppText.body(size: 13).copyWith(color: p.textMuted),
                      filled: true,
                      fillColor: p.inputFill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: p.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: p.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: p.accent),
                      ),
                    ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _save(),
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: _ActionButton(
                label: 'Edit',
                icon: Icons.edit_rounded,
                palette: p,
                filled: false,
                onTap: _startEdit,
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: AppText.body(size: 12).copyWith(color: p.error)),
          ],
        ],
      ),
    );
  }

  static String _thousands(double v) {
    final n = v.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < n.length; i++) {
      if (i > 0 && (n.length - i) % 3 == 0) buf.write(',');
      buf.write(n[i]);
    }
    return buf.toString();
  }
}

// ═══ SLEEP ═════════════════════════════════════════════════════════════════

/// SLEEP — a bedtime and a wake time, not a number of hours.
///
/// Asking for "hours" asks the member to do arithmetic they should not have
/// to; the two instants are what they actually know, and recording the PERIOD
/// is also what the event store wants (the duration is then derived, and the
/// coach can see when the night actually was).
///
/// Saving again REPLACES the night. Sleep periods merge by design, so without
/// that an edit could only ever lengthen the night it was correcting.
class _SleepCard extends StatefulWidget {
  const _SleepCard({required this.controller, required this.palette});

  final LifestyleController controller;
  final AppPalette palette;

  @override
  State<_SleepCard> createState() => _SleepCardState();
}

class _SleepCardState extends State<_SleepCard> {
  TimeOfDay? _bed;
  TimeOfDay? _wake;
  bool _editing = false;
  bool _busy = false;
  String? _error;

  /// Minutes between bedtime and wake time, crossing midnight when needed.
  /// Null when the member has not given both times, or gave the same one twice.
  int? get _minutes {
    final bed = _bed;
    final wake = _wake;
    if (bed == null || wake == null) return null;
    final b = bed.hour * 60 + bed.minute;
    final w = wake.hour * 60 + wake.minute;
    // EQUALITY IS CHECKED FIRST, and it has to be.
    //
    // The wrap-around arithmetic below cannot represent a zero-length night:
    // for w == b it takes the `else` branch and yields `1440 - b + b` = 1440.
    // So the `span == 0` guard this replaced was unreachable dead code, and
    // picking the same time twice silently recorded a TWENTY-FOUR HOUR sleep —
    // accepted by validation (24 <= 24), derived by the server (1440 minutes
    // is not > 1440), rolled up, and shown to the coach as a real night.
    if (w == b) return null;
    return w > b ? w - b : (24 * 60) - b + w;
  }

  void _startEdit() {
    final period = widget.controller.sleepPeriod;
    setState(() {
      _editing = true;
      _error = null;
      if (period != null) {
        _bed = TimeOfDay.fromDateTime(period.start);
        _wake = TimeOfDay.fromDateTime(period.end);
      }
    });
  }

  Future<void> _pick(bool bedtime) async {
    final initial = (bedtime ? _bed : _wake) ??
        (bedtime
            ? const TimeOfDay(hour: 22, minute: 30)
            : const TimeOfDay(hour: 6, minute: 30));
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: bedtime ? 'SLEEP TIME' : 'WAKE TIME',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (bedtime) {
        _bed = picked;
      } else {
        _wake = picked;
      }
      _error = null;
      _editing = true;
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    final minutes = _minutes;
    if (minutes == null) {
      setState(() => _error = _bed == null || _wake == null
          ? 'Set both a sleep time and a wake time.'
          // Both ARE set — saying "set both" would be telling the member to do
          // something they have already done.
          : "Sleep and wake time can't be the same.");
      return;
    }
    // The wake instant is on the SELECTED day; the bedtime is however long
    // before it — which lands on the previous evening whenever the night
    // crossed midnight. Neither instant is invented: both came from the
    // member.
    final day = widget.controller.selectedDay.value;
    final wake = _wake!;
    final end = DateTime(day.year, day.month, day.day, wake.hour, wake.minute);
    final start = end.subtract(Duration(minutes: minutes));

    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.controller.setSleep(
      minutes / 60.0,
      start: start,
      end: end,
      // Every save from this card is the member's statement of the night, so
      // it stands alone — it never merges with what it corrects.
      replacing: true,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = ok ? null : "That didn't save. Try again.";
      if (ok) _editing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final p = widget.palette;
    final logged = c.sleepHours;
    final target = c.targets.sleepHoursTarget;
    final completion = c.sleepCompletion;
    final met = (completion ?? 0) >= 1;
    final showEditor = _editing || !c.hasSleepRecord;
    final draft = _minutes;

    return Container(
      decoration: glassCard(p, radius: 20),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            label: 'SLEEP',
            icon: Icons.bedtime_rounded,
            tint: LifestyleTodayScreen.kSleep,
            palette: p,
            trailing: completion == null
                ? null
                : Text('${(completion * 100).round()}%',
                    style: AppText.label(size: 13).copyWith(
                        color: met
                            ? const Color(0xFF2EBD59)
                            : LifestyleTodayScreen.kSleep)),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  logged == null ? '—' : hoursMinutes(logged),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.title(size: 30).copyWith(
                      color: logged == null ? p.textMuted : p.textPrimary),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  target == null
                      ? 'goal ${hoursMinutes(LifestyleDefaults.sleepHours)}'
                          ' · suggested'
                      : 'goal ${hoursMinutes(target)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          _Bar(
            value: completion,
            tint: met
                ? const Color(0xFF2EBD59)
                : LifestyleTodayScreen.kSleep,
            palette: p,
          ),
          const SizedBox(height: 14),
          if (showEditor) ...[
            Row(
              children: [
                Expanded(
                  child: _TimeTile(
                    label: 'Sleep',
                    value: _bed,
                    icon: Icons.nightlight_round,
                    palette: p,
                    onTap: () => _pick(true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TimeTile(
                    label: 'Wake',
                    value: _wake,
                    icon: Icons.wb_sunny_rounded,
                    palette: p,
                    onTap: () => _pick(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _FieldAndAction(
              palette: p,
              action: _ActionButton(
                label: 'Save',
                icon: Icons.check_rounded,
                palette: p,
                busy: _busy,
                onTap: _save,
              ),
              child: Text(
                draft == null
                    ? 'Pick both times to see your sleep duration.'
                    : 'Duration ${hoursMinutes(draft / 60)}',
                style: AppText.body(size: 12.5).copyWith(
                    color: draft == null ? p.textMuted : p.textSecondary),
              ),
            ),
          ] else
            _FieldAndAction(
              palette: p,
              action: _ActionButton(
                label: 'Edit',
                icon: Icons.edit_rounded,
                palette: p,
                filled: false,
                onTap: _startEdit,
              ),
              child: Text(
                c.sleepPeriod == null
                    ? 'Recorded for today'
                    : '${_fmt(context, TimeOfDay.fromDateTime(c.sleepPeriod!.start))}'
                        ' → ${_fmt(context, TimeOfDay.fromDateTime(c.sleepPeriod!.end))}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(size: 12.5).copyWith(color: p.textSecondary),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: AppText.body(size: 12).copyWith(color: p.error)),
          ],
        ],
      ),
    );
  }

  static String _fmt(BuildContext context, TimeOfDay t) =>
      t.format(context);
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final TimeOfDay? value;
  final IconData icon;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final text = value == null ? 'Set time' : value!.format(context);
    return Semantics(
      button: true,
      container: true,
      label: '$label time, $text',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: p.inputFill,
              border: Border.all(color: p.border),
            ),
            child: Row(
              children: [
                Icon(icon, size: 15, color: LifestyleTodayScreen.kSleep),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: AppText.body(size: 10.5)
                              .copyWith(color: p.textMuted, height: 1.1)),
                      const SizedBox(height: 2),
                      Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.cardTitle(size: 13.5).copyWith(
                            color: value == null
                                ? p.textMuted
                                : p.textPrimary,
                            height: 1.1),
                      ),
                    ],
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
