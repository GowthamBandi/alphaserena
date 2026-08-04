import 'dart:async';

import 'package:get/get.dart';

import '../core/models/transformation_entry.dart';
import '../core/services/progress_log_service.dart';
import 'member_controller.dart';

/// Computes the latest real weight delta without trusting source-array order.
/// Partial checkpoints without weight are intentionally skipped.
double? transformationWeightChange(List<TransformationEntry> entries) {
  final weights =
      entries
          .where(
            (entry) =>
                entry.isComplete && entry.hasContent && entry.weightKg != null,
          )
          .toList()
        ..sort((a, b) {
          final dateOrder = b.recordedAt.compareTo(a.recordedAt);
          return dateOrder != 0 ? dateOrder : b.id.compareTo(a.id);
        });
  if (weights.length < 2) return null;
  return weights[0].weightKg! - weights[1].weightKg!;
}

class ProgressController extends GetxController {
  ProgressController({ProgressLogService? service}) : _injected = service;

  final MemberController memberController = Get.find<MemberController>();

  /// Resolved LAZILY, and injectable.
  ///
  /// 🔴 This was `final ProgressLogService _service = ProgressLogService();` — a
  /// FIELD INITIALIZER, and `ProgressLogService`'s own constructor resolves
  /// `FirebaseFirestore.instance`. So constructing this controller threw
  /// `[core/no-app]` before a single line of its behaviour could run, and a
  /// subclass overriding every method threw too, because the failure was at
  /// CONSTRUCTION. That is why this controller had exactly one unit test
  /// covering one pure top-level function and none covering the controller.
  ///
  /// It is the recurring defect class this codebase has now fixed in
  /// `TrainerService`, `StorageService`, `HrService`, `ClientService`,
  /// `CloudFunctionsService`, `SessionController` and the lifestyle services:
  /// **never resolve a Firebase singleton in a field initializer.**
  final ProgressLogService? _injected;
  ProgressLogService? _resolved;
  ProgressLogService get _service =>
      _injected ?? (_resolved ??= ProgressLogService());

  // `selectedTab` used to live here, driving the old three-tab Progress screen
  // (Overview / Transformation / Strength). Transformation is its own route
  // now and the other two tabs became real sections, so the field had no
  // reader left in `lib/` — a state holder for a control that no longer
  // exists is exactly the dead code this module has spent its passes removing.
  final RxBool isLoading = true.obs;
  final RxString error = ''.obs;
  final RxList<TransformationEntry> entries = <TransformationEntry>[].obs;

  StreamSubscription<List<TransformationEntry>>? _subscription;
  Worker? _linkWorker;

  List<TransformationEntry> get completed =>
      entries.where((entry) => entry.isComplete && entry.hasContent).toList();

  List<TransformationEntry> get recoveryDrafts => entries
      .where((entry) => entry.status == TransformationStatus.uploading)
      .toList();

  TransformationEntry? get latest => completed.firstOrNull;

  List<TransformationEntry> get weights =>
      completed.where((entry) => entry.weightKg != null).toList();

  double? get latestWeight => weights.firstOrNull?.weightKg;

  double? get weightChange => transformationWeightChange(completed);

  @override
  void onInit() {
    super.onInit();
    _bind();
    _linkWorker = ever(memberController.isLinked, (_) => _bind());
  }

  void retry() => _bind();

  /// Re-shares or hides one published checkpoint. The live stream delivers the
  /// new state, so nothing is optimistically mutated here — a rejected write
  /// leaves the member looking at what is actually stored.
  Future<TransformationWriteOutcome> setVisibility(
    TransformationEntry entry,
    TransformationVisibility visibility,
  ) => _service.setVisibility(recordId: entry.id, visibility: visibility);

  /// Re-subscribes after a successful local write without replacing the
  /// Progress screen with a loading state while the save confirmation closes.
  void refreshAfterSave() => _bind(showLoading: false);

  void _bind({bool showLoading = true}) {
    _subscription?.cancel();
    if (showLoading) isLoading.value = true;
    error.value = '';
    _subscription = _service.watchTransformations().listen(
      (value) {
        entries.assignAll(value);
        isLoading.value = false;
      },
      onError: (_) {
        error.value = 'Transformation history is unavailable.';
        isLoading.value = false;
      },
    );
  }

  @override
  void onClose() {
    _subscription?.cancel();
    _linkWorker?.dispose();
    super.onClose();
  }
}
