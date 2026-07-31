# Prescription Engine — Phase 3 Certification (Member Experience)

- **Date:** 2026-07-28
- **Delivered:** AlphaSerena now RENDERS what the coach actually prescribed.
  The member always knows what today asks of them: workout day, rest day,
  flexible week, cycle day, exception day, excused day, or paused coaching.
- **Scope held:** no backend changes, no analytics, no TrainerHQ redesign.
  TrainerHQ and the backend are byte-identical to their Phase 2 state.
- **Nothing committed. Nothing deployed.**

---

## 1. What changed

### The one structural change
`getMyTraining`'s `expectation` field (Phase 2) was being **discarded at the
door** — `TrainingController` read only `workout`/`diet`/`coach`. It now:

- sends the member's **local day** (`localDate`) — without it an IST member at
  11 pm was served the UTC day's (i.e. tomorrow's) expectation;
- parses `expectation` into `TodayExpectations` / `ServedExpectation`
  (new pure module `lib/core/domain/today_expectation.dart`);
- re-fetches on day rollover (`ensureFreshDay`, hooked into the dashboard's
  existing resume guard) so yesterday's "rest day" can never survive into a
  training morning.

### The single decision point
`todayWorkoutPresentation(...)` — one pure, unit-tested function — maps
(expectation × plan-present × done-today × week-progress × coach name) to the
exact words and mode Home renders. The widget is a dumb switch. The full
matrix:

| Today is… | Member sees | CTA |
|---|---|---|
| Required (daily / weekday / cycle-ON) | Today's Workout hero, as before | Start Full Workout |
| Rest (rhythm or rest-type exception) | **"Rest day"** — a calm, positive card, coach named, note shown, reason chip (Travel / Deload week / Gym closed / Coach exception) | quiet "Train anyway" link — bonus, never owed |
| Rest, but they trained | "Rest day — and you trained anyway" (bonus, celebrated) | — |
| Flexible week (any N/week) | "Your Training" + **"X of N sessions done this week — you pick the days"**; ≥N → "You've hit all N… anything more is bonus" | Start a Session |
| Optional (refeed / deload replacement) | "Optional today" + coach note | Start a Session |
| **Excused by coach** | "Today is excused — it won't count against you" (outranks every other state) | quiet "Train anyway" |
| Paused (any level) | "Coaching paused" + coach note + reason chip; "your streak is safe" | none — zero pressure |
| Not started yet | "Your plan hasn't started yet" | none |
| Ended | "Plan finished — ask {coach} for your next one" | none |
| Unknown (no schedule set) | the legacy daily card **plus the disclosure** "No schedule set — showing your plan daily." | unchanged |
| No expectation served (old backend / error) | **the pre-Phase-3 UI byte-for-byte** — deploy-order safe, offline safe | unchanged |

Week progress ("X of N") counts **logged sessions** from the day-key sets the
app already holds — an outcome, never an invented schedule.

### Supporting changes
- **Consistency cards:** on a day the coach did not ask for training (rest /
  paused / excused / flexible / not-started / ended), an unlogged workout card
  now reads **"Rest day"** (self-improvement icon), never "Pending today" —
  resting on a rest day is the plan working. Logged still wins ("Logged
  today"). Defaults unchanged → all four goldens still pass untouched.
- **Nutrition Today:** quiet by design — only pause ("log if you like,
  nothing counts against you") and coach-declared optional/refeed days add a
  note line; every other day renders exactly as before.
- **Workout screen:** one line under the plan name states what today asks of
  it ("Rest day today — prescribed by your coach", "Flexible week — any 4
  sessions…", "Coaching is paused…"), so it can never contradict Home.
- **`HomeController.workoutName`** no longer falls back to `'Rest Day'`.

## 2. Assumptions removed (the audit's findings)

1. **"Every day is a workout day."** Home's card now renders the served
   expectation; the daily assumption survives only inside the disclosed
   `unknown` fallback, where it is labelled.
2. **`workoutName ?? 'Rest Day'`** — a fabricated prescription (nobody
   prescribed rest; the plan was merely null). Removed.
3. **Empty item list ⇒ "Active Recovery / Rest Day"** — inference presented
   as prescription. Now shown **only** when no expectation was served (legacy
   backend); when the server answered, an empty plan is "waiting for your
   coach", and rest is only ever claimed when prescribed.
4. **"Pending today" on every unlogged day** — now suppressed on days nothing
   was asked.
5. **The server resolves "today" from its own clock** — the app now sends the
   member's local day.

## 3. Bugs found

1. **Timezone day-shift (real, user-facing):** with no `localDate` sent,
   every getMyTraining call resolved "today" as the UTC day — for India,
   tomorrow's expectation from 5:30 am UTC-offset onward of every evening.
   Fixed by sending the local day key (server clamps to ±1 day).
2. **Stale-day expectation after overnight resume:** the served expectation
   carried no rollover guard; a phone left open overnight would show
   yesterday's state. Fixed via `ensureFreshDay` on app resume.
3. **The `'Rest Day'` null-fallback** in `HomeController.workoutName`
   (§2.2) — the exact "invented prescription" the freeze forbids.

## 4. What was improved beyond the letter of the mission

- The rest-day screen is a **positive state** (the freeze's highest-value new
  state): coach named, note verbatim, reason chip, bonus-training celebrated.
- Coach notes always win over generated copy, so the member reads their
  coach's words, not the platform's.
- Every new state is decided in pure functions with a full unit-test matrix —
  the UI cannot drift from the tested truth.

## 5. Verification

| Check | Result |
|---|---|
| `flutter analyze` (alphaserena) | **No issues** |
| `flutter test` (alphaserena) | **392 / 392** (367 + **25 new**) |
| Debug APK (`flutter build apk --debug`) | **Built** (`app-debug.apk`) |
| Consistency-card goldens | **Unchanged and passing** (defaults preserved) |
| TrainerHQ / backend | **Untouched** — Phase 2 verification stands (986/986 · 558/558 · rules 202/202) |

**Matrices, and how each is proven:**
- *State matrix* — every `ExpectationKind` × plan × done × excused pinned in
  `test/today_expectation_test.dart`.
- *Edge cases* — junk kinds, unreadable maps, missing fields parse to null
  (never a default); tested.
- *Offline / legacy* — a failed or pre-Phase-2 response leaves `expectations`
  null → the pre-Phase-3 UI renders byte-identically; tested (`legacy` cases).
- *Refresh* — expectation rides the exact channel content already rode (open,
  Home reload, pull-to-refresh, retry) — no new sync path to break; plus the
  rollover guard.
- *Timezone* — local day key sent; server clamping was pinned in Phase 2's
  suite (`clampLocalDate ±1`).
- *Future / exception / pause matrices* — resolved SERVER-side and pinned by
  Phase 2's 34 domain tests; this phase only words them, and those words are
  pinned here.

**Coach ↔ member cross-check:** TrainerHQ makes no claim about "today's
session" anywhere — its schedule surfaces render the same server-owned
`prescription` block the member's expectation is resolved from, so no screen
pair can disagree about today. (Its consistency block, which would make
day-level claims, is deliberately a later phase.)

**Self-challenge (the personas):** the 3-day/week member and the online
"4 sessions/week" client — the two personas the old Home actively misled —
now see rest days and week-framed progress respectively. The Ramadan /
travel / deload member sees the coach's own note. The returning-after-injury
member sees "Coaching paused… your streak is safe". The first-time member
with no schedule sees the same screen as before plus one honest line. No
persona is shown a demand on a day nothing was asked.

**Said plainly — not machine-verified:** no human has exercised these flows
on a device; the APK is built, not manually driven. `ensureFreshDay`'s
Firebase-touching path and the Home widget tree itself have no widget tests
(the screen constructs five Firebase-backed controllers; the extraction
pattern used for the tested pure pieces is the path to fixing that, later).
One live end-to-end run — coach sets Mon/Wed/Fri → member's Wednesday and
Thursday screens — is owed before calling this production-proven.

## 6. What still needs later phases

1. **Consistency & calendar rebuild** — `summarise`/`calendar` still receive
   `schedule: null`, so the 30-day grid and rates still treat every past day
   as expected. Fixing history needs per-day expectations for past dates
   (version history), which today's serving layer deliberately does not
   provide — the next major milestone, on `verdictFor`/`weekVerdict`.
2. **"Starts {date}" / "ends {date}"** — the served expectation carries no
   dates, so `notYetStarted`/`ended` speak without them. Needs one additive
   serving field (backend was out of scope this phase).
3. **TrainerHQ today-line** — the coach's plan card shows the base rhythm and
   not a currently-active exception; a "today: rest (travel)" line would
   mirror the member exactly.
4. **Excuse-day timezone edge** — the coach excuses their local date, the
   member reads their own; differing timezones could mismatch (not an Indian
   deployment concern; noted).
5. Reminders, analytics, cardio track, AI — as sequenced in Phase 2's §11.

---

*Verified 2026-07-28: analyze clean · 392/392 (25 new) · goldens unchanged ·
debug APK built · TrainerHQ/backend untouched. Nothing committed.*
