import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../constants/firestore_collections.dart';
import '../models/onboarding_question_model.dart';

/// Loads the coach's onboarding form and submits the member's answers.
///
/// Questions live in `onboarding_questions` (per-org, member-readable). Answers
/// are written to `onboarding_responses/{clientId}` (one per member). File
/// answers upload to Storage `onboarding_uploads/{uid}/…`. On submit it also
/// stamps a member-owned flag `clientProfiles/{uid}.coachOnboardingDoneFor` so
/// Home can tell onboarding is complete without reading a maybe-missing doc.
class OnboardingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// The coach's questions, ordered (sorted in Dart — no composite index).
  Future<List<OnboardingQuestion>> loadQuestions(String adminId) async {
    if (adminId.isEmpty) return const [];
    final q = await _db
        .collection(FsCollections.onboardingQuestions)
        .where('adminId', isEqualTo: adminId)
        .get();
    final list =
        q.docs.map((d) => OnboardingQuestion.fromMap(d.data(), d.id)).toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  /// Uploads a photo/document answer and returns its download URL. The content
  /// type is set explicitly (image_picker/file_picker temp files infer
  /// unreliably) so the Storage `okUpload()` rule accepts it.
  Future<String> uploadFile({
    required String uid,
    required File file,
    required String filename,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref('onboarding_uploads/$uid/${ts}_$filename');
    await ref.putFile(
      file,
      SettableMetadata(contentType: _contentType(filename)),
    );
    return ref.getDownloadURL();
  }

  String _contentType(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream'; // still application/* → passes okUpload
    }
  }

  /// Writes the response doc (id == clientId) then sets the member's
  /// onboarding-done flag.
  Future<void> submit({
    required String clientId,
    required String adminId,
    required String uid,
    required List<Map<String, dynamic>> answers,
  }) async {
    final now = FieldValue.serverTimestamp();
    await _db.collection(FsCollections.onboardingResponses).doc(clientId).set({
      'clientId': clientId,
      'adminId': adminId,
      'authUid': uid,
      'answers': answers,
      'submittedAt': now,
      'updatedAt': now,
    });
    await _db
        .collection(FsCollections.clientProfiles)
        .doc(uid)
        .set({'coachOnboardingDoneFor': adminId}, SetOptions(merge: true));
  }
}
