import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import '../core/constants/firestore_collections.dart';

/// The signed-in member's live data: their own `clientProfiles` doc + the linked
/// gym `clients` doc. On start it calls `claimClientAccount` to link the member's
/// verified phone to the gym-created record (idempotent).
class MemberController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  final Rxn<Map<String, dynamic>> profile = Rxn<Map<String, dynamic>>();
  final Rxn<Map<String, dynamic>> client = Rxn<Map<String, dynamic>>();

  final RxBool isLoading = true.obs;
  final RxBool isLinked = false.obs;
  final RxString notice = ''.obs; // 'no_membership' when the gym hasn't added them

  String? linkedClientId;
  StreamSubscription? _profileSub;
  StreamSubscription? _clientSub;

  String get uid => _auth.currentUser?.uid ?? '';

  // Convenience getters (profile cache first, then the live clients doc).
  String get name =>
      (profile.value?['clientName'] ?? client.value?['name'] ?? 'Alpha')
          .toString();
  String get goal =>
      (client.value?['goal'] ?? profile.value?['goal'] ?? '').toString();
  String get gymName => (profile.value?['gymName'] ?? '').toString();
  String get trainerName => (profile.value?['trainerName'] ?? '').toString();

  @override
  void onInit() {
    super.onInit();
    _start();
  }

  Future<void> _start() async {
    final u = _auth.currentUser;
    if (u == null) {
      isLoading.value = false;
      return;
    }
    _profileSub = _db
        .collection(FsCollections.clientProfiles)
        .doc(u.uid)
        .snapshots()
        .listen((snap) {
      profile.value = snap.data();
      final cid = snap.data()?['linkedClientId']?.toString();
      if (cid != null && cid.isNotEmpty) {
        isLinked.value = true;
        _listenClient(cid);
      }
      isLoading.value = false;
    }, onError: (_) => isLoading.value = false);

    await claim();
  }

  void _listenClient(String clientId) {
    if (linkedClientId == clientId) return;
    linkedClientId = clientId;
    _clientSub?.cancel();
    _clientSub = _db
        .collection(FsCollections.clients)
        .doc(clientId)
        .snapshots()
        .listen((snap) => client.value = snap.data(), onError: (_) {});
  }

  /// Links the member's phone to their gym `clients` doc. Safe to re-call.
  Future<void> claim() async {
    try {
      final res = await _functions.httpsCallable('claimClientAccount').call();
      final data = Map<String, dynamic>.from(res.data as Map);
      final cid = (data['clientId'] ?? '').toString();
      if (cid.isNotEmpty) {
        isLinked.value = true;
        notice.value = '';
        _listenClient(cid);
      }
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') notice.value = 'no_membership';
    } catch (_) {
      // network/other — leave any existing linked state intact.
    } finally {
      isLoading.value = false;
    }
  }

  @override
  void onClose() {
    _profileSub?.cancel();
    _clientSub?.cancel();
    super.onClose();
  }
}
