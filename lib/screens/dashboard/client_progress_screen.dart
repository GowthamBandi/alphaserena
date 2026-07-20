import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../controllers/member_controller.dart';
import '../../controllers/progress_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/visibility_choice.dart';
import '../join/join_coach_screen.dart';
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
          // Only the roster load gates the page — saving a weight must never
          // blank the whole tab into the skeleton (the save dialog shows its
          // own progress).
          if (member.isLoading.value) {
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
            onPressed: () => Get.to(() => const JoinCoachScreen()),
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
      return _photosTab(progress, p);
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
    // V1.2 consistency: like measurements, the member must consciously choose
    // visibility before saving — never defaulted.
    String? visibility;
    Get.dialog(
      AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Log Weight',
          style: AppText.title(size: 18).copyWith(color: p.textPrimary),
        ),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
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
              const SizedBox(height: 14),
              VisibilityChoice(
                value: visibility,
                onChanged: (v) => setState(() => visibility = v),
              ),
            ],
          ),
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
              if (!VisibilityChoice.ensureChosen(visibility)) return;
              final success =
                  await progress.logWeight(w, visibility: visibility!);
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

  /// Honest body snapshot: the member's real weight and — only when a body-fat
  /// value was actually measured/entered — the fat estimate. The old pie chart
  /// derived muscle/bone/water from fixed fractions (fabricated data) and was
  /// removed: no number on this screen may be invented.
  Widget _bodyComposition(ProgressController progress, AppPalette p) {
    final weight = progress.latestWeight;
    final bodyFatPercent = progress.latestBodyFat;
    final hasBodyFat = bodyFatPercent > 0;

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
            'Body Snapshot',
            style: GoogleFonts.poppins(
              color: p.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _snapshotStat(
                  p,
                  label: 'Current Weight',
                  value: weight > 0 ? weight.toStringAsFixed(1) : '--',
                  unit: 'kg',
                ),
              ),
              Expanded(
                child: _snapshotStat(
                  p,
                  label: 'Body Fat',
                  value:
                      hasBodyFat ? bodyFatPercent.toStringAsFixed(1) : '--',
                  unit: hasBodyFat ? '%' : '',
                  // No hint: the app has no body-fat input yet, so pointing
                  // members anywhere would be a dead end.
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _snapshotStat(AppPalette p,
      {required String label,
      required String value,
      required String unit,
      String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.poppins(color: p.textMuted, fontSize: 10)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: GoogleFonts.poppins(
                    color: p.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            if (unit.isNotEmpty)
              Text(' $unit',
                  style:
                      GoogleFonts.poppins(color: p.textMuted, fontSize: 10)),
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: 2),
          Text(hint,
              style: GoogleFonts.poppins(color: p.textMuted, fontSize: 9)),
        ],
      ],
    );
  }

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
            value,
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

  Widget _photosTab(ProgressController progress, AppPalette p) {
    return Container(
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
            children: [
              Icon(Icons.add_a_photo_outlined, color: p.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Progress Photos',
                  style: AppText.title(size: 16).copyWith(color: p.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Capture front / side / back shots over time — your coach can see them to track your transformation.',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 14),
          Obx(() {
            if (progress.isUploadingPhoto.value) {
              return Row(
                children: [
                  SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: p.accent)),
                  const SizedBox(width: 10),
                  Text('Uploading…',
                      style:
                          AppText.body(size: 13).copyWith(color: p.textMuted)),
                ],
              );
            }
            // V1.2 consistency: the same conscious visibility choice as
            // measurements + weight, required before picking a photo.
            void upload(ImageSource source) {
              final v = progress.photoVisibility.value;
              if (!VisibilityChoice.ensureChosen(v)) return;
              progress.pickAndUploadPhoto(source, visibility: v!);
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                VisibilityChoice(
                  value: progress.photoVisibility.value,
                  onChanged: (v) => progress.photoVisibility.value = v,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _photoSourceButton(
                        p,
                        Icons.photo_camera_outlined,
                        'Camera',
                        () => upload(ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _photoSourceButton(
                        p,
                        Icons.photo_library_outlined,
                        'Gallery',
                        () => upload(ImageSource.gallery),
                      ),
                    ),
                  ],
                ),
              ],
            );
          }),
          Obx(() => progress.photoError.value.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(progress.photoError.value,
                      style: AppText.body(size: 12)
                          .copyWith(color: const Color(0xFFFF1744))),
                )),
          const SizedBox(height: 16),
          Obx(() {
            final photos = progress.progressPhotos;
            if (photos.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('No progress photos yet.',
                      style:
                          AppText.body(size: 13).copyWith(color: p.textMuted)),
                ),
              );
            }
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: photos.map((e) => _photoThumb(e, p)).toList(),
            );
          }),
        ],
      ),
    );
  }

  Widget _photoSourceButton(
      AppPalette p, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: p.accent.withValues(alpha: 0.10),
          borderRadius: AppRadii.smR,
          border: Border.all(color: p.accent.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: p.accent, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: AppText.label(size: 13).copyWith(color: p.accent)),
          ],
        ),
      ),
    );
  }

  Widget _photoThumb(Map<String, dynamic> e, AppPalette p) {
    final url = (e['photoUrl'] ?? '').toString();
    final date = e['date'];
    String label = '';
    if (date is Timestamp) {
      final d = date.toDate();
      label = '${d.day}/${d.month}';
    }
    return ClipRRect(
      borderRadius: AppRadii.smR,
      child: Stack(
        children: [
          Image.network(
            url,
            width: 104,
            height: 132,
            fit: BoxFit.cover,
            loadingBuilder: (c, child, prog) => prog == null
                ? child
                : Container(
                    width: 104,
                    height: 132,
                    color: p.surfaceAlt,
                    child: Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 1.8, color: p.accent)),
                  ),
            errorBuilder: (c, _, __) => Container(
              width: 104,
              height: 132,
              color: p.surfaceAlt,
              child: Icon(Icons.broken_image_outlined, color: p.textMuted),
            ),
          ),
          if (label.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 3),
                color: Colors.black54,
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: AppText.body(size: 10).copyWith(color: Colors.white)),
              ),
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
