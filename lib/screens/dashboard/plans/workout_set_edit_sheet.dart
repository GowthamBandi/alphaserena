import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/domain/workout_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';

/// What the member changed about one set. Null from the sheet means they
/// backed out, which must leave the logged set exactly as it was.
class SetEditResult {
  final String actualReps;
  final String actualWeight;
  final SetLogState state;

  const SetEditResult({
    required this.actualReps,
    required this.actualWeight,
    required this.state,
  });
}

/// CORRECTING ONE LOGGED SET.
///
/// The workout twin of `FoodQuantitySheet`, and deliberately the same shape:
/// a bottom sheet over the row it changes, the coach's prescription stated
/// read-only at the top, the member's own numbers below it, one primary Save.
/// A member who has corrected a meal already knows how to correct a set.
///
/// **The prescription is never editable here.** What the coach asked for is
/// theirs; what the member did is the member's. An editor that let one
/// overwrite the other would destroy the only comparison the session exists to
/// make.
class WorkoutSetEditSheet extends StatefulWidget {
  /// 1-based, as the member sees it.
  final int setNumber;
  final String exerciseName;
  final SetLog set;

  /// The tab's accent — this sheet is opened from the workout side, and its
  /// Save must not arrive in a colour the surrounding screen never uses.
  final Color accent;

  const WorkoutSetEditSheet({
    super.key,
    required this.setNumber,
    required this.exerciseName,
    required this.set,
    required this.accent,
  });

  @override
  State<WorkoutSetEditSheet> createState() => _WorkoutSetEditSheetState();
}

class _WorkoutSetEditSheetState extends State<WorkoutSetEditSheet> {
  late final TextEditingController _reps;
  late final TextEditingController _weight;
  late SetLogState _state;

  @override
  void initState() {
    super.initState();
    _reps = TextEditingController(text: widget.set.actualReps);
    _weight = TextEditingController(text: widget.set.actualWeight);
    _state = widget.set.state;
  }

  @override
  void dispose() {
    _reps.dispose();
    _weight.dispose();
    super.dispose();
  }

  /// A set cannot be COMPLETED with nothing recorded against it.
  ///
  /// Not a validation nicety: `computeSessionStats` counts a completed set
  /// towards the member's percentage and `setHitTarget` reads a set with no
  /// numeric actuals as having HIT its target — so an empty completed set
  /// would quietly award both a completion and 100% adherence for work with no
  /// evidence behind it. Bodyweight work is why only ONE of the two fields is
  /// required rather than both.
  bool get _canComplete =>
      _reps.text.trim().isNotEmpty || _weight.text.trim().isNotEmpty;

  bool get _canSave => _state != SetLogState.completed || _canComplete;

  void _save() {
    if (!_canSave) return;
    Navigator.of(context).pop(
      SetEditResult(
        actualReps: _reps.text.trim(),
        actualWeight: _weight.text.trim(),
        state: _state,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final media = MediaQuery.of(context);
    final target = _targetLine(widget.set);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: p.border)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _grabber(p),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.exerciseName.isEmpty
                            ? 'Exercise'
                            : widget.exerciseName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.title(size: 19)
                            .copyWith(color: p.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        // The coach's words verbatim when they wrote any, and
                        // simply the set number when they did not. Never
                        // "Target: —".
                        target.isEmpty
                            ? 'Set ${widget.setNumber}'
                            : 'Set ${widget.setNumber}  ·  coach asked for '
                                '$target',
                        style: AppText.body(size: 12.5)
                            .copyWith(color: p.textMuted),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _field(
                              p,
                              label: 'REPS DONE',
                              controller: _reps,
                              hint: _hintFor(widget.set.pReps, '12'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              p,
                              label: 'WEIGHT USED',
                              controller: _weight,
                              hint: _hintFor(widget.set.pWeight, 'kg'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('THIS SET',
                          style: AppText.label(size: 11).copyWith(
                              color: p.textMuted, letterSpacing: 1.2)),
                      const SizedBox(height: 8),
                      _statePicker(p),
                      if (!_canSave) ...[
                        const SizedBox(height: 12),
                        _blocker(p),
                      ],
                    ],
                  ),
                ),
              ),
              _bottomBar(p),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grabber(AppPalette p) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: p.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _field(
    AppPalette p, {
    required String label,
    required TextEditingController controller,
    required String hint,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppText.label(size: 10.5)
                  .copyWith(color: p.textMuted, letterSpacing: 1.1)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            // A DECIMAL PAD, because an ACTUAL is a measurement.
            //
            // ⚠️ The comment here used to claim the member "must be able to
            // answer in the coach's vocabulary" — "8-12", "bodyweight" — which
            // this keyboard has never permitted: `numberWithOptions` offers no
            // letters and no hyphen. The code was right and the comment was
            // wrong, and the wrong half had been copied into the HINT, which
            // then showed members placeholder text they could not type.
            //
            // A PRESCRIPTION is a range or a word; an ACTUAL is what happened,
            // and "I did bodyweight reps" is not a figure anything can score.
            // The storage contract is genuinely free text
            // (`buildSessionEntries` writes these verbatim and both apps parse
            // the leading number out), so nothing downstream constrains this —
            // it is narrowed here deliberately, to keep the member on the one
            // keyboard that can express the answer.
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            inputFormatters: [LengthLimitingTextInputFormatter(12)],
            style: AppText.cardTitle(size: 18).copyWith(color: p.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppText.cardTitle(size: 18)
                  .copyWith(color: p.textMuted.withValues(alpha: 0.5)),
              filled: true,
              fillColor: p.inputFill,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                borderSide: BorderSide(color: widget.accent, width: 1.4),
              ),
            ),
          ),
        ],
      );

  /// Three states, because the log has three. "Not done" is not a delete —
  /// the set stays prescribed and stays visible to the coach; it simply has no
  /// result yet, which is a different thing from a skip the member decided on.
  Widget _statePicker(AppPalette p) {
    const options = <(SetLogState, String, IconData)>[
      (SetLogState.completed, 'Completed', Icons.check_rounded),
      (SetLogState.skipped, 'Skipped', Icons.remove_rounded),
      (SetLogState.pending, 'Not done', Icons.circle_outlined),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (state, label, icon) in options)
          Semantics(
            button: true,
            selected: _state == state,
            inMutuallyExclusiveGroup: true,
            label: label,
            container: true,
            excludeSemantics: true,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: () => setState(() => _state = state),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _state == state
                        ? widget.accent.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: _state == state ? widget.accent : p.border,
                      width: _state == state ? 1.4 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon,
                          size: 15,
                          color:
                              _state == state ? widget.accent : p.textMuted),
                      const SizedBox(width: 7),
                      Text(
                        label,
                        style: AppText.label(size: 12.5).copyWith(
                          color: _state == state
                              ? widget.accent
                              : p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _blocker(AppPalette p) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 14, color: p.textMuted),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Add the reps or the weight you managed, or mark the set as '
              'skipped.',
              style: AppText.body(size: 12).copyWith(color: p.textMuted),
            ),
          ),
        ],
      );

  Widget _bottomBar(AppPalette p) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: p.border)),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            // ALWAYS tappable while it can save, and when it cannot the reason
            // is already on screen above it — the Profile editor's lesson: a
            // dead button with no explanation is the worst of both.
            onPressed: _canSave ? _save : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.accent,
              disabledBackgroundColor: p.border,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text('Save set',
                style: AppText.label(size: 14.5)
                    .copyWith(color: Colors.white)),
          ),
        ),
      );

  /// "10 reps × 20 kg" — the app's one phrasing for a prescribed pair, and the
  /// same rule `TodayWorkoutSection` and `NextUp.targetLine` apply: a dimension
  /// the coach left blank is absent, and a weight that already carries its unit
  /// is not suffixed twice.
  /// A PLACEHOLDER THE KEYBOARD CAN ACTUALLY PRODUCE.
  ///
  /// The hint used to echo the coach's prescription verbatim, which broke in
  /// two ways at once. The keyboard here is numeric, so a hint of
  /// "bodyweight" — or the hyphen in "8-12" — showed the member an example
  /// they physically could not type. And the full prescription is ALREADY
  /// stated one line above ("coach asked for 8-12 reps × bodyweight"), so
  /// repeating it inside the field spent the one piece of in-field guidance on
  /// a fact the member had just read.
  ///
  /// These fields record what the member DID: a measurement, and therefore a
  /// number. So the hint is the prescription's leading number when there is
  /// one ("8-12" → "8", a useful anchor for what to type) and a plain unit
  /// otherwise — never a word.
  static String _hintFor(String prescribed, String fallback) {
    final match = RegExp(r'\d+(\.\d+)?').firstMatch(prescribed.trim());
    return match?.group(0) ?? fallback;
  }

  static String _targetLine(SetLog s) {
    final r = s.pReps.trim();
    final w = s.pWeight.trim();
    final hasUnit = w.isEmpty || RegExp(r'[a-zA-Z]').hasMatch(w);
    return [
      if (r.isNotEmpty) '$r reps',
      if (w.isNotEmpty) hasUnit ? w : '$w kg',
    ].join(' × ');
  }
}
