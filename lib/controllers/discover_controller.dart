import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import '../core/models/organization_profile_model.dart';
import '../core/services/client_profile_service.dart';
import '../core/services/coach_service.dart';

String orgLocation(OrganizationProfileModel o) => o.city ?? o.state ?? '';

List<String> distinctLocations(List<OrganizationProfileModel> orgs) {
  final set = <String>{};
  for (final o in orgs) {
    final loc = orgLocation(o);
    if (loc.isNotEmpty) set.add(loc);
  }
  final list = set.toList()..sort();
  return list;
}

List<String> distinctSpecializations(List<OrganizationProfileModel> orgs) {
  final set = <String>{};
  for (final o in orgs) {
    for (final s in o.specializations) {
      if (s.isNotEmpty) set.add(s);
    }
  }
  final list = set.toList()..sort();
  return list;
}

List<OrganizationProfileModel> filterOrgs(
  List<OrganizationProfileModel> orgs, {
  String query = '',
  String? location,
  String? specialization,
}) {
  final q = query.trim().toLowerCase();
  return orgs.where((o) {
    if (location != null && orgLocation(o) != location) return false;
    if (specialization != null && !o.specializations.contains(specialization)) {
      return false;
    }
    if (q.isEmpty) return true;
    final hay = [
      o.name,
      o.tagline ?? '',
      o.city ?? '',
      o.state ?? '',
      ...o.specializations,
    ].join(' ').toLowerCase();
    return hay.contains(q);
  }).toList();
}

/// Loads published organizations + holds the member's search / filter state.
class DiscoverController extends GetxController {
  final CoachService _coaches = CoachService();
  final ClientProfileService _profiles = ClientProfileService();

  final RxBool isLoading = true.obs;
  final RxString error = ''.obs;
  final RxList<OrganizationProfileModel> all = <OrganizationProfileModel>[].obs;
  final RxString memberName = 'Alpha'.obs;

  final RxString query = ''.obs;
  final Rxn<String> locationFilter = Rxn<String>();
  final Rxn<String> specializationFilter = Rxn<String>();

  List<OrganizationProfileModel> get visible => filterOrgs(
        all,
        query: query.value,
        location: locationFilter.value,
        specialization: specializationFilter.value,
      );

  List<String> get locations => distinctLocations(all);
  List<String> get specializations => distinctSpecializations(all);

  @override
  void onInit() {
    super.onInit();
    _loadName();
    load();
  }

  Future<void> _loadName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final p = await _profiles.get(uid);
      final n = (p?['clientName'] ?? '').toString().trim();
      if (n.isNotEmpty) memberName.value = n.split(' ').first;
    } catch (_) {
      // keep the 'Alpha' fallback
    }
  }

  Future<void> load() async {
    try {
      isLoading.value = true;
      error.value = '';
      all.assignAll(await _coaches.discover());
    } catch (_) {
      error.value = 'Could not load organizations. Tap retry.';
      all.clear();
    } finally {
      isLoading.value = false;
    }
  }

  void clearFilters() {
    query.value = '';
    locationFilter.value = null;
    specializationFilter.value = null;
  }

  Future<OrganizationProfileModel?> lookupByHandle(String code) =>
      _coaches.byHandle(code);
}
