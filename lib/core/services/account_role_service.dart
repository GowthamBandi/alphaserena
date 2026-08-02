import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/firestore_collections.dart';

/// What kind of account a signed-in uid actually belongs to.
///
/// AlphaSerena is the MEMBER app. Every other kind is a professional account
/// that belongs in a different application, and must never be admitted here.
enum AccountRole {
  /// No coach record exists for this uid — a member (or a brand-new signup).
  member,

  /// `admins/{uid}` — an organization owner. Also coaches, but through TrainerHQ.
  admin,

  /// `trainers/{uid}` — staff coach. Belongs in TrainerHQ.
  trainer,

  /// `master_admins/{uid}` — platform staff. Belongs in the AlphaSerena Admin console.
  platformAdmin;

  bool get isCoachAccount => this != AccountRole.member;

  /// The app this account is supposed to use. Shown to the person, so it names
  /// the product, not the collection.
  String get homeAppName => switch (this) {
    AccountRole.admin || AccountRole.trainer => 'TrainerHQ',
    AccountRole.platformAdmin => 'the AlphaSerena Admin console',
    AccountRole.member => 'AlphaSerena',
  };

  /// How to describe the account to its owner.
  String get label => switch (this) {
    AccountRole.admin => 'an Organization Owner',
    AccountRole.trainer => 'a Trainer',
    AccountRole.platformAdmin => 'a Platform Administrator',
    AccountRole.member => 'a Member',
  };
}

/// Raised when the account type could not be established.
///
/// Deliberately distinct from "this uid is a member": a gate that cannot tell
/// those apart either locks out every member or admits every coach.
class AccountRoleUnavailable implements Exception {
  final Object cause;
  const AccountRoleUnavailable(this.cause);
  @override
  String toString() => 'AccountRoleUnavailable($cause)';
}

/// THE role-resolution path for the member app.
///
/// A professional account signing into AlphaSerena is a real, reported bug: the
/// app used to route purely on "do you hold an active membership?", so a coach
/// simply landed in the member join flow and could buy a membership — becoming
/// a client of the very platform they staff.
///
/// Resolution is by DOCUMENT EXISTENCE, mirroring TrainerHQ's `SessionController`
/// exactly, so the two apps can never disagree about who someone is. It reads
/// only the caller's OWN three documents; `tests/rules/member_role_gate_reads.mjs`
/// (in the backend repo) pins on a real emulator that a coach can read their own
/// doc AND that a member reading their own ABSENT docs is ALLOWED rather than
/// permission-denied — which is what lets this distinguish "not a coach" from
/// "could not check".
///
/// It writes NOTHING and bootstraps NOTHING. It must stay that way: it runs
/// before the app knows whether this person is even allowed in.
class AccountRoleService {
  AccountRoleService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// The DECISION, separated from the I/O so it can be tested exhaustively
  /// without a Firestore.
  ///
  /// Precedence matters only for an account that holds several records (a real
  /// case: an owner who also has a trainer record, or platform staff who also
  /// own an org). The MOST privileged wins, so the message a person is shown
  /// never under-states their account — and, more importantly, "is this a coach
  /// account?" is true if ANY professional record exists.
  static AccountRole roleFromExistence({
    required bool hasAdminDoc,
    required bool hasTrainerDoc,
    required bool hasPlatformAdminDoc,
  }) {
    if (hasPlatformAdminDoc) return AccountRole.platformAdmin;
    if (hasAdminDoc) return AccountRole.admin;
    if (hasTrainerDoc) return AccountRole.trainer;
    return AccountRole.member;
  }

  /// Resolves [uid]'s account kind.
  ///
  /// Throws [AccountRoleUnavailable] if the lookup could not complete — the
  /// caller MUST treat that as "unknown", never as "member". Reads run
  /// concurrently because they are independent and this sits on the login path.
  Future<AccountRole> resolve(String uid) async {
    try {
      final snaps = await Future.wait([
        _db.collection(FsCollections.admins).doc(uid).get(),
        _db.collection(FsCollections.trainers).doc(uid).get(),
        _db.collection(FsCollections.masterAdmins).doc(uid).get(),
      ]);
      return roleFromExistence(
        hasAdminDoc: snaps[0].exists,
        hasTrainerDoc: snaps[1].exists,
        hasPlatformAdminDoc: snaps[2].exists,
      );
    } catch (e) {
      // Includes permission-denied and offline. NEVER degrade to `member`.
      throw AccountRoleUnavailable(e);
    }
  }
}
