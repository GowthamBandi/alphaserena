import 'package:alphaserena/core/services/account_role_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// THE CROSS-APP ROLE GATE.
///
/// AlphaSerena is the member app. A trainer, organization owner or platform
/// administrator signing in here used to be routed straight into the member
/// experience — either into `ClientDashboard` (which bootstraps twelve member
/// controllers and calls `claimClientAccount`, the session's first Firestore
/// write) or into `JoinCoachScreen`, the purchase funnel, where they could buy
/// a membership and become a client of the platform they staff.
///
/// This file pins the DECISION. The two halves it deliberately does not cover
/// are covered where they can be proven for real:
///   • the Firestore reads behind it —
///     `trainershq-backend/tests/rules/member_role_gate_reads.mjs` (emulator),
///     which also pins that a coach cannot own `clientProfiles/{uid}`;
///   • the routing and teardown — the Patrol suite.
void main() {
  AccountRole role({bool admin = false, bool trainer = false, bool sa = false}) =>
      AccountRoleService.roleFromExistence(
        hasAdminDoc: admin,
        hasTrainerDoc: trainer,
        hasPlatformAdminDoc: sa,
      );

  group('who gets in', () {
    test('no professional record at all → member', () {
      expect(role(), AccountRole.member);
      expect(role().isCoachAccount, isFalse);
    });

    test('an organization owner is NOT a member', () {
      expect(role(admin: true), AccountRole.admin);
      expect(role(admin: true).isCoachAccount, isTrue);
    });

    test('a staff trainer is NOT a member', () {
      expect(role(trainer: true), AccountRole.trainer);
      expect(role(trainer: true).isCoachAccount, isTrue);
    });

    test('platform staff are NOT a member', () {
      expect(role(sa: true), AccountRole.platformAdmin);
      expect(role(sa: true).isCoachAccount, isTrue);
    });
  });

  group('dual-role accounts resolve to the MOST privileged', () {
    // Real cases: an owner who also holds a trainer record for themselves, and
    // platform staff who also run an org. Whichever way they are combined, the
    // answer must still be "coach account" — the gate must never be talked out
    // of it by a second record.
    test('owner + trainer → owner, still blocked', () {
      final r = role(admin: true, trainer: true);
      expect(r, AccountRole.admin);
      expect(r.isCoachAccount, isTrue);
    });

    test('platform admin + owner → platform admin, still blocked', () {
      final r = role(admin: true, sa: true);
      expect(r, AccountRole.platformAdmin);
      expect(r.isCoachAccount, isTrue);
    });

    test('all three records → platform admin, still blocked', () {
      final r = role(admin: true, trainer: true, sa: true);
      expect(r, AccountRole.platformAdmin);
      expect(r.isCoachAccount, isTrue);
    });

    test('ANY professional record blocks, whichever it is', () {
      for (final r in [
        role(admin: true),
        role(trainer: true),
        role(sa: true),
        role(admin: true, trainer: true),
        role(trainer: true, sa: true),
        role(admin: true, sa: true),
        role(admin: true, trainer: true, sa: true),
      ]) {
        expect(r.isCoachAccount, isTrue, reason: '$r must not reach the member app');
      }
      expect(role().isCoachAccount, isFalse);
    });
  });

  group('the account status is irrelevant — only the RECORD matters', () {
    // A suspended, inactive or org-paused trainer still holds `trainers/{uid}`.
    // Resolution is by document EXISTENCE precisely so a coach cannot become a
    // member by having their coach account disabled: their record still exists,
    // so they are still not a member. Status is TrainerHQ's problem, and this
    // test states that on purpose — the gate reads no status field at all.
    test('existence alone decides; no status is consulted', () {
      expect(role(trainer: true).isCoachAccount, isTrue);
      expect(role(admin: true).isCoachAccount, isTrue);
    });
  });

  group('what the person is told', () {
    test('each role names the application that is actually theirs', () {
      expect(AccountRole.trainer.homeAppName, 'TrainerHQ');
      expect(AccountRole.admin.homeAppName, 'TrainerHQ');
      expect(
        AccountRole.platformAdmin.homeAppName,
        'the AlphaSerena Admin console',
      );
    });

    test('every role has non-empty, distinct copy', () {
      final labels = AccountRole.values.map((r) => r.label).toSet();
      expect(labels.length, AccountRole.values.length);
      for (final r in AccountRole.values) {
        expect(r.label.trim(), isNotEmpty);
        expect(r.homeAppName.trim(), isNotEmpty);
      }
    });
  });

  group('an unavailable lookup is NOT a member', () {
    test('AccountRoleUnavailable is a distinct type, not a role', () {
      // The gate fails CLOSED. If "could not check" were folded into `member`,
      // a coach would be admitted whenever the network was slow — which is the
      // whole bug. The caller must be forced to handle it separately, so it is
      // an exception rather than an AccountRole value.
      const e = AccountRoleUnavailable('offline');
      expect(e, isA<Exception>());
      expect(AccountRole.values, isNot(contains(anything.runtimeType)));
      expect(e.toString(), contains('offline'));
    });
  });
}
