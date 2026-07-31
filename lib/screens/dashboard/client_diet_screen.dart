import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:percent_indicator/percent_indicator.dart';

import '../../controllers/diet_log_controller.dart';
import '../../controllers/member_controller.dart';
import '../../controllers/membership_controller.dart';
import '../../controllers/training_controller.dart';
import '../../core/domain/nutrition_targets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/diet_adherence.dart';
import '../../core/widgets/gradient_title.dart';
import 'membership_screen.dart';

/// The member's daily nutrition adherence logger: the coach-prescribed foods,
/// grouped by meal, each markable eaten / partial / skipped. Every mark persists
/// to `client_diet_logs` (via [DietLogController]) so the coach sees compliance.
class ClientDietScreen extends StatelessWidget {
  ClientDietScreen({super.key});

  final TrainingController c = Get.isRegistered<TrainingController>()
      ? Get.find<TrainingController>()
      : Get.put(TrainingController());
  final DietLogController log = Get.isRegistered<DietLogController>()
      ? Get.find<DietLogController>()
      : Get.put(DietLogController());

  // Canonical meal ordering; anything unknown (incl. legacy '') sorts last.
  static const List<String> _mealOrder = [
    'Breakfast',
    'Mid-morning',
    'Morning Snack',
    'Pre-Workout',
    'Lunch',
    'Evening Snack',
    'Snack',
    'Dinner',
    'Bedtime',
    'Before Bed',
  ];

  /// Legacy meal labels the COACH app normalizes away (`kMealAliases` in
  /// `diet_plan_model.dart`). Applied here too so the two apps group — and now
  /// that meal totals are shown, COUNT — the same foods together. Without it a
  /// legacy plan renders "SNACKS 120 kcal" and "EVENING SNACK 200 kcal" to the
  /// member while the coach sees one 320 kcal Evening Snack.
  static const Map<String, String> _mealAliases = {'snacks': 'Evening Snack'};

  /// The display label for a stored meal string, after aliasing.
  String _canonicalMeal(String meal) {
    final m = meal.trim();
    if (m.isEmpty) return 'Meals';
    return _mealAliases[m.toLowerCase()] ?? m;
  }

  int _mealRank(String meal) {
    final i = _mealOrder.indexWhere(
      (m) => m.toLowerCase() == meal.toLowerCase(),
    );
    return i < 0 ? _mealOrder.length : i;
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  /// Delegates to the one canonical rule so this screen, Home and My Plans can
  /// never disagree about the day's targets. This screen's local version WAS
  /// the correct one — the others summed the plan unconditionally — so the rule
  /// preserves its behaviour exactly.
  double _targetFor(
    String key,
    String targetKey,
    List<Map<String, dynamic>> items,
  ) => resolveNutritionTarget(
    diet: c.diet.value,
    targetKey: targetKey,
    itemKey: key,
    items: items,
  ).value;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          if (c.isLoading.value) {
            return Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: p.accent,
              ),
            );
          }
          // A load FAILURE must not read as "no diet assigned" — show a distinct
          // error + Retry (the coach didn't remove the plan).
          if (c.error.value.isNotEmpty && c.diet.value == null) {
            return _errorState(p, c.load);
          }
          // getMyTraining returns null for BOTH "no active plan" and
          // "membership lapsed" — an expired member must see a renew prompt,
          // not "your trainer will set up your nutrition plan".
          if (c.diet.value == null && _membershipInactive) {
            return _renewState(p);
          }
          final items = c.dietItems;
          return RefreshIndicator(
            onRefresh: c.load,
            color: p.accent,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
              children: [
                const GradientTitle(
                  'YOUR DIET',
                  size: 30,
                  textAlign: TextAlign.start,
                ),
                const SizedBox(height: 4),
                Text(
                  c.diet.value?['name']?.toString() ?? 'No diet assigned yet',
                  style: AppText.body(size: 14).copyWith(color: p.textMuted),
                ),
                const SizedBox(height: 20),
                if (items.isEmpty)
                  _empty(p)
                else ...[
                  _adherenceCard(p, items),
                  const SizedBox(height: 16),
                  ..._mealSections(p, items),
                ],
              ],
            ),
          );
        }),
      ),
    );
  }

  /// Linked to a coach but the membership is expired/frozen — the server now
  /// blanks training at the data layer for lapsed members.
  bool get _membershipInactive =>
      Get.isRegistered<MemberController>() &&
      Get.isRegistered<MembershipController>() &&
      Get.find<MemberController>().isLinked.value &&
      // The clients doc must have ARRIVED before we can call the membership
      // inactive — during cold load isLinked (from clientProfiles) resolves
      // before the clients stream, and a null doc would read as "inactive",
      // flashing the renew state at active members with no plan.
      Get.find<MemberController>().client.value != null &&
      !Get.find<MembershipController>().isActive;

  static Widget _renewState(AppPalette p) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 44, color: p.accent),
          const SizedBox(height: 14),
          Text(
            'Membership inactive',
            style: AppText.title(size: 16).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'Your plan is safe — renew your membership to unlock your nutrition plan again.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 13).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () => Get.to(() => MembershipScreen()),
            child: Text('Renew Membership', style: AppText.label(size: 13)),
          ),
        ],
      ),
    ),
  );

  // ── Adherence + targets summary ───────────────────────────────────────
  Widget _adherenceCard(AppPalette p, List<Map<String, dynamic>> items) {
    final pct = log.adherence;
    final logged = log.loggedCount;
    final total = log.totalFoods;
    final tCal = _targetFor('calories', 'targetCalories', items);
    final tPro = _targetFor('protein', 'targetProtein', items);
    final tCarb = _targetFor('carbs', 'targetCarbs', items);
    final tFat = _targetFor('fat', 'targetFat', items);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: AppRadii.lgR,
        gradient: const LinearGradient(
          colors: BrandColors.selectedGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircularPercentIndicator(
                radius: 44,
                lineWidth: 8,
                percent: pct.clamp(0.0, 1.0),
                backgroundColor: Colors.white24,
                progressColor: Colors.white,
                circularStrokeCap: CircularStrokeCap.round,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(pct * 100).round()}%',
                      style: AppText.title(
                        size: 20,
                      ).copyWith(color: Colors.white),
                    ),
                    Text(
                      'today',
                      style: AppText.body(
                        size: 9,
                      ).copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Diet adherence',
                      style: AppText.label(
                        size: 14,
                      ).copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$logged of $total foods logged',
                      style: AppText.body(
                        size: 12,
                      ).copyWith(color: Colors.white70),
                    ),
                    if (log.isSaving.value) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.6,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Saving…',
                            style: AppText.body(
                              size: 11,
                            ).copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ] else if (log.hasError.value) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Could not save — check connection',
                        style: AppText.body(
                          size: 11,
                        ).copyWith(color: Colors.white),
                      ),
                    ] else if (log.isOffline.value) ...[
                      // NOT an error state. The marks are in the local cache
                      // and replay on reconnect; saying "could not save" here
                      // would be false and would push the member to re-tap.
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.cloud_off,
                            size: 12,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              'Saved on this device — syncs when you\'re back '
                              'online',
                              style: AppText.body(
                                size: 11,
                              ).copyWith(color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _macro('KCAL', log.consumedCalories, tCal),
              _macro('PROTEIN', log.consumedProtein, tPro),
              _macro('CARBS', log.consumedCarbs, tCarb),
              _macro('FAT', log.consumedFat, tFat),
            ],
          ),
        ],
      ),
    );
  }

  Widget _macro(String label, double consumed, double target) => Expanded(
    child: Column(
      children: [
        Text(
          '${consumed.round()}${target > 0 ? '/${target.round()}' : ''}',
          style: AppText.title(size: 16).copyWith(color: Colors.white),
        ),
        Text(
          label,
          style: AppText.body(
            size: 9,
          ).copyWith(color: Colors.white70, letterSpacing: 1),
        ),
      ],
    ),
  );

  // ── Meal-grouped prescribed foods with per-food adherence ─────────────
  List<Widget> _mealSections(AppPalette p, List<Map<String, dynamic>> items) {
    // Preserve each food's GLOBAL index (= the DietLogController index space)
    // while grouping by meal for display.
    final byMeal = <String, List<int>>{};
    for (var i = 0; i < items.length; i++) {
      final key = _canonicalMeal((items[i]['meal'] ?? '').toString());
      byMeal.putIfAbsent(key, () => []).add(i);
    }
    final mealKeys = byMeal.keys.toList()
      ..sort((a, b) => _mealRank(a).compareTo(_mealRank(b)));

    final widgets = <Widget>[];
    for (final meal in mealKeys) {
      // Per-meal totals. Without them "how big is my lunch?" — the question an
      // athlete asks at every meal — means mentally adding four foods, while
      // the coach's builder shows the same number in every meal header. The sum
      // is over the PRESCRIBED foods in this meal, not the logged ones: it is
      // what the member is being asked to eat, which is what they need before
      // deciding, not a running total of what they already ate.
      final rows = byMeal[meal]!;
      final mealFoods = [for (final i in rows) items[i]];
      final mealKcal = sumMacro(mealFoods, 'calories');
      final mealP = sumMacro(mealFoods, 'protein');
      final mealC = sumMacro(mealFoods, 'carbs');
      final mealF = sumMacro(mealFoods, 'fat');
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Row(
            children: [
              Text(
                meal.toUpperCase(),
                style: AppText.label(
                  size: 12,
                ).copyWith(color: p.textSecondary, letterSpacing: 1),
              ),
              const SizedBox(width: 8),
              Expanded(child: Divider(color: p.border)),
              const SizedBox(width: 8),
              Text(
                '${mealKcal.round()} kcal · P${mealP.round()} '
                'C${mealC.round()} F${mealF.round()}',
                style: AppText.body(
                  size: 11,
                ).copyWith(color: p.textMuted),
              ),
            ],
          ),
        ),
      );
      for (final idx in byMeal[meal]!) {
        widgets.add(_foodCard(p, idx, items[idx]));
      }
    }
    return widgets;
  }

  Widget _foodCard(AppPalette p, int index, Map<String, dynamic> f) {
    final qty = (f['quantity'] ?? '').toString();
    final kcal = _num(f['calories']).round();
    final pr = _num(f['protein']).round();
    final cb = _num(f['carbs']).round();
    final ft = _num(f['fat']).round();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
        boxShadow: AppShadows.card(p.isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.12),
                  borderRadius: AppRadii.smR,
                ),
                child: Icon(Icons.restaurant, color: p.accent, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f['name']?.toString() ?? 'Food',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label(
                        size: 14,
                      ).copyWith(color: p.textPrimary),
                    ),
                    if (qty.isNotEmpty)
                      Text(
                        qty,
                        style: AppText.body(
                          size: 12,
                        ).copyWith(color: p.textMuted),
                      ),
                    Text(
                      'P$pr · C$cb · F$ft',
                      style: AppText.body(
                        size: 11,
                      ).copyWith(color: p.textMuted),
                    ),
                  ],
                ),
              ),
              Text(
                '$kcal kcal',
                style: AppText.label(size: 13).copyWith(color: p.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Obx(() {
            final current = log.statusFor(index);
            return Row(
              children: [
                _statusChip(
                  p,
                  index,
                  DietStatus.eaten,
                  'Eaten',
                  Icons.check_circle,
                  const Color(0xFF2EBD59),
                  current,
                ),
                const SizedBox(width: 8),
                _statusChip(
                  p,
                  index,
                  DietStatus.partial,
                  'Partial',
                  Icons.remove_circle,
                  const Color(0xFFF59E0B),
                  current,
                ),
                const SizedBox(width: 8),
                _statusChip(
                  p,
                  index,
                  DietStatus.skipped,
                  'Skipped',
                  Icons.cancel,
                  p.textMuted,
                  current,
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _statusChip(
    AppPalette p,
    int index,
    String status,
    String label,
    IconData icon,
    Color color,
    String current,
  ) {
    final selected = current == status;
    return Expanded(
      child: GestureDetector(
        onTap: () => log.setStatus(index, status),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: AppRadii.smR,
            border: Border.all(
              color: selected ? color : p.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 16, color: selected ? color : p.textMuted),
              const SizedBox(height: 3),
              Text(
                label,
                style: AppText.body(size: 10.5).copyWith(
                  color: selected ? color : p.textMuted,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(AppPalette p) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 50),
    child: Column(
      children: [
        Icon(Icons.restaurant_menu, size: 40, color: p.textMuted),
        const SizedBox(height: 12),
        Text(
          'No diet assigned yet',
          style: AppText.label(size: 14).copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          'Your trainer will set up your nutrition plan.',
          style: AppText.body(size: 13).copyWith(color: p.textMuted),
        ),
      ],
    ),
  );

  /// Distinct from the empty state: the load FAILED, so offer a Retry rather than
  /// implying the coach hasn't assigned a nutrition plan.
  Widget _errorState(AppPalette p, Future<void> Function() onRetry) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 44, color: p.textMuted),
          const SizedBox(height: 14),
          Text(
            "Couldn't load your training",
            style: AppText.label(size: 15).copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'Check your connection and try again.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 13).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(backgroundColor: p.accent),
            icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
            label: Text(
              'Retry',
              style: AppText.label(size: 14).copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );
}
