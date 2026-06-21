import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/training_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/gradient_title.dart';

class ClientDietScreen extends StatelessWidget {
  ClientDietScreen({super.key});

  final TrainingController c = Get.isRegistered<TrainingController>()
      ? Get.find<TrainingController>()
      : Get.put(TrainingController());

  double _sum(List<Map<String, dynamic>> items, String key) {
    double t = 0;
    for (final i in items) {
      final v = i[key];
      if (v is num) t += v.toDouble();
      if (v is String) t += double.tryParse(v) ?? 0;
    }
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          if (c.isLoading.value) {
            return Center(
                child:
                    CircularProgressIndicator(strokeWidth: 2.4, color: p.accent));
          }
          final items = c.dietItems;
          return RefreshIndicator(
            onRefresh: c.load,
            color: p.accent,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
              children: [
                const GradientTitle('YOUR DIET',
                    size: 30, textAlign: TextAlign.start),
                const SizedBox(height: 4),
                Text(
                  c.diet.value?['name']?.toString() ?? 'No diet assigned yet',
                  style: AppText.body(size: 14).copyWith(color: p.textMuted),
                ),
                const SizedBox(height: 20),
                if (items.isNotEmpty) _totals(p, items),
                const SizedBox(height: 16),
                if (items.isEmpty)
                  _empty(p)
                else
                  ...items.map((f) => _foodCard(p, f)),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _totals(AppPalette p, List<Map<String, dynamic>> items) {
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
      child: Row(
        children: [
          _macro('KCAL', _sum(items, 'calories')),
          _macro('PROTEIN', _sum(items, 'protein')),
          _macro('CARBS', _sum(items, 'carbs')),
          _macro('FAT', _sum(items, 'fat')),
        ],
      ),
    );
  }

  Widget _macro(String label, double value) => Expanded(
        child: Column(
          children: [
            Text(value.round().toString(),
                style: AppText.title(size: 22).copyWith(color: Colors.white)),
            Text(label,
                style: AppText.body(size: 10)
                    .copyWith(color: Colors.white70, letterSpacing: 1)),
          ],
        ),
      );

  Widget _foodCard(AppPalette p, Map<String, dynamic> f) {
    final qty = (f['quantity'] ?? '').toString();
    final kcal = (f['calories'] is num) ? (f['calories'] as num).round() : 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
        boxShadow: AppShadows.card(p.isDark),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.12),
                borderRadius: AppRadii.smR),
            child: Icon(Icons.restaurant, color: p.accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f['name']?.toString() ?? 'Food',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        AppText.label(size: 14).copyWith(color: p.textPrimary)),
                if (qty.isNotEmpty)
                  Text(qty,
                      style:
                          AppText.body(size: 12).copyWith(color: p.textMuted)),
              ],
            ),
          ),
          Text('$kcal kcal',
              style: AppText.label(size: 13).copyWith(color: p.textPrimary)),
        ],
      ),
    );
  }

  Widget _empty(AppPalette p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 50),
        child: Column(children: [
          Icon(Icons.restaurant_menu, size: 40, color: p.textMuted),
          const SizedBox(height: 12),
          Text('No diet assigned yet',
              style: AppText.label(size: 14).copyWith(color: p.textSecondary)),
          const SizedBox(height: 4),
          Text('Your trainer will set up your nutrition plan.',
              style: AppText.body(size: 13).copyWith(color: p.textMuted)),
        ]),
      );
}
