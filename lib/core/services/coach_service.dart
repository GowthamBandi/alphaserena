import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/firestore_collections.dart';

/// A coach's public storefront summary (read from `organizationProfiles`).
class CoachSummary {
  final String adminId;
  final String name;
  final String? logoUrl;
  final String? about;
  final String? handle;

  const CoachSummary({
    required this.adminId,
    required this.name,
    this.logoUrl,
    this.about,
    this.handle,
  });

  bool get hasLogo => logoUrl != null && logoUrl!.isNotEmpty;

  factory CoachSummary.fromMap(Map<String, dynamic> m, String id) =>
      CoachSummary(
        adminId: id,
        name: (m['name'] ?? '').toString(),
        logoUrl: m['logoUrl'] as String?,
        about: m['about'] as String?,
        handle: m['handle'] as String?,
      );
}

/// Discovery + lookup of coaches and their membership plans (member-side).
class CoachService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Published coaches the member can browse.
  Future<List<CoachSummary>> discover() async {
    final q = await _db
        .collection(FsCollections.organizationProfiles)
        .where('published', isEqualTo: true)
        .limit(50)
        .get();
    final list =
        q.docs.map((d) => CoachSummary.fromMap(d.data(), d.id)).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Look a coach up by their join code / handle.
  Future<CoachSummary?> byHandle(String handle) async {
    final h = handle.trim().toLowerCase().replaceAll('@', '');
    if (h.isEmpty) return null;
    final q = await _db
        .collection(FsCollections.organizationProfiles)
        .where('handle', isEqualTo: h)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    return CoachSummary.fromMap(q.docs.first.data(), q.docs.first.id);
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
    list.sort((a, b) =>
        ((a['price'] as num?) ?? 0).compareTo((b['price'] as num?) ?? 0));
    return list;
  }

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
