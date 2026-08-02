import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../controllers/food_history_controller.dart';
import '../../../core/models/nutrition_day_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/glass_card.dart';

/// PHASE 3B — PREVIOUS DAYS.
///
/// A chronological list of the member's logged days with per-day totals, and a
/// per-meal breakdown when a day is opened.
///
/// Days the member never logged are ABSENT rather than shown as zeroes: a row
/// reading "0 kcal" is a claim about their eating, while no row is the truth
/// that nothing was recorded. The same discipline the rest of this platform
/// applies to "not logged" versus "logged none".
class FoodHistoryScreen extends StatelessWidget {
  const FoodHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = Get.isRegistered<FoodHistoryController>()
        ? Get.find<FoodHistoryController>()
        : Get.put(FoodHistoryController());

    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Obx(
          () => Text(
            c.selected.value == null
                ? 'Previous Days'
                : _dayTitle(c.selected.value!.date),
            style: AppText.title(size: 20).copyWith(color: p.textPrimary),
          ),
        ),
        // NOT wrapped in Obx. The button looks identical in both states, so an
        // Obx here would build without reading a single observable — which
        // GetX treats as an error and throws on ("improper use of a GetX"),
        // taking the whole screen down. Reading `selected.value` inside
        // onPressed does not subscribe anything; it just reads the current
        // value at tap time, which is exactly what this needs.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: p.textPrimary,
          onPressed: () {
            // Backing out of an opened day returns to the LIST, not out of
            // history entirely — the member drilled in, so back means up.
            if (c.selected.value != null) {
              c.closeDay();
            } else {
              Navigator.of(context).maybePop();
            }
          },
        ),
      ),
      body: Obx(() {
        final day = c.selected.value;
        if (day != null) return _dayDetail(day, p);
        if (c.isLoading.value) return _skeleton(p);
        if (c.loadError.value && c.days.isEmpty) return _error(c, p);
        final logged = c.loggedDays;
        if (logged.isEmpty) return _empty(p);
        return _list(c, logged, p);
      }),
    );
  }

  // ── LIST ─────────────────────────────────────────────────────────────────

  Widget _list(FoodHistoryController c, List<HistoryDay> logged, AppPalette p) =>
      NotificationListener<ScrollNotification>(
        onNotification: (n) {
          // Page backwards when the member nears the bottom, rather than
          // fetching a year up front.
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
            c.loadMore();
          }
          return false;
        },
        child: RefreshIndicator(
          color: p.accent,
          onRefresh: c.load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              _summary(c, logged, p),
              const SizedBox(height: 18),
              for (final d in logged) _dayRow(c, d, p),
              Obx(
                () => c.isLoadingMore.value
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : const SizedBox(height: 8),
              ),
              Obx(
                () => c.reachedEnd.value
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Center(
                          child: Text(
                            'That is everything you have logged.',
                            style: AppText.body(size: 12)
                                .copyWith(color: p.textMuted),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );

  Widget _summary(
    FoodHistoryController c,
    List<HistoryDay> logged,
    AppPalette p,
  ) {
    final avg = c.averageCalories;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: glassCard(p, radius: 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Days logged',
                    style:
                        AppText.body(size: 12).copyWith(color: p.textMuted)),
                const SizedBox(height: 4),
                Text('${logged.length}',
                    style: AppText.title(size: 24)
                        .copyWith(color: p.textPrimary)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Average day',
                    style:
                        AppText.body(size: 12).copyWith(color: p.textMuted)),
                const SizedBox(height: 4),
                Text(
                  // Averaged over LOGGED days only — unlogged days are not
                  // zeroes to be divided into.
                  avg == null ? '—' : '${avg.round()} kcal',
                  style: AppText.title(size: 24)
                      .copyWith(color: const Color(0xFF2EBD59)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayRow(FoodHistoryController c, HistoryDay d, AppPalette p) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => c.open(d),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: glassCard(p, radius: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_dayTitle(d.date),
                            style: AppText.cardTitle(size: 14)
                                .copyWith(color: p.textPrimary)),
                        const SizedBox(height: 3),
                        Text(
                          '${d.entryCount} '
                          '${d.entryCount == 1 ? 'item' : 'items'} · '
                          '${d.byMeal.length} '
                          '${d.byMeal.length == 1 ? 'meal' : 'meals'}',
                          style: AppText.body(size: 12)
                              .copyWith(color: p.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Text('${d.calories.round()} kcal',
                      style: AppText.cardTitle(size: 14)
                          .copyWith(color: p.textPrimary)),
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: p.textMuted),
                ],
              ),
            ),
          ),
        ),
      );

  // ── ONE DAY ──────────────────────────────────────────────────────────────

  Widget _dayDetail(HistoryDay d, AppPalette p) {
    final byMeal = d.byMeal;
    final totals = d.totals;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: glassCard(p, radius: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${d.calories.round()}',
                  style: AppText.display(size: 32)
                      .copyWith(color: const Color(0xFF2EBD59))),
              Text('kcal from ${d.entryCount} '
                  '${d.entryCount == 1 ? 'item' : 'items'}',
                  style:
                      AppText.body(size: 12).copyWith(color: p.textMuted)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 20,
                runSpacing: 12,
                children: [
                  _macro(p, 'Protein', totals['protein'] ?? 0),
                  _macro(p, 'Carbs', totals['carbs'] ?? 0),
                  _macro(p, 'Fat', totals['fat'] ?? 0),
                  _macro(p, 'Fiber', totals['fiber'] ?? 0),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (final slot in [...kMealSlots, kOtherMealSlot])
          if (byMeal[slot] != null && byMeal[slot]!.isNotEmpty)
            _mealBlock(p, slot, byMeal[slot]!),
        // A past day is READ ONLY. Editing history from a list built for
        // review invites accidental rewrites of days the coach has already
        // read; today's log, where corrections belong, is fully editable.
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Past days are read-only.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _mealBlock(AppPalette p, String slot, List<FoodEntry> entries) {
    final kcal = entries.fold<double>(0, (a, e) => a + e.consumed.calories);
    final startedAt = mealStartedAt(entries);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text((kMealLabels[slot] ?? 'Other').toUpperCase(),
                  style: AppText.label(size: 11)
                      .copyWith(color: p.textMuted, letterSpacing: 0.8)),
              const SizedBox(width: 8),
              Text('${kcal.round()} kcal',
                  style:
                      AppText.body(size: 11).copyWith(color: p.textMuted)),
              const Spacer(),
              if (startedAt != null)
                Text(
                  // DERIVED from the earliest entry, never stored.
                  DateFormat('h:mm a').format(
                    DateTime.fromMillisecondsSinceEpoch(startedAt),
                  ),
                  style:
                      AppText.body(size: 11).copyWith(color: p.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final e in entries) _entryRow(p, e),
        ],
      ),
    );
  }

  Widget _entryRow(AppPalette p, FoodEntry e) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: glassCard(p, radius: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.foodName.isEmpty ? 'Food' : e.foodName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.cardTitle(size: 13.5)
                            .copyWith(color: p.textPrimary)),
                    const SizedBox(height: 2),
                    Text(entryAmountLabel(e),
                        style: AppText.body(size: 11.5)
                            .copyWith(color: p.textMuted)),
                  ],
                ),
              ),
              Text('${e.consumed.calories.round()} kcal',
                  style: AppText.cardTitle(size: 13)
                      .copyWith(color: p.textPrimary)),
            ],
          ),
        ),
      );

  Widget _macro(AppPalette p, String label, double grams) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppText.body(size: 11).copyWith(color: p.textMuted)),
          const SizedBox(height: 2),
          Text('${grams.toStringAsFixed(grams < 10 ? 1 : 0)} g',
              style:
                  AppText.cardTitle(size: 15).copyWith(color: p.textPrimary)),
        ],
      );

  // ── STATES ───────────────────────────────────────────────────────────────

  Widget _empty(AppPalette p) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_rounded, size: 44, color: p.textMuted),
              const SizedBox(height: 14),
              Text('No history yet',
                  style: AppText.cardTitle(size: 15)
                      .copyWith(color: p.textPrimary)),
              const SizedBox(height: 6),
              Text(
                'Days you log will appear here from tomorrow. Today\'s food '
                'stays on the Diet screen.',
                textAlign: TextAlign.center,
                style: AppText.body(size: 13).copyWith(color: p.textMuted),
              ),
            ],
          ),
        ),
      );

  Widget _error(FoodHistoryController c, AppPalette p) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 40, color: p.textMuted),
              const SizedBox(height: 14),
              Text("Couldn't load your history",
                  style: AppText.cardTitle(size: 15)
                      .copyWith(color: p.textPrimary)),
              const SizedBox(height: 6),
              Text(
                'This is a connection problem — nothing you logged is lost.',
                textAlign: TextAlign.center,
                style: AppText.body(size: 13).copyWith(color: p.textMuted),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: c.load,
                style: OutlinedButton.styleFrom(foregroundColor: p.accent),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );

  Widget _skeleton(AppPalette p) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemCount: 6,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            height: i == 0 ? 96 : 66,
            decoration: BoxDecoration(
              color: p.isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : const Color(0xFFF1F3F7),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );

  static String _dayTitle(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(d);
    return DateFormat('EEE, d MMM').format(d);
  }
}

/// The human amount on a logged entry — "2 katori", "180 g", or a dash when
/// the member only marked a prescribed item.
///
/// Shared by the Diet screen and history so one entry never reads two ways.
String entryAmountLabel(FoodEntry e) {
  if (e.quantity == null) return e.unit.isEmpty ? '—' : e.unit;
  final q = e.quantity!;
  final n = q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(1);
  return e.unit.isEmpty ? n : '$n ${e.unit}';
}
