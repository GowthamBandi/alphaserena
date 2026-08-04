import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alphaserena/core/models/member_food.dart';
import 'package:alphaserena/core/services/member_food_service.dart';

/// N17 — RECENTS MUST NOT OUTLIVE THE IDENTITY THAT EARNED THEM.
///
/// The recents list is the ONE member-scoped store in this app that lives on
/// disk rather than in a controller, so controller teardown — the mechanism
/// every other member-scoped cache relies on — cannot reach it. Its rows are
/// also the only place a private org food survives the authorization that
/// produced it: `searchMemberFoods` filters `foodDatabase` by the CALLER's
/// `clients.adminId`, and once a card is on disk nothing re-checks that. The
/// quantity sheet portions it, the log writes its frozen macros, and the
/// Firestore rules validate the member's own identity, not the food's
/// provenance — so a leaked shortcut is a fully loggable one.
///
/// Every test below fails on the pre-repair service.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = 'nutrition_recent_foods_v1';

  /// Iron Temple's private library.
  MemberFood orgFood(String name) => MemberFood(
        foodId: name.toLowerCase().replaceAll(' ', '_'),
        name: name,
        tier: MemberFoodTier.org,
        per100: const {'calories': 210, 'protein': 24},
      );

  MemberFood globalFood(String name) => MemberFood(
        foodId: name.toLowerCase().replaceAll(' ', '_'),
        name: name,
        per100: const {'calories': 130, 'protein': 3},
      );

  /// A service acting as one identity. `uid|adminId` is the whole identity a
  /// recents row depends on: the uid distinguishes two members sharing a
  /// device, the adminId distinguishes one member's two organizations.
  MemberFoodService asMember(String uid, String adminId) =>
      MemberFoodService(cacheOwner: () => '$uid|$adminId');

  /// A service whose member identity has not resolved yet (cold start, or a
  /// `clients` document still in flight).
  MemberFoodService asNobody() => MemberFoodService(cacheOwner: () => '');

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('same member, same organization — recents must still work', () {
    test('a remembered food comes back', () async {
      final s = asMember('member-a', 'iron-temple');
      await s.remember(orgFood('Iron Temple Secret Shake'));
      final r = await asMember('member-a', 'iron-temple').recents();
      expect(r.map((f) => f.name), ['Iron Temple Secret Shake']);
    });

    test('most-recent-first, deduped by foodId, bounded', () async {
      final s = asMember('member-a', 'iron-temple');
      await s.remember(globalFood('Rice'));
      await s.remember(globalFood('Paneer'));
      await s.remember(globalFood('Rice')); // re-logged, must not duplicate
      final r = await s.recents();
      expect(r.map((f) => f.name), ['Rice', 'Paneer']);

      for (var i = 0; i < MemberFoodService.maxRecents + 5; i++) {
        await s.remember(globalFood('Food $i'));
      }
      expect((await s.recents()).length, MemberFoodService.maxRecents);
    });

    test('survives a RESTART — a new service instance reads the same disk',
        () async {
      await asMember('member-a', 'iron-temple')
          .remember(orgFood('Iron Temple Secret Shake'));
      // Process death: nothing in memory, everything on disk.
      final afterColdStart = await asMember('member-a', 'iron-temple').recents();
      expect(afterColdStart.single.name, 'Iron Temple Secret Shake');
      expect(afterColdStart.single.tier, MemberFoodTier.org);
    });
  });

  group('THE N17 LEAK — a different identity must see nothing', () {
    test('DIFFERENT MEMBER, DIFFERENT ORG, SAME DEVICE (the reported bug)',
        () async {
      // Member A (Iron Temple) logs their coach's private food.
      await asMember('member-a', 'iron-temple')
          .remember(orgFood('Iron Temple Secret Shake'));

      // Member B (Steel Works) signs in on the same handset.
      final leaked = await asMember('member-b', 'steel-works').recents();

      expect(
        leaked,
        isEmpty,
        reason: 'Iron Temple\'s private food reached a Steel Works member, '
            'badged as their own coach\'s and fully loggable',
      );
    });

    test('the foreign list is DESTROYED, not merely hidden', () async {
      await asMember('member-a', 'iron-temple')
          .remember(orgFood('Iron Temple Secret Shake'));
      await asMember('member-b', 'steel-works').recents();

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key) ?? '';
      expect(
        raw.contains('Iron Temple Secret Shake'),
        isFalse,
        reason: 'a read by a foreign owner must purge the slot, or the '
            'previous member\'s library sits on this disk indefinitely',
      );
    });

    test('member B logging does not resurrect member A rows', () async {
      await asMember('member-a', 'iron-temple')
          .remember(orgFood('Iron Temple Secret Shake'));

      final b = asMember('member-b', 'steel-works');
      await b.remember(globalFood('Rice'));

      expect((await b.recents()).map((f) => f.name), ['Rice']);
    });

    test('DIFFERENT MEMBER, SAME ORG — still a cross-member leak', () async {
      // Two members of Iron Temple share a device. The food is legitimately
      // available to both, but a recents list is a record of what ONE person
      // ate, and presenting it to somebody else is still wrong.
      await asMember('member-a', 'iron-temple').remember(orgFood('Whey Scoop'));
      expect(await asMember('member-c', 'iron-temple').recents(), isEmpty);
    });

    test('SAME MEMBER, DIFFERENT ORG — the org-transfer leak', () async {
      // No sign-out happens here at all: the coach transfers the member, and
      // `clients.adminId` changes underneath a live session. The previous
      // gym\'s private foods must not follow them.
      await asMember('member-a', 'iron-temple')
          .remember(orgFood('Iron Temple Secret Shake'));
      expect(await asMember('member-a', 'steel-works').recents(), isEmpty);
    });

    test('leakage does not survive a RESTART either', () async {
      await asMember('member-a', 'iron-temple')
          .remember(orgFood('Iron Temple Secret Shake'));
      // Cold start as member B — a fresh service, nothing in memory.
      expect(await asMember('member-b', 'steel-works').recents(), isEmpty);
      // And warm again, to prove the purge held.
      expect(await asMember('member-b', 'steel-works').recents(), isEmpty);
    });

    test('a PRE-REPAIR list on disk is treated as foreign and purged',
        () async {
      // An unstamped list written by an older binary carries no owner, so it
      // cannot be proven to belong to whoever is signed in now. The only safe
      // reading of "unknown owner" is "not yours".
      SharedPreferences.setMockInitialValues({
        key: jsonEncode([orgFood('Iron Temple Secret Shake').toCache()]),
      });
      expect(await asMember('member-b', 'steel-works').recents(), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(key), isNull);
    });
  });

  group('sign-out', () {
    test('forgetRecents clears the slot', () async {
      final s = asMember('member-a', 'iron-temple');
      await s.remember(orgFood('Iron Temple Secret Shake'));
      await s.forgetRecents();
      expect(await s.recents(), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(key), isNull);
    });

    test('a SIGN-OUT WITHOUT forgetRecents is still safe', () async {
      // The eager clear on sign-out is one line in the teardown, and a crash,
      // a force-stop or an OS kill runs none of it. The owner stamp is what
      // makes the repair hold when the teardown never runs at all.
      await asMember('member-a', 'iron-temple')
          .remember(orgFood('Iron Temple Secret Shake'));
      // No forgetRecents() — the app died instead of signing out.
      expect(await asMember('member-b', 'steel-works').recents(), isEmpty);
    });
  });

  group('unresolved identity fails CLOSED', () {
    test('recents are not served before the member identity resolves',
        () async {
      await asMember('member-a', 'iron-temple').remember(orgFood('Whey Scoop'));
      expect(
        await asNobody().recents(),
        isEmpty,
        reason: 'serving a list nobody can be proven to own is how the leak '
            'reopens on a slow `clients` fetch',
      );
    });

    test('an unresolved identity does not DESTROY the owner\'s list',
        () async {
      // Failing closed must not become data loss: the rightful owner\'s
      // shortcuts have to be there once their identity arrives.
      await asMember('member-a', 'iron-temple').remember(orgFood('Whey Scoop'));
      await asNobody().recents();
      expect((await asMember('member-a', 'iron-temple').recents()).single.name,
          'Whey Scoop');
    });

    test('an unresolved identity never WRITES a list', () async {
      await asNobody().remember(orgFood('Whey Scoop'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(key), isNull);
    });
  });

  group('the cache carries no authority it did not have', () {
    test('an archived or deleted food is still only a cached card', () async {
      // N16\'s territory, pinned here so the two are never confused: recents
      // are a device-local convenience, not an authorization. This test states
      // the property the repair must not silently change — a remembered food
      // round-trips exactly as it was cached, macros and tier intact.
      final food = orgFood('Iron Temple Secret Shake');
      final s = asMember('member-a', 'iron-temple');
      await s.remember(food);
      final back = (await s.recents()).single;
      expect(back.foodId, food.foodId);
      expect(back.tier, MemberFoodTier.org);
      expect(back.per100['calories'], 210);
    });

    test('corrupt JSON reads as no recents, never as a crash', () async {
      SharedPreferences.setMockInitialValues({key: 'not json at all'});
      expect(await asMember('member-a', 'iron-temple').recents(), isEmpty);
    });
  });
}
