import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../controllers/onboarding_controller.dart';
import '../../core/models/onboarding_question_model.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/gradient_button.dart';

/// The coach's onboarding questionnaire — one branded card per question, a
/// "X of Y answered" header, all 7 question types (incl. photo/document upload),
/// and a sticky Submit that stays disabled until every REQUIRED question is
/// answered. On success it pops back to Home, which advances past `onboarding`.
class OnboardingFlowScreen extends StatefulWidget {
  const OnboardingFlowScreen({super.key});

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends State<OnboardingFlowScreen> {
  // Always create fresh so the form reflects the CURRENT coach's questions
  // (Get.put replaces any prior instance and re-runs load()). Torn down on
  // sign-out via AuthController.
  final OnboardingController c = Get.put(OnboardingController());

  final ImagePicker _imagePicker = ImagePicker();
  final Map<String, TextEditingController> _textControllers = {};

  TextEditingController _textController(String id) =>
      _textControllers.putIfAbsent(id, () => TextEditingController());

  @override
  void dispose() {
    for (final t in _textControllers.values) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        elevation: 0,
        title: Text('Complete Onboarding',
            style: AppText.cardTitle(size: 17).copyWith(color: p.textPrimary)),
        iconTheme: IconThemeData(color: p.textPrimary),
      ),
      body: Obx(() {
        if (c.isLoading.value) {
          return Center(child: CircularProgressIndicator(color: p.accent));
        }
        if (c.loadError.value.isNotEmpty) {
          return _errorState(p);
        }
        if (c.questions.isEmpty) {
          return _emptyState(p);
        }
        return _form(p);
      }),
      bottomNavigationBar: Obx(() {
        if (c.isLoading.value ||
            c.loadError.value.isNotEmpty ||
            c.questions.isEmpty) {
          return const SizedBox.shrink();
        }
        return _submitBar(p);
      }),
    );
  }

  // ── States ──────────────────────────────────────────────────────────
  Widget _errorState(AppPalette p) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: p.textMuted, size: 44),
            const SizedBox(height: 14),
            Text(c.loadError.value,
                textAlign: TextAlign.center,
                style: AppText.body(size: 13).copyWith(color: p.textMuted)),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: c.load,
              style: OutlinedButton.styleFrom(
                foregroundColor: p.accent,
                side: BorderSide(color: p.accent),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(AppPalette p) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.checklist_rtl_rounded, color: p.accent, size: 48),
            const SizedBox(height: 16),
            Text('No questions to answer',
                style: AppText.title(size: 18).copyWith(color: p.textPrimary)),
            const SizedBox(height: 8),
            Text(
              'Your coach hasn\'t added an intake form yet. You\'re all set — '
              'continue to your dashboard.',
              textAlign: TextAlign.center,
              style: AppText.body(size: 13).copyWith(color: p.textMuted),
            ),
            const SizedBox(height: 22),
            Obx(() => GradientButton(
                  label: 'Continue',
                  isLoading: c.isSubmitting.value,
                  onPressed: _onSubmit,
                )),
          ],
        ),
      ),
    );
  }

  Widget _form(AppPalette p) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      itemCount: c.questions.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, i) {
        if (i == 0) return _progressHeader(p);
        return _questionCard(p, i, c.questions[i - 1]);
      },
    );
  }

  Widget _progressHeader(AppPalette p) {
    return Obx(() {
      final total = c.questions.length;
      final done = c.answeredCount;
      final pct = total == 0 ? 0.0 : done / total;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tell your coach about you',
              style: AppText.title(size: 20).copyWith(color: p.textPrimary)),
          const SizedBox(height: 4),
          Text(
            'Answers help your coach build the right plan. Required questions are '
            'marked with *.',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    backgroundColor: p.surfaceAlt,
                    valueColor: AlwaysStoppedAnimation(p.accent),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('$done of $total answered',
                  style: AppText.label(size: 11).copyWith(color: p.textMuted)),
            ],
          ),
        ],
      );
    });
  }

  Widget _questionCard(AppPalette p, int number, OnboardingQuestion q) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: glassCard(p, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$number.',
                  style: AppText.label(size: 13)
                      .copyWith(color: p.accent, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    text: q.question.isEmpty ? 'Question' : q.question,
                    style: GoogleFonts.poppins(
                      color: p.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                    children: q.required
                        ? [
                            TextSpan(
                              text: ' *',
                              style: TextStyle(
                                  color: p.error, fontWeight: FontWeight.w700),
                            )
                          ]
                        : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _answerWidget(p, q),
        ],
      ),
    );
  }

  Widget _answerWidget(AppPalette p, OnboardingQuestion q) {
    if (q.isChoice) return _choices(p, q);
    if (q.isFile) return _fileField(p, q);
    return _textField(p, q);
  }

  // ── Text / number ───────────────────────────────────────────────────
  Widget _textField(AppPalette p, OnboardingQuestion q) {
    final ctrl = _textController(q.id);
    return TextField(
      controller: ctrl,
      onChanged: (v) => c.setText(q.id, v),
      keyboardType:
          q.isNumber ? TextInputType.number : TextInputType.multiline,
      maxLines: q.isLongText ? 4 : 1,
      minLines: q.isLongText ? 3 : 1,
      cursorColor: p.accent,
      style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: p.inputFill,
        hintText: q.isNumber ? 'Enter a number' : 'Your answer',
        hintStyle: TextStyle(color: p.textMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.accent, width: 1.4),
        ),
      ),
    );
  }

  // ── Single / multi choice ───────────────────────────────────────────
  Widget _choices(AppPalette p, OnboardingQuestion q) {
    if (q.options.isEmpty) {
      return Text('No options provided.',
          style: AppText.body(size: 12).copyWith(color: p.textMuted));
    }
    return Obx(() => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: q.options.map((opt) {
            final selected = c.isOptionSelected(q.id, opt);
            return GestureDetector(
              onTap: () => q.isMultiChoice
                  ? c.toggleMultiChoice(q.id, opt)
                  : c.setSingleChoice(q.id, opt),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: selected
                      ? p.accent.withValues(alpha: 0.14)
                      : p.inputFill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? p.accent : p.border,
                    width: selected ? 1.4 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      q.isMultiChoice
                          ? (selected
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded)
                          : (selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked),
                      size: 16,
                      color: selected ? p.accent : p.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      opt,
                      style: GoogleFonts.poppins(
                        color: selected ? p.textPrimary : p.textSecondary,
                        fontSize: 12.5,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ));
  }

  // ── Photo / document ────────────────────────────────────────────────
  Widget _fileField(AppPalette p, OnboardingQuestion q) {
    return Obx(() {
      final busy = c.uploading.contains(q.id);
      final url = c.answers[q.id] as String?;
      final hasFile = url != null && url.isNotEmpty;

      if (busy) {
        return Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: p.accent),
            ),
            const SizedBox(width: 10),
            Text('Uploading…',
                style: AppText.body(size: 12).copyWith(color: p.textMuted)),
          ],
        );
      }

      if (hasFile) {
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: p.inputFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.border),
          ),
          child: Row(
            children: [
              if (q.isPhoto)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    url,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                        Icons.image_not_supported_outlined,
                        color: p.textMuted),
                  ),
                )
              else
                Icon(Icons.description_rounded, color: p.accent, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  c.fileNames[q.id] ?? 'Uploaded',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      AppText.body(size: 12).copyWith(color: p.textPrimary),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: p.textMuted, size: 20),
                onPressed: () => c.clearFile(q.id),
              ),
            ],
          ),
        );
      }

      return OutlinedButton.icon(
        onPressed: () => q.isPhoto ? _pickPhoto(q.id) : _pickDocument(q.id),
        style: OutlinedButton.styleFrom(
          foregroundColor: p.accent,
          side: BorderSide(color: p.border),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        icon: Icon(
            q.isPhoto ? Icons.add_a_photo_outlined : Icons.upload_file_outlined,
            size: 18),
        label: Text(q.isPhoto ? 'Add Photo' : 'Upload Document',
            style: AppText.label(size: 12.5)),
      );
    });
  }

  Future<void> _pickPhoto(String questionId) async {
    final x = await _imagePicker.pickImage(
        source: ImageSource.gallery, imageQuality: 80);
    if (x == null) return;
    await c.uploadFile(questionId, File(x.path), x.name);
  }

  Future<void> _pickDocument(String questionId) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'],
    );
    final path = res?.files.single.path;
    if (path == null) return;
    await c.uploadFile(questionId, File(path), res!.files.single.name);
  }

  // ── Submit ──────────────────────────────────────────────────────────
  Widget _submitBar(AppPalette p) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          18, 10, 18, 14 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.submitError.value.isNotEmpty) ...[
            Text(c.submitError.value,
                textAlign: TextAlign.center,
                style: AppText.body(size: 11.5).copyWith(color: p.error)),
            const SizedBox(height: 8),
          ],
          Opacity(
            opacity: c.canSubmit ? 1 : 0.5,
            child: GradientButton(
              label: 'Submit & Continue',
              showChevron: true,
              isLoading: c.isSubmitting.value,
              onPressed: c.canSubmit ? _onSubmit : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onSubmit() async {
    final ok = await c.submit();
    if (ok && mounted) {
      Get.back();
      Get.snackbar(
        'All set!',
        'Your coach has your details. They\'ll set up your plan soon.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }
}
