import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/lifestyle_controller.dart';
import '../../core/models/lifestyle_log_model.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/lifestyle_math.dart';
import '../../core/widgets/glass_card.dart';

/// The member's daily lifestyle tracker: water (tap-to-add glass), steps, sleep,
/// and a coach-defined supplement checklist.
///
/// Every figure on this screen is DERIVED from the day's recorded events — the
/// same derivation the server runs — so what the member sees is what the coach
/// receives. Nothing here reads the legacy projection document.
class LifestyleTodayScreen extends StatelessWidget {
  const LifestyleTodayScreen({super.key});

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
        title: Text('Today',
            style: AppText.title(size: 20).copyWith(color: p.textPrimary)),
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
              _waterCard(c, p),
              const SizedBox(height: 14),
              _MetricField(
                label: 'STEPS',
                icon: Icons.directions_walk,
                currentValue:
                    c.steps == null ? '—' : _thousands(c.steps!.toDouble()),
                goal: c.targets.stepsTarget != null
                    ? _thousands(c.targets.stepsTarget!.toDouble())
                    : '${_thousands(LifestyleDefaults.steps.toDouble())} (suggested)',
                completion: c.stepsCompletion,
                hint: 'Steps',
                palette: p,
                validate: validateStepsEntry,
                onSubmit: (v) => c.setSteps(double.parse(v)),
              ),
              const SizedBox(height: 14),
              _MetricField(
                label: 'SLEEP',
                icon: Icons.bedtime_outlined,
                currentValue: c.sleepHours == null
                    ? '—'
                    : '${c.sleepHours!.toStringAsFixed(1)} h',
                goal: c.targets.sleepHoursTarget != null
                    ? '${c.targets.sleepHoursTarget!.toStringAsFixed(0)} h'
                    : '${LifestyleDefaults.sleepHours.toStringAsFixed(0)} h (suggested)',
                completion: c.sleepCompletion,
                hint: 'Hours',
                palette: p,
                validate: validateSleepEntry,
                onSubmit: (v) => c.setSleep(double.parse(v)),
              ),
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
      children: [block(72), block(210), block(86), block(86), block(140)],
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
      decoration: glassCard(p),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _Ring(
            value: overall,
            color: p.accent,
            palette: p,
            size: 54,
            stroke: 5,
            child: Text('${(overall * 100).round()}%',
                style: AppText.label(size: 12).copyWith(color: p.textPrimary)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TODAY',
                    style:
                        AppText.label(size: 11).copyWith(color: p.textMuted)),
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

  // ── Water ────────────────────────────────────────────────────────────────

  Widget _waterCard(LifestyleController c, AppPalette p) {
    final glasses = c.waterGlasses;
    final target = c.waterTargetGlasses;
    final completion = (c.waterCompletion ?? 0).clamp(0.0, 1.0);
    final met = completion >= 1;
    return Container(
      decoration: glassCard(p),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Text('WATER',
              style: AppText.label(size: 12).copyWith(color: p.textMuted)),
          const SizedBox(height: 14),
          _Ring(
            value: completion,
            color: met ? p.success : p.accent,
            palette: p,
            size: 128,
            stroke: 9,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$glasses',
                    style: AppText.title(size: 34)
                        .copyWith(color: p.textPrimary)),
                Text('of $target glasses',
                    style:
                        AppText.body(size: 11).copyWith(color: p.textMuted)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${c.waterMl} ml'
            '${c.targets.waterTargetMl == null ? ' · suggested goal' : ''}',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _circleBtn(p, Icons.remove, () => c.addGlass(-1),
                  enabled: glasses > 0,
                  semanticLabel: 'Remove a glass of water'),
              const SizedBox(width: 28),
              _circleBtn(p, Icons.add, () => c.addGlass(1),
                  filled: true, semanticLabel: 'Add a glass of water'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _circleBtn(AppPalette p, IconData icon, VoidCallback onTap,
      {bool filled = false,
      bool enabled = true,
      required String semanticLabel}) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1 : 0.35,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? p.accent : p.surfaceAlt.withValues(alpha: 0.6),
            ),
            child: Icon(icon,
                color: filled ? Colors.white : p.textPrimary, size: 26),
          ),
        ),
      ),
    );
  }

  // ── Supplements ──────────────────────────────────────────────────────────

  Widget _supplementsCard(LifestyleController c, AppPalette p) {
    final list = c.supplementChecklist;
    final taken = list.where((s) => s.taken).length;
    return Container(
      decoration: glassCard(p),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('SUPPLEMENTS',
                    style:
                        AppText.label(size: 12).copyWith(color: p.textMuted)),
              ),
              if (list.isNotEmpty)
                Text('$taken/${list.length}',
                    style: AppText.label(size: 12).copyWith(
                        color: taken == list.length ? p.success : p.textMuted)),
            ],
          ),
          const SizedBox(height: 10),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Your coach hasn\'t added supplements yet.',
                  style: AppText.body(size: 12.5).copyWith(color: p.textMuted)),
            )
          else
            ...list.map((s) => _supplementRow(c, p, s)),
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
        onTap: () => c.toggleSupplement(s.id),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
          child: Row(
            children: [
              Icon(s.taken ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: s.taken ? p.success : p.textMuted, size: 22),
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
                      style: AppText.label(size: 12)
                          .copyWith(color: p.textMuted)),
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

/// A completion ring. Values over 100% fill the ring rather than overflowing.
class _Ring extends StatelessWidget {
  const _Ring({
    required this.value,
    required this.color,
    required this.palette,
    required this.size,
    required this.stroke,
    this.child,
  });

  final double value;
  final Color color;
  final AppPalette palette;
  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => CircularProgressIndicator(
                value: v,
                strokeWidth: stroke,
                strokeCap: StrokeCap.round,
                backgroundColor: palette.textMuted.withValues(alpha: 0.14),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          ?child,
        ],
      ),
    );
  }
}

/// A metric entry row that owns its TextEditingController (so typed text isn't
/// lost when the parent Obx rebuilds on a log update).
///
/// Validates BEFORE writing: the derivation discards out-of-range readings, so
/// an unchecked entry used to be recorded as an event that every reader then
/// ignored — the member watched their number simply not appear.
class _MetricField extends StatefulWidget {
  final String label;
  final IconData icon;
  final String currentValue;
  final String goal;
  final double? completion;
  final String hint;
  final AppPalette palette;
  final String? Function(String?) validate;
  final Future<bool> Function(String) onSubmit;

  const _MetricField({
    required this.label,
    required this.icon,
    required this.currentValue,
    required this.goal,
    required this.completion,
    required this.hint,
    required this.palette,
    required this.validate,
    required this.onSubmit,
  });

  @override
  State<_MetricField> createState() => _MetricFieldState();
}

class _MetricFieldState extends State<_MetricField> {
  final TextEditingController _ctrl = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    if (_busy) return;
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final error = widget.validate(text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    final ok = await widget.onSubmit(text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      setState(() => _error = "That didn't save. Try again.");
      return;
    }
    _ctrl.clear();
    if (mounted) FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final completion = widget.completion;
    final met = (completion ?? 0) >= 1;
    return Container(
      decoration: glassCard(p),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(widget.icon,
                  size: 18, color: met ? p.success : p.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label,
                        style: AppText.label(size: 11)
                            .copyWith(color: p.textMuted)),
                    const SizedBox(height: 3),
                    Text('${widget.currentValue}  ·  goal ${widget.goal}',
                        style: AppText.cardTitle(size: 15)
                            .copyWith(color: p.textPrimary)),
                  ],
                ),
              ),
              SizedBox(
                width: 84,
                child: TextField(
                  controller: _ctrl,
                  enabled: !_busy,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  style:
                      AppText.body(size: 14).copyWith(color: p.textPrimary),
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    isDense: true,
                    hintStyle:
                        AppText.body(size: 11).copyWith(color: p.textMuted),
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _submit(),
                ),
              ),
              _busy
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(
                      onPressed: _submit,
                      tooltip: 'Save ${widget.label.toLowerCase()}',
                      icon:
                          Icon(Icons.check_circle, color: p.accent, size: 22),
                    ),
            ],
          ),
          if (completion != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: completion.clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: p.textMuted.withValues(alpha: 0.14),
                valueColor:
                    AlwaysStoppedAnimation(met ? p.success : p.accent),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: AppText.body(size: 12).copyWith(color: p.error)),
          ],
        ],
      ),
    );
  }
}
