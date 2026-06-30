# AlphaSerena (Client App) — Project Guide for Claude
## Read this entire file before every response. Single source of truth for the `alphaserena` project.

> 📌 **BEFORE STARTING NEW WORK, ALSO READ:**
> `docs/trainershq-integration-handoff-2026-06-28.md` — the current cross-app backend
> contract + the COMPLETE intended design (all 9 reference mockups, screen by screen).
> The build log in PART 12 below stops at **2026-06-25** and is now **stale**:
> TrainersHQ shipped a lot of member-facing backend after that (per-set workout
> `setRows`, meal-grouped diet with grams/portions/targets, member-log collections,
> membership coupons, onboarding responses). The handoff doc is authoritative on the
> backend contract; this file remains authoritative on AlphaSerena's coding rules/brand.

---

# LATEST — 2026-06-29 (CROSS-APP: TrainersHQ `getMyTraining` now gates plan STATUS + MEMBERSHIP — ✅ DEPLOYED)

TrainersHQ shipped + **deployed** (to `trainershq-f5ded`) two backend-contract changes that DIRECTLY
affect this app. **No new collections/indexes; the member app keeps calling `getMyTraining` the same
way** — but its behavior changed. Read this before touching the training/membership screens.

1. **Assigned plans now have a LIFECYCLE — `getMyTraining` only serves ACTIVE ones.**
   - `client_plan_assignments/{id}` docs gained a `status` field: **`active` | `paused` | `ended`**
     (legacy docs with no field = `active`). In TrainersHQ a coach can now **pause / resume / replace /
     remove** a client's plan from a dedicated "Manage plans" screen; "remove" = soft `ended`
     (restorable history), not a delete.
   - **`getMyTraining` now SKIPS `paused`/`ended` assignments** and serves only the latest `active`
     workout + diet. **Member-app impact:** a member's workout or diet can now legitimately become
     `null` because the coach **paused or removed** it — this is NOT a bug. Show a calm "No active plan
     right now — your coach will assign one" state (don't treat null as an error).
   - This app reads training via `getMyTraining` (server-side), so it needs NO change. IF you ever read
     `client_plan_assignments` directly (you shouldn't — keep using the CF), **filter to
     `status == 'active'`**.

2. **`getMyTraining` now ENFORCES membership server-side** (this closes the PART 12 Section-5 TODO
   "server-side membership check in getMyTraining + mid-session re-gate").
   - If the member is **frozen** (`membershipFrozen`), **deactivated** (`membershipActive == false`),
     or **past `membershipExpiry`**, the CF returns the same empty `{workout:null, diet:null}` shape
     (no new error contract — this app already handles null). Members with NO membership fields at all
     are still served (legacy/test safety).
   - **Member-app impact:** content is now blocked at the data layer when a membership lapses mid-use —
     the entry gate is no longer the only line of defence. But `null` from `getMyTraining` is now
     **ambiguous** (no active plan OR inactive membership). **Disambiguate using `MembershipController`
     status:** if membership is expired/frozen → show the **renew / switch-coach** state (not "no plan
     assigned"). The in-dashboard `membership_screen` still has the stale "ask your gym to add you"
     copy — point it at renew/switch-coach.

**Deployed 2026-06-29** from TrainersHQ: `firestore:rules` (a `client_plan_assignments` *update* rule,
internal to the coach app) + `functions:getMyTraining`. Nothing for this app to deploy; just align the
training/membership UI with the two behaviors above. (TrainersHQ also: redesigned its trainer-side
chat + made its plan-management screens — both trainer-side only, no member-app contract change. The
`chats/{clientId}/messages` thread this app uses is unchanged.)

---

# 2026-06-25 (CLIENT PERFORMANCE LOGGING — DESIGNED, not built)

NEW cross-app feature: the client **records actual performance** against the assigned plan, and the
trainer (trainersHQ) reviews it. Designed via the brainstorming workflow. **Full spec lives in the
trainersHQ repo:** `trainersHQ/docs/superpowers/specs/2026-06-25-client-performance-logging-design.md`.
**Status: spec done, implementation NOT started.**

- **Workout — PREMIUM PER-SET experience (agreed design):** one exercise at a time
  ("Exercise N of M") with a video hero, a READ-ONLY red **Coach Prescription** card
  (Set/Reps/Kg/Rest table), then **Your Performance** as an accordion where only the
  ACTIVE set is open — client enters **Reps Done + Weight Used**, taps **COMPLETE SET**
  (the set locks to `✔ Set n · reps · kg`), a **full-screen rest-timer modal** runs a
  circular countdown from that set's prescribed rest (with **Skip Rest**), then the next
  set auto-expands. A `● ● ○ ○` **progress strip** shows "2 / 4 Sets Completed". Actuals
  save per set to the new `client_workout_sessions` collection (`entries[].sets[]` =
  prescribed + actual + completed). This is the client follow-up; needs the trainer
  per-set authoring + a repaired `getMyTraining`.
- **Diet:** turn the assigned foods into a daily **adherence checklist** (Eaten / Skipped / Partial +
  note); saves/updates one doc per day in the new `client_diet_logs` collection
  (id `{clientId}_{yyyy-MM-dd}`). ⚠️ This **replaces** the current in-memory-only "Log Food" mock —
  `DashboardController.addMeal` persists NOTHING today.
- **FUNCTIONS-FREE:** write directly to Firestore; security rules verify ownership. The member already
  holds its `clients` doc live (`MemberController.client` + `linkedClientId`), so `clientId` + `adminId`
  are available with no extra read.
- Add `clientWorkoutSessions` / `clientDietLogs` constants to `FsCollections` (keep in sync with
  trainersHQ). No new Firestore index needed.

---

# PART 1: WHAT THIS APP IS

Project: **alphaserena** (pubspec name: `alphaserena`)
Type: **Flutter MOBILE app** (Android + iOS) — the **CLIENT / GYM-MEMBER app**.
Brand: **AlphaSerena** (⚠️ login screen still says the old name "Fitopia" — must be rebranded).
Who uses it: **Clients** = gym members / trainees who belong to a fitness organization.

This is ONE of THREE apps in the AlphaSerena platform (see PART 2). This app is the
member-facing one: a client logs in, sees the workout & diet plans their trainer
assigned, tracks progress, chats with their trainer, and (future) buys their gym
membership subscription.

Developer:
  Name: Gowtham Bandi (founder), Rajahmundry, Andhra Pradesh, India
  Level: Beginner developer — explain clearly, one step at a time.

---

# PART 2: THE PLATFORM (read this — it explains everything)

AlphaSerena is a multi-tenant fitness SaaS. **All three apps share ONE Firebase
backend: `trainershq-f5ded`.**

| App | Folder | Platform | Who | Role |
|---|---|---|---|---|
| **trainersHQ** | `/Users/gowthambandi/flutters/trainersHQ` | Mobile | Gym owner (admin) + Trainer (staff) + Super admin | The ORGANIZATION app. Owners buy a platform plan, create trainers, manage clients, build workout/diet plans. **Most mature — feature complete.** |
| **alphaserena** (THIS APP) | `/Users/gowthambandi/flutters/alphaserena` | Mobile | Client (gym member) | The CLIENT app. UI built, **NOT wired to Firestore yet.** |
| **alphaserena_admin** | `/Users/gowthambandi/flutters/alphaserena_admin` | Web | Founder / super admin (Gowtham) | The FOUNDER console. Creates platform subscription plans, approves/blocks gym owners. Old/messy code. |

### Two subscription tiers (CRITICAL to understand)
1. **Tier 1 — Platform SaaS (Founder → Organizations):** The founder creates
   `subscription_plans` in `alphaserena_admin`. Gym-owner admins buy these inside
   **trainersHQ** to unlock the app and get usage limits (max trainers/clients/etc).
2. **Tier 2 — Gym memberships (Organization → Clients):** Each gym creates its OWN
   membership plans for its members. **Clients buy these in THIS app (alphaserena).**
   ⚠️ Tier 2 does **NOT exist in the data model yet** — it must be designed and built
   (see PART 8 gaps + PART 9 roadmap).

### The roles hierarchy
Super Admin (founder) → Admin (gym owner, pays Tier 1) → Trainer (staff) → **Client (this app, pays Tier 2)**

---

# PART 3: TECH STACK

- Flutter (Dart SDK — match `pubspec.yaml`), Material 3.
- **GetX** (`get`) — state management + DI + (currently NOT used for routing; uses
  `Get.to`/`Get.offAll` with widget literals, no named routes yet).
- Firebase: `firebase_core` (init via native `google-services.json`, package
  `com.alphaserena`, project `trainershq-f5ded`). **Auth + Firestore + Storage are
  NOT wired yet** — only `Firebase.initializeApp()` is called.
- UI deps: `google_fonts` (Poppins), `country_picker`, `pinput` (OTP boxes),
  `video_player`/`chewie` (workout videos — via `VideoServiceController`).

Commands:
```bash
flutter pub get
flutter run            # mobile device/emulator
flutter analyze        # keep zero issues after every change
flutter build apk
```

---

# PART 4: CURRENT FILE STRUCTURE (verified)

```
lib/
├── main.dart                      Entry → Firebase.init → MyApp → home: PhoneLoginScreen
├── controllers/
│   ├── theme_controller.dart      Dark/light (RxBool isDarkMode)
│   ├── dashboard_controller.dart  ⚠️ ALSO has its own isDarkMode + in-memory meal/calorie tracking
│   ├── onboarding_controller.dart 5-page onboarding form (text controllers only)
│   ├── workout_controller.dart    Workout player state — ⚠️ DUMMY data, sets/rest timer
│   └── video_service_controller.dart  chewie/video_player wrapper
├── models/
│   └── workout_model.dart         WorkoutModel + WorkoutSet (fromJson only)
└── screens/
    ├── auth/
    │   ├── login_screen.dart      PhoneLoginScreen — country picker + phone field
    │   ├── otp_screen.dart        ⚠️ FAKE OTP — checks length==6 then opens dashboard
    │   └── onboarding_screen.dart 5-step onboarding (diet, goals, activity)
    └── dashboard/
        ├── dashboard_screen.dart  ClientDashboard — bottom nav (IndexedStack, 4 tabs)
        ├── home/client_home_screen.dart
        ├── activity/activity_screen.dart
        ├── client_progress_screen.dart
        ├── client_workout_screen.dart
        ├── client_diet_screen.dart
        ├── client_chat_screen.dart
        ├── workout_player_screen.dart       video + sets + rest overlay
        ├── clients/client_trainer_schedule_screen.dart
        └── profile/client_profile_screen.dart
```

Entry flow today: `PhoneLoginScreen` → `OTPVerificationScreen` → (fake verify) →
`ClientDashboard`. No splash, no session restore, no auth guard.

---

# PART 5: CURRENT STATE — WHAT IS REAL vs DUMMY

✅ Built (UI only):
- Phone login screen (country picker, India default) — UI only, no auth call.
- OTP screen (pinput 6-box) — ⚠️ **fake**, no Firebase phone verification.
- 5-step onboarding form (diet type, previous diet, medical, goal, activity).
- Client dashboard shell with bottom nav (Home / Schedule / Activity / Progress /
  Profile — note labels vs pages are slightly mismatched).
- Workout player (video via chewie, sets, rest timer) — ⚠️ dummy workout data.
- Diet / progress / chat / profile screens — static UI.

❌ NOT built / not wired:
- **No Firebase Auth** (no phone OTP verification, no session).
- **No Firestore** anywhere (zero `collection()` calls).
- No link between a client and their organization (`adminId`) or trainer (`trainerId`).
- No reading of assigned workout/diet plans from the backend.
- No real chat (the trainersHQ `chats/{clientId}/messages` thread is built for this).
- No membership purchase (Tier 2).
- No design-system file — every screen hardcodes colors/fonts inline.
- Brand still says "Fitopia" on the login screen.

---

# PART 6: ARCHITECTURE NOTES & KNOWN ISSUES (read before "fixing")

1. **Two theme sources of truth.** `ThemeController.isDarkMode` AND
   `DashboardController.isDarkMode` both exist. Standardize on `ThemeController`
   only (it's the one screens read).
2. **No named routes.** Navigation uses `Get.to(() => Widget())` /
   `Get.offAll(() => Widget())`. When wiring real auth we should add a session
   controller + named routes (mirror trainersHQ's `SessionController` pattern).
3. **Fake auth.** `otp_screen.dart` does not call `FirebaseAuth.verifyPhoneNumber`.
   Real wiring = phone auth → resolve the client's `clients/{docId}` record → route.
4. **Clients are data records in the backend.** In trainersHQ, the `clients`
   collection has NO auth account — clients are created by admins/trainers with
   fields `{name, phone, email?, adminId, trainerId?, status, ...}`. To give a
   client a login, we must **link a Firebase Auth uid (phone) to a `clients` doc**
   (match by phone, or store `authUid` on the client doc). This is the #1
   architecture decision before wiring data.
5. **Dummy data everywhere.** `workout_controller.dart` loads a hardcoded workout;
   `dashboard_controller.dart` tracks meals/calories in memory only.

---

# PART 7: FIREBASE / DATA MODEL (shared backend — do NOT invent collisions)

Backend: `trainershq-f5ded`. The CANONICAL collection names live in trainersHQ at
`lib/core/constants/firestore_collections.dart` (`FsCollections`). **This app must
reuse the same names** — never create a parallel/renamed collection.

Collections this app will read/write (once wired):
- `clients/{id}` — the member's own record (READ; `adminId`, `trainerId`, `status`,
  `goal`, profile). **Canonical = `clients`** (legacy `clints` is deprecated — never use).
- `client_plan_assignments/{id}` — which workout/diet plan is assigned to this client (READ).
- `workoutPlans/{id}`, `dietPlans/{id}`, `weeklyWorkoutPlans/{id}` — the assigned
  plan content (READ).
- `exercises/{id}`, `foodDatabase/{id}` — referenced by plans (READ).
- `chats/{clientId}/messages/{id}` — the trainer↔client thread (READ + WRITE; built
  in trainersHQ so the client joins the SAME thread).
- `workout_notes_clients/{id}` — trainer notes about this client (READ).
- Tier-2 membership plans + client subscription — ⚠️ **NEW collections, not designed
  yet** (see PART 8).

RULE: create a `lib/core/constants/firestore_collections.dart` mirroring trainersHQ's
`FsCollections` and use it everywhere. Never hardcode collection strings.

---

# PART 8: CROSS-APP GAPS TO RESOLVE (platform-wide)

1. **Client ↔ Auth linkage** — decide how a phone-auth client maps to a `clients`
   doc (match-by-phone vs `authUid` field). trainersHQ must write the matching field
   when admins/trainers create clients.
2. **Tier-2 membership model missing** — there is no collection for org-created
   member plans nor for a client's active membership. Proposed (confirm with founder):
   - `membershipPlans/{id}` — org-owned (`adminId`), the gym's plans for members.
   - `clientSubscriptions/{id}` (or a `membership` map on the client doc) — the
     client's active membership + expiry, written server-side after payment.
   - Payments via Razorpay, verified by a Cloud Function (same pattern trainersHQ
     uses for Tier-1).
3. **Brand migration** — "Fitopia" → "AlphaSerena" across the client app.
4. **No Cloud Functions for client actions yet** — membership purchase must be
   server-verified (never trust the client to set its own membership/expiry).

---

# PART 9: WHAT TO BUILD NEXT (proposed order — confirm before starting)

Phase A — Foundation:
1. Rebrand "Fitopia" → "AlphaSerena"; pick ONE theme controller.
2. Add `core/constants/firestore_collections.dart` (mirror trainersHQ `FsCollections`).
3. (Recommended) Adopt the shared design system — see PART 10.

Phase B — Real auth & session:
4. Real Firebase **phone OTP** (`verifyPhoneNumber` + `signInWithCredential`).
5. Splash + `SessionController` (resolve the client's `clients` doc, route to
   onboarding vs dashboard). Add named routes + an auth guard.
6. Decide & implement client↔`clients` linkage (PART 8 #1).

Phase C — Real data:
7. Client home/profile from the real `clients` doc.
8. Assigned workout/diet plans from `client_plan_assignments` + plan collections
   (replace the dummy `WorkoutController` data).
9. Real chat via `chats/{clientId}/messages`.

Phase D — Tier-2 membership:
10. Design Tier-2 model (PART 8 #2), build the buy-membership flow + Cloud Function.

---

# PART 10: DESIGN SYSTEM (brand is shared with trainersHQ)

Brand voice = gym "arena / warrior". Accent color and fonts match trainersHQ.
See `/Users/gowthambandi/flutters/trainersHQ/DESIGN_SYSTEM.md` for the full spec.

- **Accent:** `Colors.redAccent.shade700` = `#D50000` (buttons, active states, icons).
- **Gradient:** `#D50000 → #FB8C00` (orange) for titles; `#D50000 → #FF6E40` for selected cards.
- **Fonts (google_fonts):** Teko (display/titles), Poppins (body/buttons — what this
  app already uses), Inter (lists).
- **Client app is dark-first** (`#0E0E0E`/black bg) with a light mode toggle.
- Radii: 14 (inputs/buttons), 16–18 (cards), 20 (bottom nav).

RULE (target): centralize tokens into `lib/core/theme/` and stop hardcoding hex/fonts
in screens — mirror trainersHQ's `core/theme` + `core/widgets`.

---

# PART 11: CODING RULES

1. Reuse the shared backend collection names (mirror `FsCollections`) — never hardcode.
2. GetX: `Get.find<X>()`, register shared controllers once (permanent). No `new` singletons.
3. `debugPrint()` only — no `print()` in committed code.
4. Null-safe; defensive `fromMap` (handle `Timestamp | String | num`) like trainersHQ models.
5. Every screen: loading + empty + error states.
6. Sensitive/financial actions (membership purchase) go through a **Cloud Function** —
   never write membership/expiry directly from the client.
7. `.withValues(alpha: x)` instead of deprecated `.withOpacity()`.
8. Run `flutter analyze` after each change; keep it clean.
9. One thing at a time. After each step run `flutter analyze` and report back.

---

# PART 12: BUILD STATUS

## Phase 0 — Understanding ✅
  ✅ Platform model + this app's role documented (this file).

## Phase A / Section 0 — Foundation & brand ✅ DONE (2026-06-21)
  ✅ Design system ported (dark-first) — lib/core/theme/ (app_colors+AppPalette,
     app_text [Teko/Poppins/Inter], app_radii, app_shadows, app_theme) + lib/core/
     widgets/ (primary_button, app_text_field, gradient_title). context.palette works.
  ✅ lib/core/constants/firestore_collections.dart — FsCollections mirroring the
     canonical shared names (clients, client_plan_assignments, workoutPlans, dietPlans,
     weeklyWorkoutPlans, exercises, foodDatabase, chats, + clientProfiles for the
     member's own app profile).
  ✅ lib/core/constants/quotes.dart — motivational arena lines (Quotes.daily/random/hype).
  ✅ main.dart wired to AppTheme.light/dark, title 'AlphaSerena'; ThemeController is
     dark-first (default dark, persisted). flutter analyze clean.
  ⏳ Rebrand the "Fitopia" text on the login screen — done in Section 1.
  ⏳ Migrate the existing screens onto the tokens — done as each screen is rebuilt.

## Phase B / Section 1 — Auth & onboarding ✅ DONE (2026-06-21)
  ✅ REAL phone OTP — controllers/auth_controller.dart (verifyPhoneNumber +
     signInWithCredential; auto-retrieval handled). Login + OTP screens rebuilt on
     the brand; "Fitopia" REBRANDED to AlphaSerena everywhere.
  ✅ Splash — screens/auth/splash_screen.dart: brand wordmark + "THE ARENA FOR
     ALPHAS" + a daily Quote; routes on cold start (signed out → login; signed in →
     onboarding if not done, else dashboard).
  ✅ Onboarding — screens/auth/onboarding_screen.dart: motivational, collects
     name/goal/gender/age/activity → saves to clientProfiles/{uid} (member-owned)
     via core/services/client_profile_service.dart, then → dashboard.
  ✅ Routing: splash → login → otp → (onboarding | dashboard). AuthController.routeAfterAuth
     decides via clientProfiles.onboardingComplete. signOut → login.
  ✅ Shared rule added (trainersHQ/firestore.rules): clientProfiles/{uid} read/write
     if request.auth.uid == uid. ⚠️ DEPLOY needed.
  ✅ flutter analyze: no errors (remaining lints are in the old dashboard screens,
     rebuilt in Section 2/3).
  ⚠️ TESTING: enable Phone sign-in in Firebase Auth; on real Android add the app's
     SHA-1/SHA-256, or add a test phone number + fixed OTP for quick testing.
  ⏳ Client ↔ gym `clients` doc linkage (to read ASSIGNED plans) — Section 2 (a
     claimClientAccount Cloud Function matching the verified phone + a clients rule).

## Phase C / Section 2 — Data linkage & Home ✅ DONE (2026-06-21)
  ✅ claimClientAccount Cloud Function (trainersHQ/functions/src/members.ts) — links
     the member's VERIFIED phone (auth token) to the gym `clients` doc: sets
     clients.authUid + writes clientProfiles {linkedClientId, gymName, trainerName,
     clientName, goal}. Idempotent. Compiles (tsc).
  ✅ Member rules (trainersHQ/firestore.rules): clients read where authUid==uid;
     chats read+create where the client's authUid==uid (member can always message).
  ✅ controllers/member_controller.dart — calls claim() + live-streams clientProfiles
     + the linked clients doc; exposes name/goal/gymName/trainerName; 'no_membership'
     notice + retry. cloud_functions dep added.
  ✅ Home screen rebuilt (screens/dashboard/home/client_home_screen.dart) on the
     brand + REAL data: greeting, daily quote banner, goal/trainer/gym cards,
     not-linked state with retry, theme toggle. flutter analyze: no errors.
  ⚠️ DEPLOY: firebase deploy --only functions,firestore:rules (adds claimClientAccount
     + the member rules). iOS phone auth also needs an APNs key in Firebase.
## Phase C / Section 3 — Member screens ✅ DONE (2026-06-21)
  ✅ getMyTraining Cloud Function (trainersHQ/functions/src/members.ts) — resolves the
     member's most-recent assigned workout + diet plans server-side (enriches exercise
     video/instructions + food macros), so the member needs NO read access to gym
     plan/exercise/food collections. Compiles (tsc).
  ✅ controllers/training_controller.dart — loads getMyTraining (workout + diet).
  ✅ Screens rebuilt on the brand + real data:
     • Workout (client_workout_screen) — assigned exercises → tap → workout_player_screen
       (real video via video_player, sets/reps/instructions).
     • Diet (client_diet_screen) — assigned foods + macro totals.
     • Progress (client_progress_screen) — member-owned weight log (writes
       clientProfiles.weightLog; member-owned rule).
     • Chat (client_chat_screen) — REAL-TIME chats/{clientId}/messages with the trainer.
     • Profile (client_profile_screen) — info + chat link + theme toggle + sign out.
     • Dashboard shell (dashboard_screen) — 5-tab bottom nav (Home/Workout/Diet/
       Progress/Profile), registers Member + Training controllers.
  ✅ Deleted dead files (old workout_controller/onboarding_controller/video_service_
     controller/workout_model + schedule/activity screens). WHOLE PROJECT lint-clean:
     flutter analyze → No issues found.
  ⚠️ DEPLOY: getMyTraining ships with `firebase deploy --only functions`.

## CLIENT APP CORE COMPLETE: splash → phone OTP → onboarding → dashboard
   (Home · Workout(+video) · Diet · Progress · Chat · Profile), all real-data, brand,
   dark-first, lint-clean. Both Android + iOS (iOS phone auth needs an APNs key).

## Phase D / Section 4 — Tier-2 membership ✅ DONE (2026-06-21)
  ✅ Members buy the GYM's membership via Razorpay. Backend (trainersHQ):
     membershipPlans + memberPayments collections + rules (gym writes own plans while
     operating, members read; receipts server-written); CFs createMembershipOrder +
     verifyAndActivateMembership (member-authed, HMAC-verified, writes membership +
     membershipExpiry on the member's clients doc). Compiles (tsc).
  ✅ Gym side (trainersHQ): features/memberships — admin creates/edits membership plans
     (Membership plans screen + route + hub tile + MembershipService).
  ✅ Client side (alphaserena): razorpay_flutter added; ClientRazorpayController (buy →
     createMembershipOrder → native sheet → verifyAndActivateMembership);
     MembershipController (gym's plans + current membership status); MembershipScreen
     (status card + plans + Buy); entry from Profile. flutter analyze: no issues.
  ⚠️ DEPLOY functions+rules; uses the live Razorpay key (secret). iOS: Razorpay pod +
     APNs setup.

## PLATFORM COMPLETE: all 3 apps feature-complete. alphaserena = Sections 0–4 done,
   lint-clean, both platforms.

## PRODUCTION AUDIT (2026-06-21): all 3 apps `flutter analyze` clean; no print(),
   no "Fitopia", no withOpacity, no real TODOs. Fixed a multi-user bug:
   AuthController.signOut now deletes the member-scoped controllers (Member/Training/
   Membership/ClientRazorpay) so a different member on the same device starts clean.

## Phase E / Section 5 — JOIN A COACH (member self-subscribe) ✅ DONE (2026-06-23)
  ⚠️ MODEL CORRECTION: this SaaS is for ONLINE trainers / influencers / individual coaches, NOT gyms.
  Members join a coach ONLY by subscribing — the coach NEVER adds clients by phone. The old
  "ask your gym to add your number" model is replaced.
  ✅ Backend (lives in trainersHQ): `verifyAndActivateMembership` now CREATES the member's `clients`
     doc under the plan's coach on first purchase (+ links clientProfiles.linkedClientId). ⚠️ DEPLOY
     from trainersHQ: `firebase deploy --only functions:verifyAndActivateMembership` (UPDATE — no gotcha).
  ✅ Coach discovery: trainersHQ `organizationProfiles` gained `handle` (join code) + `published`.
  ✅ Member side (this app):
     • `core/services/coach_service.dart` — CoachSummary + discover() (published coaches) /
       byHandle(code) / plans(adminId) / hasActiveMembership(uid).
     • `controllers/join_controller.dart` — browse + code lookup.
     • `screens/join/join_coach_screen.dart` — enter a coach's code OR browse published coaches.
     • `screens/join/coach_storefront_screen.dart` — coach profile + plans + Subscribe (reuses
       ClientRazorpayController) → on success → ClientDashboard.
     • MEMBERSHIP GATE wired into splash + AuthController.routeAfterAuth + onboarding: signed-in →
       onboarding → (no active membership) JoinCoachScreen → dashboard. `flutter analyze` clean.
  ✅ DONE (2026-06-29, TrainersHQ): server-side membership check in `getMyTraining` — expired/frozen/
     deactivated members now get `{workout:null,diet:null}`, so content IS blocked mid-session at the
     data layer (see the LATEST 2026-06-29 section). ⏳ STILL TODO (client-side UX): disambiguate a
     `null` from getMyTraining (no plan vs. inactive membership) using MembershipController status →
     show a renew/switch-coach state; the in-dashboard membership_screen still shows the stale "ask your
     gym to add you" copy (members now self-join — point it at renew / switch-coach); also handle a plan
     becoming null because the coach paused/removed it; phone-number validation + onboarding polish.

## Phase F / Section 6 — PRODUCTION HARDENING (step-by-step, screen by screen) — IN PROGRESS
  Goal: take each already-built screen from "UI + real data" to "production-perfect" (no UX
  bugs, no flow issues, no missing loading/error states), one section at a time, before moving on.

  ### 6.1 — Splash · Login · OTP ✅ DONE (2026-06-29)
  Audited the full splash → login → otp → routing flow and fixed 5 issues:
  - **BEFORE:** Tapping **Resend OTP** called `sendOtp()` whose `codeSent` always did
    `Get.to(OtpScreen())` — so a resend **pushed a duplicate OTP screen** on top of the current
    one (back button revealed a stale screen with a dead timer).
    **NOW:** `sendOtp(phone, {isResend})` only navigates on the first send; resend refreshes in
    place and passes `forceResendingToken: _resendToken` so a genuine new SMS is sent.
  - **BEFORE:** The OTP **"Verify & Continue" button had no loading state** — after entering the
    code, `signInWithCredential` + `routeAfterAuth` (a Firestore membership query) ran for several
    seconds with zero feedback and the button stayed live.
    **NOW:** the button is wrapped in `Obx` bound to `AuthController.isLoading` (matches the login
    button), so it shows the spinner during the round-trip.
  - **BEFORE:** No **double-submit guard** — `onCompleted` auto-fired `verifyOtp` on the 6th digit
    AND the button could be tapped, allowing concurrent `signInWithCredential`/`Get.offAll` calls.
    **NOW:** `verifyOtp` early-returns if `isLoading` is already true (resend guards on it too).
  - **BEFORE:** A transient network error in the membership check **dumped an active (paying)
    member into the Discover/Join screen** — splash defaulted `active=false` on error, and
    `routeAfterAuth` had **no try/catch at all** (an error there stranded a just-signed-in user on
    the OTP screen).
    **NOW:** both splash `_decide()` and `routeAfterAuth` catch the error and fall back to the
    **dashboard** for an already-authenticated user (the dashboard re-checks membership/linkage and
    surfaces its own retry states), instead of bouncing them to Join.
  - **BEFORE:** Phone validation was a generic 6–15 digit length check (the gap flagged in commit
    `b2198c3`) — a malformed Indian number only bounced back from Firebase.
    **NOW:** `_validatePhone` enforces **exactly 10 digits starting 6–9 for India (+91)** and keeps
    the sane 6–15 generic bound for other country codes.
  - `flutter analyze lib/screens/auth/ lib/controllers/auth_controller.dart` → **No issues found.**

  ### 6.2 — Discover · Storefront · Payment ✅ DONE (2026-06-29)
  Audited the join flow (`join_coach_screen`, `coach_storefront_screen`, `plans_screen`,
  `plan_details_screen`, `checkout_screen`, `payment_success_screen`, `client_razorpay_controller`).
  **Storefront passed clean** (lazy cover-video, all loading/error/placeholder states, guarded social
  links — no changes). Fixed 4 issues across Discover + Payment:
  - **BEFORE (Discover):** The "Enter Coach Code" sheet's **Find** button popped the sheet FIRST, then
    awaited `lookupByHandle` with **no spinner** (slow network = nothing visibly happened) and **no
    try/catch** — a network error threw uncaught with zero feedback.
    **NOW:** the sheet uses a `StatefulBuilder` with a local `busy`/`errorText`; Find shows a spinner,
    wraps the lookup in try/catch, keeps the sheet open on "not found"/error with inline red text, and
    only pops + navigates on success (+ autofocus, submit-on-enter, disabled-while-busy).
  - **BEFORE (Payment correctness):** the success receipt showed `amountPaid: _total` — the *client's*
    optimistic figure. The server (`createMembershipOrder`) recomputes the discount, so a coupon whose
    state changed between preview and pay could make the receipt show a **wrong amount**.
    **NOW:** `ClientRazorpayController.buy` stores the server's `amount` (paise) and the success
    callback reports the **actual charged amount** (`onSuccess(paymentId, amountPaidRupees)`); checkout
    passes that straight to the receipt.
  - **BEFORE (stale copy):** `client_razorpay_controller` verify-failure said *"Contact your gym if
    charged"* — but the model is ONLINE COACHES, not gyms.
    **NOW:** *"Contact support if you were charged."*
  - **BEFORE (misleading copy):** the success "What's Next" promised *"Check your inbox for
    confirmation"* (no email is ever collected — checkout sends `email: ''`) and *"Our team will
    contact you within 24 hrs"* (gym-ish, not the coach lifecycle).
    **NOW:** *"Your membership is active right away" · "{org} will set up your plan shortly" · "Open
    your dashboard and get ready to train!"* — accurate to what actually happens.
  - **Polish:** removed a decorative `chevron_right` on the Discover "verified" trust banner that
    implied it was tappable when it wasn't.
  - `flutter analyze lib/screens/join/ lib/controllers/client_razorpay_controller.dart
    lib/controllers/discover_controller.dart` → **No issues found.**

  ### 6.3 — FULL-FUNNEL pass: splash → … → Razorpay success/failure ✅ DONE (2026-06-29)
  Re-traced the entire journey as one connected funnel (not screen-by-screen) to catch CROSS-SCREEN
  navigation / back-stack / money-path issues the per-section passes missed. Fixed 2 production bugs:
  - **BEFORE (back-stack):** after paying, `checkout` does `Get.off(PaymentSuccessScreen)`, leaving
    `…→PlanDetails→Success` on the stack. The success screen's app-bar back/close went to the
    dashboard, but **Android hardware back popped to `PlanDetailsScreen`** — the just-bought plan, with
    "Choose This Plan" still live → the member could **re-enter checkout and pay AGAIN**.
    **NOW:** `PaymentSuccessScreen` is wrapped in `PopScope(canPop:false, onPopInvokedWithResult:…)`
    that routes hardware-back to `ClientDashboard` (Flutter 3.38 API).
  - **BEFORE (money path):** if Razorpay CAPTURED the payment but `verifyAndActivateMembership` failed
    (transient network), the member was charged-but-not-activated with only a snackbar AND
    `isProcessing` went false → the **"Proceed to Pay" button went live again** = a re-tap created a
    NEW order = **double charge**.
    **NOW:** `ClientRazorpayController` splits verify into `_runVerify()` + a `needsVerifyRetry` Rx.
    On verify failure it keeps the captured payment identifiers and flips `needsVerifyRetry`; the
    checkout bottom button then reads **"Retry Confirmation"** and calls `retryVerification()` (the CF
    is idempotent on order/payment/signature, so NO re-charge). A normal Pay button can never start a
    2nd order once a payment is captured. `resetVerifyState()` runs on checkout `dispose` so a later
    checkout opens fresh. The receipt still shows the SERVER-charged amount (from 6.2).
  - Verified the failure branches end-to-end: createOrder error → snackbar + retry; sheet
    cancel/decline → `_error` snackbar, overlay clears; verify fail → Retry Confirmation; verify ok →
    success screen. `flutter analyze` (whole project) → **No issues found.**
  - ⏭️ NEXT: user to pick the next section.

  ### 6.4 — App-wide connectivity gate (offline screen) ✅ DONE (2026-06-29)
  New cross-cutting feature (brainstormed): a global "No Internet" full-screen takeover whenever the
  device is offline, anywhere in the app, that auto-dismisses when connection returns.
  - **Decision (user):** app-wide + always-when-offline + full-screen takeover (vs per-operation /
    banner).
  - `controllers/connectivity_controller.dart` — GetX permanent singleton. Listens to
    `connectivity_plus` radio changes + re-checks on app-resume (`WidgetsBindingObserver`), but every
    decision is confirmed with a **real reachability probe** (`InternetAddress.lookup` on google.com /
    cloudflare.com, 4s timeout) so "Wi-Fi up but no internet" (captive portals/dead routers) reads as
    offline. Exposes `isOnline` (optimistic-true on cold start to avoid a flash) + `isChecking`;
    `recheck()` powers the Refresh button.
  - `screens/common/no_internet_screen.dart` — branded dark takeover: Lottie
    `assets/animations/no_internet_connection.json` (user-supplied) with a `wifi_off` fallback via
    `errorBuilder`, title/subtitle, `GradientButton` Refresh (spinner via `isChecking`), `PopScope`
    blocks back.
  - `main.dart` — registered the controller + mounted the overlay via `GetMaterialApp.builder` (a
    `Stack` with an `Obx`), so it sits ABOVE every route/dialog/snackbar and needs no per-screen wiring.
  - Deps/permissions: added `connectivity_plus: ^6.1.0`; Android manifest gained `INTERNET` +
    `ACCESS_NETWORK_STATE`. `assets/animations/` already registered in pubspec.
  - `flutter pub get` ok; `flutter analyze` (whole project) → **No issues found.**

---

# END — update PART 12 as each item completes; never delete done items, mark them ✅.
