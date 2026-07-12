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
  Worker? _clientWorker;
  String? _boundAdminId;

  @override
  void onInit() {
    super.onInit();
    _listenPlans();
    // Re-bind if the linked client (and thus the gym) resolves later.
    _clientWorker = ever(member.client, (_) => _listenPlans());
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
    final frozen = member.client.value?['membershipFrozen'] == true;
    if (frozen) return false;
    final active = member.client.value?['membershipActive'] == true;
    if (!active) return false;
    final e = _parseExpiry(member.client.value?['membershipExpiry']);
    return e != null && e.isAfter(DateTime.now());
  }

  DateTime? get expiry => _parseExpiry(member.client.value?['membershipExpiry']);

  /// Defensive expiry parser — handles Timestamp (Firestore native) or ISO string.
  static DateTime? _parseExpiry(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  /// True when membership is active and expiring within 7 days.
  bool get isExpiringSoon {
    if (!isActive) return false;
    final e = expiry;
    if (e == null) return false;
    return e.difference(DateTime.now()).inDays <= 7;
  }

  @override
  void onClose() {
    _sub?.cancel();
    _clientWorker?.dispose();
    super.onClose();
  }
}
