import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../constants/firestore_collections.dart';
import '../domain/member_profile_form.dart';

/// What actually happened to a profile write.
///
/// A Firestore write completes only on SERVER acknowledgement, so with no
/// usable connection it never completes at all — it is durably committed to the
/// local cache and replayed when the device reconnects. Awaiting it
/// unconditionally is what left the Save button spinning forever on a plane or
/// in a basement gym, with the member never told that their change was safe.
/// The member is told which of the two happened instead of waiting for an
/// acknowledgement that is not coming. Same contract, same 4 s budget, as
/// `CoachingEventWriter` and the Transformation writer.
enum ProfileSaveOutcome {
  /// The server has the change; the coach's projection is already being
  /// recomputed.
  acknowledged,

  /// Committed locally and queued. It will sync — and only then reach the
  /// coach — without any further action from the member.
  queued,
}

/// UMHIPP P2 — writes the member's canonical identity sections to
/// `clientProfiles/{uid}.profile.<section>` (member-owned, member-private).
/// The P3 backend trigger (`onClientProfileWritten`) projects the
/// coach-visible sections onto `clients/{id}.sharedProfile`; nothing here
/// writes to any coach-owned document.
///
/// TWO write paths, deliberately, because "this field is blank" means two
/// different things depending on who is writing:
///
///  • [save] — the onboarding wizard. ADDITIVE: it collects a subset of the
///    profile, so an absent value means "not asked" and must never clobber
///    something already stored.
///  • [saveForm] — the full editor. AUTHORITATIVE over the fields it shows: a
///    field the member emptied is DELETED. Without this the member could never
///    remove a phone number, an emergency contact, an address or their photo
///    once saved — every writer skipped empty values, so a deletion was
///    silently discarded and the stale value kept flowing to their coach.
///
/// During the P2→P5 transition the legacy flat fields existing consumers read
/// (`clientName`, `height`, `weight`) are dual-written, per the spec's
/// dual-read/dual-write migration strategy — they are removed only in P5.
class MemberIdentityService {
  MemberIdentityService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    this.ackTimeout = const Duration(seconds: 4),
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  /// How long to wait for a server acknowledgement before reporting the write
  /// as [ProfileSaveOutcome.queued].
  final Duration ackTimeout;

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

  /// The member-owned Storage folder for this member's avatar. Uid-scoped by
  /// rule (`profile_photos/{uid}` — read/write only by that uid).
  static String photoFolder(String uid) => 'profile_photos/$uid';

  /// Uploads the member's profile photo and returns its download URL.
  ///
  /// The filename is timestamped so a replacement is a new object rather than
  /// an overwrite — an overwrite keeps the same download URL, and every
  /// `CachedNetworkImage` in both apps (plus the coach's roster) would keep
  /// serving the OLD picture from cache until it expired. [deletePhotoAt]
  /// removes the superseded object once the new URL is stored.
  Future<String> uploadPhoto(String uid, File file) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref('${photoFolder(uid)}/$ts.jpg');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  /// Best-effort removal of a superseded avatar object.
  ///
  /// Scoped to the member's OWN folder before deleting anything: a stored
  /// `photoUrl` is not guaranteed to point at this member's uploads (a legacy
  /// record can carry a coach-set picture), and deleting whatever a URL happens
  /// to name would let a stale field destroy someone else's file. Failures are
  /// swallowed — an orphaned object is a storage-cost problem, never a reason
  /// to fail the member's save.
  Future<void> deletePhotoAt(String uid, String url) async {
    if (url.trim().isEmpty) return;
    try {
      final ref = _storage.refFromURL(url);
      if (!ref.fullPath.startsWith('${photoFolder(uid)}/')) return;
      await ref.delete();
    } catch (_) {
      // Already gone, not ours, or offline — nothing here is worth surfacing.
    }
  }

  /// Saves the FULL profile the editor shows: blank fields are deleted, present
  /// fields are written, and every value has already been validated by
  /// [MemberProfileForm.errors].
  ///
  /// One `set(..., merge: true)`, so sections this editor does not own —
  /// `medical`, `documents`, `goals`, the member's `privacy` overrides, and
  /// every coach-owned field on `clients/{id}` — are untouched.
  Future<ProfileSaveOutcome> saveForm(String uid, MemberProfileForm form) {
    final patch = materializePatch(buildProfilePatch(form));
    return _commit(uid, {
      ...patch,
      'uid': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Saves the canonical identity/contact/bodyMetrics sections in one write.
  /// Merge-write: absent optional fields never clobber earlier values.
  Future<ProfileSaveOutcome> save(
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
  }) {
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

    return _commit(uid, {
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
    });
  }

  Future<ProfileSaveOutcome> _commit(
    String uid,
    Map<String, dynamic> payload,
  ) async {
    final op = _ref(uid).set(payload, SetOptions(merge: true));
    try {
      await op.timeout(ackTimeout);
      return ProfileSaveOutcome.acknowledged;
    } on TimeoutException {
      // The write IS committed to the local cache and the SDK will replay it.
      // Adopt the orphaned Future so a late failure cannot surface as an
      // unhandled async error and take down the isolate.
      unawaited(op.catchError((Object _) {}));
      return ProfileSaveOutcome.queued;
    }
  }

  /// Replaces every [kClearField] marker the pure domain emitted with
  /// Firestore's delete sentinel.
  ///
  /// Keeping the sentinel out of the domain is what lets the whole payload be
  /// asserted in a plain unit test with no emulator and no plugin registrant;
  /// this is the one place the two vocabularies meet.
  static Map<String, dynamic> materializePatch(Map<String, dynamic> patch) =>
      _materialize(patch) as Map<String, dynamic>;

  static Object? _materialize(Object? node) {
    if (identical(node, kClearField)) return FieldValue.delete();
    if (node is Map) {
      return <String, dynamic>{
        for (final entry in node.entries)
          entry.key.toString(): _materialize(entry.value),
      };
    }
    return node;
  }
}
