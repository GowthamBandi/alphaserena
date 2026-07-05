import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/lifestyle_controller.dart';
import '../../core/models/lifestyle_log_model.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/serena/serena_tokens.g.dart';
import '../../core/utils/lifestyle_math.dart';
import '../../core/widgets/glass_card.dart';

/// The member's daily lifestyle tracker: water (tap-to-add glass), steps, sleep,
/// and a coach-defined supplement checklist. Writes one doc per day.
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
        title:
            Text('Today', style: AppText.title(size: 20).copyWith(color: p.textPrimary)),
      ),
      body: Obx(() {
        if (!c.canLog) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text('Join a coach to start tracking your day.',
                  textAlign: TextAlign.center,
                  style: AppText.body(size: 14).copyWith(color: p.textMuted)),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _waterCard(c, p),
            const SizedBox(height: 14),
            _MetricField(
              label: 'STEPS',
              currentValue:
                  c.log.value?.steps?.value.toStringAsFixed(0) ?? '—',
              goal:
                  '${effectiveTarget(c.targets.stepsTarget?.toDouble(), LifestyleDefaults.steps.toDouble()).round()}',
              hint: 'Enter steps',
              palette: p,
              onSubmit: (v) {
                final n = double.tryParse(v);
                if (n != null) c.setSteps(n);
              },
            ),
            const SizedBox(height: 14),
            _MetricField(
              label: 'SLEEP',
              currentValue: c.log.value?.sleepHours == null
                  ? '—'
                  : '${c.log.value!.sleepHours!.value.toStringAsFixed(1)} h',
              goal:
                  '${effectiveTarget(c.targets.sleepHoursTarget, LifestyleDefaults.sleepHours).toStringAsFixed(0)} h',
              hint: 'Hours slept',
              palette: p,
              onSubmit: (v) {
                final n = double.tryParse(v);
                if (n != null) c.setSleep(n);
              },
            ),
            const SizedBox(height: 14),
            _supplementsCard(c, p),
          ],
        );
      }),
    );
  }

  Widget _waterCard(LifestyleController c, AppPalette p) {
    final glasses = c.waterGlasses;
    final target = c.waterTargetGlasses;
    return Container(
      decoration: glassCard(p),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Text('WATER',
              style: AppText.label(size: 12).copyWith(color: p.textMuted)),
          const SizedBox(height: 10),
          Text('$glasses / $target glasses',
              style: AppText.title(size: 24).copyWith(color: p.textPrimary)),
          const SizedBox(height: 4),
          Text('${(glasses * c.targets.glassSizeMl).round()} ml',
              style: AppText.body(size: 12).copyWith(color: p.textMuted)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _circleBtn(p, Icons.remove, () => c.addGlass(-1),
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
      {bool filled = false, required String semanticLabel}) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
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
    );
  }

  Widget _supplementsCard(LifestyleController c, AppPalette p) {
    final list = c.supplementChecklist;
    return Container(
      decoration: glassCard(p),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('SUPPLEMENTS',
              style: AppText.label(size: 12).copyWith(color: p.textMuted)),
          const SizedBox(height: 8),
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
    final label = s.dose == null ? s.name : '${s.name} · ${s.dose}';
    // M3 a11y: a supplement toggle is a checkbox; expose its checked state.
    return Semantics(
      checked: s.taken,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => c.toggleSupplement(s.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              // "Taken" now reads as done (SDS success green) rather than the
              // brand accent, matching the universal done/active language.
              Icon(s.taken ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: s.taken
                      ? const Color(SerenaColor.statusActiveLight)
                      : p.textMuted,
                  size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: AppText.body(size: 14).copyWith(
                        color: s.taken ? p.textPrimary : p.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A metric entry row that owns its TextEditingController (so typed text isn't
/// lost when the parent Obx rebuilds on a log update). Shows the current value +
/// goal and writes on submit.
class _MetricField extends StatefulWidget {
  final String label;
  final String currentValue;
  final String goal;
  final String hint;
  final AppPalette palette;
  final void Function(String) onSubmit;

  const _MetricField({
    required this.label,
    required this.currentValue,
    required this.goal,
    required this.hint,
    required this.palette,
    required this.onSubmit,
  });

  @override
  State<_MetricField> createState() => _MetricFieldState();
}

class _MetricFieldState extends State<_MetricField> {
  final TextEditingController _ctrl = TextEditingController();

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit(text);
    _ctrl.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Container(
      decoration: glassCard(p),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.label,
                    style:
                        AppText.label(size: 12).copyWith(color: p.textMuted)),
                const SizedBox(height: 4),
                Text('${widget.currentValue}  ·  goal ${widget.goal}',
                    style: AppText.cardTitle(size: 15)
                        .copyWith(color: p.textPrimary)),
              ],
            ),
          ),
          SizedBox(
            width: 90,
            child: TextField(
              controller: _ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              style: AppText.body(size: 14).copyWith(color: p.textPrimary),
              decoration: InputDecoration(
                hintText: widget.hint,
                isDense: true,
                hintStyle:
                    AppText.body(size: 11).copyWith(color: p.textMuted),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          IconButton(
            onPressed: _submit,
            tooltip: 'Save ${widget.label.toLowerCase()}',
            icon: Icon(Icons.check_circle, color: p.accent, size: 22),
          ),
        ],
      ),
    );
  }
}
