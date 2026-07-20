import 'dart:io';

import 'package:get/get.dart';

import '../core/models/onboarding_question_model.dart';
import '../core/services/onboarding_service.dart';
import 'member_controller.dart';

/// Drives the coach's onboarding questionnaire for the signed-in member.
///
/// Loads the coach's questions ([OnboardingService.loadQuestions]) for the
/// member's linked org, holds the in-progress answers + per-question file-upload
/// state, validates that every REQUIRED question is answered, and submits to
/// `onboarding_responses/{clientId}` (which also stamps
/// `clientProfiles.coachOnboardingDoneFor` so Home advances past `onboarding`).
class OnboardingController extends GetxController {
  final OnboardingService _service = OnboardingService();
  final MemberController _member = Get.find<MemberController>();

  final RxBool isLoading = true.obs;
  final RxString loadError = ''.obs;
  final RxList<OnboardingQuestion> questions = <OnboardingQuestion>[].obs;

  /// Answer per questionId. Value types by question type:
  /// shortText/longText/number → String · singleChoice → String ·
  /// multiChoice → `List<String>` · photo/document → String (download URL).
  final RxMap<String, dynamic> answers = <String, dynamic>{}.obs;

  /// questionIds whose file is currently uploading (disables their tile).
  final RxSet<String> uploading = <String>{}.obs;

  /// Per-question answer visibility chosen by the member: 'shared' (default)
  /// or 'private'. Written verbatim onto each answer in the payload — the
  /// trainer app hides 'private' answers behind a privacy notice. Absent on
  /// legacy responses → treated as shared, so nothing existing breaks.
  final RxMap<String, String> visibility = <String, String>{}.obs;

  static const String kShared = 'shared';
  static const String kPrivate = 'private';

  String visibilityOf(String questionId) => visibility[questionId] ?? kShared;

  void setVisibility(String questionId, String v) {
    visibility[questionId] = v == kPrivate ? kPrivate : kShared;
  }

  /// Original filename of an uploaded file answer, for display.
  final RxMap<String, String> fileNames = <String, String>{}.obs;

  final RxBool isSubmitting = false.obs;
  final RxString submitError = ''.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    try {
      isLoading.value = true;
      loadError.value = '';
      questions.value = await _service.loadQuestions(_member.adminId);
    } catch (_) {
      loadError.value = 'Could not load the onboarding form. Tap retry.';
    } finally {
      isLoading.value = false;
    }
  }

  // ── Answer mutation ─────────────────────────────────────────────────
  void setText(String questionId, String value) {
    if (value.trim().isEmpty) {
      answers.remove(questionId);
    } else {
      answers[questionId] = value;
    }
  }

  void setSingleChoice(String questionId, String option) {
    answers[questionId] = option;
  }

  void toggleMultiChoice(String questionId, String option) {
    final current = (answers[questionId] as List?)?.cast<String>() ?? <String>[];
    final next = [...current];
    if (next.contains(option)) {
      next.remove(option);
    } else {
      next.add(option);
    }
    if (next.isEmpty) {
      answers.remove(questionId);
    } else {
      answers[questionId] = next;
    }
  }

  bool isOptionSelected(String questionId, String option) {
    final v = answers[questionId];
    if (v is List) return v.contains(option);
    return v == option;
  }

  /// Uploads a picked file for a photo/document question and stores its URL.
  Future<void> uploadFile(String questionId, File file, String filename) async {
    final uid = _member.uid;
    if (uid.isEmpty) {
      submitError.value = 'Not signed in.';
      return;
    }
    try {
      uploading.add(questionId);
      submitError.value = '';
      final url =
          await _service.uploadFile(uid: uid, file: file, filename: filename);
      answers[questionId] = url;
      fileNames[questionId] = filename;
    } catch (_) {
      submitError.value = 'Upload failed. Please try again.';
    } finally {
      uploading.remove(questionId);
    }
  }

  void clearFile(String questionId) {
    answers.remove(questionId);
    fileNames.remove(questionId);
  }

  // ── Progress / validation ───────────────────────────────────────────
  bool isAnswered(String questionId) {
    final v = answers[questionId];
    if (v == null) return false;
    if (v is String) return v.trim().isNotEmpty;
    if (v is List) return v.isNotEmpty;
    return true;
  }

  int get answeredCount => questions.where((q) => isAnswered(q.id)).length;

  /// Submit is allowed only when every REQUIRED question is answered.
  bool get canSubmit =>
      !isSubmitting.value &&
      questions.where((q) => q.required).every((q) => isAnswered(q.id));

  // ── Submit ──────────────────────────────────────────────────────────
  Future<bool> submit() async {
    if (!canSubmit) return false;
    final clientId = _member.clientId;
    final adminId = _member.adminId;
    final uid = _member.uid;
    if (clientId.isEmpty || adminId.isEmpty || uid.isEmpty) {
      submitError.value = 'Your account is still linking. Please try again.';
      return false;
    }
    try {
      isSubmitting.value = true;
      submitError.value = '';
      final payload = questions
          .where((q) => isAnswered(q.id))
          .map((q) => {
                'questionId': q.id,
                'question': q.question,
                'type': q.type,
                'options': q.options,
                'value': answers[q.id],
                // Member-chosen privacy (V2, additive): absent on legacy docs
                // → the trainer app defaults to shared.
                'visibility': visibilityOf(q.id),
              })
          .toList();
      await _service.submit(
        clientId: clientId,
        adminId: adminId,
        uid: uid,
        answers: payload,
      );
      return true;
    } catch (_) {
      submitError.value = 'Could not submit. Check your connection and retry.';
      return false;
    } finally {
      isSubmitting.value = false;
    }
  }
}
