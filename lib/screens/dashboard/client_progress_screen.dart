import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/member_controller.dart';
import '../../controllers/progress_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/primary_button.dart';
import 'profile/body_measurements_screen.dart';

/// Progress — weekly overview, trend chart, body composition, measurements.
class ClientProgressScreen extends StatelessWidget {
  const ClientProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final progress = Get.isRegistered<ProgressController>()
        ? Get.find<ProgressController>()
        : Get.put(ProgressController());
    final member = Get.isRegistered<MemberController>()
        ? Get.find<MemberController>()
        : Get.put(MemberController());

    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        bottom: false,
        child: Obx(() {
          final loading =
              member.isLoading.value || progress.isSavingWeight.value;
          if (loading) {
            return _skeletonLoader(p);
          }

          final linked = member.isLinked.value;

          return RefreshIndicator(
            onRefresh: () async {
              await member.claim();
            },
            color: p.accent,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              children: [
                _header(p),
                const SizedBox(height: 16),
                _tabs(progress, p),
                const SizedBox(height: 16),

                if (!linked) ...[
                  _unlinkedCard(p),
                ] else ...[
                  // Dynamic tabs rendering
                  _renderTabContent(context, progress, member, p),
                ],
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _header(AppPalette p) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Progress',
                style: GoogleFonts.poppins(
                  color: p.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Track your journey. See your transformation.',
                style: GoogleFonts.poppins(color: p.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tabs(ProgressController progress, AppPalette p) {
    const tabNames = ['Overview', 'Body Stats', 'Photos', 'Strength'];
    return Row(
      children: List.generate(tabNames.length, (i) {
        final active = progress.selectedTab.value == i;
        return Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => progress.selectedTab.value = i,
            child: Column(
              children: [
                Text(
                  tabNames[i],
                  style: GoogleFonts.poppins(
                    color: active ? p.accent : p.textMuted,
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: active ? 2 : 1,
                  color: active ? p.accent : p.border,
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _unlinkedCard(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          Icon(Icons.link_off_rounded, color: p.accent, size: 40),
          const SizedBox(height: 14),
          Text(
            'Connect to a Coach',
            style: AppText.title(size: 16).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'No coach linked yet. Find a coach or enter a handle to unlock progress logs and metrics tracking.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
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
            onPressed: () => Get.to(() {}),
            child: Text('Find a Coach', style: AppText.label(size: 13)),
          ),
        ],
      ),
    );
  }

  Widget _renderTabContent(
    BuildContext context,
    ProgressController progress,
    MemberController member,
    AppPalette p,
  ) {
    final idx = progress.selectedTab.value;
    if (idx == 0) {
      return Column(
        children: [
          _zoneBanner(p),
          const SizedBox(height: 18),
          _weekOverview(p),
          const SizedBox(height: 16),
          _progressOverTime(context, progress, p),
          const SizedBox(height: 16),
          _bodyComposition(progress, p),
          const SizedBox(height: 18),
          _ctaBanner(p),
        ],
      );
    } else if (idx == 1) {
      return _bodyStatsTab(member, p);
    } else if (idx == 2) {
      return _photosTab(p);
    } else {
      return _strengthTab(p);
    }
  }

  Widget _zoneBanner(AppPalette p) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: Image.asset(
                'assets/images/progress_banner.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: p.surfaceAlt),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    p.surface,
                    p.surface.withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      "You're in the zone!",
                      style: GoogleFonts.poppins(
                        color: p.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('🔥', style: TextStyle(fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Consistency is your\nsuperpower.',
                  style: GoogleFonts.poppins(
                    color: p.textMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _weekOverview(AppPalette p) {
    final stats = [
      (p.accent, Icons.fitness_center, '4 / 6', 'Workouts\nCompleted'),
      (
        const Color(0xFF2EBD59),
        Icons.local_fire_department,
        '2,350',
        'Calories\nBurned',
      ),
      (
        const Color(0xFF3B82F6),
        Icons.timer_outlined,
        '5h 45m',
        'Workout\nTime',
      ),
      (const Color(0xFFF59E0B), Icons.trending_up, '98%', 'Plan\nAdherence'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This Week Overview',
            style: GoogleFonts.poppins(
              color: p.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: stats
                .map(
                  (s) => Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(s.$2, color: s.$1, size: 16),
                        const SizedBox(height: 6),
                        Text(
                          s.$3,
                          style: GoogleFonts.poppins(
                            color: p.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          s.$4,
                          style: GoogleFonts.poppins(
                            color: p.textMuted,
                            fontSize: 9,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _progressOverTime(
    BuildContext context,
    ProgressController progress,
    AppPalette p,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Weight Progress (kg)',
                style: GoogleFonts.poppins(
                  color: p.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              GestureDetector(
                onTap: () => _showLogWeightDialog(context, progress, p),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: p.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.add, color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        'Log Weight',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(height: 150, child: _lineChart(progress, p)),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              _delta(
                progress.weightDeltaText,
                'Weight Change',
                progress.isWeightUp,
                p,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showLogWeightDialog(
    BuildContext context,
    ProgressController progress,
    AppPalette p,
  ) {
    final weightCtrl = TextEditingController();
    Get.dialog(
      AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Log Weight',
          style: AppText.title(size: 18).copyWith(color: p.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: weightCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: TextStyle(color: p.textPrimary),
              decoration: InputDecoration(
                labelText: 'Weight (kg)',
                labelStyle: TextStyle(color: p.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: p.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: p.accent),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('Cancel', style: TextStyle(color: p.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              final w = double.tryParse(weightCtrl.text.trim());
              if (w == null || w <= 0) {
                Get.snackbar('Input Error', 'Please enter a valid weight.');
                return;
              }
              final success = await progress.logWeight(w);
              if (success) {
                Get.back();
                Get.snackbar('Success', 'Weight of $w kg logged successfully.');
              }
            },
            child: Text(
              'Save',
              style: TextStyle(color: p.accent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineChart(ProgressController progress, AppPalette p) {
    final spots = progress.weightSpots;
    final labels = progress.chartXLabels;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (spots.length - 1).toDouble().clamp(1.0, double.infinity),
        minY: progress.minWeight,
        maxY: progress.maxWeight,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: true),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 5,
              getTitlesWidget: (v, meta) => Text(
                v.toInt().toString(),
                style: GoogleFonts.poppins(color: p.textMuted, fontSize: 8),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    labels[i],
                    style: GoogleFonts.poppins(color: p.textMuted, fontSize: 8),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: p.accent,
            barWidth: 2.4,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: p.accent.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _delta(String value, String label, bool up, AppPalette p) {
    final color = up ? p.accent : const Color(0xFF2EBD59);
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                up ? Icons.arrow_upward : Icons.arrow_downward,
                color: color,
                size: 10,
              ),
              const SizedBox(width: 2),
              Text(
                value,
                style: GoogleFonts.poppins(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: p.textMuted, fontSize: 8.5),
          ),
        ],
      ),
    );
  }

  Widget _bodyComposition(ProgressController progress, AppPalette p) {
    final weight = progress.latestWeight;
    final bodyFatPercent = progress.latestBodyFat;

    // Mass calculations based on body fat percentage
    final fatMass = weight * (bodyFatPercent / 100);
    final muscleMass =
        weight * 0.40; // mock 40% standard muscle mass calculation
    final boneMass = weight * 0.05; // mock 5% bone mass
    final waterWeight = weight * 0.50; // mock 50% water weight

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Body Composition Estimates',
            style: GoogleFonts.poppins(
              color: p.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 92,
                height: 92,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 26,
                    sections: [
                      PieChartSectionData(
                        value: muscleMass,
                        color: const Color(0xFF3B82F6),
                        radius: 18,
                        showTitle: false,
                      ),
                      PieChartSectionData(
                        value: fatMass,
                        color: p.accent,
                        radius: 18,
                        showTitle: false,
                      ),
                      PieChartSectionData(
                        value: boneMass,
                        color: const Color(0xFF2EBD59),
                        radius: 18,
                        showTitle: false,
                      ),
                      PieChartSectionData(
                        value: waterWeight,
                        color: const Color(0xFFFFCA28),
                        radius: 18,
                        showTitle: false,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Weight',
                    style: GoogleFonts.poppins(
                      color: p.textMuted,
                      fontSize: 9.5,
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        weight.toStringAsFixed(1),
                        style: GoogleFonts.poppins(
                          color: p.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        ' kg',
                        style: GoogleFonts.poppins(
                          color: p.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Body Fat Estimate',
                    style: GoogleFonts.poppins(color: p.textMuted, fontSize: 9),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        bodyFatPercent.toStringAsFixed(1),
                        style: GoogleFonts.poppins(
                          color: p.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        ' %',
                        style: GoogleFonts.poppins(
                          color: p.textMuted,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _compLegend(
                    const Color(0xFF3B82F6),
                    'Muscle Mass',
                    '${muscleMass.toStringAsFixed(1)} kg',
                    p,
                  ),
                  _compLegend(
                    p.accent,
                    'Body Fat',
                    '${fatMass.toStringAsFixed(1)} kg',
                    p,
                  ),
                  _compLegend(
                    const Color(0xFF2EBD59),
                    'Bone Mass',
                    '${boneMass.toStringAsFixed(1)} kg',
                    p,
                  ),
                  _compLegend(
                    const Color(0xFFFFCA28),
                    'Water Weight',
                    '${waterWeight.toStringAsFixed(1)} kg',
                    p,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _compLegend(Color c, String label, String value, AppPalette p) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.poppins(color: p.textMuted, fontSize: 10),
            ),
            const SizedBox(width: 10),
            Text(
              value,
              style: GoogleFonts.poppins(
                color: p.textPrimary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _bodyStatsTab(MemberController member, AppPalette p) {
    final chest = member.profile.value?['latestChest']?.toString() ?? '--';
    final waist = member.profile.value?['latestWaist']?.toString() ?? '--';
    final arms = member.profile.value?['latestArms']?.toString() ?? '--';
    final hips = member.profile.value?['latestHips']?.toString() ?? '--';
    final thighs = member.profile.value?['latestThighs']?.toString() ?? '--';

    final measurementsList = [
      (Icons.favorite_border, 'Chest', chest),
      (Icons.straighten, 'Waist', waist),
      (Icons.fitness_center, 'Arms / Biceps', arms),
      (Icons.accessibility_new, 'Hips', hips),
      (Icons.airline_seat_legroom_extra, 'Thighs', thighs),
    ];

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: AppRadii.cardR,
            border: Border.all(color: p.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Key Measurements',
                    style: GoogleFonts.poppins(
                      color: p.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Get.to(() => const BodyMeasurementsScreen()),
                    child: Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: p.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...measurementsList.map(
                (e) => _measurementRow(e.$1, e.$2, e.$3, p),
              ),
              const SizedBox(height: 18),
              PrimaryButton(
                label: 'Log Body Measurements',
                icon: Icons.edit_note,
                onPressed: () => Get.to(() => const BodyMeasurementsScreen()),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _measurementRow(
    IconData icon,
    String label,
    String value,
    AppPalette p,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: p.accent, size: 18),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                color: p.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value != '--' ? value : '--',
            style: GoogleFonts.poppins(
              color: p.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _photosTab(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          Icon(Icons.add_a_photo_outlined, color: p.textMuted, size: 44),
          const SizedBox(height: 14),
          Text(
            'Progress Photos',
            style: AppText.title(size: 16).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'Upload front, side, and back comparison pictures to track your physical transformation visually. This feature is coming soon!',
            textAlign: TextAlign.center,
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _strengthTab(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          Icon(Icons.emoji_events_outlined, color: p.textMuted, size: 44),
          const SizedBox(height: 14),
          Text(
            'Strength & 1RM Progression',
            style: AppText.title(size: 16).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'Log and graph your 1-Rep Max (1RM) lifts for Squats, Bench Press, and Deadlifts to see your power increase over time. This feature is coming soon!',
            textAlign: TextAlign.center,
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _ctaBanner(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: p.isDark
              ? [const Color(0xFF1A0E0E), const Color(0xFF2A0E0E)]
              : [const Color(0xFFFFF2F2), const Color(0xFFFFECEC)],
        ),
        border: Border.all(color: p.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.emoji_events, color: p.accent, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Small daily improvements lead to',
                  style: GoogleFonts.poppins(color: p.textMuted, fontSize: 11),
                ),
                Text(
                  'Big transformations.',
                  style: GoogleFonts.poppins(
                    color: p.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeletonLoader(AppPalette p) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120,
                  height: 24,
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 220,
                  height: 12,
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          height: 40,
          decoration: BoxDecoration(
            color: p.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          height: 150,
          decoration: BoxDecoration(
            color: p.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          height: 220,
          decoration: BoxDecoration(
            color: p.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ],
    );
  }
}
