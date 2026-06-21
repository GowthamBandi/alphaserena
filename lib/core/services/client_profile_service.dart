import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/firestore_collections.dart';

/// The member's OWN app profile (`clientProfiles/{uid}`, keyed by auth uid).
/// Holds onboarding answers + (later) the linked gym `clients` doc id.
/// Member reads/writes only their own doc (security rule: uid == auth.uid).
class ClientProfileService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection(FsCollections.clientProfiles).doc(uid);

  Future<Map<String, dynamic>?> get(String uid) async =>
      (await _ref(uid).get()).data();

  Future<bool> isOnboardingComplete(String uid) async {
    final d = await get(uid);
    return d != null && d['onboardingComplete'] == true;
  }

  Stream<Map<String, dynamic>?> watch(String uid) =>
      _ref(uid).snapshots().map((s) => s.data());

  Future<void> saveOnboarding(
    String uid, {
    required String phone,
    required Map<String, dynamic> data,
  }) async {
    await _ref(uid).set({
      'uid': uid,
      'phone': phone,
      ...data,
      'onboardingComplete': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
