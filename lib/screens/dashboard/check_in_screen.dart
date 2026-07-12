import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/check_in_controller.dart';
import '../../core/models/check_in_submission_model.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/check_in_math.dart';
import '../../core/widgets/gradient_title.dart';

/// The member's weekly check-in: rate how the week went (energy/sleep/…), log an
/// optional weight + note, and submit. An open (unreviewed) submission is loaded
/// for editing; past check-ins + coach responses show below. Writes
/// `client_check_in_submissions` via [CheckInController].
class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  final CheckInController c = Get.isRegistered<CheckInController>()
      ? Get.find<CheckInController>()
      : Get.put(CheckInController());

  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _weightCtrl = TextEditingController();
  Worker? _seedWorker;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    _seedFromOpen(c.open.value);
    // Seed the text fields from the existing open submission once it streams in
    // (edit mode) without clobbering anything the member has already typed.
    _seedWorker = ever<CheckInSubmissionModel?>(c.open, _seedFromOpen);
  }

  void _seedFromOpen(CheckInSubmissionModel? s) {
    if (_seeded || s == null) return;
    _seeded = true;
    if (_noteCtrl.text.isEmpty) _noteCtrl.text = s.note;
    if (_weightCtrl.text.isEmpty && s.weightKg != null) {
      _weightCtrl.text = _trimZero(s.weightKg!);
    }
  }

  String _trimZero(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  @override
  void dispose() {
    _seedWorker?.dispose();
    _noteCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final ok = await c.submit();
    if (!mounted) return;
    if (ok) {
      Get.back();
      Get.snackbar('Check-in sent', 'Your coach will review it soon.',
          snackPosition: SnackPosition.BOTTOM);
    } else {
      Get.snackbar('Could not submit', 'Please try again in a moment.',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        elevation: 0,
        iconTheme: IconThemeData(color: p.textPrimary),
        title: Text('Check-In',
            style: AppText.title(size: 18).copyWith(color: p.textPrimary)),
      ),
      body: SafeArea(
        child: Obx(() {
          if (c.isLoading.value) {
            return Center(
                child:
                    CircularProgressIndicator(strokeWidth: 2.4, color: p.accent));
          }
          if (!c.canLog) {
            return _notLinked(p);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              const GradientTitle('WEEKLY CHECK-IN',
                  size: 26, textAlign: TextAlign.start),
              const SizedBox(height: 6),
              _statusLine(p),
              const SizedBox(height: 18),
              _ratingsCard(p),
              const SizedBox(height: 16),
              _weightNoteCard(p),
              const SizedBox(height: 18),
              _submitButton(p),
              const SizedBox(height: 26),
              _historySection(p),
            ],
          );
        }),
      ),
    );
  }

  Widget _statusLine(AppPalette p) {
    final due = c.isDue;
    final next = c.nextCheckInAt;
    final text = due
        ? 'Your check-in is due — tell your coach how the week went.'
        : next != null
            ? 'Next check-in ${next.day}/${next.month}/${next.year}. You can submit anytime.'
            : 'Keep your coach updated on how you feel and progress.';
    return Text(text,
        style: AppText.body(size: 13).copyWith(
            color: due ? const Color(0xFFF59E0B) : p.textMuted));
  }

  // ── Ratings (1..5 per dimension) ──────────────────────────────────────
  Widget _ratingsCard(AppPalette p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
        boxShadow: AppShadows.card(p.isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('HOW WAS YOUR WEEK?',
              style: AppText.label(size: 12)
                  .copyWith(color: p.textSecondary, letterSpacing: 1)),
          const SizedBox(height: 6),
          for (final key in kCheckInRatingKeys) _ratingRow(p, key),
        ],
      ),
    );
  }

  Widget _ratingRow(AppPalette p, String key) {
    final label = kCheckInRatingLabels[key] ?? key;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label,
                style: AppText.body(size: 13.5).copyWith(color: p.textPrimary)),
          ),
          Expanded(
            flex: 5,
            child: Obx(() {
              final value = c.ratings[key] ?? 0;
              return Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var n = 1; n <= 5; n++)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (c.ratings[key] == n) {
                          c.clearRating(key);
                        } else {
                          c.setRating(key, n);
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(left: 8),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: n <= value
                              ? p.accent
                              : p.accent.withValues(alpha: 0.10),
                          border: Border.all(
                              color: n <= value ? p.accent : p.border),
                        ),
                        alignment: Alignment.center,
                        child: Text('$n',
                            style: AppText.body(size: 11).copyWith(
                                color: n <= value ? Colors.white : p.textMuted,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── Weight + note ─────────────────────────────────────────────────────
  Widget _weightNoteCard(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
        boxShadow: AppShadows.card(p.isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('WEIGHT (KG) — OPTIONAL',
              style: AppText.label(size: 12)
                  .copyWith(color: p.textSecondary, letterSpacing: 1)),
          const SizedBox(height: 8),
          TextField(
            controller: _weightCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: AppText.body(size: 15).copyWith(color: p.textPrimary),
            onChanged: (v) => c.setWeight(double.tryParse(v.trim())),
            decoration: _fieldDecoration(p, 'e.g. 72.5'),
          ),
          const SizedBox(height: 16),
          Text('NOTE TO YOUR COACH',
              style: AppText.label(size: 12)
                  .copyWith(color: p.textSecondary, letterSpacing: 1)),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            maxLines: 4,
            style: AppText.body(size: 14).copyWith(color: p.textPrimary),
            onChanged: c.setNote,
            decoration: _fieldDecoration(
                p, 'How did training, diet and recovery feel this week?'),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(AppPalette p, String hint) => InputDecoration(
        hintText: hint,
        hintStyle: AppText.body(size: 13).copyWith(color: p.textMuted),
        filled: true,
        fillColor: p.background,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
            borderRadius: AppRadii.smR, borderSide: BorderSide(color: p.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: AppRadii.smR,
            borderSide: BorderSide(color: p.accent, width: 1.4)),
      );

  Widget _submitButton(AppPalette p) {
    return Obx(() {
      final enabled = c.canSubmit && !c.isSaving.value;
      final editing = c.open.value != null;
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: enabled ? p.accent : p.accent.withValues(alpha: 0.4),
            disabledBackgroundColor: p.accent.withValues(alpha: 0.4),
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: AppRadii.smR),
          ),
          onPressed: enabled ? _submit : null,
          child: c.isSaving.value
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(editing ? 'Update Check-In' : 'Submit Check-In',
                  style: AppText.label(size: 15).copyWith(color: Colors.white)),
        ),
      );
    });
  }

  // ── Past check-ins ────────────────────────────────────────────────────
  Widget _historySection(AppPalette p) {
    return Obx(() {
      final items = c.history;
      if (items.isEmpty) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PAST CHECK-INS',
              style: AppText.label(size: 12)
                  .copyWith(color: p.textSecondary, letterSpacing: 1)),
          const SizedBox(height: 10),
          ...items.map((s) => _historyCard(p, s)),
        ],
      );
    });
  }

  Widget _historyCard(AppPalette p, CheckInSubmissionModel s) {
    final when = s.submittedAt;
    final period = when != null ? periodLabel(when) : 'Check-in';
    final reviewed = s.isReviewed;
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
              Expanded(
                child: Text(period,
                    style: AppText.label(size: 14)
                        .copyWith(color: p.textPrimary)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (reviewed ? const Color(0xFF2EBD59) : p.accent)
                      .withValues(alpha: 0.14),
                  borderRadius: AppRadii.smR,
                ),
                child: Text(reviewed ? 'Reviewed' : 'Submitted',
                    style: AppText.body(size: 10.5).copyWith(
                        color: reviewed ? const Color(0xFF2EBD59) : p.accent,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (s.weightKg != null || s.hasAnyRating) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (s.weightKg != null) '${_trimZero(s.weightKg!)} kg',
                if (s.hasAnyRating) '${s.ratings.length} ratings',
              ].join('  ·  '),
              style: AppText.body(size: 12).copyWith(color: p.textMuted),
            ),
          ],
          if (s.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(s.note,
                style: AppText.body(size: 13).copyWith(color: p.textPrimary)),
          ],
          if (reviewed && s.coachResponse.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFF2EBD59).withValues(alpha: 0.08),
                borderRadius: AppRadii.smR,
                border: Border.all(
                    color: const Color(0xFF2EBD59).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      s.reviewedByName.isNotEmpty
                          ? 'Coach ${s.reviewedByName}'
                          : 'Coach response',
                      style: AppText.label(size: 11)
                          .copyWith(color: const Color(0xFF2EBD59))),
                  const SizedBox(height: 3),
                  Text(s.coachResponse,
                      style:
                          AppText.body(size: 13).copyWith(color: p.textPrimary)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _notLinked(AppPalette p) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_late_outlined, size: 42, color: p.textMuted),
            const SizedBox(height: 12),
            Text('Join a coach first',
                style:
                    AppText.label(size: 15).copyWith(color: p.textSecondary)),
            const SizedBox(height: 4),
            Text('Check-ins unlock once you have an active membership.',
                textAlign: TextAlign.center,
                style: AppText.body(size: 13).copyWith(color: p.textMuted)),
          ],
        ),
      );
}
