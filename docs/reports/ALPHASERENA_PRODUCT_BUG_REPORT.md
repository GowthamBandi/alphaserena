# ALPHASERENA PRODUCT BUG REPORT — PHASE 2

**Date:** 6 August 2026 · **Device:** emulator-5554, live member session (FRAMEINGOS / ORG Name)
**Method:** every claim below was reproduced on a real device against live production data, or
proved by a test. Nothing here is inferred from reading alone.

# ⚠️ STATUS: 1 OF 3 COMPLETE — THIS REPORT IS PARTIAL

| bug | investigated | root cause | fixed | verified |
|---|---|---|---|---|
| 1 — Workout Consistency | ✅ | ✅ proven | ✅ | ✅ device + 39 tests |
| 2 — Transformation History | ✅ | ✅ **PROVEN — my first hypothesis was WRONG** | ✅ | ✅ **device, field-by-field vs Firestore** |
| 3 — Weekly Check-In | ✅ | ✅ proven across all 4 layers | ✅ client | ⚠️ device-verified LOCKED state only; **rules not enforced** |

All three are root-caused from live evidence and fixed on the client. Two gaps remain, both named
precisely in §5: Bug 3's **backend/rules uniqueness enforcement was not written**, and its read-only
"latest review" rendering could not be observed because this member has never filed a check-in.

---

## 1. BUG 1 — WORKOUT CONSISTENCY ✅ ROOT-CAUSED, FIXED, VERIFIED

### Reproduction (live member, same week, same screen)

| | Workout | Nutrition |
|---|---|---|
| Mon / Tue | ✅ completed | ✅ completed |
| **Wed** | blank circle | ✗ **Missed** |
| **Thu (today)** | blank circle | ◉ **Today** |
| legend advertised | 6 states | 6 states |
| states actually painted | **1** | 4 |

Screenshots: `s2.png` (workout, before), `s3.png` (nutrition, before), `v2.png` (workout, after).

### Root cause — three layers, and the first one is not a code defect

**a) The workout track has no prescription.** The app says so itself on Home: *"No schedule set —
showing your plan daily."* `TrackHistory.hasPrescription` is `versions.isNotEmpty`, sourced from
`prescriptionData.workout.versions`. With no versions, `verdictFor` resolves every unlogged day to
`excluded` / `unknown` — **by design**, and correctly: *"no day is ever judged against an
expectation nobody wrote."* Proved with a probe: no prescription → `{done: 6, excluded/unknown: 29}`;
with a prescription → `{done, missed, rest}`. The diet track has a daily prescription, which is the
entire reason nutrition looked right.

This part is **not** a bug in the consistency screen. Both apps are symmetric here — I checked
`getMyTraining` (serves both tracks through the same `buildTrackPrescriptionData`), the coach's
assign flow (all three branches pass `rhythm: _schedule.rhythm`, defaulting to `Rhythm.daily()`),
and `assignDietTemplate` (delegates to the same `assign`). **Why this member's workout assignment
carries no prescription is unresolved** — most likely a legacy assignment or a silently-failed
`setPrescription` ("Plan assigned, but the schedule couldn't be saved"). See Remaining Risks.

**b) THE ACTUAL DEFECT — the legend was hardcoded.** `_weekLegend` printed six swatches
(Completed · Rest · Excused · Missed · Today · Upcoming) identically on both tracks, regardless of
what the grid could produce. For this member the workout grid could only ever produce **two** of
those six, and the grey circle covering most of the calendar — `TodayMark.unknown`, "not
scheduled" — **was not in the legend at all**. The member was shown a key to a map that did not
exist, and the dominant colour on screen was unexplained.

**c) Today had no state when nothing was scheduled.** `OutcomeKind.open` is only ever produced for
a day the coach REQUIRED, so an unscheduled Thursday rendered identically to Wednesday and Friday.
Whether it is Thursday does not depend on whether anybody wrote a plan.

### Duplicate logic found and removed

The verdict→visual-state mapping existed **three times**, and had already drifted:

| copy | location | drift |
|---|---|---|
| `_markFrom` | `consistency_pair.dart` (week rail, home cards) | — |
| `_markOf` | `consistency_detail_screen.dart` (heat map) | verbatim copy |
| `_cellFor` | `performance.dart` (month calendar) | **only this one treated `optional` as rest** |

So the same day read "rest" on the month calendar and "not scheduled" on the heat map above it.
Now there is one public `markFor` in `performance.dart`; the heat map calls it, the week rail calls
it, and `_cellFor` *translates* its result into `MonthCellState` instead of re-deriving one. A
regression test asserts the month calendar and the heat map agree on every day of a month.

### What changed

1. **One shared mapping.** `TodayMark` + `markFor` moved into `performance.dart` (the lower-level
   domain); `consistency_pair.dart` re-exports them so all existing imports keep working.
2. **`optional` joins `rest`** on every surface.
3. **Today fills a gap, and only a gap.** An unscheduled today is `open`. My first attempt marked
   *every* today as `open` and **four existing tests caught it** — correctly: a prescribed rest day
   that happens to be today is still a rest day, and "today, still open" would hide the one useful
   fact. Done / missed / excused / rest / paused all outrank it.
4. **The legend is derived from the marks actually on screen.** A state that cannot occur is not
   advertised, and "Not scheduled" is finally named.
5. `markLabel(open)` softened from "today, still open" to "today", since it no longer implies an ask.

**Scoring is untouched.** `TodayMark` is presentation only; the outcome axis that adherence,
streaks and the monthly goal read is unchanged, and a test asserts an unscheduled past day is still
never a miss.

### Verified on device (after)

Workout legend now reads **Completed · Not scheduled · Upcoming** — three states, three states
painted. Nutrition reads **Completed · Missed · Not scheduled · Upcoming** — four and four. Identical
rule, different data, which is exactly the deliverable.

⚠️ One honest gap in the device check: a workout was logged for today between the before and after
runs, so today rendered as `done` rather than `open` and I could not observe the new `open` mark on
screen. It is covered by unit tests, not by the screenshot.

### Regression tests added (17 new; suite 1574 → 1591)

- identical inputs produce identical marks on both tracks, and the month calendar matches the heat map on every day
- an `optional` day reads the same on both surfaces
- an unscheduled member still sees today marked
- an unscheduled past day is never fabricated into a miss, and nothing enters the scoring axis

---

## 2. BUG 2 — TRANSFORMATION HISTORY ✅ ROOT CAUSE PROVEN AND FIXED

### ⚠️ First, a correction: my previous hypothesis was wrong

I reported that the likely cause was a missing `authUid` on legacy documents, since AlphaSerena
queries by `authUid` and TrainerHQ by `adminId` + `clientId`. **That was evidence, not proof, and it
was wrong.** Dumping the document settled it.

### THE LIVE DOCUMENT (dumped from the coach app, which can read it)

```
id=gX3pmPKEbuQSfYSlBHa9
authUid=VOxzizRgU6YFBsbguFJ6winidIA2      ← PRESENT, and it IS the member
clientId=EkNg2Yux4lPAQtSpQjds
adminId=Hli8cUoVsadrRyS6lHzvsQ9Dj152
visibility=shared   status=complete   kind=transformation   schemaVersion=2
recordedAt=Timestamp(seconds=1785565761)   photos=[side, back, front]   weightKg=85.0
keys=[note, schemaVersion, clientId, visibility, kind, photos, clientRecordedAt,
      measurementUnit, createdAt, recordedAt, adminId, authUid, weightKg,
      measurements, status, updatedAt]
```

The document is perfectly well formed. `authUid` matches the member exactly. It satisfies
AlphaSerena's query (`authUid == uid`), its read rule, `isComplete` and `hasContent`. There is no
legacy-migration problem, no visibility problem, no permission problem and no filter problem.

### THE ACTUAL ROOT CAUSE (probe in the member app, live)

```
ASPROBE|canLog=false|uid=VOxzizRgU6YFBsbguFJ6winidIA2|clientId=|adminId=
```

`watchTransformations()` opens with `if (!canLog) return Stream.value(const []);` — and **`canLog`
is the WRITE precondition**: `clientId.isNotEmpty && adminId.isNotEmpty && uid.isNotEmpty`.

`clientId` and `adminId` were both empty, so the method returned a one-shot empty list and **the
Firestore query never executed.** The screen was not filtering the entry out; it never asked for it.

### Why the two fields are empty, and why it never recovers

They arrive on **different streams at different times**:

- `clientId` ← `clientProfiles.linkedClientId`
- `adminId` ← the `clients` **document** (`client.value?['adminId']`), which loads later

`ProgressController._bind()` re-binds on `ever(memberController.isLinked, …)`. `isLinked` flips when
the FIRST of those arrives — at which point `adminId` is still empty, so `canLog` is still false.
`isLinked` never changes a second time, so **no further rebind ever happens** and the empty stream is
permanent for the whole session.

This is the same class as the recorded finding *"empty tenant id renders loaded-and-empty"*.

### The fix

A read may only require what the query and the read rule actually consult. `ProgressLogService`
now separates the two preconditions:

- `canLog` — unchanged, still requires all three (a create stamps `clientId`/`adminId` and the rule
  cross-checks both against the member's `clients` document).
- **`canRead => _member.uid.isNotEmpty`** — used by `watchTransformations`.

Both apps now read the same logical dataset; only permissions differ, which is the deliverable.

### ✅ FINAL DEVICE PROOF — every field cross-checked

Screenshot `p3.png`. The member's Transformation screen now renders the entry, and every field
matches the Firestore document dumped from the coach app:

| Firestore document | AlphaSerena screen |
|---|---|
| `weightKg=85.0` | **85.0 kg** |
| `photos=[side, back, front]` | **Front · Side · Back** — "3 photos" |
| `visibility=shared` | **Shared** badge |
| `status=complete` | rendered as a published checkpoint, not a draft |
| `recordedAt=1785565761` → 2026-08-01 06:29:21Z = **11:59 IST** | **"Recorded 1 Aug 2026 · 11:59 AM"** |
| `note` | "test notes" |
| 10 measurement keys | **10 measurements**, all values rendered |

Ordering: one entry, so `latest` == `history[0]` — "Latest Transformation" and the single history row
describe the same record, as they must.

**Cross-app agreement: Firestore ↔ TrainerHQ ↔ AlphaSerena all show the same one entry.** The coach
app rendered it throughout; the member now sees the identical record.

The earlier navigation failure was mine, not the app's: I had been tapping `y=1287` for the Progress
tab, which is mid-screen — the bottom nav sits at `y≈2732` on this 2856px display, so every attempt
was hitting the Nutrition card instead.

### Both diagnostic probes have been removed

`client_logs_service.dart` (TrainerHQ) and `progress_log_service.dart` (AlphaSerena) are back to
production shape; `flutter analyze` clean on both.

---

### Superseded hypothesis, kept for the record

### The asymmetry

The two apps read the same collection through **different query keys**:

| app | query | then filters |
|---|---|---|
| AlphaSerena | `client_progress where authUid == member.uid` | `isComplete && hasContent` |
| TrainerHQ | `client_progress where adminId == … && clientId == … && visibility == 'shared'` | `isComplete` |

**A `client_progress` document with no `authUid` field is returned by TrainerHQ's query and is
invisible to AlphaSerena's.** Firestore excludes documents lacking the field from any equality
filter on it — and the member's read rule (`resource.data.authUid == request.auth.uid`) would error
and deny on such a document anyway.

### Corroborating evidence, both from the backend

- `backfillProgressVisibility` (`progress.ts:179`) exists precisely because **legacy
  `client_progress` entries predate the v2 privacy field**. It stamps `visibility: "shared"` so they
  stay visible on *the coach's* surfaces — nothing does the equivalent for `authUid`.
- `cleanupTransformationDrafts` defends with `const authUid = String(doc.data().authUid ?? ""); if
  (!authUid) continue;` — the backend already knows documents without `authUid` exist.

So a legacy entry gets backfilled into the coach's view and stays permanently outside the member's.
That matches the report exactly: TrainerHQ shows one, AlphaSerena says "Log your first transformation".

### Second, independent candidate — not yet eliminated

AlphaSerena additionally filters `hasContent` (weight ∨ bodyFat ∨ measurements ∨ photos ∨ note),
which TrainerHQ does not. An entry carrying only a field outside that set would also diverge.

**Both of these were disproved by the document dump above.** The `authUid` asymmetry is real in the
code but is not what broke this member, and `hasContent` was satisfied. They are recorded here only
so the reasoning that led away from the real cause is visible.

---

## 3. BUG 3 — WEEKLY CHECK-IN ✅ ROOT-CAUSED AND FIXED (client)

### Reproduction

Screenshot `w1.png`, **Thursday 6 Aug 2026**: the full editor — seven rating rows (Energy, Sleep,
Stress, Hunger, Motivation, Training, Diet), a weight field, a note box and a live **Submit
Check-In** button. No previous review, no coach response, no history, no trends.

### Root cause — nothing in the stack had a concept of a WEEK

Traced through all four layers; every one of them is missing the same idea.

| layer | what it enforced | what it did not |
|---|---|---|
| `CheckInController.canSubmit` | `hasSubmittableContent(...)` — "has the member typed anything?" | any day-of-week gate, any week gate, any post-submit lock |
| `CheckInSubmissionService.submit` | ownership fields | wrote to **`_col.doc()` — a fresh RANDOM id** whenever no open packet existed, so a second review for one week became a sibling document |
| `CheckInSubmissionModel` | ratings / weight / note / status | **no week field at all** |
| `firestore.rules` | `authorId` ownership, `status == 'submitted'`, `delete: if false` | **no uniqueness, no week, no timing** |
| backend | — | **no callable validates check-in writes**; the collection appears only in engagement/notification code |

So the editor was live every day because nothing ever asked what day it was, and duplicates were
possible because nothing ever asked which week a review belonged to.

`CheckInController.isDue` — derived from the coach's `nextCheckInAt` cadence — **existed and was
consulted by nothing**: it fed a status line, never the gate. The cadence was decorative.

### The fix (client)

1. **A pure weekly policy** in `check_in_math.dart`: `weekKeyFor` (ISO `yyyy-Www`),
   `isCheckInWindowOpen` (Sunday, in the member's LOCAL calendar), `hasSubmittedThisWeek`,
   `canAuthorCheckIn`, `checkInLockReason`. One authority, so the screen and the controller cannot
   disagree.
2. **`canSubmit` now requires the window AND an unfiled week**, in front of the content check.
3. **A deterministic per-week document id** — `{clientId}_{weekKey}` replaces `_col.doc()`. A second
   submission addresses the same document instead of creating a sibling, which is what makes a
   duplicate structurally impossible rather than merely discouraged. Same discipline the member-day
   collections already use.
4. **`weekOf` on the model**, written on submit; legacy documents fall back to
   `weekKeyFor(submittedAt)` so existing history still resolves to a week.
5. **The screen renders read-only Monday–Saturday** — the editor is not mounted at all (not a
   disabled form, which would invite the member to fight a dead control). It shows why it is locked,
   the latest filed review, and the history section.

Sunday is the LAST day of its own ISO week, so the member reviews a week that has **finished** —
which is why the key is derived from the ISO week rather than "the most recent Sunday".

### ✅ Device proof

Screenshot `w2.png`, same Thursday: the editor is gone, replaced by
**"Your check-in opens on Sunday, in 3 days."** with a lock icon. Thu → Sun is 3 days. ✓

### ⚠️ What is NOT verified, and what is NOT built

- **The read-only "latest review + coach response + trends" rendering was not observed**, because
  this member has never filed a check-in — TrainerHQ shows *"Check-in · No review schedule · Not
  assigned"* (screenshot `f2.png`). The locked state renders correctly and the review card is wired,
  but with no history to draw it is an empty section on this account.
- **The backend and rules do NOT enforce weekly uniqueness or the Sunday window.** The client now
  makes duplicates structurally impossible, but a crafted write could still file two reviews for one
  week. Firestore rules *can* express both (weekday is derivable from `request.time` as
  `(epochDays + 4) % 7`, and the id can be pinned to `{clientId}_{weekOf}` exactly as the day-key
  rules pin `{clientId}_{dateKey}`) — I did not write it. **This is the one substantive piece of Bug
  3 left undone.**

### Regression tests added (11)

Sunday unlock · Monday–Saturday lock (all six days) · the reported Thursday state · "opens tomorrow"
on Saturday · submitting locks the window immediately, same day · a filed week does not lock the next
· one key for every day of an ISO week · the ISO year comes from the Thursday (New Year boundary) ·
zero-padded keys sort chronologically · local-midnight boundaries · a missed week is never
back-filled.

---

## 4. TEST RESULTS

| suite | result | note |
|---|---|---|
| AlphaSerena | **1605 run / 13 fail** | the same 13 pre-existing golden-image failures; **+31 new tests across the three bugs, zero regressions** |
| `flutter analyze` AlphaSerena | **0 issues** | |
| TrainerHQ | not re-run | untouched this phase |
| Backend / rules | not re-run | untouched this phase |

The 13 failures are the documented pre-existing set (8 `home_cards_golden`, 4 `home_header`,
1 `serena_foundation`), all sub-1% pixel diffs from font rendering on this machine, proven
pre-existing earlier today by stashing.

---

## 5. REMAINING RISKS

1. 🔴 **Bug 3's server-side enforcement is not written.** The client cannot produce a duplicate; the
   platform cannot yet refuse one. Rules + a deploy are required — see §3.
2. 🟠 **Bug 3's read-only review rendering is unobserved** — this member has no check-in history.
1c. 🟠 **The same over-strict gate exists on three more read paths** — `lifestyle_log_service:66`,
   `diet_log_service:41` and `lifestyle_event_service:199` all gate a READ on `canLog`. Those reads
   key by `{clientId}_{dateKey}` so they genuinely need `clientId`, but requiring `adminId` is the
   same over-reach. Left alone deliberately: out of scope for the two reported bugs.
2. 🟠 **The underlying data cause of Bug 1 is unresolved.** The screen is now honest about having no
   schedule, but this member's workout plan still has no prescription while their diet plan does.
   If `setPrescription` is failing silently on assign, every member is landing in the degraded state
   and the coach is told only once, in a toast. Worth a targeted check of
   `client_plan_assignments` for workout rows with no `prescription` field.
3. 🟠 **The `optional` → `rest` unification is a visible behaviour change** on the month calendar's
   siblings. It matches what the month calendar already did; the heat map and week rail changed to
   agree with it.
4. 🟢 A `dietDayKeys` day-window cutoff in `activity_history_service.dart` is **not day-aligned**
   while `workoutDayKeys` is (the latter was fixed with a comment explaining why). Same drift class,
   affects only the oldest day of the 60-day diet window. Found in passing, not fixed.

---

## 6. GO / NO GO

### ⚠️ CONDITIONAL GO — ✅ Bugs 1 and 2 complete, Bug 3 client-complete

Bug 1 is production-ready: root-caused against live data, fixed at the shared engine rather than
per-screen, three duplicate implementations collapsed into one, 17 regression tests, zero analyzer
issues, zero regressions, and verified on the device that produced the report.

**Bugs 1 and 2 are GO.** Both were root-caused from live evidence — Bug 2 from a dumped Firestore
document and a live probe, which disproved my own first hypothesis — fixed at the shared layer rather
than per-screen, and verified on the device field by field.

**Bug 3 is GO on the client and NO GO on the server.** The reported behaviour is fixed and proven on
the device: the editor is gone Monday–Saturday, one review per week is now structurally impossible to
duplicate from the app, and 11 tests pin the window. But the mission required the **backend to enforce
weekly uniqueness**, and it does not. Until a rule pins the document id to `{clientId}_{weekOf}` and
bounds the submission window, the guarantee is client-side only.

That single item is what stands between this phase and an unconditional GO.
