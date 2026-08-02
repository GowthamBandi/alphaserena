import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/domain/food_portion_math.dart';
import '../../../core/models/member_food.dart';
import '../../../core/models/nutrition_day_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/glass_card.dart';

/// What the member chose, handed back to the caller. Null means they backed out.
class FoodQuantityResult {
  final PortionSelection selection;
  final String mealSlot;
  final String? note;

  const FoodQuantityResult({
    required this.selection,
    required this.mealSlot,
    this.note,
  });
}

/// NIP PHASE 3A — FOOD DETAILS + QUANTITY + LIVE PREVIEW.
///
/// The contract of this sheet is "never surprise the user": the numbers shown
/// while the member is adjusting are the EXACT numbers that will be written to
/// their log, computed by the same [scaleMacros] the write path calls. There is
/// no second rounding, no server-side re-derivation, and no "approximately".
///
/// Opened for a searched food, a recent food and a plan food alike — one sheet,
/// so the preview, the arithmetic and the stored shape cannot diverge by
/// entry point.
class FoodQuantitySheet extends StatefulWidget {
  final MemberFood food;
  final String mealSlot;

  /// Prefilled when EDITING an existing entry rather than adding a new one.
  final PortionSelection? initialSelection;
  final String? initialNote;
  final bool isEdit;

  const FoodQuantitySheet({
    super.key,
    required this.food,
    required this.mealSlot,
    this.initialSelection,
    this.initialNote,
    this.isEdit = false,
  });

  @override
  State<FoodQuantitySheet> createState() => _FoodQuantitySheetState();
}

class _FoodQuantitySheetState extends State<FoodQuantitySheet> {
  late PortionSelection _selection;
  late String _mealSlot;
  late final TextEditingController _amount;
  late final TextEditingController _note;

  /// Guards the double-tap: a second tap on Add while the first is closing the
  /// sheet would pop twice and, on some navigators, log the food twice.
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selection = widget.initialSelection ?? widget.food.defaultSelection;
    _mealSlot = widget.mealSlot;
    _amount = TextEditingController(text: _formatQty(_selection.quantity));
    _note = TextEditingController(text: widget.initialNote ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  static String _formatQty(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  Map<String, double> get _preview =>
      scaleMacros(widget.food.per100, _selection.totalGrams);

  /// Applies a typed amount without fighting the member's cursor: the text
  /// field stays the source of truth for what is on screen, and only the
  /// derived selection is rebuilt.
  void _onAmountChanged(String raw) {
    final v = double.tryParse(raw.trim());
    if (v == null) {
      setState(() {}); // re-render to surface the disabled Add button
      return;
    }
    setState(() {
      _selection = PortionSelection(
        mode: _selection.mode,
        quantity: v,
        portionLabel: _selection.portionLabel,
        gramsPerPortion: _selection.gramsPerPortion,
      );
    });
  }

  void _setMode(PortionMode mode, {FoodPortionOption? portion}) {
    setState(() {
      if (mode == PortionMode.grams) {
        // Carry the CURRENT gram amount across rather than resetting to a
        // default: the member switching to grams wants to fine-tune what they
        // already chose, not start over.
        final grams = _selection.totalGrams > 0
            ? _selection.totalGrams
            : kFoodBaseGrams;
        _selection = PortionSelection.grams(grams);
      } else if (portion != null) {
        _selection = PortionSelection(
          mode: PortionMode.portion,
          quantity: 1,
          portionLabel: portion.label,
          gramsPerPortion: portion.grams,
        );
      }
      _amount.text = _formatQty(_selection.quantity);
      _amount.selection =
          TextSelection.collapsed(offset: _amount.text.length);
    });
  }

  void _bump(double delta) {
    final next = (_selection.quantity + delta);
    if (next <= 0) return;
    setState(() {
      _selection = PortionSelection(
        mode: _selection.mode,
        quantity: double.parse(next.toStringAsFixed(2)),
        portionLabel: _selection.portionLabel,
        gramsPerPortion: _selection.gramsPerPortion,
      );
      _amount.text = _formatQty(_selection.quantity);
      _amount.selection =
          TextSelection.collapsed(offset: _amount.text.length);
    });
  }

  void _submit() {
    if (_submitting || !_selection.isValid) return;
    setState(() => _submitting = true);
    Navigator.of(context).pop(
      FoodQuantityResult(
        selection: _selection,
        mealSlot: _mealSlot,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final media = MediaQuery.of(context);
    final preview = _preview;
    final overCalories = (preview['calories'] ?? 0) > kMaxEntryCalories;
    final overGrams = _selection.totalGrams > kMaxEntryGrams;

    return Padding(
      // Lifts the whole sheet above the keyboard so the Add button and the
      // preview stay visible while the member types an amount — the two things
      // they are looking at.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        decoration: BoxDecoration(
          color: p.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _grabber(p),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  children: [
                    _header(p),
                    const SizedBox(height: 18),
                    _mealSelector(p),
                    const SizedBox(height: 18),
                    _amountSection(p),
                    const SizedBox(height: 18),
                    _previewCard(p, preview),
                    if (overGrams || overCalories) ...[
                      const SizedBox(height: 12),
                      _limitWarning(p, overGrams: overGrams),
                    ],
                    const SizedBox(height: 16),
                    _noteField(p),
                  ],
                ),
              ),
              _actionBar(p, preview),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grabber(AppPalette p) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: p.textMuted.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _header(AppPalette p) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.food.name,
                  style: AppText.title(size: 19).copyWith(color: p.textPrimary),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FoodTierBadge(
                      tier: widget.food.tier,
                      official: widget.food.isOfficial,
                    ),
                    if (widget.food.brand != null)
                      Text(
                        widget.food.brand!,
                        style: AppText.body(size: 12)
                            .copyWith(color: p.textMuted),
                      ),
                    if (widget.food.serving != null)
                      Text(
                        '· ${widget.food.serving}',
                        style: AppText.body(size: 12)
                            .copyWith(color: p.textMuted),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.close_rounded, color: p.textMuted),
            tooltip: 'Close',
          ),
        ],
      );

  Widget _mealSelector(AppPalette p) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(p, 'Meal'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final slot in kMealSlots)
                _chip(
                  p,
                  label: kMealLabels[slot]!,
                  selected: _mealSlot == slot,
                  onTap: () => setState(() => _mealSlot = slot),
                ),
            ],
          ),
        ],
      );

  Widget _amountSection(AppPalette p) {
    final portions = widget.food.portions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(p, 'How much'),
        const SizedBox(height: 8),
        if (portions.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final portion in portions)
                _chip(
                  p,
                  label: widget.food.massKnown
                      ? '${portion.label} · ${_formatQty(portion.grams)} g'
                      : portion.label,
                  selected: _selection.mode == PortionMode.portion &&
                      _selection.portionLabel == portion.label,
                  onTap: () =>
                      _setMode(PortionMode.portion, portion: portion),
                ),
              // Offered only when a real mass is known. For a legacy entry the
              // gram basis is a scaling pivot, not a measurement — switching
              // to grams would write that pivot back as the member's amount.
              if (widget.food.massKnown)
                _chip(
                  p,
                  label: 'Grams',
                  selected: _selection.mode == PortionMode.grams,
                  onTap: () => _setMode(PortionMode.grams),
                ),
            ],
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            _stepper(p, icon: Icons.remove_rounded, onTap: () => _bump(
                  _selection.mode == PortionMode.grams ? -10 : -0.5,
                )),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _amount,
                onChanged: _onAmountChanged,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                textAlign: TextAlign.center,
                style: AppText.title(size: 22).copyWith(color: p.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: p.isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFF3F5F9),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  suffixText: _selection.storedUnit,
                  suffixStyle:
                      AppText.body(size: 13).copyWith(color: p.textMuted),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _stepper(p, icon: Icons.add_rounded, onTap: () => _bump(
                  _selection.mode == PortionMode.grams ? 10 : 0.5,
                )),
          ],
        ),
        // Stated only when it is a MEASUREMENT. A legacy entry has no recorded
        // mass, and an honest gap beats a confident wrong figure.
        if (widget.food.massKnown &&
            _selection.mode == PortionMode.portion &&
            _selection.totalGrams > 0) ...[
          const SizedBox(height: 8),
          Text(
            '= ${_formatQty(_selection.totalGrams)} g',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
        ],
      ],
    );
  }

  /// THE PREVIEW. Shown before anything is written, always.
  Widget _previewCard(AppPalette p, Map<String, double> preview) => Container(
        padding: const EdgeInsets.all(16),
        decoration: glassCard(p, radius: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Both sides FLEX. Found by the widget test: at 390dp the fixed
            // label plus a Spacer plus a four-digit calorie figure overflowed
            // by 17px — and a nutrition number is the one thing on this card
            // that must never be clipped. The label yields first (it is
            // static text the member has already read); the figure keeps its
            // space and right-aligns.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    'You will log',
                    overflow: TextOverflow.ellipsis,
                    style: AppText.cardTitle(size: 14)
                        .copyWith(color: p.textPrimary),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${(preview['calories'] ?? 0).round()} kcal',
                    textAlign: TextAlign.end,
                    style: AppText.title(size: 20)
                        .copyWith(color: const Color(0xFF2EBD59)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Wraps rather than scrolls: at large text scales four macros on
            // one row would overflow, and a nutrition figure must never be
            // truncated.
            Wrap(
              spacing: 18,
              runSpacing: 12,
              children: [
                _macroStat(p, 'Protein', preview['protein'] ?? 0),
                _macroStat(p, 'Carbs', preview['carbs'] ?? 0),
                _macroStat(p, 'Fat', preview['fat'] ?? 0),
                _macroStat(p, 'Fiber', preview['fiber'] ?? 0),
              ],
            ),
          ],
        ),
      );

  Widget _macroStat(AppPalette p, String label, double grams) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: AppText.body(size: 11).copyWith(color: p.textMuted)),
          const SizedBox(height: 2),
          Text(
            '${grams.toStringAsFixed(grams < 10 ? 1 : 0)} g',
            style: AppText.cardTitle(size: 15).copyWith(color: p.textPrimary),
          ),
        ],
      );

  Widget _limitWarning(AppPalette p, {required bool overGrams}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: p.error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.error.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: p.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                overGrams
                    ? 'That is over ${kMaxEntryGrams.round()} g in one entry. '
                        'Split it into separate entries so your coach can read it.'
                    : 'That is over ${kMaxEntryCalories.round()} kcal in one '
                        'entry. Double-check the amount before logging.',
                style: AppText.body(size: 12).copyWith(color: p.textPrimary),
              ),
            ),
          ],
        ),
      );

  Widget _noteField(AppPalette p) => TextField(
        controller: _note,
        maxLength: 280,
        minLines: 1,
        maxLines: 3,
        style: AppText.body(size: 14).copyWith(color: p.textPrimary),
        decoration: InputDecoration(
          hintText: 'Note for your coach (optional)',
          hintStyle: AppText.body(size: 13).copyWith(color: p.textMuted),
          counterText: '',
          filled: true,
          fillColor: p.isDark
              ? Colors.white.withValues(alpha: 0.05)
              : const Color(0xFFF3F5F9),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      );

  Widget _actionBar(AppPalette p, Map<String, double> preview) {
    final canAdd = _selection.isValid && !_submitting;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: canAdd ? _submit : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: p.accent,
            disabledBackgroundColor: p.accent.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            widget.isEdit
                ? 'Save changes'
                : 'Add to ${kMealLabels[_mealSlot] ?? 'meal'} · '
                    '${(preview['calories'] ?? 0).round()} kcal',
            style: AppText.label(size: 15).copyWith(color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(AppPalette p, String text) => Text(
        text.toUpperCase(),
        style: AppText.label(size: 11).copyWith(
          color: p.textMuted,
          letterSpacing: 0.8,
        ),
      );

  Widget _stepper(AppPalette p,
          {required IconData icon, required VoidCallback onTap}) =>
      Material(
        color: p.isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF3F5F9),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: p.textPrimary, size: 20),
          ),
        ),
      );

  Widget _chip(
    AppPalette p, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      Material(
        color: selected
            ? p.accent
            : (p.isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFF3F5F9)),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              label,
              style: AppText.body(size: 13).copyWith(
                color: selected ? Colors.white : p.textPrimary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      );
}

/// WHICH LIBRARY a food came from, shown to the member.
///
/// Not decoration: when a search returns the gym's "Roti" and the platform's
/// "Roti / Chapati", the badge is what tells the member which one their coach
/// built their plan against.
class FoodTierBadge extends StatelessWidget {
  final MemberFoodTier tier;
  final bool official;

  const FoodTierBadge({super.key, required this.tier, this.official = false});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isOrg = tier == MemberFoodTier.org;
    final color = isOrg ? p.accent : const Color(0xFF3B82F6);
    final label = isOrg ? "Your coach's" : (official ? 'Verified' : 'Library');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (official && !isOrg) ...[
            Icon(Icons.verified_rounded, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: AppText.body(size: 10.5).copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
