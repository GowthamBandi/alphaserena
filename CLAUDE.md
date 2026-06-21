# AlphaSerena (Client App) — Project Guide for Claude
## Read this entire file before every response. Single source of truth for the `alphaserena` project.

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

## Phase D — Tier-2 membership ⏳ NOT STARTED (needs design + Cloud Function)

---

# END — update PART 12 as each item completes; never delete done items, mark them ✅.
