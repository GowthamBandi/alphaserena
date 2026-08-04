import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:patrol/patrol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alphaserena/controllers/connectivity_controller.dart';
import 'package:alphaserena/controllers/food_search_controller.dart';
import 'package:alphaserena/core/domain/food_portion_math.dart';
import 'package:alphaserena/core/models/member_food.dart';
import 'package:alphaserena/core/services/member_food_service.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/nutrition/add_food_screen.dart';

/// PATROL — N17: A SHARED DEVICE, ON A REAL DEVICE.
///
/// WHY THIS SUITE EXISTS, AND WHY THE EXISTING ONE COULD NOT HAVE CAUGHT N17.
///
/// `add_food_patrol_test.dart`'s `_FixtureFoodService` overrides `recents()`
/// to `const []` and `remember()` to a no-op. Twenty device tests drove the
/// Add Food screen and not one of them touched the recents cache — the whole
/// defect lived under a stub. That is not a Patrol limitation; it is what the
/// fixture chose not to model, and the same habit is what let the workout
/// consistency engine ship broken behind hand-made cards.
///
/// So this suite fixes ONLY the thing a device test genuinely cannot have —
/// a phone-OTP member session, which is externally blocked on this emulator —
/// and leaves everything the defect lives in REAL:
///
///   REAL `MemberFoodService.recents` / `remember` / `forgetRecents`
///   REAL `SharedPreferences`, on the device's own disk
///   REAL `FoodSearchController`, registered so `onInit` actually runs
///   REAL `AddFoodScreen`, rendering real rows with real tier badges
///
/// Only `search()` is stubbed, because it is the one call that needs a signed
/// in member to reach `searchMemberFoods`. The identity is supplied through
/// `cacheOwner` — the exact value a live session resolves to — so a member
/// switch and an organization transfer are performed here the same way the
/// app performs them: the identity changes, and the disk does not.
void main() {
  const prefsKey = 'nutrition_recent_foods_v1';

  // Two organizations that have nothing to do with each other.
  const ironTemple = 'memberA|org-iron-temple';
  const steelWorks = 'memberB|org-steel-works';
  const ironTempleOther = 'memberC|org-iron-temple'; // member C, same gym
  const transferred = 'memberA|org-steel-works'; // A, after an org transfer

  MemberFood food(
    String name, {
    MemberFoodTier tier = MemberFoodTier.global,
    double calories = 250,
  }) =>
      MemberFood(
        foodId: name.toLowerCase().replaceAll(' ', '_'),
        name: name,
        tier: tier,
        per100: {
          'calories': calories, 'protein': 24, 'carbs': 8,
          'fat': 9, 'fiber': 1, 'sugar': 0, 'saturatedFat': 4,
        },
        portions: const [FoodPortionOption(label: 'scoop', grams: 40)],
      );

  /// Iron Temple's PRIVATE library — the thing that must never travel.
  final secretShake = food('Iron Temple Secret Shake',
      tier: MemberFoodTier.org, calories: 210);

  Future<void> boot() async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    Get.reset();
    // A genuinely shared device starts with whatever the last member left.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
  }

  /// Opens Add Food as [owner], over the REAL recents cache on this device.
  Future<FoodSearchController> openAs(
    PatrolIntegrationTester $,
    String owner, {
    List<MemberFood> browse = const [],
  }) async {
    // DISCARD ANY PREVIOUS SCREEN FIRST. `AddFoodScreen` captures its search
    // controller in `initState`, so re-pumping a second one at the same tree
    // position REUSES the old State — and would silently render the previous
    // identity's controller. The app never hits this (a sign-out navigates
    // away and destroys the tree), but a test that mounts twice does, and it
    // would report the repair as data loss it is not causing.
    await $.pumpWidgetAndSettle(const SizedBox.shrink());

    final service = _RealCacheFoodService(owner: owner)..browse = browse;
    final conn = Get.put(ConnectivityController(), permanent: true);
    conn.isOnline.value = true;
    final controller = Get.put(
      FoodSearchController(service: service, connectivity: conn),
      tag: 'patrol_recents_$owner',
    );
    // `onInit` already fired the load; awaiting the SAME real path again is
    // what makes the assertion deterministic. Without it the SharedPreferences
    // platform-channel round trip can land after `pumpAndSettle` has returned,
    // and a genuinely-populated list reads as empty — a green leak test for
    // the wrong reason.
    await controller.refreshRecents();
    await $.pumpWidgetAndSettle(
      MaterialApp(
        theme: AppTheme.dark,
        home: AddFoodScreen(
          initialMealSlot: 'lunch',
          searchController: controller,
        ),
      ),
    );
    return controller;
  }

  /// What a SIGN-OUT does on this device — the teardown, minus navigation.
  /// `AuthController._teardownToLogin` calls exactly this.
  Future<void> signOut() async {
    await MemberFoodService().forgetRecents();
    Get.reset();
  }

  /// What a CRASH or force-stop does: nothing at all.
  Future<void> processDeath() async => Get.reset();

  /// Logs [f] as [owner] would — the real `remember`, the real disk.
  Future<void> logAs(String owner, MemberFood f) =>
      _RealCacheFoodService(owner: owner).remember(f);

  Future<String?> diskContents() async =>
      (await SharedPreferences.getInstance()).getString(prefsKey);

  setUp(boot);
  tearDown(() async {
    Get.reset();
    await (await SharedPreferences.getInstance()).remove(prefsKey);
  });

  // ── THE REPORTED BUG ──────────────────────────────────────────────────────

  patrolTest(
      'MEMBER SWITCH: member B never sees Iron Temple\'s private food',
      ($) async {
    // Member A, Iron Temple, logs their coach's private shake. Real write.
    await logAs(ironTemple, secretShake);
    expect(await diskContents(), isNotNull,
        reason: 'the recents cache must genuinely be on this disk, or the '
            'test is proving nothing');

    await signOut();

    // Member B, Steel Works, signs in on the SAME handset and opens Add Food.
    await openAs($, steelWorks, browse: [food('Steel Works Mass Gainer',
        tier: MemberFoodTier.org, calories: 380)]);

    expect($('Iron Temple Secret Shake').exists, false,
        reason: 'a competitor gym\'s private food reached a Steel Works '
            'member\'s shortcut list');
    // The header renders `text.toUpperCase()`, so 'RECENT' is the string that
    // is actually on screen. Asserting 'Recent' here would have passed even
    // WITH the leak on screen — a green test proving nothing.
    expect($('RECENT').exists, false,
        reason: 'there is no Recent section to show — member B has logged '
            'nothing on this device');
    // Their OWN gym's food is unaffected: the repair isolates, it does not
    // break the feature.
    expect($('Steel Works Mass Gainer').exists, true);
  });

  patrolTest(
      'MEMBER SWITCH AFTER A CRASH: no sign-out ran, still no leak',
      ($) async {
    // The eager clear is one line in a teardown that a force-stop, an OS kill
    // or a crash never executes. The owner stamp is what has to hold here.
    await logAs(ironTemple, secretShake);
    await processDeath();

    await openAs($, steelWorks);
    expect($('Iron Temple Secret Shake').exists, false);
  });

  patrolTest('ORG SWITCH: a transferred member loses the old gym\'s foods',
      ($) async {
    // No sign-out happens in this scenario AT ALL. The coach transfers the
    // member and `clients.adminId` changes underneath a live session.
    await logAs(ironTemple, secretShake);
    await openAs($, transferred);
    expect($('Iron Temple Secret Shake').exists, false,
        reason: 'the previous gym\'s library followed the member to the new '
            'one, mislabelled as the NEW coach\'s');
  });

  patrolTest('SAME ORG, DIFFERENT MEMBER: still not your list', ($) async {
    // The food is legitimately available to member C. A recents list is still
    // a record of what ONE person ate.
    await logAs(ironTemple, secretShake);
    await openAs($, ironTempleOther);
    expect($('Iron Temple Secret Shake').exists, false);
  });

  // ── THE FEATURE STILL WORKS ───────────────────────────────────────────────

  patrolTest('SAME MEMBER: recents survive and render with their tier badge',
      ($) async {
    await logAs(ironTemple, secretShake);
    await logAs(ironTemple, food('Basmati Rice', calories: 130));

    await openAs($, ironTemple);

    expect($('RECENT').exists, true);
    expect($('Iron Temple Secret Shake').exists, true);
    expect($('Basmati Rice').exists, true);
    // Provenance survives the cache round trip — an org food still reads as
    // the coach's, which is the whole reason the tier is stored.
    expect($("Your coach's").exists, true);
  });

  patrolTest('SAME MEMBER, COLD START: recents survive process death',
      ($) async {
    await logAs(ironTemple, secretShake);
    await processDeath(); // nothing in memory; everything on disk
    await openAs($, ironTemple);
    expect($('Iron Temple Secret Shake').exists, true);
  });

  patrolTest('SIGN OUT then SIGN BACK IN as the same member', ($) async {
    // Signing out DELETES the list, deliberately: a member who signs out on a
    // shared handset should not leave their coach's library on it. Their food
    // LOG is server-owned and untouched — recents are a convenience.
    await logAs(ironTemple, secretShake);
    await signOut();
    await openAs($, ironTemple);
    expect($('Iron Temple Secret Shake').exists, false);
    expect(await diskContents(), isNull,
        reason: 'sign-out must destroy the slot, not just hide it');
  });

  patrolTest('a NEW member can build their own recents on the same device',
      ($) async {
    await logAs(ironTemple, secretShake);
    await logAs(steelWorks, food('Steel Works Mass Gainer',
        tier: MemberFoodTier.org, calories: 380));

    await openAs($, steelWorks);
    expect($('RECENT').exists, true);
    expect($('Steel Works Mass Gainer').exists, true);
    expect($('Iron Temple Secret Shake').exists, false,
        reason: 'member B\'s own list must not carry member A\'s rows '
            'forward when it replaces them');
  });

  // ── UPGRADE + FAILURE MODES ───────────────────────────────────────────────

  patrolTest('an UNSTAMPED list left by an older binary is purged on sight',
      ($) async {
    // Devices upgrading into the repair already hold a leaked library. An
    // unowned list cannot be proven to belong to whoever signs in next, and
    // the only safe reading of "unknown owner" is "not yours".
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, jsonEncode([secretShake.toCache()]));

    await openAs($, steelWorks);

    expect($('Iron Temple Secret Shake').exists, false);
    expect(await diskContents(), isNull,
        reason: 'the pre-repair blob must be REMOVED from the disk, not left '
            'sitting there unread');
  });

  patrolTest('a corrupt cache renders the empty state, never a crash',
      ($) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, 'not json at all');
    await openAs($, ironTemple);
    expect($('Search foods').exists, true);
  });

  patrolTest('recents are not served before the identity resolves', ($) async {
    // A `clients` document still in flight resolves to no owner. Serving a
    // list nobody can be proven to own is how this reopens on a slow fetch;
    // and failing closed must not DESTROY the rightful owner's list either.
    await logAs(ironTemple, secretShake);

    await openAs($, ''); // identity unresolved
    expect($('Iron Temple Secret Shake').exists, false);

    Get.reset();
    await openAs($, ironTemple); // identity arrives
    expect($('Iron Temple Secret Shake').exists, true,
        reason: 'failing closed must not become data loss');
  });
}

/// REAL recents, stubbed search.
///
/// `search()` is the only method that needs a signed-in member (it calls
/// `searchMemberFoods`), so it is the only method overridden. `recents`,
/// `remember` and `forgetRecents` are inherited and run for real against this
/// device's own SharedPreferences — which is the entire point of the suite.
class _RealCacheFoodService extends MemberFoodService {
  _RealCacheFoodService({required String owner})
      : super(cacheOwner: (() => owner));

  List<MemberFood> browse = const [];

  @override
  Future<FoodSearchOutcome> search(String query, {int limit = 24}) async =>
      FoodSearchOutcome(foods: query.trim().isEmpty ? browse : const []);
}
