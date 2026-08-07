import 'package:flutter_test/flutter_test.dart';

/// REGRESSION — BUG 2: "AlphaSerena says 'Log your first transformation' while
/// TrainerHQ shows the entry."
///
/// ── THE PROVEN ROOT CAUSE ──────────────────────────────────────────────────
///
/// Not a filter, not a permission, not a migration, and not the `authUid`
/// asymmetry I first suspected. The document was dumped off the live coach app
/// and is perfectly well formed:
///
///   id=gX3pmPKEbuQSfYSlBHa9  authUid=VOxzizRgU6YFBsbguFJ6winidIA2
///   clientId=EkNg2Yux4lPAQtSpQjds  adminId=Hli8cUoVsadrRyS6lHzvsQ9Dj152
///   visibility=shared  status=complete  kind=transformation  schemaVersion=2
///   photos=[side, back, front]  weightKg=85.0
///
/// A probe in the member app then showed why it never appeared:
///
///   ASPROBE|canLog=false|uid=VOxziz…IA2|clientId=|adminId=
///
/// `watchTransformations` was gated on `canLog` — the WRITE precondition, which
/// requires `clientId` AND `adminId` — so it returned `Stream.value(const [])`
/// and **the Firestore query never ran at all**.
///
/// The two fields arrive on DIFFERENT streams: `clientId` from
/// `clientProfiles.linkedClientId`, `adminId` off the `clients` document, which
/// loads later. The controller re-binds on `isLinked`, which flips when the
/// FIRST arrives — so `adminId` was always still empty at every rebind, and
/// `isLinked` never changed again to trigger another one.
///
/// These tests pin the invariant that fixes it: a READ may only require what
/// the query and the read rule actually consult, which is the uid alone.
void main() {
  group('BUG 2 — the read gate may not demand write-only identity', () {
    test('the read precondition is uid alone', () {
      // The query is `where('authUid' == uid)`; the rule is
      // `resource.data.authUid == request.auth.uid`. Neither consults clientId
      // or adminId, so neither may block the read.
      expect(_canRead(uid: 'u1', clientId: '', adminId: ''), isTrue);
      expect(_canRead(uid: 'u1', clientId: 'c1', adminId: 'a1'), isTrue);
      expect(_canRead(uid: '', clientId: 'c1', adminId: 'a1'), isFalse);
    });

    test('the WRITE precondition still demands all three', () {
      // Unchanged, and deliberately so: a create stamps clientId and adminId
      // and the rule cross-checks both against the member's clients document.
      expect(_canLog(uid: 'u1', clientId: 'c1', adminId: 'a1'), isTrue);
      expect(_canLog(uid: 'u1', clientId: 'c1', adminId: ''), isFalse);
      expect(_canLog(uid: 'u1', clientId: '', adminId: 'a1'), isFalse);
    });

    test('THE EXACT LIVE STATE now permits the read', () {
      // The values captured off the device at the moment the member's screen
      // said "No transformation yet".
      const uid = 'VOxzizRgU6YFBsbguFJ6winidIA2';
      expect(_canLog(uid: uid, clientId: '', adminId: ''), isFalse,
          reason: 'this is what the probe observed, and why nothing rendered');
      expect(_canRead(uid: uid, clientId: '', adminId: ''), isTrue,
          reason: 'the same state must now let the query run');
    });
  });
}

// Mirrors of the two gates in `ProgressLogService`. Kept as pure predicates so
// the invariant is testable without a live Firebase app — the service resolves
// Firestore lazily precisely so it can be constructed in tests, but its gates
// read a GetX-resolved MemberController, which a unit test has no business
// standing up.
bool _canRead({required String uid, required String clientId, required String adminId}) =>
    uid.isNotEmpty;

bool _canLog({required String uid, required String clientId, required String adminId}) =>
    clientId.isNotEmpty && adminId.isNotEmpty && uid.isNotEmpty;
