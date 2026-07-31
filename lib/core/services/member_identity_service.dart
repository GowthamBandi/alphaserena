import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../constants/firestore_collections.dart';

/// UMHIPP P2 — writes the member's canonical identity sections to
/// `clientProfiles/{uid}.profile.<section>` (member-owned, member-private).
/// The P3 backend trigger (`onClientProfileWritten`) projects the
/// coach-visible sections onto `clients/{id}.sharedProfile`; nothing here
/// writes to any coach-owned document.
///
/// During the P2→P5 transition the legacy flat fields existing consumers read
/// (`clientName`, `height`, `weight`) are dual-written, per the spec's
/// dual-read/dual-write migration strategy — they are removed only in P5.
class MemberIdentityService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection(FsCollections.clientProfiles).doc(uid);

  /// Whether identity setup has already been completed (it runs ONCE, ever —
  /// it is org-independent, unlike the per-coach questionnaire).
  static bool isComplete(Map<String, dynamic>? profileDoc) {
    final profile = profileDoc?['profile'];
    if (profile is! Map) return false;
    final identity = profile['identity'];
    return identity is Map &&
        (identity['displayName'] ?? '').toString().trim().isNotEmpty;
  }

  /// Uploads the member's profile photo to the member-owned Storage path
  /// (`profile_photos/{uid}` — uid-scoped by rule) and returns its URL.
  Future<String> uploadPhoto(String uid, File file) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref('profile_photos/$uid/$ts.jpg');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  /// Saves the canonical identity/contact/bodyMetrics sections in one write.
  /// Merge-write: absent optional fields never clobber earlier values.
  Future<void> save(
    String uid, {
    required String displayName,
    String? photoUrl,
    String? gender,
    String? dob, // yyyy-MM-dd
    required String phone,
    String? email,
    double? heightCm,
    double? weightKg,
    // Display-unit preference ('cm'|'ftin', 'kg'|'lb') — lives under the
    // member-private `preferences` section (onlyMe; never projected to the
    // coach). Storage stays canonical metric regardless.
    String? heightUnit,
    String? weightUnit,
  }) async {
    final identity = <String, dynamic>{
      'displayName': displayName,
      if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
      if (gender != null && gender.isNotEmpty) 'gender': gender,
      if (dob != null && dob.isNotEmpty) 'dob': dob,
    };
    final contact = <String, dynamic>{
      if (phone.isNotEmpty) 'phone': phone,
      if (email != null && email.isNotEmpty) 'email': email,
    };
    final bodyMetrics = <String, dynamic>{
      'heightCm': ?heightCm,
      'weightKg': ?weightKg,
    };

    await _ref(uid).set({
      'uid': uid,
      'profile': {
        'identity': identity,
        if (contact.isNotEmpty) 'contact': contact,
        if (bodyMetrics.isNotEmpty) 'bodyMetrics': bodyMetrics,
        if (heightUnit != null || weightUnit != null)
          'preferences': {
            'units': {
              'height': ?heightUnit,
              'weight': ?weightUnit,
            },
          },
      },
      // Transitional dual-write (P5 removes): today's consumers read these.
      'clientName': displayName,
      if (email != null && email.isNotEmpty) 'email': email,
      'height': ?heightCm,
      'weight': ?weightKg,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
