import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../core/models/check_in_submission_model.dart';
import '../core/services/check_in_submission_service.dart';
import '../core/utils/check_in_math.dart';
import 'member_controller.dart';

/// Drives the member's weekly check-in: loads their open submission (edit) or a
/// fresh form, tracks ratings/weight/note, and submits. Also exposes whether a
/// check-in is due (from the coach's cadence on the clients doc) + past history.
class CheckInController extends GetxController {
  final CheckInSubmissionService _service = CheckInSubmissionService();
  final MemberController _member = Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());

  final Rxn<CheckInSubmissionModel> open = Rxn<CheckInSubmissionModel>();
  final RxList<CheckInSubmissionModel> history = <CheckInSubmissionModel>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isSaving = false.obs;

  // Editable form state.
  final RxMap<String, int> ratings = <String, int>{}.obs;
  final RxnDouble weightKg = RxnDouble();
  final RxString note = ''.obs;

  StreamSubscription? _openSub;
  StreamSubscription? _mineSub;
  Worker? _linkWorker;
  String? _loadedId; // the open doc currently mirrored into the form

  bool get canLog => _service.canLog;

  /// The coach's next check-in date (from the clients doc), if any. Defensive
  /// parse (Timestamp | String | DateTime): the coach app writes Firestore
  /// types — a String-only parse silently made "due" never fire.
  DateTime? get nextCheckInAt {
    final raw = _member.client.value?['nextCheckInAt'];
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  bool get isDue {
    final next = nextCheckInAt;
    return next == null ? false : !DateTime.now().isBefore(next);
  }

  /// Every week the member has already filed, as ISO week keys.
  Set<String> get submittedWeeks => {
        for (final s in history)
          if (s.weekOf.isNotEmpty)
            s.weekOf
          else if (s.submittedAt != null)
            weekKeyFor(s.submittedAt!),
      };

  /// Sunday, and not already filed. See `check_in_math.dart`.
  bool get isWindowOpen =>
      canAuthorCheckIn(now: DateTime.now(), submittedWeekKeys: submittedWeeks);

  /// Why the editor is closed, or null when it is open.
  String? get lockReason => checkInLockReason(
      now: DateTime.now(), submittedWeekKeys: submittedWeeks);

  /// This week's filed review, when there is one.
  CheckInSubmissionModel? get thisWeeksSubmission {
    final key = weekKeyFor(DateTime.now());
    for (final s in history) {
      final k = s.weekOf.isNotEmpty
          ? s.weekOf
          : (s.submittedAt == null ? '' : weekKeyFor(s.submittedAt!));
      if (k == key) return s;
    }
    return null;
  }

  /// The most recent filed review — what Monday–Saturday renders.
  CheckInSubmissionModel? get latest => history.isEmpty ? null : history.first;

  /// THE SUBMISSION GATE.
  ///
  /// Content is necessary but was, until this fix, also SUFFICIENT: the editor
  /// was live on every day of the week and nothing stopped a second review for
  /// a week already filed. The window and the one-per-week rule now sit in
  /// front of it, resolved by the shared policy so the screen cannot disagree.
  bool get canSubmit =>
      isWindowOpen &&
      hasSubmittableContent(
          note: note.value, ratings: ratings, weightKg: weightKg.value);

  @override
  void onInit() {
    super.onInit();
    _bind();
    // Re-bind when the member links: on first init `canLog` may be false (claim()
    // unresolved), which would leave the streams permanently empty (no history,
    // no open packet to edit).
    _linkWorker = ever(_member.isLinked, (_) => _bind());
  }

  void _bind() {
    _openSub?.cancel();
    _mineSub?.cancel();
    _openSub = _service.watchOpen().listen((s) {
      open.value = s;
      // Mirror the open doc into the form once (don't clobber active edits).
      if (s != null && _loadedId != s.id) {
        _loadedId = s.id;
        ratings.value = Map<String, int>.from(s.ratings);
        weightKg.value = s.weightKg;
        note.value = s.note;
      }
      isLoading.value = false;
    }, onError: (_) => isLoading.value = false);
    _mineSub = _service
        .watchMine()
        .listen((list) => history.value = list, onError: (_) {});
  }

  void setRating(String key, int value) {
    if (value < 1 || value > 5) return;
    ratings[key] = value;
  }

  void clearRating(String key) => ratings.remove(key);
  void setWeight(double? kg) => weightKg.value = kg;
  void setNote(String v) => note.value = v;

  Future<bool> submit() async {
    if (!canSubmit || isSaving.value) return false; // re-entry guard (no dup packets)
    isSaving.value = true;
    try {
      final id = await _service.submit(
        id: open.value?.id,
        weekOf: weekKeyFor(DateTime.now()),
        weightKg: weightKg.value,
        ratings: Map<String, int>.from(ratings),
        note: note.value,
      );
      return id != null;
    } finally {
      isSaving.value = false;
    }
  }

  @override
  void onClose() {
    _openSub?.cancel();
    _mineSub?.cancel();
    _linkWorker?.dispose();
    super.onClose();
  }
}
