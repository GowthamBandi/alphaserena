import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import '../core/constants/firestore_collections.dart';
import '../core/services/member_push_service.dart';

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
  String? _lastTrainerId;
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

  /// The owning org id + this member's client doc id — needed to write an
  /// org review (which is gated to active members in the security rules).
  String get adminId => (client.value?['adminId'] ?? '').toString();
  String get clientId => linkedClientId ?? '';

  /// The trainer assigned to this member (from the linked clients doc), if any.
  String get trainerId => (client.value?['trainerId'] ?? '').toString();

  // NOTE: membership "active" state lives in MembershipController.isActive (the
  // single source of truth — honours membershipFrozen + membershipExpiry).
  // A prior `hasActiveMembership` getter here checked only `membershipActive`
  // and diverged (a frozen member read as active); removed to avoid two answers.

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
        _initPush();
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
        .listen((snap) {
      final data = snap.data();
      final newTrainerId = (data?['trainerId'] ?? '').toString();
      // The coach reassigned the member's trainer mid-session → the cached
      // gymName/trainerName in clientProfiles is now stale. Re-claim (the CF is
      // the single source that re-derives them) so the trainer card updates live.
      // Only on an actual change (not initial load) → no re-claim loop.
      final trainerChanged =
          _lastTrainerId != null && _lastTrainerId != newTrainerId;
      _lastTrainerId = newTrainerId;
      client.value = data;
      if (trainerChanged) claim();
    }, onError: (_) {});
  }

  bool _pushInited = false;

  /// Registers this device for push once the member is linked (permission is
  /// asked in a signed-in, linked context — never on the login screen).
  /// Fire-and-forget: push failing must never affect the member session.
  void _initPush() {
    if (_pushInited) return;
    _pushInited = true;
    final push = Get.isRegistered<MemberPushService>()
        ? Get.find<MemberPushService>()
        : Get.put(MemberPushService(), permanent: true);
    push.init();
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
