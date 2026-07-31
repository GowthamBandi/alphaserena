import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../core/constants/firestore_collections.dart';
import '../screens/dashboard/home/membership_status.dart';
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

  DateTime? get expiry =>
      _parseExpiry(member.client.value?['membershipExpiry']);

  /// The raw `membershipFrozen` flag. [isActive] already folds this in; exposed
  /// so the Home header can distinguish "paused" from "expired" instead of
  /// collapsing both into a single not-active state.
  bool get isFrozen => member.client.value?['membershipFrozen'] == true;

  /// The raw `membershipActive` flag, WITHOUT the freeze/expiry conditions.
  /// Use [isActive] for entitlement decisions — this exists only so the header
  /// can tell "flag off" apart from "flag on but the date has passed".
  bool get activeFlag => member.client.value?['membershipActive'] == true;

  /// Whether the clients document carries any membership information at all.
  /// Distinguishes a genuinely unenrolled member from one whose membership is
  /// merely inactive.
  bool get hasMembershipRecord {
    final c = member.client.value;
    if (c == null) return false;
    return c.containsKey('membershipActive') ||
        c.containsKey('membershipExpiry') ||
        c['membership'] != null;
  }

  /// True until the linked clients document has arrived, which is what actually
  /// gates membership truth. NOTE: [isLoading] tracks the membership *plans*
  /// query and says nothing about the member's own membership.
  bool get isMembershipLoading =>
      member.isLoading.value || member.client.value == null;

  /// THE membership lifecycle state — the single engine every surface reads.
  ///
  /// Home's header already resolved membership through [MembershipStatus] (eight
  /// states, each with its own deliberately chosen wording and a non-colour
  /// glyph). Profile did not: it carried its own two-state binary AND a separate
  /// Active/Inactive badge, so on a frozen membership one screen said "Expired"
  /// and "Inactive" sixty pixels apart while Home said "Paused" — four labels for
  /// one fact.
  ///
  /// Exposing it here means neither screen derives membership language any more;
  /// they render what this returns. Adding a state, or changing a word, now
  /// happens in exactly one place and both surfaces move together.
  MembershipStatus get status => MembershipStatus.of(
    loading: isMembershipLoading,
    frozen: isFrozen,
    activeFlag: activeFlag,
    hasRecord: hasMembershipRecord,
    expiry: expiry,
  );

  /// The member's plan name, or `''` when the record does not carry one.
  /// Previously defaulted to the invented plan name 'Transform Program'.
  String get planName => (membership?['planName'] ?? '').toString().trim();

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
