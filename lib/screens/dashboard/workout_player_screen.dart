import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/premium_video_player.dart';
import '../../core/widgets/primary_button.dart';

/// THE EXERCISE SCREEN — the demo, and everything the coach said about it.
///
/// The video is the reason a member opens this screen, so it leads, at full
/// width, with a real player ([PremiumVideoPlayer]). Everything below it is
/// the coach's own curation — the movement's target, the equipment, the
/// difficulty, the written instructions — rendered only where it exists.
///
/// NOTHING HERE IS INVENTED. Every field is the exercise library's own, served
/// by `getMyTraining`. An absent field produces no chip and no heading rather
/// than a placeholder, because "—" beside a label is a claim that the coach
/// left something blank when the truth may be that this app never asked for it.
class WorkoutPlayerScreen extends StatelessWidget {
  final Map<String, dynamic> exercise;
  const WorkoutPlayerScreen({super.key, required this.exercise});

  String _s(String key) => (exercise[key] ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    final name = _s('name').isEmpty ? 'Exercise' : _s('name');
    final sets = _s('sets');
    final reps = _s('reps');
    final weight = _s('weight');
    final muscle = _s('muscleGroup');
    final equipment = _s('equipment');
    final difficulty = _s('difficulty');
    final instructions = _s('instructions');

    // The video's own length, curated by the coach's upload. Rendered only
    // when a video actually exists to have a length.
    final durationSecs = exercise['videoDurationSeconds'];
    final durationLabel = (durationSecs is num && durationSecs > 0)
        ? '${durationSecs ~/ 60}:'
            '${(durationSecs % 60).toInt().toString().padLeft(2, '0')}'
        : '';

    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        elevation: 0,
        iconTheme: IconThemeData(color: p.textPrimary),
        title: Text(
          name,
          style: AppText.cardTitle(size: 16).copyWith(color: p.textPrimary),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            PremiumVideoPlayer(
              videoUrl: _s('videoUrl'),
              posterUrl: _s('thumbnailUrl'),
              title: '$name demonstration',
            ),
            const SizedBox(height: 18),

            // What the coach PRESCRIBED for this exercise today. Each stat
            // renders only when the plan actually carries it — "0 sets" is
            // missing data, not a prescription.
            if (sets.isNotEmpty && sets != '0' ||
                reps.isNotEmpty && reps != '0' ||
                weight.isNotEmpty && weight != '0')
              _prescription(p, sets: sets, reps: reps, weight: weight),

            if (muscle.isNotEmpty ||
                equipment.isNotEmpty ||
                difficulty.isNotEmpty ||
                durationLabel.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (muscle.isNotEmpty)
                    _chip(p, Icons.my_location_rounded, muscle, p.accent),
                  if (equipment.isNotEmpty)
                    _chip(p, Icons.fitness_center_rounded, equipment, null),
                  if (difficulty.isNotEmpty)
                    _chip(p, Icons.signal_cellular_alt_rounded, difficulty,
                        null),
                  if (durationLabel.isNotEmpty && _s('videoUrl').isNotEmpty)
                    _chip(p, Icons.timer_outlined, durationLabel, null),
                ],
              ),
            ],

            if (instructions.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text(
                'HOW TO',
                style: AppText.label(size: 11.5)
                    .copyWith(color: p.textMuted, letterSpacing: 1.8),
              ),
              const SizedBox(height: 9),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: glassCard(p, radius: 14),
                child: Text(
                  instructions,
                  style: AppText.feature(size: 14)
                      .copyWith(color: p.textSecondary, height: 1.55),
                ),
              ),
            ],

            const SizedBox(height: 26),
            PrimaryButton(
              label: 'Done',
              icon: Icons.check,
              onPressed: () => Get.back(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _prescription(
    AppPalette p, {
    required String sets,
    required String reps,
    required String weight,
  }) {
    final stats = <(String, String)>[
      if (sets.isNotEmpty && sets != '0') ('SETS', sets),
      if (reps.isNotEmpty && reps != '0') ('REPS', reps),
      if (weight.isNotEmpty && weight != '0' && weight != '0.0')
        ('WEIGHT', weight),
    ];
    if (stats.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: glassCard(p, radius: 16),
      child: Row(
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) Container(width: 1, height: 28, color: p.border),
            Expanded(
              child: Column(
                children: [
                  Text(
                    stats[i].$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title(size: 21).copyWith(color: p.accent),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stats[i].$1,
                    style: AppText.body(size: 10.5)
                        .copyWith(color: p.textMuted, letterSpacing: 1),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(AppPalette p, IconData icon, String label, Color? tint) {
    final c = tint ?? p.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppText.body(size: 12).copyWith(color: p.textSecondary),
          ),
        ],
      ),
    );
  }
}
