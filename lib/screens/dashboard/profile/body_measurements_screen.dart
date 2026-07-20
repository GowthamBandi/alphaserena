import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../controllers/member_controller.dart';
import '../../../core/services/client_profile_service.dart';
import '../../../core/services/progress_log_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/visibility_choice.dart';

class BodyMeasurementsScreen extends StatefulWidget {
  const BodyMeasurementsScreen({super.key});

  @override
  State<BodyMeasurementsScreen> createState() => _BodyMeasurementsScreenState();
}

class _BodyMeasurementsScreenState extends State<BodyMeasurementsScreen> {
  final _waist = TextEditingController();
  final _chest = TextEditingController();
  final _arms = TextEditingController();
  final _hips = TextEditingController();
  final _thighs = TextEditingController();

  final MemberController member = Get.find<MemberController>();
  final ClientProfileService _profileService = ClientProfileService();
  final ProgressLogService _progressLog = ProgressLogService();

  bool _saving = false;

  /// Transformation V1.1: whether this entry is shared with the coach or kept
  /// private. NULL until the member consciously chooses — saving is blocked
  /// until then (no silent default).
  String? _visibility;

  @override
  void dispose() {
    _waist.dispose();
    _chest.dispose();
    _arms.dispose();
    _hips.dispose();
    _thighs.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final waistVal = double.tryParse(_waist.text.trim());
    final chestVal = double.tryParse(_chest.text.trim());
    final armsVal = double.tryParse(_arms.text.trim());
    final hipsVal = double.tryParse(_hips.text.trim());
    final thighsVal = double.tryParse(_thighs.text.trim());

    if (waistVal == null && chestVal == null && armsVal == null && hipsVal == null && thighsVal == null) {
      Get.snackbar('Input Required', 'Please fill in at least one measurement to log.');
      return;
    }

    // V1.1: the member must consciously decide visibility — never defaulted.
    final visibility = _visibility;
    if (!VisibilityChoice.ensureChosen(visibility)) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _saving = true);

    try {
      final entry = {
        'date': DateTime.now().toIso8601String(),
        'waist': waistVal ?? 0.0,
        'chest': chestVal ?? 0.0,
        'arms': armsVal ?? 0.0,
        'hips': hipsVal ?? 0.0,
        'thighs': thighsVal ?? 0.0,
      };

      final updates = <String, dynamic>{
        'measurementsLog': FieldValue.arrayUnion([entry]),
      };

      if (waistVal != null) updates['latestWaist'] = waistVal;
      if (chestVal != null) updates['latestChest'] = chestVal;
      if (armsVal != null) updates['latestArms'] = armsVal;
      if (hipsVal != null) updates['latestHips'] = hipsVal;
      if (thighsVal != null) updates['latestThighs'] = thighsVal;

      await _profileService.update(uid, updates);

      // Also write the coach-readable `client_progress` entry (measurements map)
      // so the trainer sees these — the clientProfiles copy stays for in-app UI.
      final measurements = <String, dynamic>{
        if (waistVal != null) 'waist': waistVal,
        if (chestVal != null) 'chest': chestVal,
        if (armsVal != null) 'arms': armsVal,
        if (hipsVal != null) 'hips': hipsVal,
        if (thighsVal != null) 'thighs': thighsVal,
      };
      await _progressLog.addEntry(
          measurements: measurements, visibility: visibility!);

      _waist.clear();
      _chest.clear();
      _arms.clear();
      _hips.clear();
      _thighs.clear();

      Get.snackbar('Success', 'Body measurements logged successfully.');
    } catch (e) {
      Get.snackbar('Error', 'Failed to save measurements. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: p.textPrimary),
          onPressed: () => Get.back(),
        ),
        title: Text(
          'Body Measurements',
          style: AppText.title(size: 20).copyWith(color: p.textPrimary),
        ),
      ),
      body: SafeArea(
        child: Obx(() {
          final log = member.profile.value?['measurementsLog'] as List? ?? [];
          final history = log.reversed.toList();

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              _formSection(p),
              const SizedBox(height: 24),
              if (history.isNotEmpty) ...[
                Text(
                  'Log History',
                  style: GoogleFonts.poppins(color: p.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                ...history.map((e) => _historyCard(Map<String, dynamic>.from(e), p)),
              ],
            ],
          );
        }),
      ),
    );
  }

  Widget _formSection(AppPalette p) {
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
          Text(
            'Log New Stats',
            style: GoogleFonts.poppins(color: p.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Enter values in inches or cm (keep your unit choice consistent).',
            style: GoogleFonts.poppins(color: p.textMuted, fontSize: 10.5),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _field(_waist, 'Waist', Icons.straighten, p)),
              const SizedBox(width: 12),
              Expanded(child: _field(_chest, 'Chest', Icons.straighten, p)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _field(_arms, 'Arms / Biceps', Icons.straighten, p)),
              const SizedBox(width: 12),
              Expanded(child: _field(_hips, 'Hips', Icons.straighten, p)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _field(_thighs, 'Thighs', Icons.straighten, p)),
              const SizedBox(width: 12),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          // The ONE shared visibility chooser (V1.2) — same control, wording
          // and validation as the weight + photo flows.
          VisibilityChoice(
            value: _visibility,
            onChanged: (v) => setState(() => _visibility = v),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Save Measurements',
            icon: Icons.check,
            isLoading: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon, AppPalette p) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: GoogleFonts.poppins(color: p.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: p.textMuted, size: 16),
        labelText: label,
        labelStyle: GoogleFonts.poppins(color: p.textMuted, fontSize: 12),
        fillColor: p.surfaceAlt,
        filled: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: p.border),
          borderRadius: BorderRadius.circular(10),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: p.accent),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _historyCard(Map<String, dynamic> e, AppPalette p) {
    final dateStr = e['date']?.toString() ?? '';
    DateTime? date = DateTime.tryParse(dateStr);
    final formattedDate = date != null ? DateFormat('dd MMM yyyy, hh:mm a').format(date) : dateStr;

    final waist = e['waist'] as num? ?? 0.0;
    final chest = e['chest'] as num? ?? 0.0;
    final arms = e['arms'] as num? ?? 0.0;
    final hips = e['hips'] as num? ?? 0.0;
    final thighs = e['thighs'] as num? ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 12, color: p.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    formattedDate,
                    style: GoogleFonts.poppins(color: p.textMuted, fontSize: 10.5, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _metric('Chest', chest, p),
              _metric('Waist', waist, p),
              _metric('Arms', arms, p),
              _metric('Hips', hips, p),
              _metric('Thighs', thighs, p),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, num val, AppPalette p) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(color: p.textMuted, fontSize: 9.5),
        ),
        const SizedBox(height: 2),
        Text(
          val > 0 ? '$val' : '--',
          style: GoogleFonts.poppins(color: p.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
