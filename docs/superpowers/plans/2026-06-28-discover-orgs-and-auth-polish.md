# Production Splash, Login & Real Org Discovery — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hardcoded Discover list with live `organizationProfiles` data (rich cards, functional search + Location/Specialization filters, real states), and give splash + login a production polish pass with the AlphaSerena wordmark.

**Architecture:** Port the canonical `OrganizationProfileModel` from TrainersHQ as the single org model. `CoachService` returns it; a new `DiscoverController` (GetX) loads it once and exposes pure, testable search/filter logic. The Discover screen renders real cards with loading/empty/error states. The existing join/checkout flow stays on the legacy `DiscoverOrg` via a `DiscoverOrg.fromProfile()` adapter (full removal is the next chunk).

**Tech Stack:** Flutter, GetX, cloud_firestore, google_fonts, intl. Tests via `flutter test`.

> **Spec deviation (intentional):** The spec (§4.5/§5) called for deleting `DiscoverOrg` and retyping the storefront. After verifying the code, `DiscoverOrg` is a constructor type threaded through **8** downstream join/checkout screens (out of scope this chunk). To keep this chunk focused and the app compiling, we **keep** `DiscoverOrg`/`MembershipPlan`/`inr`/`kPlans`, **delete only the fake `kSampleOrgs`**, and bridge via `DiscoverOrg.fromProfile()`. Full removal + storefront rebuild happens when we rebuild the storefront/checkout next chunk.

## Global Constraints

- Mirror `FsCollections` names; never hardcode collection strings. (`FsCollections.organizationProfiles`, `.clientProfiles`)
- GetX DI: `Get.find<X>()`; member-scoped controllers non-permanent.
- `debugPrint()` only — no `print()`.
- Defensive `fromMap` (handle `null | String | num | List`).
- Every screen: loading + empty + error states.
- `.withValues(alpha: x)` — never deprecated `.withOpacity()`.
- Visible brand wordmark = **AlphaSerena** (no "Alphas Arena", no "Fitopia").
- `flutter analyze` → **No issues found** after every task.
- Gender filter is out of scope (no backend field) — do not add it.

---

### Task 1: Port `OrganizationProfileModel`

**Files:**
- Create: `lib/core/models/organization_profile_model.dart`
- Test: `test/organization_profile_model_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class OrganizationProfileModel` with fields `adminId, name, logoUrl?, about?, tagline?, city?, state?, specializations:List<String>, statClientsTrained?, statYearsExperience?, statCertifiedTrainers?, statTransformations?, coverImageUrl?, coverVideoUrl?, rating:double, reviewCount:int, verified:bool, published:bool, handle?, testimonialQuote?, testimonialAuthor?, transformations:List<Transformation>, whatWeOffer:List<String>, whyChooseUs:List<String>, operatingHours?, address?, phone?, email?, instagram?, website?, facebook?, youtube?, twitter?`; getters `hasLogo`, `hasCoverImage`, `hasRating`; factory `OrganizationProfileModel.fromMap(Map<String,dynamic> m, String id)`. Also `class Transformation` with `fromMap`.

- [ ] **Step 1: Write the failing test**

```dart
// test/organization_profile_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/models/organization_profile_model.dart';

void main() {
  test('fromMap parses rich fields defensively', () {
    final m = OrganizationProfileModel.fromMap({
      'name': 'Alpha Strength Co.',
      'tagline': 'Build Strength.',
      'city': 'Mumbai',
      'state': 'Maharashtra',
      'specializations': ['Strength Training', '', 'Fat Loss'],
      'statClientsTrained': '1.2K+',
      'rating': '4.9', // string → double
      'reviewCount': 320,
      'verified': true,
      'published': true,
      'logoUrl': '  ', // blank → null
    }, 'admin123');

    expect(m.adminId, 'admin123');
    expect(m.name, 'Alpha Strength Co.');
    expect(m.city, 'Mumbai');
    expect(m.specializations, ['Strength Training', 'Fat Loss']); // blanks dropped
    expect(m.statClientsTrained, '1.2K+');
    expect(m.rating, 4.9);
    expect(m.reviewCount, 320);
    expect(m.verified, isTrue);
    expect(m.hasRating, isTrue);
    expect(m.logoUrl, isNull); // blank string → null
    expect(m.hasLogo, isFalse);
  });

  test('fromMap tolerates a near-empty doc', () {
    final m = OrganizationProfileModel.fromMap({'name': 'X'}, 'id1');
    expect(m.name, 'X');
    expect(m.specializations, isEmpty);
    expect(m.rating, 0);
    expect(m.reviewCount, 0);
    expect(m.verified, isFalse);
    expect(m.hasRating, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/organization_profile_model_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../organization_profile_model.dart'`.

- [ ] **Step 3: Write the model**

Create `lib/core/models/organization_profile_model.dart` with the exact content ported from `D:\flutter works\trainersHQ\lib\core\models\organization_profile_model.dart` (the helpers `_strOrNull`, `_strList`, `_toDouble`, `_toInt`; the `Transformation` class; the full `OrganizationProfileModel` with `fromMap`/`fromSnapshot` and getters `hasLogo`, `hasCoverImage`, `hasCoverVideo`, `hasRating`). Field names must match that file verbatim.

> If reading the source file is not possible during execution, reproduce it from the field list in this task's **Interfaces** block plus: helpers parse defensively (`_strOrNull` trims and returns null for blank; `_strList` drops blanks; `_toDouble`/`_toInt` accept num|String); `hasRating => reviewCount > 0`; `hasLogo => logoUrl != null && logoUrl!.isNotEmpty`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/organization_profile_model_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Verify analyze + commit**

```bash
flutter analyze lib/core/models/organization_profile_model.dart
git add lib/core/models/organization_profile_model.dart test/organization_profile_model_test.dart
git commit -m "feat: port OrganizationProfileModel for member-side org discovery"
```
Expected analyze: No issues.

---

### Task 2: `CoachService` returns the rich model

**Files:**
- Modify: `lib/core/services/coach_service.dart`

**Interfaces:**
- Consumes: `OrganizationProfileModel` (Task 1).
- Produces: `CoachService.discover() → Future<List<OrganizationProfileModel>>`; `CoachService.byHandle(String) → Future<OrganizationProfileModel?>`; unchanged `plans(String) → Future<List<Map<String,dynamic>>>`, `hasActiveMembership(String) → Future<bool>`. The lean `CoachSummary` class is **removed**.

- [ ] **Step 1: Replace `CoachSummary` + rewrite `discover`/`byHandle`**

In `lib/core/services/coach_service.dart`:
1. Delete the `CoachSummary` class entirely.
2. Add import: `import '../models/organization_profile_model.dart';`
3. Replace `discover()`:

```dart
  /// Published organizations the member can browse (top-rated first).
  Future<List<OrganizationProfileModel>> discover() async {
    final q = await _db
        .collection(FsCollections.organizationProfiles)
        .where('published', isEqualTo: true)
        .limit(50)
        .get();
    final list = q.docs
        .map((d) => OrganizationProfileModel.fromMap(d.data(), d.id))
        .toList();
    list.sort((a, b) {
      final r = b.rating.compareTo(a.rating); // rating desc
      if (r != 0) return r;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }
```

4. Replace `byHandle()`:

```dart
  /// Look an organization up by its join code / handle.
  Future<OrganizationProfileModel?> byHandle(String handle) async {
    final h = handle.trim().toLowerCase().replaceAll('@', '');
    if (h.isEmpty) return null;
    final q = await _db
        .collection(FsCollections.organizationProfiles)
        .where('handle', isEqualTo: h)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    return OrganizationProfileModel.fromMap(q.docs.first.data(), q.docs.first.id);
  }
```

Leave `plans()` and `hasActiveMembership()` unchanged.

- [ ] **Step 2: Verify analyze**

Run: `flutter analyze lib/core/services/coach_service.dart`
Expected: No issues in this file. (Other files that imported `CoachSummary` are addressed in their own tasks; if analyze reports breakages elsewhere now, note them — they are `join_coach_screen.dart` only, fixed in Task 5.)

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/coach_service.dart
git commit -m "feat: CoachService.discover/byHandle return OrganizationProfileModel"
```

---

### Task 3: `DiscoverController` + pure filter logic (TDD)

**Files:**
- Create: `lib/controllers/discover_controller.dart`
- Test: `test/discover_filter_test.dart`

**Interfaces:**
- Consumes: `OrganizationProfileModel` (Task 1), `CoachService` (Task 2), `ClientProfileService` (existing).
- Produces, as **top-level pure functions** in `discover_controller.dart` (testable without Firebase):
  - `String orgLocation(OrganizationProfileModel o)` → `o.city ?? o.state ?? ''`.
  - `List<String> distinctLocations(List<OrganizationProfileModel> orgs)` → sorted distinct non-empty `orgLocation`.
  - `List<String> distinctSpecializations(List<OrganizationProfileModel> orgs)` → sorted distinct non-empty specializations.
  - `List<OrganizationProfileModel> filterOrgs(List<OrganizationProfileModel> orgs, {String query = '', String? location, String? specialization})`.
- Produces `class DiscoverController extends GetxController` with: `RxBool isLoading`, `RxString error`, `RxList<OrganizationProfileModel> all`, `RxString memberName`, `RxString query`, `Rxn<String> locationFilter`, `Rxn<String> specializationFilter`; getters `List<OrganizationProfileModel> get visible`, `List<String> get locations`, `List<String> get specializations`; methods `Future<void> load()`, `Future<void> refresh()`, `void clearFilters()`, `Future<OrganizationProfileModel?> lookupByHandle(String code)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/discover_filter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/models/organization_profile_model.dart';
import 'package:alphaserena/controllers/discover_controller.dart';

OrganizationProfileModel _org(String name,
        {String? city, String? state, List<String> specs = const []}) =>
    OrganizationProfileModel(
        adminId: name, name: name, city: city, state: state, specializations: specs);

void main() {
  final orgs = [
    _org('Alpha Strength', city: 'Mumbai', state: 'Maharashtra',
        specs: ['Strength Training', 'Fat Loss']),
    _org('FitNation', city: 'Bangalore', state: 'Karnataka',
        specs: ['HIIT', 'Fat Loss']),
    _org('Zenith Wellness', city: 'Pune', state: 'Maharashtra',
        specs: ['Yoga']),
  ];

  test('query matches name and specialization, case-insensitive', () {
    expect(filterOrgs(orgs, query: 'alpha').map((o) => o.name), ['Alpha Strength']);
    expect(filterOrgs(orgs, query: 'fat loss').map((o) => o.name),
        ['Alpha Strength', 'FitNation']);
  });

  test('location filter matches city', () {
    expect(filterOrgs(orgs, location: 'Mumbai').map((o) => o.name),
        ['Alpha Strength']);
  });

  test('specialization filter narrows the list', () {
    expect(filterOrgs(orgs, specialization: 'Yoga').map((o) => o.name),
        ['Zenith Wellness']);
  });

  test('filters and query combine with AND', () {
    expect(
        filterOrgs(orgs, query: 'fit', specialization: 'Fat Loss')
            .map((o) => o.name),
        ['FitNation']);
  });

  test('distinct helpers are sorted and de-duped', () {
    expect(distinctLocations(orgs), ['Bangalore', 'Mumbai', 'Pune']);
    expect(distinctSpecializations(orgs),
        ['Fat Loss', 'HIIT', 'Strength Training', 'Yoga']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/discover_filter_test.dart`
Expected: FAIL — `discover_controller.dart` / `filterOrgs` not found.

- [ ] **Step 3: Write the controller + pure functions**

Create `lib/controllers/discover_controller.dart`:

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import '../core/models/organization_profile_model.dart';
import '../core/services/client_profile_service.dart';
import '../core/services/coach_service.dart';

String orgLocation(OrganizationProfileModel o) => o.city ?? o.state ?? '';

List<String> distinctLocations(List<OrganizationProfileModel> orgs) {
  final set = <String>{};
  for (final o in orgs) {
    final loc = orgLocation(o);
    if (loc.isNotEmpty) set.add(loc);
  }
  final list = set.toList()..sort();
  return list;
}

List<String> distinctSpecializations(List<OrganizationProfileModel> orgs) {
  final set = <String>{};
  for (final o in orgs) {
    for (final s in o.specializations) {
      if (s.isNotEmpty) set.add(s);
    }
  }
  final list = set.toList()..sort();
  return list;
}

List<OrganizationProfileModel> filterOrgs(
  List<OrganizationProfileModel> orgs, {
  String query = '',
  String? location,
  String? specialization,
}) {
  final q = query.trim().toLowerCase();
  return orgs.where((o) {
    if (location != null && orgLocation(o) != location) return false;
    if (specialization != null && !o.specializations.contains(specialization)) {
      return false;
    }
    if (q.isEmpty) return true;
    final hay = [
      o.name,
      o.tagline ?? '',
      o.city ?? '',
      o.state ?? '',
      ...o.specializations,
    ].join(' ').toLowerCase();
    return hay.contains(q);
  }).toList();
}

/// Loads published organizations + holds the member's search / filter state.
class DiscoverController extends GetxController {
  final CoachService _coaches = CoachService();
  final ClientProfileService _profiles = ClientProfileService();

  final RxBool isLoading = true.obs;
  final RxString error = ''.obs;
  final RxList<OrganizationProfileModel> all = <OrganizationProfileModel>[].obs;
  final RxString memberName = 'Alpha'.obs;

  final RxString query = ''.obs;
  final Rxn<String> locationFilter = Rxn<String>();
  final Rxn<String> specializationFilter = Rxn<String>();

  List<OrganizationProfileModel> get visible => filterOrgs(
        all,
        query: query.value,
        location: locationFilter.value,
        specialization: specializationFilter.value,
      );

  List<String> get locations => distinctLocations(all);
  List<String> get specializations => distinctSpecializations(all);

  @override
  void onInit() {
    super.onInit();
    _loadName();
    load();
  }

  Future<void> _loadName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final p = await _profiles.get(uid);
      final n = (p?['clientName'] ?? '').toString().trim();
      if (n.isNotEmpty) memberName.value = n.split(' ').first;
    } catch (_) {
      // keep the 'Alpha' fallback
    }
  }

  Future<void> load() async {
    try {
      isLoading.value = true;
      error.value = '';
      all.assignAll(await _coaches.discover());
    } catch (_) {
      error.value = 'Could not load organizations. Tap retry.';
      all.clear();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> refresh() => load();

  void clearFilters() {
    query.value = '';
    locationFilter.value = null;
    specializationFilter.value = null;
  }

  Future<OrganizationProfileModel?> lookupByHandle(String code) =>
      _coaches.byHandle(code);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/discover_filter_test.dart`
Expected: PASS (all 5 tests).

- [ ] **Step 5: Verify analyze + commit**

```bash
flutter analyze lib/controllers/discover_controller.dart
git add lib/controllers/discover_controller.dart test/discover_filter_test.dart
git commit -m "feat: DiscoverController with tested search + location/specialization filters"
```
Expected analyze: No issues.

---

### Task 4: `DiscoverOrg.fromProfile` adapter

**Files:**
- Modify: `lib/screens/join/discover_models.dart`

**Interfaces:**
- Consumes: `OrganizationProfileModel` (Task 1).
- Produces: `factory DiscoverOrg.fromProfile(OrganizationProfileModel o)` so the existing storefront/checkout flow can receive a real org. (`kSampleOrgs` removal happens in Task 5, once `join_coach_screen` no longer references it.)

- [ ] **Step 1: Add the adapter factory**

In `lib/screens/join/discover_models.dart`, add an import and a factory on `DiscoverOrg` (keep all existing fields/classes for now):

```dart
import 'package:flutter/material.dart';
import '../../core/models/organization_profile_model.dart';
```

Add inside `class DiscoverOrg`, after the existing const constructor:

```dart
  /// Bridge a live org profile into the legacy presentation model used by the
  /// (still-mock) storefront + checkout flow. Network images via [thumb]/[hero].
  factory DiscoverOrg.fromProfile(OrganizationProfileModel o) => DiscoverOrg(
        id: o.adminId,
        name: o.name,
        tagline: o.tagline ?? '',
        city: o.city ?? '',
        state: o.state ?? '',
        clientsLabel: o.statClientsTrained ?? '',
        plusAvatars: 0,
        rating: o.rating,
        verified: o.verified,
        tags: o.specializations,
        thumb: o.coverImageUrl ?? o.logoUrl ?? '',
        hero: o.coverImageUrl ?? o.logoUrl ?? '',
        logoColor: const Color(0xFFE10600),
        logoIcon: Icons.fitness_center,
      );
```

> Note: `DiscoverOrg.thumb`/`hero` are now possibly network URLs or empty. The storefront/checkout screens are out of scope this chunk and may render an imperfect image — acceptable; they get rebuilt next chunk. Do **not** change them here.

- [ ] **Step 2: Verify analyze + commit**

```bash
flutter analyze lib/screens/join/discover_models.dart
git add lib/screens/join/discover_models.dart
git commit -m "feat: DiscoverOrg.fromProfile adapter bridging live org → legacy flow"
```
Expected: No issues.

---

### Task 5: Rewrite the Discover screen on real data

**Files:**
- Rewrite: `lib/screens/join/join_coach_screen.dart`
- Modify: `lib/screens/join/discover_models.dart` (remove `kSampleOrgs` only)

**Interfaces:**
- Consumes: `DiscoverController` (Task 3), `OrganizationProfileModel` (Task 1), `DiscoverOrg.fromProfile` (Task 4), `CoachStorefrontScreen` (existing).
- Produces: a `JoinCoachScreen` that registers `DiscoverController`, shows loading/empty/error/populated states, functional search + Location + Specialization filters, a `+` FAB code-entry sheet, and navigates to `CoachStorefrontScreen(org: DiscoverOrg.fromProfile(model))`.

- [ ] **Step 1: Rewrite `join_coach_screen.dart`**

Replace the file with a version that:
1. Registers the controller in `initState`: `final c = Get.put(DiscoverController());` (use `Get.isRegistered` guard if re-entered: `Get.put(DiscoverController())` is fine; GetX replaces).
2. Wraps the body in `Obx(() { ... })` switching on `c.isLoading` / `c.error` / `c.visible.isEmpty`:
   - **loading:** centered `CircularProgressIndicator(color: Color(0xFFE10600))`.
   - **error:** centered column — message `c.error.value` + a red "Retry" button → `c.load()`.
   - **empty (no orgs at all):** friendly empty state ("No organizations yet", subtitle "Check back soon or enter a coach's code.").
   - **empty (filters hide all):** "No matches" + a "Clear filters" button → `c.clearFilters()`.
   - **populated:** the existing card list, but built from `c.visible` with `_orgCard(OrganizationProfileModel)`.
3. **Header greeting** uses `c.memberName.value` (no more "John Doe"). Drop the fake notification badge number; the bell is a plain inert icon.
4. **Search bar** `onChanged: (v) => c.query.value = v`.
5. **Filters row:** keep "All" (→ `c.clearFilters()`), **Location ▾** and **Specialization ▾**. Remove the **Gender** chip. Each of Location/Specialization opens a bottom-sheet listing `c.locations` / `c.specializations` (single-select); selecting sets `c.locationFilter.value` / `c.specializationFilter.value`; the chip shows the active value + is highlighted red when set; tapping an active chip again (or choosing the same) clears it. If the source list is empty, show a "No options" sheet.
6. **`_orgCard(OrganizationProfileModel o)`** mirrors the current visual but reads real fields:
   - image: `o.coverImageUrl ?? o.logoUrl` via `Image.network` with `errorBuilder`/`loadingBuilder` → a neutral placeholder container; if both null, placeholder only.
   - **Verified** row only `if (o.verified)`.
   - name `o.name`; tagline only `if (o.tagline != null)`.
   - location row only `if (orgLocation(o).isNotEmpty)` showing `'${o.city ?? ''}${o.city != null && o.state != null ? ', ' : ''}${o.state ?? ''}'`.
   - clients label only `if (o.statClientsTrained != null)` → `'${o.statClientsTrained} Clients'`. Drop the fake avatar stack (no data).
   - rating pill only `if (o.hasRating)` → `'${o.rating.toStringAsFixed(1)} (${o.reviewCount})'`.
   - specialization chips from `o.specializations`.
   - red `>` button → `_open(o)`.
7. `_open(OrganizationProfileModel o)` → `Get.to(() => CoachStorefrontScreen(org: DiscoverOrg.fromProfile(o)))`.
8. **`+` FAB** → `_showCodeSheet()`: a bottom-sheet with a text field + "Find" button → `final org = await c.lookupByHandle(code);` then if non-null `Get.to(() => CoachStorefrontScreen(org: DiscoverOrg.fromProfile(org)))`, else `Get.snackbar('Not found', 'No organization found for that code.')`.
9. Keep the existing bottom nav + sign-out menu. Keep the verified-trust footer banner.
10. Imports: add `import 'package:get/get.dart';`, `import '../../controllers/discover_controller.dart';`, `import '../../core/models/organization_profile_model.dart';`. Remove the now-unused `kSampleOrgs` usage.

> Reuse the existing styling constants/widgets (`_bg/_card/_muted/_red`, `_circleIcon`, `_tagChip`, `_verifiedBanner`, `_bottomNav`) — only the data source + filter/state wiring changes. Keep `debugPrint` if any logging is needed; no `print`.

- [ ] **Step 2: Remove `kSampleOrgs` from `discover_models.dart`**

Delete the `const List<DiscoverOrg> kSampleOrgs = [ ... ];` block (lines defining the 4 fake orgs). Keep `DiscoverOrg`, `MembershipPlan`, `kPlans`, `inr`, and the new `fromProfile` factory.

- [ ] **Step 3: Verify analyze**

Run: `flutter analyze`
Expected: **No issues found** across the whole project (Task 2's `CoachSummary` removal is now fully resolved since `join_coach_screen` no longer imports it).

- [ ] **Step 4: Manual smoke (real data)**

Run: `flutter run` on an emulator/device signed in as an onboarded member without an active membership (so the Discover/Join surface shows). Confirm:
- Real published orgs appear (rating→name order); a missing image shows the placeholder, not a crash.
- Typing in search narrows the list; Location and Specialization sheets list real values and filter; "All"/"Clear filters" reset.
- Tapping `>` opens the storefront with that org's name; `+` code entry resolves a known handle.
- Empty state shows if no orgs / no matches.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/join/join_coach_screen.dart lib/screens/join/discover_models.dart
git commit -m "feat: Discover screen on live organizationProfiles with search + filters + states"
```

---

### Task 6: Brand wordmark → AlphaSerena

**Files:**
- Modify: `lib/core/widgets/brand.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class AlphaSerenaWordmark extends StatelessWidget` (renders "ALPHA" white + "SERENA" red, same Poppins w800 letter-spaced style, param `double fontSize = 26`). The old `AlphasArenaWordmark` is renamed to this.

- [ ] **Step 1: Rename + retext the wordmark**

In `lib/core/widgets/brand.dart`:
1. Update the doc comment ("AlphaSerena" / drop the "ALPHAS ARENA" description).
2. Rename `class AlphasArenaWordmark` → `class AlphaSerenaWordmark` (and its constructor).
3. Change the `RichText` spans to:

```dart
        children: [
          TextSpan(text: 'ALPHA', style: style.copyWith(color: Colors.white)),
          TextSpan(
            text: 'SERENA',
            style: style.copyWith(color: const Color(0xFFE10600)),
          ),
        ],
```

Leave `AlphaAMark` unchanged.

- [ ] **Step 2: Verify analyze**

Run: `flutter analyze lib/core/widgets/brand.dart`
Expected: No issues in this file (the two call sites in splash/login still say `AlphasArenaWordmark` and are updated in Tasks 7–8; analyze across the project will flag them until then — that is expected and resolved by Task 8).

- [ ] **Step 3: Commit**

```bash
git add lib/core/widgets/brand.dart
git commit -m "refactor: rename brand wordmark to AlphaSerenaWordmark (ALPHA + SERENA)"
```

---

### Task 7: Splash production polish

**Files:**
- Modify: `lib/screens/auth/splash_screen.dart`

**Interfaces:**
- Consumes: `AlphaSerenaWordmark` (Task 6).
- Produces: splash that uses the new wordmark + a crash-proof hero image.

- [ ] **Step 1: Use the new wordmark + add an asset fallback**

In `lib/screens/auth/splash_screen.dart`:
1. Replace `const AlphasArenaWordmark(fontSize: 26)` → `const AlphaSerenaWordmark(fontSize: 26)`.
2. Add an `errorBuilder` to the hero `Image.asset(...)` so a missing asset degrades to brand black rather than throwing:

```dart
          Image.asset(
            'assets/images/splash_hero.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, __, ___) =>
                const ColoredBox(color: Color(0xFF0E0E0E)),
          ),
```

Leave the routing logic in `_decide()` unchanged.

- [ ] **Step 2: Verify analyze + commit**

```bash
flutter analyze lib/screens/auth/splash_screen.dart
git add lib/screens/auth/splash_screen.dart
git commit -m "polish: splash uses AlphaSerena wordmark + crash-proof hero image"
```
Expected: No issues in this file.

---

### Task 8: Login production polish

**Files:**
- Modify: `lib/screens/auth/login_screen.dart`

**Interfaces:**
- Consumes: `AlphaSerenaWordmark` (Task 6) — optional; or update the inline "Alphas Arena" text.
- Produces: login with AlphaSerena branding and no dead UI.

- [ ] **Step 1: Rebrand + remove dead UI**

In `lib/screens/auth/login_screen.dart`:
1. Change the inline heading text `'Alphas Arena'` → `'AlphaSerena'`.
2. Remove the dead **Skip** `Align`/`TextButton` block (the one whose `onPressed` only shows a "Sign in required" snackbar).
3. Remove the decorative **"or continue with"** row (`_orContinueWith()` call + the `_supportButton()` + the "Need Help?" text block), since there is no real support channel defined. Delete the now-unused `_orContinueWith()` and `_supportButton()` methods to keep analyze clean.
4. Keep the phone input, the digits-only formatter, the 6–15 length guard, and `Send OTP`.

- [ ] **Step 2: Verify analyze + commit**

```bash
flutter analyze lib/screens/auth/login_screen.dart
git add lib/screens/auth/login_screen.dart
git commit -m "polish: login rebranded to AlphaSerena; remove dead Skip + decorative support UI"
```
Expected: No issues in this file (no unused-method warnings).

---

### Task 9: Brand sweep + full verification gate

**Files:**
- Modify: any remaining files containing `Alphas Arena` / `Fitopia` (expected: none beyond Tasks 7–8, but verify).

**Interfaces:**
- Consumes: all prior tasks.
- Produces: a clean, fully-analyzing project with no stale brand strings.

- [ ] **Step 1: Sweep for stale brand strings**

Run:
```bash
grep -rn "Alphas Arena\|AlphasArena\|Fitopia" lib/
```
Expected: **no matches.** If any remain, update visible copy to `AlphaSerena` and the widget reference to `AlphaSerenaWordmark`, then re-run until clean.

- [ ] **Step 2: Full analyze + test run**

```bash
flutter analyze
flutter test
```
Expected: `flutter analyze` → **No issues found.** `flutter test` → all tests pass (model + filter tests green; the default `widget_test.dart`, if it references removed symbols, must be fixed or its assertion updated to pump `MyApp` without error).

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "chore: brand sweep + verification — Discover/auth chunk complete"
```

---

## Self-Review

**Spec coverage:**
- §A data layer (port model, expand service, controller) → Tasks 1–3. ✓
- §B Discover screen real data + functional search/Location/Specialization filters + states → Task 5. ✓
- §C splash polish (wordmark + asset fallback) → Tasks 6–7. ✓
- §D login polish (wordmark, remove dead Skip/social, validation kept) → Tasks 6, 8. ✓
- §E brand sweep (AlphaSerena, no Fitopia/Alphas Arena) → Tasks 6–9. ✓
- §4.5 storefront compile-bridge → handled via the `DiscoverOrg.fromProfile` adapter (Task 4) instead of retyping (documented deviation). Storefront still compiles + receives real data. ✓
- §5 "delete kSampleOrgs/DiscoverOrg" → `kSampleOrgs` deleted (Task 5); `DiscoverOrg` kept as adapter (documented deviation; full delete next chunk). ✓
- Gender filter dropped → Task 5 step 1.5. ✓
- Edge cases (no orgs, missing fields, rating 0, handle miss, name fallback) → Tasks 3 + 5. ✓

**Placeholder scan:** No "TBD"/"handle edge cases" left abstract — each state, filter, and field-guard is spelled out. Model port has a fallback reproduction note in case the source file is unreadable. ✓

**Type consistency:** `OrganizationProfileModel`, `filterOrgs`, `distinctLocations`, `distinctSpecializations`, `orgLocation`, `DiscoverController` getters/methods, `DiscoverOrg.fromProfile`, `AlphaSerenaWordmark` — names used identically across tasks. ✓

**Known follow-ups (next chunk, not this plan):** full storefront §6.3 rebuild + retype the join/checkout flow off `DiscoverOrg`; favorites persistence; notifications source; per-country phone validation; Gender filter (needs backend field).
