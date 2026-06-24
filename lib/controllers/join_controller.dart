import 'package:get/get.dart';

import '../core/services/coach_service.dart';

/// Drives the "find your coach" flow — browse published coaches + look one up
/// by join code.
class JoinController extends GetxController {
  final CoachService _service = CoachService();

  final RxBool isLoading = true.obs;
  final RxBool isSearching = false.obs;
  final RxList<CoachSummary> coaches = <CoachSummary>[].obs;

  @override
  void onInit() {
    super.onInit();
    loadDiscovery();
  }

  Future<void> loadDiscovery() async {
    isLoading.value = true;
    try {
      coaches.value = await _service.discover();
    } catch (_) {
      coaches.clear();
    } finally {
      isLoading.value = false;
    }
  }

  Future<CoachSummary?> lookup(String code) async {
    isSearching.value = true;
    try {
      return await _service.byHandle(code);
    } catch (_) {
      return null;
    } finally {
      isSearching.value = false;
    }
  }
}
