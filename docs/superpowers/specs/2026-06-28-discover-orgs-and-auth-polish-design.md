# Design — Production Splash, Login & Real Organization Discovery

> Date: 2026-06-28 · App: **alphaserena** (member app) · Author: brainstorming session
> Backend contract source of truth: `docs/trainershq-integration-handoff-2026-06-28.md`
> (§6.2 Discover, §6.3 storefront, §8 brand). Coding rules: `CLAUDE.md` PART 11 / handoff §9.

## 1. Goal & boundary

Make the **first-run surface production-ready**: Splash → Phone Login → **Discover (a real
list of fitness organizations from the backend)**.

**In scope (this chunk):**
- Splash: production polish (no behavior rewrite).
- Login: production polish (no auth rewrite).
- Discover: replace the 100% hardcoded list with **live `organizationProfiles` data**, a rich
  card matching §6.2, **functional search + Location + Specialization filters**, and first-class
  loading / empty / error states.
- Brand: visible wordmark becomes **AlphaSerena** (not "Alphas Arena").

**Boundary — explicitly NOT in this chunk:**
- The coach **storefront detail** (§6.3) full rebuild, and the join/checkout/payment flow.
  They remain functional-enough to **compile**; the storefront is minimally adapted to the new
  model and gets its full §6.3 rebuild in the next chunk.
- Favorites persistence and a real notifications source (bell). Left visible but inert this pass.

## 2. Current state (verified in code 2026-06-28)

- `screens/join/join_coach_screen.dart` — the Discover screen, but renders **`kSampleOrgs`**
  (4 hardcoded orgs in `discover_models.dart`), a hardcoded **"John Doe"** greeting, a fake
  **"2"** notification badge, and **non-functional** filter chips (Gender/Location/Specialization).
  It never calls `CoachService.discover()`.
- `core/services/coach_service.dart` — has a real `discover()` that queries
  `organizationProfiles where published == true`, but returns a **lean `CoachSummary`**
  (only adminId/name/logoUrl/about/handle).
- `screens/join/discover_models.dart` — presentation mock: `DiscoverOrg`, `kSampleOrgs`,
  a hardcoded `kPlans`, plus the keeper helper `inr()` and a `MembershipPlan` model.
- `screens/join/coach_storefront_screen.dart` — takes a `DiscoverOrg` (depends on the mock).
- `screens/auth/splash_screen.dart` — real routing (authStateChanges + onboarding +
  `hasActiveMembership` gate), real hero `assets/images/splash_hero.png`, wordmark "Alphas Arena".
- `screens/auth/login_screen.dart` — **real phone-OTP** wired via `AuthController`. Has a dead
  **"Skip"** button (snackbar only), a decorative **"or continue with" + headset** support button,
  wordmark "Alphas Arena", basic length validation (6–15 digits).
- Authoritative backend model: `TrainersHQ/lib/core/models/organization_profile_model.dart`
  (`OrganizationProfileModel`) — the exact field set this app must mirror.

## 3. Decisions (from brainstorming)

| Decision | Choice |
|---|---|
| Real org data in backend | Published orgs exist → wire straight to live data. |
| Splash/login scope | Production polish pass (keep structure + behavior). |
| Discover filters | **Functional** search + Location + Specialization. |
| Gender filter | **Dropped** — no `gender` field on `organizationProfiles`; do not invent one. |
| Brand wordmark | **AlphaSerena** everywhere visible. |
| Discover load strategy | **One-shot `Future` + pull-to-refresh** (orgs near-static; cheaper than a stream). |
| Mock data | **Delete** `kSampleOrgs` / `DiscoverOrg`; salvage `inr()` + `MembershipPlan`. |
| Favorites / notifications | Inert/visible this pass (no backend). |

## 4. Architecture

### 4.1 Model — port `OrganizationProfileModel`
Create `lib/core/models/organization_profile_model.dart` mirroring the TrainersHQ model
**exactly** (field names + defensive `fromMap` handling `null | String | num | List`). Includes
the nested `Transformation`. Fields used by Discover: `adminId, name, logoUrl, tagline, city,
state, specializations[], statClientsTrained, coverImageUrl, rating, reviewCount, verified,
published, handle`. The remaining storefront fields (about, stat*, testimonial*, transformations[],
whatWeOffer[], whyChooseUs[], operatingHours, socials) are carried for the next chunk.

Helper getters reused: `hasLogo`, `hasCoverImage`, `hasRating` (`reviewCount > 0`).

This model **replaces** both the lean `CoachSummary` and the fake `DiscoverOrg`.

### 4.2 Service — `CoachService`
- `discover()` → returns `List<OrganizationProfileModel>` (query unchanged:
  `organizationProfiles where published == true`, limit 50). Sort: rating desc, then name asc,
  so the "Top Rated" section is meaningful (orgs with no rating fall to the bottom, name-ordered).
- `byHandle(code)` → returns `OrganizationProfileModel?` (used by the `+` FAB "enter code" sheet).
- `plans(adminId)` and `hasActiveMembership(uid)` — unchanged.

### 4.3 Controller — `DiscoverController` (GetX)
New `lib/controllers/discover_controller.dart`. Registered when Discover opens
(`Get.put`, non-permanent — torn down with the join surface).

State:
- `RxBool isLoading`, `RxString error`, `RxList<OrganizationProfileModel> all` (raw load).
- `RxString memberName` — read once from `clientProfiles/{uid}.clientName` (MemberController is
  not registered pre-join), fallback `'Alpha'`.
- `RxString query`; `Rxn<String> locationFilter`; `Rxn<String> specializationFilter`.
- Derived `List<OrganizationProfileModel> get visible` — applies query + filters over `all`.
- Derived `List<String> get locations` / `get specializations` — distinct values from `all`,
  for the filter sheets.

Methods: `load()` (try/catch → error message + empty list on failure), `refresh()`,
`lookupByHandle(code)` (→ open storefront or "not found" snackbar).

Filtering rules (client-side over the loaded list):
- **search**: case-insensitive contains over name / tagline / specializations / city / state.
- **Location**: exact match on `city` OR `state` (label shows "City, State"; distinct set built
  from non-empty values).
- **Specialization**: org's `specializations` contains the chosen value.
- Filters + search combine with AND.

### 4.4 Screen — `join_coach_screen.dart` (rewrite, keep visual language)
- Replace `kSampleOrgs` with `Obx` over `DiscoverController`.
- **States:** loading (centered spinner), error (message + Retry → `load()`), empty
  ("No organizations yet" friendly copy), populated (cards).
- **Greeting:** real `memberName`. Remove the fake "John Doe".
- **Cards (§6.2):** square `coverImageUrl`/`logoUrl` image (asset/network with graceful
  placeholder when absent), **Verified** badge only when `verified == true`, name, tagline,
  📍`city, state` (only if present), "{statClientsTrained} Clients" (only if present), specialization
  chips, red `>` → storefront. Avatar stack is decorative (no real avatar data) — keep subtle or
  drop if it looks empty without `statClientsTrained`.
- **Search bar:** wired to `query`.
- **Filters:** "All" (clears), **Location ▾** and **Specialization ▾** open a bottom-sheet of
  distinct values (single-select; active chip shows the selection + a clear affordance).
  **Gender chip removed.**
- **`+` FAB:** opens an "Enter coach code" bottom-sheet → `lookupByHandle` → storefront.
- **Bell + heart:** inert this pass (no snackbar spam; just non-interactive or a single
  "coming soon"). Notification badge number removed (no real source).
- **Bottom nav:** unchanged (Discover active; others gated as today).

### 4.5 Storefront compile-bridge
`coach_storefront_screen.dart` currently takes `DiscoverOrg`. Change its constructor to accept
`OrganizationProfileModel` and map the handful of fields it already displays. **No full §6.3
rebuild here** — just enough that it compiles and shows real data. Full rebuild = next chunk.

### 4.6 Splash polish
- Wordmark → **AlphaSerena** (via `core/widgets/brand.dart`).
- `Image.asset(splash_hero)` wrapped with `errorBuilder` → solid near-black brand fallback
  (`#0E0E0E`) so a missing asset never crashes the first frame.
- Routing logic unchanged.

### 4.7 Login polish
- Wordmark → **AlphaSerena**.
- Remove the dead **"Skip"** button (no anonymous path exists).
- Headset/support: make it a real action (e.g. `mailto:`/WhatsApp support link) OR remove the
  "or continue with" + headset block entirely. Default: **remove** the block to avoid dead UI
  (revisit if a support channel is defined).
- Phone validation: keep digits-only formatter; keep 6–15 length guard. (Full per-country
  validation deferred — flagged in CLAUDE.md, not blocking.)

### 4.8 Brand sweep
Grep the repo for `Alphas Arena` and `Fitopia`; update visible strings to **AlphaSerena**.
`core/widgets/brand.dart` `AlphasArenaWordmark` renamed/retargeted to render "AlphaSerena"
(keep the red "A" treatment if it reads well).

## 5. Files

| File | Action |
|---|---|
| `lib/core/models/organization_profile_model.dart` | **new** — port from TrainersHQ |
| `lib/core/services/coach_service.dart` | edit — `discover()`/`byHandle()` return the rich model |
| `lib/controllers/discover_controller.dart` | **new** — load + search + filters + name |
| `lib/screens/join/join_coach_screen.dart` | rewrite — real data, states, functional filters |
| `lib/screens/join/discover_models.dart` | **delete** `DiscoverOrg`/`kSampleOrgs`; salvage `inr()` + `MembershipPlan` into a keeper file |
| `lib/screens/join/coach_storefront_screen.dart` | edit — accept `OrganizationProfileModel` (compile bridge) |
| `lib/screens/auth/splash_screen.dart` | edit — wordmark + asset fallback |
| `lib/screens/auth/login_screen.dart` | edit — wordmark, remove dead Skip/social |
| `lib/core/widgets/brand.dart` | edit — wordmark → AlphaSerena |

## 6. Edge cases & states

- **No published orgs** → friendly empty state, not a blank screen.
- **Org missing image/tagline/city/stat** → each rendered conditionally; card never shows
  empty rows or broken images (placeholder for image).
- **rating/reviewCount == 0 / verified == false** → hide the rating + Verified badge (clean).
- **Network/permission error on load** → error state with Retry.
- **`clientProfiles.clientName` empty** → greeting falls back to "Alpha".
- **Handle lookup miss** → "No organization found for that code" snackbar; no navigation.
- **Coupon/checkout/storefront** → untouched logic; only the model type bridges.

## 7. Non-goals (defer, tracked)

- Storefront §6.3 full rebuild; checkout coupon UI; payment polish.
- Favorites persisted to the member profile; real notifications/FCM badges.
- Gender filter (needs a backend field — out of scope until one exists).
- Per-country exact phone validation.

## 8. Acceptance

- Discover shows **real** published organizations from `organizationProfiles`, sorted rating→name.
- Search + Location + Specialization filters actually narrow the list; "All" resets.
- Loading / empty / error states all reachable and correct.
- Tapping a card opens the storefront with that org's real data (compile-bridged).
- `+` FAB code entry resolves a real org by handle.
- Splash + login show **AlphaSerena**; no "Alphas Arena"/"Fitopia" strings remain; no dead Skip.
- `flutter analyze` → no issues. No `print()`, no `.withOpacity()`.
