import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/training_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/gradient_title.dart';
import 'workout_player_screen.dart';

class ClientWorkoutScreen extends StatelessWidget {
  ClientWorkoutScreen({super.key});

  final TrainingController c = Get.isRegistered<TrainingController>()
      ? Get.find<TrainingController>()
      : Get.put(TrainingController());

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
          final items = c.workoutItems;
          return RefreshIndicator(
            onRefresh: c.load,
            color: p.accent,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
              children: [
                const GradientTitle('YOUR WORKOUT',
                    size: 30, textAlign: TextAlign.start),
                const SizedBox(height: 4),
                Text(
                  c.workout.value?['name']?.toString() ??
                      (c.error.value.isNotEmpty
                          ? c.error.value
                          : 'No workout assigned yet'),
                  style: AppText.body(size: 14).copyWith(color: p.textMuted),
                ),
                const SizedBox(height: 20),
                if (items.isEmpty)
                  _empty(p)
                else
                  ...items.asMap().entries.map((e) => _exerciseCard(
                      context, p, e.key + 1, e.value)),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _exerciseCard(
      BuildContext context, AppPalette p, int n, Map<String, dynamic> ex) {
    final sets = (ex['sets'] ?? 0).toString();
    final reps = (ex['reps'] ?? 0).toString();
    final hasVideo = (ex['videoUrl'] ?? '').toString().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
        boxShadow: AppShadows.card(p.isDark),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadii.cardR,
          onTap: () => Get.to(() => WorkoutPlayerScreen(exercise: ex)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.12),
                      borderRadius: AppRadii.smR),
                  child: Text('$n',
                      style: AppText.title(size: 18).copyWith(color: p.accent)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ex['name']?.toString() ?? 'Exercise',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label(size: 14)
                              .copyWith(color: p.textPrimary)),
                      const SizedBox(height: 2),
                      Text('$sets sets × $reps reps',
                          style: AppText.body(size: 12)
                              .copyWith(color: p.textMuted)),
                    ],
                  ),
                ),
                Icon(hasVideo ? Icons.play_circle_fill : Icons.chevron_right,
                    color: hasVideo ? p.accent : p.textMuted, size: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty(AppPalette p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 50),
        child: Column(children: [
          Icon(Icons.fitness_center, size: 40, color: p.textMuted),
          const SizedBox(height: 12),
          Text('No workout assigned yet',
              style: AppText.label(size: 14).copyWith(color: p.textSecondary)),
          const SizedBox(height: 4),
          Text('Your trainer will assign one soon.',
              style: AppText.body(size: 13).copyWith(color: p.textMuted)),
        ]),
      );
}
