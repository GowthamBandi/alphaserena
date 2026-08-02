import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/firestore_collections.dart';
import '../models/organization_profile_model.dart';

/// Discovery + lookup of coaches and their membership plans (member-side).
class CoachService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Published organizations the member can browse (top-rated first).
  Future<List<OrganizationProfileModel>> discover() async {
    final q = await _db
        .collection(FsCollections.organizationProfiles)
        .where('published', isEqualTo: true)
        .limit(50)
        .get();
    final list = q.docs
        .map((d) => OrganizationProfileModel.fromMap(d.data(), d.id))
        .toList();
    list.sort((a, b) {
      final r = b.rating.compareTo(a.rating); // rating desc
      if (r != 0) return r;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  /// Look an organization up by its join code / handle.
  Future<OrganizationProfileModel?> byHandle(String handle) async {
    final h = handle.trim().toLowerCase().replaceAll('@', '');
    if (h.isEmpty) return null;
    final q = await _db
        .collection(FsCollections.organizationProfiles)
        .where('handle', isEqualTo: h)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    return OrganizationProfileModel.fromMap(
      q.docs.first.data(),
      q.docs.first.id,
    );
  }

  /// Load a single organization's storefront by its id (== adminId). Used to
  /// open the member's OWN coach storefront from Home. Returns null if the
  /// profile doc is missing.
  Future<OrganizationProfileModel?> byId(String adminId) async {
    if (adminId.isEmpty) return null;
    final d = await _db
        .collection(FsCollections.organizationProfiles)
        .doc(adminId)
        .get();
    if (!d.exists) return null;
    return OrganizationProfileModel.fromMap(d.data()!, d.id);
  }

  /// Realtime storefront source. TrainerHQ writes this same document, so logo,
  /// cover, authored content and aggregate rating update without a refresh.
  Stream<OrganizationProfileModel?> watchById(String adminId) {
    if (adminId.isEmpty) return Stream.value(null);
    return _db
        .collection(FsCollections.organizationProfiles)
        .doc(adminId)
        .snapshots()
        .map((d) => d.exists ? OrganizationProfileModel.fromSnapshot(d) : null);
  }

  /// A coach's active membership plans (cheapest first).
  Future<List<Map<String, dynamic>>> plans(String adminId) async {
    final q = await _db
        .collection(FsCollections.membershipPlans)
        .where('adminId', isEqualTo: adminId)
        .get();
    final list = q.docs
        .map((d) => {...d.data(), 'id': d.id})
        .where((m) => m['isActive'] != false)
        .toList();
    list.sort(
      (a, b) =>
          ((a['price'] as num?) ?? 0).compareTo((b['price'] as num?) ?? 0),
    );
    return list;
  }

  Stream<List<Map<String, dynamic>>> watchPlans(String adminId) => _db
      .collection(FsCollections.membershipPlans)
      .where('adminId', isEqualTo: adminId)
      .snapshots()
      .map((q) {
        final list = q.docs
            .map((d) => {...d.data(), 'id': d.id})
            .where((m) => m['isActive'] != false)
            .toList();
        list.sort(
          (a, b) =>
              ((a['price'] as num?) ?? 0).compareTo((b['price'] as num?) ?? 0),
        );
        return list;
      });

  /// Whether this member already holds an active membership with any coach
  /// (drives the join gate: no active membership → join flow).
  Future<bool> hasActiveMembership(String uid) async {
    final q = await _db
        .collection(FsCollections.clients)
        .where('authUid', isEqualTo: uid)
        .get();
    final now = DateTime.now();
    for (final d in q.docs) {
      final data = d.data();
      if (data['membershipActive'] != true) continue;
      final exp = data['membershipExpiry'];
      DateTime? e;
      if (exp is Timestamp) {
        e = exp.toDate();
      } else if (exp is String) {
        e = DateTime.tryParse(exp);
      }
      if (e != null && e.isAfter(now)) return true;
    }
    return false;
  }
}
