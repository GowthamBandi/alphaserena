import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../core/constants/firestore_collections.dart';
import 'member_controller.dart';

/// Tier-2: the member's gym's membership plans + the member's current membership
/// (read off their `clients` doc, which MemberController streams).
class MembershipController extends GetxController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final MemberController member = Get.find<MemberController>();

  final RxList<Map<String, dynamic>> plans = <Map<String, dynamic>>[].obs;
  final RxBool isLoading = true.obs;

  StreamSubscription? _sub;
  String? _boundAdminId;

  @override
  void onInit() {
    super.onInit();
    _listenPlans();
    // Re-bind if the linked client (and thus the gym) resolves later.
    ever(member.client, (_) => _listenPlans());
  }

  void _listenPlans() {
    final adminId = member.client.value?['adminId']?.toString();
    if (adminId == null || adminId.isEmpty) {
      isLoading.value = false;
      return;
    }
    if (adminId == _boundAdminId) return;
    _boundAdminId = adminId;
    _sub?.cancel();
    // Single-field query (no composite index needed); filter isActive in Dart.
    _sub = _db
        .collection(FsCollections.membershipPlans)
        .where('adminId', isEqualTo: adminId)
        .snapshots()
        .listen((s) {
      plans.value = s.docs
          .map((d) => {...d.data(), 'id': d.id})
          .where((m) => m['isActive'] != false)
          .toList();
      isLoading.value = false;
    }, onError: (_) => isLoading.value = false);
  }

  Map<String, dynamic>? get membership {
    final m = member.client.value?['membership'];
    return m is Map ? Map<String, dynamic>.from(m) : null;
  }

  bool get isActive {
    final exp = member.client.value?['membershipExpiry']?.toString();
    if (exp == null) return false;
    final dt = DateTime.tryParse(exp);
    return dt != null && dt.isAfter(DateTime.now());
  }

  DateTime? get expiry {
    final exp = member.client.value?['membershipExpiry']?.toString();
    return exp == null ? null : DateTime.tryParse(exp);
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }
}
