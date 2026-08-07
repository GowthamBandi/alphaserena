import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import '../core/constants/firestore_collections.dart';
import '../core/domain/coach_identity.dart';
import '../core/domain/member_identity.dart';
import '../core/services/coach_service.dart';
import '../core/services/member_push_service.dart';
import 'training_controller.dart';

/// The signed-in member's live data: their own `clientProfiles` doc + the linked
/// gym `clients` doc. On start it calls `claimClientAccount` to link the member's
/// verified phone to the gym-created record (idempotent).
class MemberController extends GetxController {
  // LAZY, so this controller can be CONSTRUCTED without a live Firebase app.
  // Every collaborator that needs a member (the lifestyle controller, its
  // services) took one by value, and `FirebaseAuth.instance` in a field
  // initialiser meant none of them could be built in a unit test — which is
  // why the member's whole lifestyle write path had no coverage at all.
  // Nothing here resolves until it is actually used, so production behaviour
  // is unchanged.
  late final FirebaseAuth _auth = FirebaseAuth.instance;
  late final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final FirebaseFunctions _functions = FirebaseFunctions.instance;

  final Rxn<Map<String, dynamic>> profile = Rxn<Map<String, dynamic>>();
  final Rxn<Map<String, dynamic>> client = Rxn<Map<String, dynamic>>();

  final RxBool isLoading = true.obs;
  final RxBool isLinked = false.obs;
  final RxString notice =
      ''.obs; // 'no_membership' when the gym hasn't added them

  /// The member's linked `clients` doc id — REACTIVE.
  ///
  /// It was a plain field, and that is load-bearing: `canLog` — the guard
  /// every lifestyle surface branches on inside an `Obx` — reads `clientId`
  /// FIRST, and `&&` short-circuits. For an unlinked member the closure
  /// therefore observed no `Rx` at all, GetX threw "improper use of a GetX"
  /// by design, and the member got a framework error where the join prompt
  /// should have been. Nothing rebuilt when their linkage landed either,
  /// because nothing was subscribed to the thing that changed.
  ///
  /// Exposed as a plain `String?` getter so every existing reader
  /// (`call_service`, `client_chat_screen`) is untouched; only the storage
  /// became observable.
  final RxnString _linkedClientId = RxnString();
  String? get linkedClientId => _linkedClientId.value;

  /// The linked client id as a REACTIVE value.
  ///
  /// Exposed because `isLinked` and this id are set at different moments, and a
  /// consumer whose QUERY depends on the id must observe the id — watching the
  /// boolean instead leaves a stream bound before the id arrived, emitting an
  /// empty result that reads exactly like "you have nothing".
  RxnString get linkedClientIdRx => _linkedClientId;

  String? _lastTrainerId;
  StreamSubscription? _profileSub;
  StreamSubscription? _clientSub;

  String get uid => _auth.currentUser?.uid ?? '';

  /// A canonical UMHIPP section off `clientProfiles/{uid}.profile.<key>`, or an
  /// empty map. Members written before P2 simply have none of them, which every
  /// resolver below treats as "unknown" rather than as a default.
  Map<String, dynamic> section(String key) {
    final p = profile.value?['profile'];
    if (p is Map) {
      final s = p[key];
      if (s is Map) return Map<String, dynamic>.from(s);
    }
    return const <String, dynamic>{};
  }

  String _identity(String key) => (section('identity')[key] ?? '').toString();

  /// The member's display name, or `''` when none can be honestly claimed.
  ///
  /// Resolved through `resolveMemberName` — the SINGLE identity rule shared with
  /// every other screen. It no longer ends in the literal `'Alpha'`, which used
  /// to flow from here into `org_reviews.memberName`, `client_feedback.clientName`,
  /// chat `senderName` and the call `callerName`, recording members in their
  /// coach's inbox under a name the app invented for them.
  ///
  /// `identity.name` is accepted alongside `identity.displayName` because
  /// TrainerHQ's `ClientProfileAdapter` writes the canonical identity section
  /// with the key `name`; reading both keeps the two apps interoperable without
  /// either having to change the shared schema unilaterally.
  String get name => resolveMemberName(
    canonicalDisplayName: _identity('displayName').isNotEmpty
        ? _identity('displayName')
        : _identity('name'),
    legacyClientName: (profile.value?['clientName'] ?? '').toString(),
    coachRecordName: (client.value?['name'] ?? '').toString(),
  );

  /// The member's OWN profile photo, or `''` → callers render [initials].
  /// Uploaded in Identity Setup and, until now, never shown back to the member
  /// anywhere in the app.
  String get photoUrl =>
      resolveMemberPhoto(canonicalPhotoUrl: _identity('photoUrl'));

  /// Initials for the member's own avatar when no photo exists.
  String get initials => initialsOf(name);

  /// Age in whole years, or `null` when neither source can supply one.
  /// Prefers the member-authored `identity.dob` over the coach-typed
  /// `clients.age`, which is frozen at the moment it was entered.
  int? get age => resolveMemberAge(
    dob: _identity('dob'),
    coachRecordAge: client.value?['age'],
  );

  String get gender => _identity('gender');
  String get dob => _identity('dob');

  /// The member's contact phone — the number they authored, else the credential
  /// they signed in with.
  ///
  /// The order used to be reversed, and that made the phone field UNEDITABLE:
  /// Edit Profile wrote `contact.phone`, this getter kept returning
  /// `FirebaseAuth.phoneNumber`, and reopening the editor showed the auth number
  /// again — so every edit looked as though it had been silently discarded. It
  /// had not; it was being shadowed. `contact.phone` is a MEMBER-OWNED field of
  /// a member-owned document and is what the coach projection carries, so the
  /// member's own value is the answer whenever they have given one. The auth
  /// credential remains the fallback (and the seed the editor prefills with) —
  /// it is real, verified data, just not something the member chose.
  String get phone {
    final canonical = (section('contact')['phone'] ?? '').toString().trim();
    if (canonical.isNotEmpty) return canonical;
    return (_auth.currentUser?.phoneNumber ?? '').trim();
  }

  /// Email from the canonical contact section, the legacy dual-write, or the
  /// Google credential. The last of those is why a Google-signed-in member used
  /// to see a literal `'No Email'` beside their own verified address.
  String get email {
    final canonical = (section('contact')['email'] ?? '').toString().trim();
    if (canonical.isNotEmpty) return canonical;
    final legacy = (profile.value?['email'] ?? '').toString().trim();
    if (legacy.isNotEmpty) return legacy;
    return (_auth.currentUser?.email ?? '').trim();
  }

  /// Height in cm — canonical section, else the transitional dual-write.
  double? get heightCm {
    final canonical = section('bodyMetrics')['heightCm'];
    if (canonical is num) return canonical.toDouble();
    final legacy = profile.value?['height'];
    return legacy is num ? legacy.toDouble() : null;
  }

  /// The member's weight in kg — their canonical `bodyMetrics.weightKg`, else
  /// the historical `weightLog`, else the legacy dual-write.
  ///
  /// `weightLog` used to rank FIRST, and that made the weight field
  /// permanently uneditable for anyone who had ever logged one. The array has
  /// no writer left anywhere in the app — Transformation replaced it and
  /// records weight in `client_progress` — so it is frozen legacy data that
  /// simply shadowed `bodyMetrics.weightKg` forever: the member typed a new
  /// weight, the editor wrote it, the projection carried it to their coach, and
  /// the member's own screen went on showing a number from a system that no
  /// longer exists. A dead source of truth outranking a live one is the
  /// definition of a stale cache.
  ///
  /// It is kept as a FALLBACK because for a long-standing member with no
  /// canonical value it is the only weight the app holds.
  double? get weightKg {
    final canonical = section('bodyMetrics')['weightKg'];
    if (canonical is num) return canonical.toDouble();
    final log = profile.value?['weightLog'];
    if (log is List && log.isNotEmpty) {
      final last = log.last;
      if (last is Map && last['weight'] is num) {
        return (last['weight'] as num).toDouble();
      }
    }
    final legacy = profile.value?['weight'];
    return legacy is num ? legacy.toDouble() : null;
  }

  /// The member's target weight in kg, or null — authored in Edit Profile and
  /// projected to the coach under `bodyMetrics`.
  double? get goalWeightKg {
    final v = section('bodyMetrics')['goalWeightKg'];
    return v is num ? v.toDouble() : null;
  }

  String get goal =>
      (client.value?['goal'] ?? profile.value?['goal'] ?? '').toString();

  /// The RAW `clientProfiles.gymName` mirror. Prefer [orgName], which outranks
  /// this with the live storefront value; a renamed organisation never updates
  /// this field.
  String get gymName => (profile.value?['gymName'] ?? '').toString();

  /// The assigned coach's display name, or '' when none can be honestly named.
  ///
  /// Assignment truth is the LIVE `clients.trainerId`; the name comes from the
  /// server-resolved `clientProfiles` mirror, which `claimClientAccount` writes
  /// (it is the only party that may read `trainers`/`admins`). See
  /// `core/domain/coach_identity.dart` for the rule, including the
  /// admin-as-trainer case and stale-mirror rejection.
  String get trainerName => resolveCoachName(
    trainerId: trainerId,
    adminId: adminId,
    mirroredName: (profile.value?['trainerName'] ?? '').toString(),
    mirroredFor: (profile.value?['trainerNameFor'] ?? '').toString(),
    liveName: _liveCoach('name'),
  );

  /// The LIVE coach identity served by `getMyTraining`, which re-resolves it on
  /// every app open, Home reload and pull-to-refresh.
  ///
  /// This is the fix for the persistent "Your Coach". The `clientProfiles`
  /// mirror is written by exactly one party at exactly one moment — a
  /// successful `claimClientAccount` — so it could not reflect a coach who was
  /// assigned while the app was closed, and NOTHING re-derived it when a coach
  /// simply renamed themselves or changed their photo. The mirror is now the
  /// OFFLINE FALLBACK, not the source of truth.
  ///
  /// Read through `resolveCoachName`'s existing `liveName` slot, which already
  /// outranks the mirror by design — so the staleness rules that protect a
  /// removed or reassigned coach are unchanged.
  String _liveCoach(String key) {
    if (!Get.isRegistered<TrainingController>()) return '';
    final c = Get.find<TrainingController>().coach.value;
    final servedId = (c?['coachId'] ?? c?['id'] ?? '').toString();
    // A clients.trainerId reassignment arrives through the realtime document
    // before the callable refresh can finish. Never let the previous served
    // coach outrank that newer assignment during the gap.
    if (servedId.isNotEmpty && servedId != coachId) return '';
    return (c?[key] ?? '').toString().trim();
  }

  /// The coach's avatar, mirrored by `claimClientAccount` under the same
  /// staleness guard as the name. '' → the header renders initials, never a
  /// stranger's face.
  String get trainerPhotoUrl {
    final live = _liveCoach('photoUrl');
    return resolveCoachPhoto(
      name: trainerName,
      // Live first, mirror second — identical precedence to the name, so the
      // face and the name can never come from different generations of data.
      mirroredPhoto: live.isNotEmpty
          ? live
          : (profile.value?['trainerPhotoUrl'] ?? '').toString(),
    );
  }

  /// The owning org id + this member's client doc id — needed to write an
  /// org review (which is gated to active members in the security rules).
  String get adminId => (client.value?['adminId'] ?? '').toString();
  String get clientId => linkedClientId ?? '';

  /// The trainer assigned to this member (from the linked clients doc), if any.
  String get trainerId => (client.value?['trainerId'] ?? '').toString();

  /// The currently responsible coach: delegated trainer, else org owner. This
  /// is derived from the live clients document and therefore changes in the
  /// same frame as a TrainerHQ reassignment—never from a stale name mirror.
  String get coachId => trainerId.isNotEmpty ? trainerId : adminId;

  // ── Organisation identity ────────────────────────────────────────────
  //
  // Moved here from HomeController so Home and Profile resolve the member's
  // organisation through ONE cache and ONE rule. Profile previously read the
  // stale `clientProfiles.gymName` mirror directly and fell back to the literal
  // 'Alpha Arena' — a string that reads as a real gym — while Home resolved a
  // better chain that Profile could not reach.

  /// `organizationProfiles/{adminId}.logoUrl`, or null → callers render the
  /// neutral AlphaSerena mark, never a fabricated org identity.
  final Rxn<String> orgLogoUrl = Rxn<String>();

  /// The live storefront name. Kept separate from [gymName] so [orgName] can
  /// rank it ABOVE the mirror.
  final Rxn<String> orgLiveName = Rxn<String>();

  /// The platform-controlled `verified` flag. The badge renders only when true.
  final RxBool orgVerified = false.obs;

  /// True only while the storefront fetch is genuinely in flight, so callers can
  /// skeleton instead of flashing a placeholder at a member who has an org.
  final RxBool orgLoading = false.obs;

  String _orgFetchedFor = '';
  StreamSubscription? _orgSub;

  /// The organisation's display name, or `''` when none can be honestly claimed.
  /// Live storefront value first, stale mirror second — see [resolveOrgName].
  String get orgName =>
      resolveOrgName(liveName: orgLiveName.value ?? '', mirroredName: gymName);

  /// Whether a real organisation name is known from either source.
  bool get hasOrgName => orgName.isNotEmpty;

  /// Rebinds the live organization document (pull-to-refresh remains useful for
  /// retrying after an error, but normal TrainerHQ edits need no refresh).
  Future<void> refreshOrg() async {
    await _orgSub?.cancel();
    _orgSub = null;
    _orgFetchedFor = '';
    _maybeFetchOrg();
  }

  void _maybeFetchOrg() {
    final id = adminId;
    if (id.isEmpty || id == _orgFetchedFor) return;
    _orgFetchedFor = id;
    orgLoading.value = true;
    _orgSub?.cancel();
    _orgSub = CoachService()
        .watchById(id)
        .listen(
          (org) {
            orgLogoUrl.value = (org?.hasLogo ?? false) ? org!.logoUrl : null;
            final n = org?.name.trim() ?? '';
            orgLiveName.value = n.isEmpty ? null : n;
            orgVerified.value = org?.verified ?? false;
            orgLoading.value = false;
          },
          onError: (_) {
            orgLoading.value = false;
            _orgFetchedFor = '';
          },
        );
  }

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
    _linkedClientId.value = clientId;
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
          if (trainerChanged) {
            claim();
            if (Get.isRegistered<TrainingController>()) {
              Get.find<TrainingController>().load();
            }
          }
          // Org identity is resolved here rather than on Home so EVERY screen
          // (Profile included) sees the same organisation. Self-guarded on
          // adminId, so this is a no-op after the first successful fetch.
          _maybeFetchOrg();
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
    _orgSub?.cancel();
    super.onClose();
  }
}
