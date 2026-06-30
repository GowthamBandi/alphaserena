# AlphaSerena ← TrainersHQ — Integration Handoff & Full Design Spec

> **Written 2026-06-28 from inside the TrainersHQ repo, by the Claude session that
> has the complete current trainer-app + backend state in context.**
>
> **Read order for a fresh AlphaSerena session:** `CLAUDE.md` (this app's own guide)
> → **this file** → then start work. This file is the *current cross-app contract*
> + the *complete intended design* of the member app. AlphaSerena's own `CLAUDE.md`
> build log stops at **2026-06-25** and is now stale — TrainersHQ shipped a large
> amount of member-facing backend between 2026-06-25 and 2026-06-28 that this app
> has NOT caught up to. Where the two disagree, **this file wins on the backend
> contract**; `CLAUDE.md` still wins on AlphaSerena's own coding rules/brand.

---

## 0. How to use this document

There are **three apps on one Firebase backend (`trainershq-f5ded`)**:

| App | Repo path | Who | Status |
|---|---|---|---|
| **TrainersHQ** | `D:\flutter works\trainersHQ` | Coach/admin + trainer + super-admin | Mature, feature-complete. The **authoring + data backend**. |
| **AlphaSerena** (this app) | `D:\flutter works\alphaserena` | Client / gym member | Core built (auth→dashboard→membership). Needs to catch up to the new contract + the full design below. |
| **alphaserena_admin_portel** | `D:\flutter works\alphaserena_admin_portel` | Founder / super-admin | Web founder console. Out of scope here. |

**All Cloud Functions + Firestore rules live in the TrainersHQ repo** (`functions/`,
`firestore.rules`). AlphaSerena never deploys backend; it only **calls CFs** and
**reads/writes the member-permitted collections**. When this doc says "needs a
backend change," that change is made + deployed *from TrainersHQ*, not here.

**Golden rule:** never invent or rename a collection. Mirror the canonical names in
`TrainersHQ/lib/core/constants/firestore_collections.dart` (reproduced in §4).

---

## 1. What AlphaSerena is (the product)

A **dark-first, red/black, "arena for alphas"** Flutter mobile app (Android + iOS)
for the **online-coaching client**. Business model: this is **NOT gym/walk-in
software** — coaches are online trainers / influencers / individual coaches, and a
member **joins a coach ONLY by buying that coach's membership inside this app**. The
coach never adds clients manually; buying a plan *creates* the client record under
that coach (server-side).

The member journey: **discover a coach → view their storefront → buy a membership
(Tier-2, Razorpay) → onboard → daily training loop** (workout with per-set logging,
diet with per-meal adherence logging, progress tracking, chat with the trainer).

Brand: **AlphaSerena** (the design mockups label it "Alphas Arena" — treat the
wordmark as AlphaSerena; the legacy "Fitopia" name is already removed). Accent red
`#D50000`; near-black bg `#0E0E0E`. See §8.

---

## 2. The two subscription tiers (don't confuse them)

1. **Tier 1 — Platform SaaS (Founder → Coach).** The coach buys a platform plan
   inside **TrainersHQ** to unlock the app + usage limits. **AlphaSerena has nothing
   to do with Tier 1.**
2. **Tier 2 — Gym/coach membership (Coach → Member).** Each coach creates membership
   plans (`membershipPlans`). **Members buy these in THIS app** via Razorpay,
   server-verified. This is the only purchase flow AlphaSerena implements.

---

## 3. AlphaSerena current state (what already exists — verify in code before reusing)

Per its `CLAUDE.md`, Sections 0–5 are built and lint-clean:

- **Section 0 — Foundation:** `lib/core/theme/` (AppPalette via `context.palette`,
  AppText, radii, shadows, theme), `lib/core/widgets/`, `core/constants/
  firestore_collections.dart` (FsCollections mirror), `core/constants/quotes.dart`.
  Dark-first ThemeController.
- **Section 1 — Auth:** REAL Firebase **phone OTP** (`AuthController`), splash,
  onboarding (writes `clientProfiles/{uid}`), routing splash→login→otp→
  (onboarding|dashboard).
- **Section 2 — Data linkage & Home:** `claimClientAccount` CF wired,
  `MemberController` (streams `clientProfiles` + the linked `clients` doc), Home
  screen on real data.
- **Section 3 — Member screens:** `getMyTraining`-backed Workout (+video player),
  Diet, Progress (member-owned weight log to `clientProfiles.weightLog`), Chat
  (real-time `chats/{clientId}/messages`), Profile. 5-tab dashboard shell.
- **Section 4 — Tier-2 membership:** `ClientRazorpayController` + `MembershipController`
  + `MembershipScreen` (buy via `createMembershipOrder` → native sheet →
  `verifyAndActivateMembership`).
- **Section 5 — Join a coach:** `coach_service.dart`, `join_controller.dart`,
  `JoinCoachScreen` (enter code OR browse published coaches), `CoachStorefrontScreen`,
  membership gate in splash/routeAfterAuth/onboarding.

> ⚠️ **The current screens are functional but FAR simpler than the intended design in
> §6.** They were built before the rich mockups. Most will be substantially rebuilt
> to match §6, and the new logging/progress features (§6.5–6.8) don't exist yet.

**Known issues to clean up (from AlphaSerena CLAUDE.md, still open):**
- in-dashboard `membership_screen` shows stale "ask your gym to add you" copy → point
  at renew / switch-coach.
- No server-side membership check in `getMyTraining`, no in-session expiry re-gate
  (entry gate only).
- `DashboardController.addMeal` persists NOTHING (in-memory mock) — replaced by the
  real diet-log writer in §6.5.
- Phone-number validation + onboarding polish.

---

## 4. Canonical collections (mirror these exactly)

From `TrainersHQ/lib/core/constants/firestore_collections.dart`. **AlphaSerena reads
or writes only the member-permitted subset (marked ✍️ = member writes, 👁 = member
reads, 🔒 = member has no direct access — go through a CF).**

```
Identity:    master_admins 🔒 · admins 🔒(via CF) · trainers 🔒(via CF) · clients 👁(own)
Membership:  membershipPlans 👁 · memberPayments 🔒(CF writes) · membershipCoupons 🔒(CF) · redemptions 🔒
Content:     exercises 🔒 · foodDatabase 🔒 · workoutPlans 🔒 · dietPlans 🔒 · weeklyWorkoutPlans 🔒
             → all plan content reaches the member via getMyTraining CF, NOT direct reads
Onboarding:  onboarding_questions 👁(read the form) · onboarding_responses ✍️(submit answers)
Member logs: client_workout_sessions ✍️ · client_diet_logs ✍️ · client_progress ✍️
Chat:        chats/{clientId}/messages ✍️👁
Profile:     organizationProfiles 👁(coach storefront) · clientProfiles ✍️👁(member's own app profile)
Feedback:    client_feedback ✍️ (member → coach complaints/feedback)
```

> The member's own training plans are resolved **server-side** by `getMyTraining` so
> the member needs NO read access to `workoutPlans`/`dietPlans`/`exercises`/
> `foodDatabase`. Do not try to read those directly — rules forbid it.

---

## 5. Cloud Function contract (current — as of 2026-06-28)

All are `onCall` (Firebase callable). Call via the `cloud_functions` package against
region **`us-central1`**. Names + params + returns:

### 5.1 `claimClientAccount()` — (no args)
Links the signed-in member's **verified phone** to a coach's `clients` doc (matches
several stored phone formats). Sets `clients.authUid` + writes `clientProfiles/{uid}`
`{linkedClientId, gymName, trainerName, clientName, goal}`. Idempotent.
Returns `{clientId, adminId, trainerId, gymName, trainerName, name}`.
Throws `not-found` if no record for this number (pre-purchase), `already-exists` if
linked to a different account.
> In the self-subscribe model the `clients` doc is usually **created by the purchase
> CF**, so claim mostly matters for legacy/coach-added members.

### 5.2 `getMyTraining()` — (no args)  ⭐ UPDATED since 2026-06-25
Resolves the member's most-recently-assigned workout + diet plan, fully enriched.
Returns `{workout, diet}` (either may be `null`).

```jsonc
workout: {
  name: string,
  items: [{
    name: string,
    sets: number,            // legacy summary count
    reps: string,            // legacy summary, e.g. "8-12"
    weight: string,          // legacy summary
    setRows: [{ reps: string, weight: string, rest: string }],  // ⭐ NEW per-set rows
    videoUrl: string, instructions: string, muscleGroup: string
  }]
}
diet: {
  name: string,
  items: [{
    name: string, quantity: string, calories: number,
    protein: number, carbs: number, fat: number,
    meal: string,            // ⭐ "Breakfast"|"Mid-morning"|"Lunch"|"Evening Snack"|"Dinner"|"Bedtime" (or "" legacy)
    grams: number|null,      // ⭐ NEW per-100g gram scaling
    portionLabel: string|null, portionQty: number|null   // ⭐ NEW named portion (e.g. "1 katori")
  }],
  targetCalories: number|null, targetProtein: number|null,  // ⭐ NEW optional per-plan daily targets
  targetCarbs: number|null, targetFat: number|null
}
```
**The `setRows` array is the source for the per-set "Coach Prescription" table
(§6.4).** When `setRows` is empty (legacy plan) fall back to the flat `sets/reps/
weight` summary. **The `meal`/`grams`/`portion*`/`target*` diet fields drive the
meal-grouped nutrition screen + target rings (§6.5)** — the current Diet screen
ignores them and must be upgraded.

### 5.3 Membership purchase (Tier-2 Razorpay)

- **`createMembershipOrder({ planId, couponCode? })`** → `{orderId, amount(paise),
  currency, keyId}`. Re-validates the coupon server-side; charges the discounted
  amount; writes a `pendingOrders/{orderId}` binding (anti plan-swap).
- **`verifyAndActivateMembership({ planId, razorpayOrderId, razorpayPaymentId,
  razorpaySignature })`** → `{ok:true, expiry}`. HMAC-verifies, idempotent,
  **creates the `clients` doc under the coach on first purchase** (self-subscribe),
  extends from `max(now, currentExpiry)`, writes a `memberPayments` receipt, and
  atomically records any coupon redemption. Writes `membership`,
  `membershipActive:true`, `membershipExpiry` (ISO string), `membershipFrozen:false`
  on the member's `clients` doc.

### 5.4 `previewMembershipCoupon({ planId, code })` — ⭐ NEW (live since 2026-06-27)
Member-authed coupon preview for the checkout coupon field (§6.3 step 3).
Returns `{valid:true, couponId, couponCode, discount, finalAmount, message}` or
`{valid:false, message}`. **AlphaSerena does NOT have a coupon input yet — this is a
gap (see §7).** Pass the same `couponCode` to `createMembershipOrder` to actually
charge the discounted amount.

### 5.5 (admin-only, not callable by members) `recordOfflineMembership`, all
TrainersHQ admin CFs — listed only so you don't accidentally call them.

---

## 6. THE COMPLETE DESIGN VISION (member app, screen by screen)

Source: the 9 design mockups in `TrainersHQ/assets/images/step1..step9.png` (the
AlphaSerena reference designs). This is the **intended** member app; build toward it.
Brand is dark/black with red `#D50000` accents, generous cards, rounded corners.

### 6.1 — STEP 1: Onboarding/Auth (3 screens)
- **Splash:** full-bleed athletic hero image, "ALPHAS ARENA" wordmark (A in red),
  tagline "TRAIN. TRANSFORM. TRIUMPH.", 3-dot carousel. *(Built; keep.)*
- **Phone login:** "Welcome to Alphas Arena / Your fitness journey starts here",
  country picker (+91 default) + mobile field, red **Send OTP** button, "or continue
  with → Need Help?" (headset), "Your data is safe with us" footer, **Skip** top-right.
- **Verify OTP:** shield icon, 6-box pinput, "Resend OTP in 00:30", **Verify &
  Continue**, "We never share your information" note. *(Real OTP already wired.)*

### 6.2 — STEP 2: Discover (coach/org list) — bottom-nav tab "Discover"
"Welcome, {name} 👋 / Find the best fitness organizations and start your
transformation." Notification bell (badge) + filter icon. **Search** bar
("organization, coach, or specialty…"). **Filter chips:** All / Gender ▾ / Location ▾
/ Specialization ▾. Section "⭐ Top Rated Organizations". **Org cards:** square brand
image + ⭐rating overlay, **Verified** badge (red shield), name, tagline, 📍city/state,
**stacked member avatars + "1.2K+ Clients"**, specialization chips (Strength
Training / Muscle Building / Fat Loss), heart (favorite) + red `>` arrow. Footer
banner "All organizations are verified and trusted". Bottom nav: **Discover · My Plans
· (+) · Messages · Profile** (center red + FAB).
> Data: `organizationProfiles` where `published == true`. Fields used: name, tagline,
> logoUrl/coverImageUrl, city, state, specializations[], rating, reviewCount, verified,
> stat strings (statClientsTrained etc.), handle. *(`coach_service.discover()` exists;
> the card design needs the full treatment.)*

### 6.3 — STEP 3: Coach storefront detail
Video hero (cover video w/ play button, 16:9, scrub bar) over the gym image; back +
favorite + share. **VERIFIED ORGANIZATION** label, logo tile, name + tagline,
📍location, ⭐rating + "(320 Reviews)". Specialization chips. **Stat band** (4 cols):
Clients Trained / Years Experience / Certified Trainers / Transformations (coach-typed
strings). **About** + a red pull-quote card. **Client Transformations** horizontal
before/after gallery (name + goal caption, "View All"). **What We Offer** icon grid
(Personalized Workout / Custom Nutrition / 1-on-1 Coaching / Progress Tracking / 24-7
Support). **Why Choose Us** check list + a red gradient "Ready to Start Your
Transformation? → **Choose This Organization**" CTA. Footer: Operating Hours / Contact
/ Follow Us (social icons).
> All fields already exist on `organizationProfiles` (TrainersHQ storefront authoring
> shipped them: coverVideoUrl, specializations, stat*, testimonial*, transformations[],
> whatWeOffer[], whyChooseUs[], operatingHours, socials, rating/reviewCount/verified).
> *(`CoachStorefrontScreen` exists but is much simpler than this.)*

### 6.4 — STEP 4: Membership purchase (6-screen flow) + STEP 6 of step4 success
1. **Plans screen** — coach plans as cards: "MOST POPULAR" ribbon on featured,
   name, "₹3,999 / 12 weeks", perk check-list, member avatars + "1.2K+ Clients
   Transformed". `membershipPlans` where `adminId == coach && isActive`.
2. **Plan details** — hero image, price, description, feature rows w/ icons, "Choose
   This Plan".
3. **Checkout** — plan summary, **Apply Coupon** field (→ `previewMembershipCoupon`,
   "FIT20 Applied! You saved ₹800"), Subtotal/Discount/Total, payment-method radio
   (Razorpay/Card/UPI), trust row, **Proceed to Pay ₹X**.  ⭐ **Coupon UI is a gap.**
4. **Razorpay** — native sheet (handled by SDK).
5. **Processing** — secure animation.
6. **Success** — green check + confetti, "Payment Successful! Welcome to {coach}",
   Order Details (plan/duration/amount/payment id/date), "What's Next?" checklist,
   **Go to My Plans** / Back to Home.
> Flow exists end-to-end except the **coupon input** + the polished success screen.

### 6.5 — STEP 5: Home dashboard (the daily hub) — tab "Home"
"Good Morning, {name}! 👋 / Ready to crush your goals today?" + bell + chat icon.
- **Trainer card:** trainer avatar (online dot), "Your Trainer {name}", specialization,
  **Message Trainer** | "Next Check-in {date/time}" + **View Trainer Profile >**.
- **Stat band:** Day Streak 🔥 / Plan Adherence % / Commitment Level / Member Since.
- **Today's Plan** (two cards): Workout (name, "6 Exercises · 18 Sets", "60-75 min",
  completion ring %, **Start / Continue Workout**); Nutrition ("Day 12 of Plan",
  "5/5 Meals Logged", logged ring %, **Log Meals**).
- **Today's Summary** grid: Calories / Protein / Water / Steps / Sleep / Weight
  (each value-of-target with a bar). ⚠️ **Water/Steps/Sleep are NOT in the backend
  yet** — see §7 (deferred or member-local).
- **Progress Overview:** Weight / Body Fat % / Muscle Mass / Plan Progress with
  since-start deltas.
- **Quick Actions:** Log Workout / Log Nutrition / Upload Photo / Add Note / View
  Progress. **Daily Motivation** quote + **Today's Tip**.

### 6.6 — STEP 6: Complete WORKOUT experience (the premium per-set flow)
Flow: **Overview → Exercise (sets view) → Rest Timer → Next Set → Cardio → Upload
Proof → Complete.** Exercise types render differently: **Warmup / Workout (sets+reps)
/ Cardio (time/distance/calories) / Cooldown**. Legend: Completed / Current / Pending /
Locked(upcoming) / Optional.
1. **Workout Overview:** Day Streak banner, "Push Day · 6 Exercises · 75-90 min",
   **Workout Summary** chips (Warmup 2 / Workout 4 / Cardio 1 / Cooldown 1),
   expandable sections per block, **Start Workout ▶**.
2. **Exercise – sets view:** video hero (play), "Exercise 2 of 6", a **read-only red
   COACH PRESCRIPTION table** (Set / Reps / Weight / Rest — from `setRows`), then
   **YOUR PERFORMANCE** accordion: only the **active set** open, "SET 1 OF 4", trainer
   target chips, **Reps Done + Weight Used** inputs, **Complete Set N**.
3. **Rest Timer overlay:** full-screen circular countdown ("01:30 Rest for 90
   seconds"), "Great Set! Set 1 Completed", "Volume Lifted 480 KG", **Skip Rest**.
4. **Next Set active:** `● ● ○ ○` sets-progress strip "2/4", completed sets collapse
   to "✔ 12 Reps · 40 kg", current set expanded, upcoming sets **locked**.
5. **Cardio session:** big elapsed timer "28:45", Target Time/Distance/Calories,
   pause/stop, "Tip from your trainer".
6. **Upload Proof (optional):** "Great job!", upload a screenshot/photo of the
   activity, **Complete Activity**.
> **Writes `client_workout_sessions`** (per-set prescribed-vs-actual) — see §6 data
> shape in §4 → details in the model contract §6.9 below. **This screen does not exist
> yet and is the single biggest build.**

### 6.7 — STEP 7: My Plans → NUTRITION plan + logging flow — tab "My Plans"
- **My Plans:** Workout Plan | **Nutrition Plan** tabs. "Current Nutrition Plan: Fat
  Loss Plan · Active · Day 12 of 42" progress bar. **Plan Overview** daily targets
  (Kcal/Protein/Carbs/Fats/Fiber). **Today's Progress** ring + macro bars.
- **Nutrition Plan:** week day-strip, **Daily Targets** cards (Kcal/Protein/Carbs/
  Fats/Fiber), **Today's Meals** list (Breakfast/Lunch/Pre-Workout/Dinner/Before Bed)
  each w/ kcal + P/C/F + fiber + a check ring (logged state).
- **Meal detail (e.g. Breakfast):** **Trainer Prescribed** food list w/ quantities,
  **Nutrition Information** (cal/P/C/F/fiber), **Instructions from Trainer**, **Your
  Log** (followed / time logged / note / photo), **View Full Day**.
- **Nutrition LOGGING flow (6 steps):** Select Meal → View Prescription → **Log Your
  Meal** (As Prescribed | **Custom Portion** w/ per-food portion adjusters) → **Add
  Note** (energy-level emoji + taste star rating + text) → **Upload Photo** → **Meal
  Complete** (green check, macro summary, "Back to Meals").
> Diet content comes from `getMyTraining.diet` (now meal-grouped w/ `meal`/`grams`/
> `portion*`/`target*`). **Writes `client_diet_logs`** (one doc/day, eaten/partial/
> skipped per food). **Replaces the in-memory `addMeal` mock.**

### 6.8 — STEP 8: Progress — tab "Progress"
"Track your daily actions, nutrition & results", month + year selectors. **Day-strip
calendar** (Completed ✓ / Partial / Missed ✗ / No Data, Today highlighted). Per-day
metric cards (Workout 6/6 / Nutrition 5/5 / Water / Steps / Sleep). **Workout Summary**
+ **Nutrition Summary** donuts. **Calories Over Time** line chart (toggle Calories /
Weight / Body Fat %). **Body Composition** (Weight/Body Fat/Muscle Mass/BMI/Visceral
Fat). **Daily Habit Consistency** bars, **Weekly Overview**, **Achievements** badges,
**Today's Log Overview**.
> Driven by `client_progress` (weight/measurements/photos) + aggregates over
> `client_workout_sessions` + `client_diet_logs`. **Body Fat/Muscle/BMI/Visceral/
> Water/Steps/Sleep/Achievements are NOT in the backend** — see §7.

### 6.9 — STEP 9: My Profile — tab "Profile"
Avatar + camera, name + edit, **Client ID (AS24567)** copyable, email/phone, **Trainer
card** (Message Trainer). Stat band: Member Since / Current Streak / Longest Streak /
Commitment Level. **Current Plan** + **Overall Progress** donut (Workout/Nutrition/
Consistency/Lifestyle %). **Body Metrics** (Weight/Body Fat/Muscle/BMI/Waist vs start).
**Achievements** badges. **Quick Actions** (Edit Profile / Change Password /
Notification Settings / Help & Support / Log Out). **Account Overview** (Total Workouts
/ Meals Logged / Photos Uploaded).

---

## 6.9 Member-write collection shapes (write these EXACTLY; rules enforce ownership)

Every member-write create rule requires, in the new doc:
`authorId`(or `authUid`) `== request.auth.uid`, AND a `get()` proving the target
`clients/{clientId}.authUid == request.auth.uid`, AND `adminId == clients/{clientId}.adminId`.
So **every write must include the correct `clientId` + `adminId`** (both available
from `MemberController` / `clientProfiles.linkedClientId` + the linked `clients` doc).
`delete` is always `false` (history preserved). `update` allowed only by the author and
may not change `authorId/authUid/clientId/adminId`.

### `client_workout_sessions/{autoId}` ✍️ (STEP 6)
```jsonc
{
  clientId, adminId, authorId: uid,
  planId, planName,
  date: <ISO or Timestamp>,
  entries: [{
    exerciseName, exerciseId,
    note?,
    sets: [{
      setNumber: int,
      prescribedReps, prescribedWeight, prescribedRest,   // copy from setRows
      actualReps, actualWeight,                            // what the member did
      completed: bool
    }]
  }],
  createdAt, updatedAt
}
```

### `client_diet_logs/{clientId}_{yyyy-MM-dd}` ✍️ (STEP 7) — one doc/day, deterministic id
```jsonc
{
  clientId, adminId, authorId: uid,
  planName, dateKey: "yyyy-MM-dd", date,
  adherencePct: number(0..1),   // optional; trainer side falls back to averaging item scores
  items: [{ foodName, quantity, calories?, status: "eaten"|"partial"|"skipped", note? }],
  createdAt, updatedAt
}
```

### `client_progress/{autoId}` ✍️ (STEP 8) — note `authUid` (not authorId)
```jsonc
{
  clientId, adminId, authUid: uid,
  date,
  weightKg?: number,
  measurements?: { waist: number, chest: number, ... },   // map<string,double>
  photoUrl?,            // Storage: progress_photos/{uid}/...  (rule already allows)
  note?,
  createdAt
}
```

### `onboarding_responses/{clientId}` ✍️ (post-purchase onboarding) — id == clientId, `authUid`
```jsonc
{
  clientId, adminId, authUid: uid,
  submittedAt, updatedAt,
  answers: [{
    questionId, question,            // SNAPSHOT the question text+type at submit time
    type,                            // "shortText"|"longText"|"number"|"singleChoice"|"multiChoice"|"photo"|"document"
    options: [..],                   // for choice types
    value                            // string | string[] | Storage URL (for photo/document)
  }]
}
```
> The form to render comes from `onboarding_questions` (👁 readable; one doc per
> question, has `text`, `type`, `options`, `required`, `order`). Photo/document
> answers upload to Storage (`onboarding_uploads/{uid}/**`, rule already deployed) and
> store the URL as the answer `value`.

### `client_feedback/{autoId}` ✍️ (Profile → Help/feedback to coach)
Member-write: `{ authUid: uid, adminId, clientId, category, rating, message,
anonymous?, requestTrainerChange?, status:"open", createdAt }`. Trainers CANNOT read
it (complaint privacy); the owning admin reads + responds.

---

## 7. THE GAP LIST (what to build / what needs backend) — prioritized

**Legend:** ✅ backend ready, build UI here · 🛠 needs a TrainersHQ backend change
first · 🟡 design-only field with no backend (defer or member-local).

| # | Feature | Status | Notes |
|---|---|---|---|
| 1 | **Per-set workout logging (STEP 6)** | ✅ build here | `getMyTraining.setRows` ready; write `client_workout_sessions`. Biggest build. |
| 2 | **Diet meal-grouping + targets + per-meal logging (STEP 7)** | ✅ build here | Upgrade Diet screen to use `meal`/`grams`/`portion*`/`target*`; write `client_diet_logs`. Replaces `addMeal` mock. |
| 3 | **Onboarding responses submit** | ✅ build here | Render `onboarding_questions`, write `onboarding_responses`. Currently only `clientProfiles` is written. |
| 4 | **Body-progress logging (STEP 8 core)** | ✅ build here | Write `client_progress` (weight/measurements/photo). Move off `clientProfiles.weightLog`. |
| 5 | **Coupon input at checkout (STEP 4.3)** | ✅ build here | `previewMembershipCoupon` is live; add the field + pass `couponCode` to `createMembershipOrder`. |
| 6 | **Discover + storefront rich design (STEP 2/3)** | ✅ build here | All `organizationProfiles` fields exist; rebuild cards/detail to the mockups. |
| 7 | **Home dashboard rich design (STEP 5)** | ✅ partial | Trainer card / streaks / Today's Plan rings; some sub-metrics are 🟡. |
| 8 | **In-session membership expiry re-gate** | 🛠 | `getMyTraining` should refuse when membership expired/frozen (server check) — change in TrainersHQ. |
| 9 | **Water / Steps / Sleep tracking (STEP 5/8)** | 🟡 | No backend. Either defer, or store member-local/`clientProfiles`. Decide before building those cards. |
| 10 | **Body Fat % / Muscle Mass / BMI / Visceral / Achievements / Streaks** | 🟡 | No backend fields. Body Fat/Muscle could ride in `client_progress.measurements`; BMI derivable from weight+height; achievements/streaks need a design + store. Decide scope. |
| 11 | **Reviews / ratings WRITE** | 🛠 | Storefront shows rating/reviewCount (read-only, platform-controlled). Member WRITING a review needs a new collection + CF — not designed. Out of scope unless requested. |
| 12 | **Notifications (bell badges)** | 🛠 | FCM exists on the coach side; member push not wired. Defer. |

> **Anything marked 🟡/🛠 is a design decision for the user before building** — don't
> silently invent backend. The ✅ items are the real near-term work and match what
> TrainersHQ already deployed for.

---

## 8. Design system / brand (shared with TrainersHQ)

- **Palette:** **black + red only.** Accent `#D50000` (buttons/active/icons), bright
  red `#FF1744` reserved for error/expired, deep `#7A0000`. Near-black bg `#0E0E0E`.
  Dark-first with a light toggle. (TrainersHQ removed the orange/amber gradients —
  match that: **no orange/yellow**.)
- **Type:** the mockups use a clean sans; AlphaSerena currently uses Poppins. Keep
  AlphaSerena's existing `AppText` tokens — don't re-theme mid-build unless asked.
- **Surfaces:** frosted/glass cards, 1px subtle border, rounded corners (14 inputs/
  buttons, 16-18 cards, 20 bottom nav), soft black shadows (no colored glow).
- **Bottom nav (final, from mockups):** **Home · My Plans · Progress · Chat ·
  Profile** for the *member dashboard*; the *Discover* surface (pre-join) uses
  **Discover · My Plans · (+) · Messages · Profile**. Reconcile: Discover is the
  entry/marketplace; once a coach is joined the daily app is the 5-tab dashboard.
- Centralize tokens in `lib/core/theme/` (already done). Never hardcode hex/fonts.

---

## 9. Coding rules (from AlphaSerena CLAUDE.md — still apply)

1. Mirror `FsCollections` names; never hardcode collection strings.
2. GetX: `Get.find<X>()`, shared controllers registered once (permanent). Delete
   member-scoped controllers on sign-out (multi-user device safety).
3. `debugPrint()` only — no `print()`.
4. Defensive `fromMap` (handle `Timestamp | String | num`) like TrainersHQ models.
5. Every screen: loading + empty + error states.
6. **Financial/sensitive actions go through a Cloud Function** — never write
   membership/expiry/payment directly.
7. `.withValues(alpha:)` not deprecated `.withOpacity()`.
8. `flutter analyze` clean after every change.
9. One thing at a time; report back after each step.

---

## 10. Recommended build order (member side)

Each item: brainstorm (if non-trivial) → build → `flutter analyze` → report.

1. **Diet upgrade (STEP 7 read side):** make the Diet/My-Plans screen consume the new
   meal-grouped `getMyTraining.diet` (meals, grams/portions, daily targets + rings).
   Pure read; low risk; unblocks the logging UI.
2. **Diet logging (STEP 7 write side):** per-meal adherence → `client_diet_logs`.
3. **Per-set workout flow (STEP 6):** the big one — overview → sets view → rest timer
   → cardio → proof → `client_workout_sessions`.
4. **Progress (STEP 8 core):** `client_progress` logging + trend/before-after using
   the existing chart widgets ported from TrainersHQ patterns.
5. **Onboarding responses:** render `onboarding_questions` + submit
   `onboarding_responses`.
6. **Checkout coupon (STEP 4.3):** `previewMembershipCoupon` field.
7. **Discover + storefront polish (STEP 2/3), Home polish (STEP 5), Profile (STEP 9).**
8. Decide 🟡 items (water/steps/sleep, body-composition, achievements) with the user.

---

## 11. Backend changes that must be made *in TrainersHQ* (not here)

Track these; they are the only items requiring a TrainersHQ deploy:

- **`getMyTraining` membership gate** (gap #8): refuse/empty when the caller's
  membership is expired or frozen, so content is blocked mid-session.
- **Any 🟡 metric you decide to ship** (body composition, achievements/streaks,
  water/steps/sleep) that needs a real field/collection or aggregation CF.
- **Reviews write path** (gap #11) if ever in scope: a `reviews` collection + a CF
  that recomputes `organizationProfiles.rating`/`reviewCount`.

Everything else in §6/§7 marked ✅ is already deployed and ready for the member app to
consume.

---

*End of handoff. Update §3/§7/§10 as AlphaSerena sections complete; keep the §5/§6.9
contract in sync if TrainersHQ changes a CF or a member-write shape.*
