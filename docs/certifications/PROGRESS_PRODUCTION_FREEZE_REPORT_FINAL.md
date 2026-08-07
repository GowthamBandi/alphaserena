# PROGRESS — PRODUCTION FREEZE REPORT (FINAL)

**Date:** 2026-08-04
**Repositories:** `alphaserena`, `trainersHQ`, `trainershq-backend`
**Device:** emulator-5554 (`sdk_gphone16k_arm64`, Android 16, 1280×2856 @ 480dpi), live Google-signed-in member
**Scope:** the Progress module — Overview, Analytics, Insights, History, Achievements, Transformation, Weekly check-in, Schedule.

This report supersedes `PROGRESS_PRODUCTION_FREEZE_REPORT.md`. Per Rule 1, nothing in that
document was taken as evidence; every claim below was re-derived from the current working tree,
the running emulator, or a suite executed in this engagement.

---

## 0. WHAT THIS ENGAGEMENT ACTUALLY FOUND

Three real defects, each **proven with a failing test before any code changed**, then fixed,
then re-proven. Two were product defects shipped in the working tree; one was a pair of test
defects that made a green-looking suite impossible to complete.

| # | Severity | Defect | Proof | Status |
|---|---|---|---|---|
| D1 | 🔴 | Progress scored Lifestyle against **stale coach goals** | `progress_live_targets_test.dart` | Fixed, 5/5 |
| D2 | 🟠 | Every Progress chart rendered a **phantom third axis label**, often a duplicate date | `progress_chart_axis_test.dart` | Fixed, 6/6, device-confirmed |
| D3 | 🟠 | Two **deterministic Patrol failures** in the Transformation suite | Re-run twice, identical | Fixed, 24/24 |

---

## 1. BASELINE (re-established, not assumed)

| Suite | Result |
|---|---|
| AlphaSerena `flutter analyze` | **0 issues** |
| AlphaSerena `flutter test` | **1527 pass / 14 fail** |
| TrainerHQ `flutter analyze` | 26 issues — all `info`/`warning`, no errors |
| TrainerHQ `flutter test` | 1880 pass / 3 fail |
| Cloud Functions | **1027 / 1027** |
| Firestore + Storage rules | **399 / 399** |

The 14 AlphaSerena and 3 TrainerHQ failures are **pre-existing golden-image** failures (missing
font faces on this machine). Their distribution is byte-identical to the untouched baseline taken
before any edit: `home_cards_golden` 8, `home_header` 4, `log_transformation_screen` 1,
`serena_foundation` 1. **Zero logic failures, zero regressions.** Test count rose 1513 → 1527;
all 14 new tests are the regression guards written for D1 and D2.

---

## 2. DEFECT D1 — LIFESTYLE SCORED AGAINST STALE COACH GOALS 🔴

A lifestyle ratio is `met / asked`. The two halves come from **different documents that change
independently**: values from `coaching_rollups` (server-derived, changes when the member logs),
goals from `clients/{id}.lifestyleTargets` + `.supplementPlan` (coach-authored).

`_bindRollups` read the goals **inside the rollup stream's listener**, pinning them to the instant
a rollup happened to arrive. A coach edit lands on the live `clients` listener but writes no
rollup — so a new goal could not reach the member's score until they logged something else.

**Proven before the fix:** coach lowers the step goal 10,000 → 8,000 for a member walking 9,000
every day. The member's Progress kept reporting **Lifestyle 0%** while their coach saw **100%**
for the same days. A coach adding a supplement showed 100% instead of the honest 50%.

`LifestyleHistoryController._signature()` already carried exactly this guard. Progress was the
surface that missed it, so the shape was copied rather than reinvented: a goals signature
re-scores `lifestyle` **in memory**, because the values did not change — only the question asked
of them.

**Verification — 5/5**, including a test proving a coach edit costs **zero extra Firestore reads**
and that unrelated `clients` field changes cause no re-subscription.

---

## 3. DEFECT D2 — A PHANTOM THIRD AXIS LABEL ON EVERY CHART 🟠

Observed on the emulator: a two-point Nutrition series rendered **"3 Aug · 3 Aug · 4 Aug"**.

**Root cause proven from fl_chart 1.2.0's own source**, not inferred. `AxisChartHelper
.iterateThroughAxis` does not anchor ticks to `minX`; it anchors to `LineChartData.baselineX`,
which **defaults to 0 — the Unix epoch**:

```dart
final mod = (baseline - min) % interval;   // → [0, interval)
return min + mod;                          // an INTERIOR tick
```

With `interval == maxX - minX`, `mod` is the offset of the member's first data point from an
epoch-aligned grid — an arbitrary instant strictly inside the span. `minIncluded`/`maxIncluded`
then both default to true, so the iterator emits `min` and `max` **around** it. Three labels, for
every series whose start is not exactly interval-aligned with the epoch — i.e. essentially always.

This was **not** a formatter bug, timezone issue, floating-point rounding, or duplicate source
data; the first test in the file pins that the series genuinely has two points.

| Series | Before | After |
|---|---|---|
| 2-point nutrition | `3 Aug, 4 Aug, 4 Aug` | `3 Aug, 4 Aug` |
| 31-day adherence | `5 Jul, **6 Jul**, 4 Aug` | `5 Jul, 4 Aug` |
| 3-point weight | `1 Jun, **14 Jun**, 1 Aug` | `1 Jun, 1 Aug` |
| both ends same day | `4 Aug, 4 Aug, 4 Aug` | `4 Aug` |

The middle tick sat on **no record at all** — on the weight chart it labelled "14 Jun", a date on
which nothing was measured. The ends are now selected in `getTitlesWidget`, where the promise can
be kept regardless of what the tick generator offers, and a same-day span states its date once.

`ProgressChart` had **zero tests** before this (411 lines). It now has 6.

**Device-confirmed on the exact screen that exposed it:** Nutrition now reads `3 Aug … 4 Aug`;
Workout quality reads `31 Jul … 4 Aug`.

---

## 4. DEFECT D3 — TWO DETERMINISTIC PATROL FAILURES 🟠

The Transformation suite failed **22/24 on two consecutive runs — identical failures, not flake**.
Both were test defects; the product was correct in both cases. Root-caused, not worked around.

**"a measurements-only check-in publishes once and reports back"** — `_save` awaits
`_showSuccess`, which pops its dialog after 250ms/750ms and then pops the **screen** via
`Get.back()`. The test called `pumpAndSettle()` *before* asserting the confirmation, which runs
both timers to completion. It asserted against a screen that had already closed. Every
product-side assertion (`finalizeCalls == 1`, measurements, visibility, `saved == 1`) passed —
only the transient-UI assertion failed. Fixed by asserting the dialog while it is on screen.

**"a three-year history is built lazily, not all at once"** — asserted `built > 0` without
scrolling. The header sliver (latest snapshot, automatic comparison, log button, heading) is
**taller than the device viewport**, so `SliverList.builder` correctly builds zero rows until the
member scrolls. `$('Transformation history')` passed because Flutter finders search the element
**tree**, not the screen — it proved nothing about scroll position. The test now scrolls to the
timeline and asserts the property it exists to defend: rows build, and far fewer than 150.

---

## 5. RUNTIME VERIFICATION (Phase 3) — emulator, live member

| Check | Result | Evidence |
|---|---|---|
| Cold start → dashboard | **PASS** | session persisted, no re-auth, real coach/plan data |
| Cold start → Progress | **PASS** | full render; frames 2–4 byte-identical → no flicker, no first-run flash |
| Chart fix live | **PASS** | two axis anchors on both Workout and Nutrition |
| Warm start ×4 (background→resume) | **PASS** | scroll position, selected metric chip and all data preserved |
| Memory across 4 resume cycles | **PASS** | 541.7 → 543.5 → 540.9 → 540.0 → 539.2 MB — no leak, no accumulating listeners |
| Landscape | **PASS** | nav → side rail, tiles reflow 3-across, no clipping/overflow |
| Offline | **PASS** | app-wide connectivity takeover engages |
| Reconnect | **PASS** | full data restored, identical figures, no stale or blank state |

⚠️ **Debug build.** Absolute startup time (~9s to dashboard) and PSS (~540 MB) are **not
production-representative** and are reported as behaviour, not as performance numbers.

---

## 6. CROSS-APP PARITY (Phase 4) — the most important finding

**Verified true:** `progress_analytics.dart` is **byte-identical** in both repos
(`bdd700fb…c1797`), and both parity tests pin that same hash independently.
`transformation_comparison.dart` differs only by model type and class naming — same 0.05
unchanged-threshold, same head-to-toe measurement order. Not a numeric drift.

**But the parity is of SOURCE, not of RENDERED NUMBERS.** In TrainerHQ:

- `lib/core/analytics/progress_analytics.dart` is imported by its own adapter file and **3 test
  files** — nothing else.
- `lib/core/analytics/analytics_adapters.dart` is imported by **nothing at all**.
- **No screen, feature or controller in `lib/features/` references either.**

The coach app renders from a **second engine**, `lib/core/progress/progress_series.dart`
(`workoutAdherenceSeries`, `workoutStreak`, `progressScore`). The hash pin therefore guarantees
the member's file matches a file **the coach app never executes**. The claim in AlphaSerena's own
source — *"hash-pinned against it, so a member and their coach can never quote different
numbers"* — is structurally weaker than stated.

**Severity is moderated by real, existing guards**, which I verified rather than assumed:
`test/progress_threshold_contract_test.dart` pins `AnalyticsPolicy == ProgressPolicy` **and** both
to the backend rollup config (`windowDays 28`, `minSample 3`, `onTrackPct 0.8`), and documents
this exact trap. Algorithms compared directly: `workoutStreak` is verbatim identical;
`workoutAdherenceSeries` is identical modulo the model accessor.

**One concrete divergence found:** `exerciseIdentity` guards differ — the coach skips an entry
whose `exerciseName` is empty, the member skips only when **both** name and id are empty. An
id-only entry is counted by the member's strength picker and dropped by the coach's. Narrow, but
real. Not changed here: TrainerHQ's M5 engine is frozen and editing it needs its own regression
pass in that repo.

⚠️ **No side-by-side runtime comparison was performed.** I did not open the same client in
TrainerHQ on a device and compare rendered figures. This is the single largest evidence gap in
this report.

---

## 7. BACKEND (Phase 5)

Progress reads exactly five collections. All five have rules coverage and a live producer — **no
orphan, dead, write-only or read-only collection in the Progress path**.

| Collection | Query shape | Index required |
|---|---|---|
| `client_workout_sessions` | `where(authorId)`, sorted **in memory** | none |
| `client_check_in_submissions` | `where(authorId)` (+`status`), sorted in memory | none |
| `client_progress` | doc reads | none |
| `coaching_rollups` | doc reads by deterministic id | none |
| `client_nutrition_days` | doc reads by deterministic id | none |

Every Progress query is equality-only with client-side sorting, so **no composite index is
missing** — confirmed against `firestore.indexes.json` (68 indexes; none needed for these paths).
Producers verified present: `coaching_events.ts`, `nutrition.ts`, `progress.ts`, `engagement.ts`.

🟡 **Known debt, unchanged:** `fetchSessionHistory` is **unbounded** — no `limit`, no date window,
because there is no `[authorId, date]` composite index. A member with years of history downloads
their entire workout history once per controller lifetime. The source documents this deliberately
rather than adding a second read path.

---

## 8. PERFORMANCE (Phase 8) — measured, and the measurement said *don't optimise*

New `test/progress_scale_bench_test.dart` reproduces the exact getter sweep the screen performs,
call for call, at multiplicities counted from the source.

| Measurement | Result |
|---|---|
| Growth, 4× data (250 → 1000 sessions) | **2.95× – 3.46×** → **linear, no O(n²)** |
| Redundant recomputation per build | **1.46×** |
| Device memory across 4 resume cycles | **stable / slightly declining** |

I initially suspected ~3× redundancy from reading the call sites (`dimensions` reachable six ways
in one build). The measurement disproved that: repeated getters cost 46% extra, and the bulk is
inherent single-pass work. **Per Rule 3, no optimisation was made** — the measurable reason was
absent. The benchmark is kept as a regression guard, asserting a machine-independent *ratio*
rather than a flaky wall-clock budget.

⚠️ **Not measured:** on-device frame timings, CPU, and rebuild counts under a profile/release
build. A debug build would not have produced representative numbers.

*Correction to an intermediate finding:* a widget-level harness that appeared to hang for 10
minutes was my own bug — `Future.delayed` does not fire under `testWidgets`' fake clock. The app
was never at fault.

---

## 9. UX (Phase 6)

Fixed with a measurable reason: **D2**, the phantom axis label — a chart that names a date on
which nothing was recorded is a correctness defect wearing a UI costume.

Verified sound on device: honest empty/low-confidence states (Nutrition at 2 days reads
"building", not a fabricated percentage); no 0% ring where no score exists; every figure states
its window ("last 30 days", "within the loaded history"); the score ring, dimension bars and
stat band agree (mean of 100/55/27 = 61%).

Observations recorded, **deliberately not changed**:

- 🟡 The offline takeover **replaces** Progress entirely, hiding history already cached on the
  device. Apple Health / Whoop / Strava show cached data behind an offline banner. This is
  app-wide and an explicitly recorded product decision ("app-wide + always-when-offline +
  full-screen takeover") — changing it is out of scope for Progress and contradicts that decision.
- 🟡 After the offline takeover swaps the tree, the analytics chip selection and scroll offset
  reset (the chip lives in local `State`). Data is correct; cosmetic.

---

## 10. ACCESSIBILITY (Phase 7)

Covered by passing tests in the `resilience` group: 320dp @ **2.0× text scale**, 360dp @ 1.5×,
300dp width, tablet width, landscape, and range switching. The shortcut row stacks above 1.6×
scale and reserves its height by construction rather than by `IntrinsicHeight` measurement — a
device-found overflow the source documents. Semantics are container-scoped with explicit labels
on dimension rows, the score ring and activity rows.

Device-verified: **landscape only**.
⚠️ **Not verified on device:** large font scales, tablet, small phone, and **TalkBack was not
tested at all**.

---

## 11. PATROL (Phase 9) — real emulator, no mocked services

```
progress_patrol_test.dart        📝 20  ✅ 20  ❌ 0  ⏩ 0
transformation_patrol_test.dart  📝 24  ✅ 24  ❌ 0  ⏩ 0
                                 ───────────────────────
                                 TOTAL 44  ✅ 44  ❌ 0
```

Both run against an APK built from the current tree, **including both fixes**. Full enumeration is
present (`Total: 20`/`Total: 24`, not `Total: 0`), so the Android JUnit silent-drop trap is not
masking anything. The Transformation result is **after** D3; it was 22/24 twice before.

---

## 12. PRODUCTION READINESS SCORE

| Dimension | Score | Basis |
|---|---|---|
| Architecture | **8.5 / 10** | Clean controller/adapter/shared-core split, lazy Firebase resolution, one listener per collection. −1.5: TrainerHQ runs a second engine. |
| Backend | **9 / 10** | 1027 CF + 399 rules tests green; no orphan collections; no missing index. −1: unbounded session fetch. |
| UI | **9 / 10** | Honest states throughout; axis defect fixed. −1: chip/scroll reset after takeover. |
| UX | **8.5 / 10** | Every figure states its window; nothing fabricated. −1.5: offline hides cached history. |
| Performance | **8 / 10** | Linear, no O(n²), memory stable. −2: no device frame/CPU measurement. |
| Accessibility | **7.5 / 10** | Strong host coverage at 2.0×/320dp/tablet. −2.5: TalkBack untested, scales unverified on device. |
| Testing | **9 / 10** | 1527 tests, 44/44 Patrol, benchmark + 11 new regression guards. −1: 14 pre-existing golden failures. |
| Reliability | **9 / 10** | Cold/warm/offline/reconnect/rotate all pass; no leaks over 4 cycles. |
| Maintainability | **8 / 10** | Exceptional defect-archaeology comments. −2: duplicated engine and twin files across repos. |

**Weighted overall: 8.5 / 10**

---

## 13. REMAINING TECHNICAL DEBT

1. 🟠 **TrainerHQ renders from a second analytics engine**; the hash-pinned shared core is dead
   code there, kept alive by tests — the exact failure mode this codebase deleted before
   (`core/domain/consistency.dart`). Guarded by the threshold contract test, but the render paths
   are not unified.
2. 🟠 **`exerciseIdentity` diverges** between the two engines for id-only entries.
3. 🟡 **`fetchSessionHistory` is unbounded** — needs an `[authorId, date]` composite index to
   window server-side.
4. 🟡 **14 pre-existing golden-image failures** (missing font faces on this machine) suppress the
   ability to add new goldens for Progress.
5. 🟡 Offline takeover hides on-device cached history (recorded product decision).
6. 🟡 Emulator clock skew of **−61s** could not be corrected (`adb root` refused); tolerable for
   Firebase Auth, but worth noting for any future auth debugging.

---

## 14. FINAL DECISION

# ⚠️ CONDITIONAL GO

**Why not NO GO.** Every suite is green with zero logic failures. Three real defects were found,
proven, fixed and regression-tested. Patrol is 44/44 on a real emulator against a real backend
with a real member. Cold start, warm start, rotation, offline and reconnect all pass with device
evidence, and memory is stable across repeated resume cycles. The module is materially better
than when this engagement started, and nothing known to be broken is shipping.

**Why not GO.** The mission's own bar is explicit: *"Only issue GO if every remaining phase has
been completed with runtime evidence."* Three phases do not meet it:

- **Phase 4** — no side-by-side runtime comparison against TrainerHQ was performed, and the
  discovery that the coach app renders from a different engine makes that comparison *more*
  necessary, not less. "Every number must match" is currently proven at source level only.
- **Phase 7** — TalkBack was never exercised; large fonts and tablet were verified in widget
  tests, not on the device.
- **Phase 8** — no on-device frame, CPU or rebuild measurement; the debug build cannot supply
  representative numbers.

**Conditions to convert to GO** (in priority order):

1. Open the same client in TrainerHQ on a device and compare, figure by figure, against this
   member's Progress screen: workout adherence, streak, volume, nutrition, lifestyle, weight
   series, achievements. Any mismatch is a D1-class defect.
2. Decide the two-engine question deliberately — either wire TrainerHQ's surfaces to the shared
   core, or delete the dead copy and drop the parity claim from AlphaSerena's source comments.
   The present state asserts a guarantee the architecture does not provide.
3. Run Progress under a profile build with TalkBack enabled at 2.0× text scale on a real device;
   capture frame timings.

I am **not** issuing GO on the evidence gathered, and I have not represented source-level parity
as runtime parity.
