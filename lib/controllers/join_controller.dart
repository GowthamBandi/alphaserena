import 'package:get/get.dart';

import '../core/models/organization_profile_model.dart';
import '../core/services/coach_service.dart';

/// Drives the "find your coach" flow — browse published coaches + look one up
/// by join code.
///
/// NOTE: superseded by [DiscoverController] for the member-facing Discover
/// screen. Kept for reference; not currently registered.
class JoinController extends GetxController {
  final CoachService _service = CoachService();

  final RxBool isLoading = true.obs;
  final RxBool isSearching = false.obs;
  final RxList<OrganizationProfileModel> coaches =
      <OrganizationProfileModel>[].obs;

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

  Future<OrganizationProfileModel?> lookup(String code) async {
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
