import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../controllers/food_log_controller.dart';
import '../../../controllers/food_search_controller.dart';
import '../../../core/domain/food_portion_math.dart';
import '../../../core/models/member_food.dart';
import '../../../core/models/nutrition_day_model.dart';
import '../../../core/services/nutrition_day_service.dart' show DietSaveResult;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/glass_card.dart';
import 'food_quantity_sheet.dart';

/// NIP PHASE 3A — ADD FOOD.
///
/// The member's primary nutrition workflow: choose a meal, find a food, set the
/// amount, see exactly what will be logged, log it.
///
/// STRUCTURE. Meal first, then search — because the meal is the one choice the
/// member always knows before they start, and fixing it up front means adding
/// three foods to lunch costs one meal tap instead of three. The sheet still
/// lets them change it per food, for the correction case.
///
/// The screen stays open after a successful add. Logging one food and being
/// thrown back to Home is the single most common complaint about food loggers;
/// a meal is usually more than one item.
class AddFoodScreen extends StatefulWidget {
  /// The meal to preselect — passed when entered from a meal's "+" affordance.
  final String? initialMealSlot;

  /// Injected search controller.
  ///
  /// Exists for two reasons. It is the seam the on-device suite drives the
  /// real screen through without a member session — and it removes an
  /// unconditional `Get.put(tag: 'add_food')`, which would REPLACE the
  /// controller of an Add Food screen still on the navigation stack: the
  /// second screen's dispose then deletes the tag, and returning to the first
  /// leaves it bound to a disposed controller.
  final FoodSearchController? searchController;

  const AddFoodScreen({
    super.key,
    this.initialMealSlot,
    this.searchController,
  });

  @override
  State<AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends State<AddFoodScreen> {
  late final FoodSearchController _search;
  late final FoodLogController _log;
  late final bool _ownsSearch;
  late final String _searchTag;
  late final TextEditingController _queryField;
  final FocusNode _searchFocus = FocusNode();

  late String _mealSlot;

  /// Foods added in THIS session, newest first — the running receipt.
  ///
  /// Without it the member taps Add, the sheet closes, and nothing visibly
  /// happens: the totals that changed are on another screen. This is the
  /// feedback that makes rapid multi-item entry feel safe.
  final List<_JustAdded> _justAdded = [];

  @override
  void initState() {
    super.initState();
    _mealSlot = widget.initialMealSlot ?? defaultMealSlotForNow();
    // Each screen instance owns its OWN controller, keyed by identity rather
    // than a shared tag, so two Add Food screens on the stack cannot evict
    // each other. `_ownsSearch` records whether we created it, so an injected
    // one is never deleted out from under its owner.
    final injected = widget.searchController;
    _ownsSearch = injected == null;
    _searchTag = 'add_food_${identityHashCode(this)}';
    _search = injected ?? Get.put(FoodSearchController(), tag: _searchTag);
    _log = Get.isRegistered<FoodLogController>()
        ? Get.find<FoodLogController>()
        : Get.put(FoodLogController());
    _queryField = TextEditingController();
    // The member opened a search screen. Focusing the field is what they came
    // for — but only when they did NOT arrive with a meal preselected from a
    // "+" tap, where the browse list is the more useful first thing to see.
    if (widget.initialMealSlot == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _queryField.dispose();
    _searchFocus.dispose();
    if (_ownsSearch) Get.delete<FoodSearchController>(tag: _searchTag);
    super.dispose();
  }

  /// The meal a member most likely means at this hour.
  ///
  /// Saves a tap in the common case and is always visibly overridable — the
  /// meal chips are on screen, not buried. It never guesses silently.
  static String defaultMealSlotForNow([DateTime? now]) {
    final h = (now ?? DateTime.now()).hour;
    if (h < 10) return 'breakfast';
    if (h < 12) return 'mid_morning';
    if (h < 16) return 'lunch';
    if (h < 19) return 'evening_snack';
    if (h < 22) return 'dinner';
    return 'bedtime';
  }

  Future<void> _openFood(MemberFood food) async {
    // The day may have rolled over while this screen sat open.
    _log.ensureFreshDay();

    final result = await showModalBottomSheet<FoodQuantityResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FoodQuantitySheet(food: food, mealSlot: _mealSlot),
    );
    if (result == null || !mounted) return;

    final outcome = await _log.logFood(
      food: food,
      mealSlot: result.mealSlot,
      selection: result.selection,
      note: result.note,
    );
    if (!mounted) return;

    if (outcome == DietSaveResult.failed) {
      _toast(
        'Could not log ${food.name}. Try again.',
        isError: true,
      );
      return;
    }

    setState(() {
      _justAdded.insert(
        0,
        _JustAdded(
          food: food,
          mealSlot: result.mealSlot,
          calories: (scaleMacros(food.per100, result.selection.totalGrams)[
                  'calories'] ??
              0),
          queued: outcome == DietSaveResult.queued,
        ),
      );
    });
    unawaited(_search.refreshRecents());

    _toast(
      outcome == DietSaveResult.queued
          // Honest, and specifically NOT an error: the entry is in the local
          // cache and Firestore replays it on reconnect.
          ? '${food.name} saved on this device — syncs when you\'re back online'
          : '${food.name} added to ${kMealLabels[result.mealSlot]}',
    );
  }

  void _toast(String message, {bool isError = false}) {
    final p = context.palette;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: AppText.body(size: 13).copyWith(color: Colors.white),
          ),
          backgroundColor: isError ? p.error : const Color(0xFF2EBD59),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Add Food',
          style: AppText.title(size: 20).copyWith(color: p.textPrimary),
        ),
      ),
      // Tap anywhere off the field to dismiss the keyboard — the list is the
      // thing being read once a search returns.
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          children: [
            _mealStrip(p),
            _searchField(p),
            Expanded(child: _results(p)),
          ],
        ),
      ),
    );
  }

  Widget _mealStrip(AppPalette p) => SizedBox(
        height: 46,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final slot in kMealSlots) ...[
              _mealChip(p, slot),
              const SizedBox(width: 8),
            ],
          ],
        ),
      );

  Widget _mealChip(AppPalette p, String slot) {
    final selected = _mealSlot == slot;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? p.accent
            : (p.isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFF3F5F9)),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _mealSlot = slot),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Text(
                kMealLabels[slot]!,
                style: AppText.body(size: 13).copyWith(
                  color: selected ? Colors.white : p.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchField(AppPalette p) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          controller: _queryField,
          focusNode: _searchFocus,
          onChanged: _search.onQueryChanged,
          onSubmitted: _search.runSearch,
          textInputAction: TextInputAction.search,
          style: AppText.body(size: 15).copyWith(color: p.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search foods',
            hintStyle: AppText.body(size: 14).copyWith(color: p.textMuted),
            prefixIcon: Icon(Icons.search_rounded, color: p.textMuted, size: 20),
            suffixIcon: Obx(
              () => _search.query.value.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: 'Clear',
                      icon: Icon(Icons.close_rounded,
                          color: p.textMuted, size: 18),
                      onPressed: () {
                        _queryField.clear();
                        _search.clear();
                      },
                    ),
            ),
            filled: true,
            fillColor: p.isDark
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0xFFF3F5F9),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      );

  Widget _results(AppPalette p) => Obx(() {
        final state = _search.state.value;
        final plan = _search.planFoodsFor(_mealSlot);
        final recents = _search.recents;
        final results = _search.results;
        final browsing = _search.query.value.trim().isEmpty;

        if (state == FoodSearchState.loading && results.isEmpty) {
          return _skeleton(p);
        }
        if (state == FoodSearchState.offline && results.isEmpty) {
          return _emptyState(
            p,
            icon: Icons.wifi_off_rounded,
            title: 'You are offline',
            body: 'Food search needs a connection. Anything you have already '
                'logged is safe and will sync when you reconnect.',
            action: ('Try again', _search.retry),
          );
        }
        if (state == FoodSearchState.failed && results.isEmpty) {
          return _emptyState(
            p,
            icon: Icons.error_outline_rounded,
            title: "Couldn't load foods",
            body: 'Something went wrong reaching the food library.',
            action: ('Try again', _search.retry),
          );
        }
        if (state == FoodSearchState.empty) {
          return _emptyState(
            p,
            icon: Icons.search_off_rounded,
            title: 'No foods match "${_search.query.value.trim()}"',
            body: 'Try a shorter or simpler word — "chicken" finds more than '
                '"grilled chicken breast".',
          );
        }

        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            if (_search.keepTyping.value) _hint(p, 'Keep typing to search'),
            if (_search.orgResultsPartial.value)
              _hint(
                p,
                "Showing part of your coach's library — some foods may be missing.",
              ),
            if (_justAdded.isNotEmpty) ...[
              _sectionHeader(p, 'Added just now'),
              for (final a in _justAdded.take(5)) _justAddedRow(p, a),
              const SizedBox(height: 18),
            ],
            if (browsing && plan.isNotEmpty) ...[
              _sectionHeader(
                p,
                'From your plan · ${kMealLabels[_mealSlot]}',
              ),
              for (final f in plan) _foodRow(p, f),
              const SizedBox(height: 18),
            ],
            if (browsing && recents.isNotEmpty) ...[
              _sectionHeader(p, 'Recent'),
              for (final f in recents) _foodRow(p, f),
              const SizedBox(height: 18),
            ],
            if (results.isNotEmpty) ...[
              _sectionHeader(p, browsing ? 'All foods' : 'Results'),
              for (final f in results) _foodRow(p, f),
            ],
            if (browsing && results.isEmpty && plan.isEmpty && recents.isEmpty)
              _emptyState(
                p,
                icon: Icons.restaurant_rounded,
                title: 'Search to add your first food',
                body: 'Your gym\'s foods appear first, then the wider library.',
                inline: true,
              ),
          ],
        );
      });

  Widget _sectionHeader(AppPalette p, String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: AppText.label(size: 11)
              .copyWith(color: p.textMuted, letterSpacing: 0.8),
        ),
      );

  Widget _foodRow(AppPalette p, MemberFood food) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openFood(food),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: glassCard(p, radius: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          food.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.cardTitle(size: 14)
                              .copyWith(color: p.textPrimary),
                        ),
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FoodTierBadge(
                              tier: food.tier,
                              official: food.isOfficial,
                            ),
                            Text(
                              '${food.caloriesPer100.round()} kcal / '
                              '${kFoodBaseGrams.round()} g',
                              style: AppText.body(size: 11.5)
                                  .copyWith(color: p.textMuted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.add_circle_outline_rounded,
                      color: p.accent, size: 22),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _justAddedRow(AppPalette p, _JustAdded a) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFF2EBD59).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF2EBD59).withValues(alpha: 0.30),
            ),
          ),
          child: Row(
            children: [
              Icon(
                a.queued
                    ? Icons.cloud_queue_rounded
                    : Icons.check_circle_rounded,
                size: 18,
                color: const Color(0xFF2EBD59),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${a.food.name} · ${kMealLabels[a.mealSlot]}'
                  '${a.queued ? ' · will sync' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      AppText.body(size: 13).copyWith(color: p.textPrimary),
                ),
              ),
              Text(
                '${a.calories.round()} kcal',
                style: AppText.cardTitle(size: 13)
                    .copyWith(color: p.textPrimary),
              ),
            ],
          ),
        ),
      );

  Widget _hint(AppPalette p, String text) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 10),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 14, color: p.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: AppText.body(size: 12).copyWith(color: p.textMuted),
              ),
            ),
          ],
        ),
      );

  Widget _skeleton(AppPalette p) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemCount: 7,
        itemBuilder: (_, _) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: p.isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : const Color(0xFFF1F3F7),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );

  Widget _emptyState(
    AppPalette p, {
    required IconData icon,
    required String title,
    required String body,
    (String, VoidCallback)? action,
    bool inline = false,
  }) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: p.textMuted),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppText.cardTitle(size: 15).copyWith(color: p.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          textAlign: TextAlign.center,
          style: AppText.body(size: 13).copyWith(color: p.textMuted),
        ),
        if (action != null) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: action.$2,
            style: OutlinedButton.styleFrom(
              foregroundColor: p.accent,
              side: BorderSide(color: p.accent.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(action.$1),
          ),
        ],
      ],
    );
    if (inline) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: content,
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: content,
      ),
    );
  }
}

class _JustAdded {
  final MemberFood food;
  final String mealSlot;
  final double calories;
  final bool queued;

  const _JustAdded({
    required this.food,
    required this.mealSlot,
    required this.calories,
    required this.queued,
  });
}
