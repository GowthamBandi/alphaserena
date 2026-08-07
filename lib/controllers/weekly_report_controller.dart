import 'dart:async';

import 'package:get/get.dart';

import '../core/models/weekly_report_models.dart';
import '../core/services/weekly_report_service.dart';
import '../core/weekly_reports/question_engine.dart';
import 'member_controller.dart';

/// Drives the member's Weekly Report.
///
/// WHAT THIS CONTROLLER DOES NOT DO, and the whole design depends on it:
/// it never decides whether a report is open, which week it covers, or when it
/// is due. Those are `snapshot.status`, `snapshot.periodKey`, `snapshot.dueAt`
/// — written by the server in the organization's timezone. The retiring
/// check-in decided all three from `DateTime.now()` on the member's device, and
/// device clock skew of +3 and +6 days is already proven in production here.
///
/// `DateTime.now()` appears exactly once below, to render a COUNTDOWN. A wrong
/// clock makes that countdown wrong; it cannot open, close or miss a report.
class WeeklyReportController extends GetxController {
  WeeklyReportController({WeeklyReportService? service})
      : _service = service ?? WeeklyReportService();

  final WeeklyReportService _service;
  final MemberController _member = Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());

  final RxList<WeeklyReportSnapshot> reports = <WeeklyReportSnapshot>[].obs;
  final RxMap<String, WeeklyReportSubmission> submissions =
      <String, WeeklyReportSubmission>{}.obs;
  final RxMap<String, WeeklyReportReview> reviews =
      <String, WeeklyReportReview>{}.obs;
  final Rx<WeeklyReportRollup> rollup = const WeeklyReportRollup().obs;

  final RxBool isLoading = true.obs;
  final RxBool isSaving = false.obs;
  final RxBool isSubmitting = false.obs;
  final RxBool hasQueuedWrite = false.obs;
  final RxString errorText = ''.obs;

  /// Local answers for the report being edited, keyed by question id. Mirrors
  /// the stored shape (`{value: …}`) so a draft round-trip is a no-op.
  final RxMap<String, dynamic> draft = <String, dynamic>{}.obs;

  /// Questions the member has interacted with. Errors are shown ONLY for these
  /// until they try to submit — a form that turns red before it has been
  /// touched reads as broken rather than helpful.
  final RxSet<String> touched = <String>{}.obs;
  final RxBool showAllErrors = false.obs;

  StreamSubscription? _snapSub;
  StreamSubscription? _subSub;
  StreamSubscription? _revSub;
  StreamSubscription? _rollSub;
  Worker? _linkWorker;
  Timer? _saveTimer;
  DateTime? _saveDeadline;
  String? _seededFor;

  /// Autosave debounce. Long enough that typing a paragraph is one write,
  /// short enough that closing the app mid-sentence loses nothing.
  static const Duration saveDebounce = Duration(milliseconds: 1200);

  /// However continuously the member types, a pending draft is never deferred
  /// beyond this — the starvation guard the lifestyle debounce needed too.
  static const Duration saveDeadline = Duration(seconds: 6);

  @override
  void onInit() {
    super.onInit();
    _bind();
    // Re-bind when the member links: on first init `canRead` may be false
    // (claim() unresolved), which would leave every stream permanently empty.
    // Re-bind on the LINKED CLIENT ID, not merely on `isLinked`.
    //
    // 🔴 `WeeklyReportService.canRead` requires `clientId`, and the query is
    // keyed on the member's uid — but the worker watched a BOOLEAN that is set
    // at a different moment. A controller constructed in the window between
    // them bound `Stream.value(const [])`, which emits once and closes: the
    // member was told "No weekly report yet — your coach sends one every week"
    // permanently, with no error and no retry, while a real report sat in
    // production waiting for them.
    //
    // Observe the value the query actually depends on.
    _linkWorker = everAll(
      [_member.isLinked, _member.linkedClientIdRx],
      (_) => _bind(),
    );
  }

  /// Re-binds every stream after a failure. Without it the error state would be
  /// a dead end: the member is told something went wrong and given no way to
  /// ask again short of restarting the app.
  void retry() {
    errorText.value = '';
    isLoading.value = true;
    _bind();
  }

  void _bind() {
    _snapSub?.cancel();
    _subSub?.cancel();
    _revSub?.cancel();
    _rollSub?.cancel();

    // NOT YET READABLE. Deliberately bind NOTHING rather than an empty stream:
    // an empty emission is indistinguishable from "no reports exist", and the
    // screen would state the second while the first is true. `isUnlinked`
    // drives honest copy instead, and the worker above re-binds the moment the
    // link lands.
    if (!_service.canRead) {
      reports.clear();
      isLoading.value = false;
      return;
    }

    _snapSub = _service.watchAll().listen((list) {
      reports.value = list;
      isLoading.value = false;
      // A successful emission CLEARS a previous failure. Leaving it set would
      // strand the error state over data that has since arrived.
      errorText.value = '';
      _seedDraft();
    }, onError: (Object e) {
      isLoading.value = false;
      errorText.value = 'Could not load your reports.';
    });

    _subSub = _service.watchAllSubmissions().listen((m) {
      submissions.value = m;
      _seedDraft();
    }, onError: (_) {});

    _revSub = _service.watchAllReviews().listen(
          (m) => reviews.value = m,
          onError: (_) {},
        );

    _rollSub = _service.watchRollup().listen(
          (r) => rollup.value = r,
          onError: (_) {},
        );
  }

  /// Registers EVERY reactive value with the enclosing `Obx`.
  ///
  /// 🔴 WHY THIS EXISTS — the same defect proven on the coach side in
  /// production. `Obx` records only the Rx reads made DURING its own builder
  /// call. This screen's builder returns `_FormView`, whose `build` runs later
  /// and reads `draft`, `isSaving`, `hasQueuedWrite`, `isSubmitting`, `touched`
  /// and `showAllErrors` — none of which were therefore observed.
  ///
  /// On the member side the consequences are worse than a stale card: the
  /// progress bar would not move as they answered, the "Saving…" indicator
  /// would never appear, and the submit gate — which is derived from `draft` —
  /// would not re-evaluate. Reading `.value` is the entire mechanism; do not
  /// "optimise" these statements away.
  void observeAll() {
    // `.length` on an Rx COLLECTION, not `.value`: GetX marks the collection
    // `value` getter `@protected`, and `length` registers the very same
    // dependency on the whole Rx.
    reports.length;
    submissions.length;
    reviews.length;
    draft.length;
    touched.length;
    rollup.value;
    showAllErrors.value;
    isSaving.value;
    isSubmitting.value;
    hasQueuedWrite.value;
    errorText.value;
  }

  // ── what the member is looking at ─────────────────────────────────────────

  /// The report to act on: the newest one still accepting answers, else the
  /// newest of any kind. Never invents one.
  WeeklyReportSnapshot? get current {
    for (final r in reports) {
      if (r.acceptsAnswers) return r;
    }
    return reports.isEmpty ? null : reports.first;
  }

  WeeklyReportSubmission? submissionFor(String id) => submissions[id];
  WeeklyReportReview? reviewFor(String id) => reviews[id];

  WeeklyReportSubmission? get currentSubmission {
    final c = current;
    return c == null ? null : submissions[c.id];
  }

  /// Reports the member can browse — everything that was issued, whatever
  /// happened to it. A missed week is part of the record.
  List<WeeklyReportSnapshot> get history => reports;

  /// True when there is no report at all yet.
  bool get isAwaitingFirstReport => !isLoading.value && reports.isEmpty;

  /// True when this session cannot READ reports at all — the member's account
  /// is not yet linked to a coach's client record.
  ///
  /// 🔴 WITHOUT THIS THE EMPTY STATE LIED. `WeeklyReportService.watchAll`
  /// returns an EMPTY STREAM when it has no linked client, which is
  /// indistinguishable from "your coach has not sent one" — and that is what
  /// the screen said: "Your coach sends one every week." A confident statement
  /// about the coach, made when the app does not yet know who the member is.
  ///
  /// Two different facts, two different states.
  bool get isUnlinked => !_service.canRead;

  /// Time until the current report opens, or null when it is already open.
  ///
  /// DISPLAY ONLY. `opensAt` is an absolute instant the server wrote; a skewed
  /// device renders a wrong number of days and changes nothing else.
  Duration? countdownTo(DateTime now) {
    final c = current;
    final opens = c?.opensAt;
    if (c == null || opens == null) return null;
    if (c.status != WeeklyReportStatus.scheduled) return null;
    final d = opens.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  /// Time left to submit, or null when there is no deadline in play.
  Duration? remainingFor(WeeklyReportSnapshot s, DateTime now) {
    final due = s.dueAt;
    if (due == null || !s.acceptsAnswers) return null;
    final d = due.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  // ── the form ──────────────────────────────────────────────────────────────

  /// Seeds the local draft from the stored submission, ONCE per report.
  ///
  /// Guarded by `_seededFor` rather than by emptiness: a member who has cleared
  /// every answer would otherwise have the stored draft poured back in on the
  /// next snapshot tick, silently undoing the clear.
  void _seedDraft() {
    final c = current;
    if (c == null) return;
    if (_seededFor == c.id) return;
    _seededFor = c.id;
    final stored = submissions[c.id];
    draft.value = stored == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(stored.answers);
    touched.clear();
    showAllErrors.value = false;
  }

  /// The engine's view of the current report. THE single source for the
  /// progress bar, the per-question errors and the submit gate — so they can
  /// never disagree about how much is left.
  ///
  /// Named `completion`, not `completionOf`, deliberately: a method with the
  /// engine function's name SHADOWS it inside this class, and the wrapper then
  /// recurses into itself instead of delegating. Caught by the analyzer here;
  /// it would have been a stack overflow on the member's first keystroke.
  ReportCompletion completion(WeeklyReportSnapshot s) =>
      completionOf(s.questions, draft);

  /// Visible questions for [s] under the current answers, in author order.
  List<QuestionDefinition> visibleFor(WeeklyReportSnapshot s) =>
      visibleQuestions(s.questions, draft);

  dynamic answerFor(String questionId) => answerValue(draft, questionId);

  /// The verdict to SHOW for a question — null while it is untouched and the
  /// member has not tried to submit.
  AnswerVerdict? verdictFor(QuestionDefinition q) {
    if (!showAllErrors.value && !touched.contains(q.id)) return null;
    final v = validateAnswer(q, answerValue(draft, q.id));
    return v.ok ? null : v;
  }

  /// Records an answer and schedules an autosave.
  void setAnswer(QuestionDefinition q, dynamic value) {
    final s = current;
    if (s == null || !s.acceptsAnswers) return;
    touched.add(q.id);
    if (!isAnswered(value)) {
      draft.remove(q.id);
    } else {
      draft[q.id] = <String, dynamic>{'type': q.type, 'value': value};
    }
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveDeadline ??= DateTime.now().add(saveDeadline);
    _saveTimer?.cancel();
    final untilDeadline = _saveDeadline!.difference(DateTime.now());
    final delay = untilDeadline < saveDebounce ? untilDeadline : saveDebounce;
    _saveTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => flushDraft(),
    );
  }

  /// Writes the pending draft now. Called by the debounce, by `onClose`, and by
  /// the screen when the member leaves — a draft owed to the server must not be
  /// dropped because they navigated away inside the debounce window.
  Future<void> flushDraft() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    _saveDeadline = null;
    final s = current;
    if (s == null || !s.acceptsAnswers) return;
    if (isSubmitting.value) return;

    isSaving.value = true;
    try {
      final outcome = await _service.saveDraft(
        snapshot: s,
        answers: Map<String, dynamic>.from(draft),
      );
      hasQueuedWrite.value = outcome == ReportWriteOutcome.queued;
      errorText.value =
          outcome == ReportWriteOutcome.failed ? 'Could not save your draft.' : '';
    } finally {
      isSaving.value = false;
    }
  }

  /// THE SUBMIT GATE — the engine's, not a second opinion.
  bool canSubmit(WeeklyReportSnapshot s) =>
      s.acceptsAnswers && completion(s).canSubmit;

  /// Submits the current report.
  ///
  /// Returns false and reveals every error when the engine refuses, so a
  /// disabled-looking button never leaves the member without a reason.
  Future<bool> submitCurrent() async {
    final s = current;
    if (s == null || isSubmitting.value) return false;
    if (!canSubmit(s)) {
      showAllErrors.value = true;
      return false;
    }

    // Re-entry guard AND flush: a pending debounce would otherwise land after
    // the submit and rewrite the document as a draft.
    _saveTimer?.cancel();
    isSubmitting.value = true;
    try {
      final outcome = await _service.submit(
        snapshot: s,
        answers: Map<String, dynamic>.from(draft),
      );
      if (outcome == ReportWriteOutcome.failed) {
        errorText.value = 'Could not send your report. Please try again.';
        return false;
      }
      hasQueuedWrite.value = outcome == ReportWriteOutcome.queued;
      errorText.value = '';
      return true;
    } finally {
      isSubmitting.value = false;
    }
  }

  @override
  void onClose() {
    // Flush before tearing down, or the last edits inside the debounce window
    // are lost. Fire-and-forget: `onClose` cannot await.
    if (_saveTimer?.isActive == true) unawaited(flushDraft());
    _saveTimer?.cancel();
    _snapSub?.cancel();
    _subSub?.cancel();
    _revSub?.cancel();
    _rollSub?.cancel();
    _linkWorker?.dispose();
    super.onClose();
  }
}
