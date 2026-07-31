# AlphaSerena — Diet Consumption V1 Certification

- **Date:** 2026-07-28
- **Scope:** `alphaserena` (member app) consuming the frozen coach-side stack
- **Treated as frozen and untouched:** the Food Platform, the Global Food
  Database, the Organisation Food Library architecture, and the TrainerHQ Diet
  Builder. No coach-side file was modified in this pass.
- **Predecessors:** `FOOD_PLATFORM_V1.md`,
  `FOOD_PLATFORM_SUPER_ADMIN_RELEASE_CERTIFICATION.md`,
  `FOOD_PLATFORM_TRAINERHQ_INTEGRATION_CERTIFICATION.md`,
  `DIET_BUILDER_PRODUCTION_CERTIFICATION.md` (all in `trainersHQ/docs/`)
- **Nothing committed.**

---

## 1. How AlphaSerena consumes a diet

```
TrainerHQ builder  ──►  dietPlans/{id}            (library template)
                            │  assign snapshots items
                            ▼
                   client_plan_assignments/{id}   (the per-client copy)
                            │
                   getMyTraining ─► buildDiet     (server-resolved, one-shot)
                            │  prefers the assignment snapshot;
                            │  falls back to the template only for
                            │  legacy reference-only assignments
                            ▼
   TrainingController.diet ──► ClientDietScreen ──► DietLogController
                                                          │
                                                          ▼
                                              client_diet_logs/{clientId}_{date}
```

The member **never reads `foodDatabase`** — the rules deny every food branch, and
nothing in the app tries. Everything arrives pre-resolved through one callable.
Targets come from `clients/{id}.dietTargets`, never from the plan.

## 2. What I found

The consumption layer was in good shape. Nutrition Foundation V2A/V2B had
already solved the two hardest problems — meal marks bind to a food by stable
identity rather than array position, and each logged mark freezes its own
consumed-nutrition snapshot so history survives later edits. I did not
re-litigate either.

Three defects remained, all in AlphaSerena's own court.

### D1 · Marks silently rebound to the wrong food after a mid-session plan change

`restoreAction` returns `noop` the moment the member has local marks — correct,
because re-running a full restore would clobber in-flight toggles. But the same
guard meant a plan arriving **later in the session** left the index-keyed
`statuses` map describing a food list that no longer existed.

The failure was silent and precise. Mark Roti at index 3; the coach deletes a
food above it; the member pulls to refresh — the gesture is right there on the
screen. Index 3 is now Paneer. The screen shows the wrong food ticked, and the
next write logs **Paneer as eaten**. Nothing errors, and the member's adherence
record becomes quietly false.

Fixed with `remapStatusesOnPlanChange`, the live-session twin of the existing
identity restore: a surviving food keeps its mark wherever it moved to, a
deleted food loses its mark, and an inserted food arrives unmarked rather than
pre-ticked. `planFoodsDiffer` compares position as well as membership, because a
pure **reorder** changes no food but changes what every index means — exactly the
case a length check misses.

### D2 · Offline logging showed "Saving…" forever

`DietLogService.saveDay` awaited Firestore's `set()`. That Future applies the
write to the local cache immediately but does not complete until the **server**
acknowledges it — so with no connection it never completes at all. `isSaving`
stayed true indefinitely.

The data was never at risk (Firestore queues and replays it), but the app said
nothing true: no confirmation, no error, just a spinner. An athlete logging
lunch in a basement gym had no way to know their day was recorded.

Now time-boxed: a server ack within 4 s reports **synced**, a timeout reports
**queued**, and only a real rejection reports **failed**. `queued` is deliberately
not an error — the screen says *"Saved on this device — syncs when you're back
online"*, because telling a member their log was lost when it wasn't would push
them to re-tap or give up.

**A defect in the fix itself, caught and closed:** `timeout` does not cancel the
underlying write. The abandoned operation stays pending and may **fail** minutes
later with nobody awaiting it — an unhandled async error that can take the
isolate down. The orphan is now adopted explicitly.

### D3 · No per-meal totals

The member saw per-food macros and a day total, but nothing per meal — so *"how
big is my lunch?"*, the question an athlete asks before every meal, meant
mentally adding four foods. The coach's builder shows that number in every meal
header.

Added, and routed through a shared `sumMacro` so a meal total can never be
computed differently from the day total.

Adding them surfaced a real inconsistency: TrainerHQ declares a deliberate meal
alias (`Snacks` → `Evening Snack`) that AlphaSerena did not apply. A legacy plan
would have shown the member two headings and two smaller totals where the coach
saw one merged meal. The alias is now applied on this side too.

## 3. Do the numbers match TrainerHQ?

**Yes, and it is now pinned by test rather than by inspection.**

`test/diet_trainerhq_parity_test.dart` runs the **same realistic athlete's day**
that `trainersHQ/test/diet_builder_workflow_test.dart` pins — same eight foods,
same grams, same expected totals — and asserts identical results:

```
calories 1668.5 · protein 125.6 · carbs 188.7 · fat 45.5 · fiber 17.9
```

The fixture is duplicated deliberately rather than shared: the two apps are
separate binaries with no common package, and a fixture that could drift on one
side without failing on the other would defeat the purpose.

Parity holds **structurally**, not coincidentally: neither side re-derives
anything. The builder resolves `per100 × grams / 100` once and stores it;
`dietItemForMember` forwards every field verbatim; both apps then perform a plain
sum. Nothing rounds, rescales or re-reads a food document in between — rounding
exists only at the point of display.

Also asserted: meal totals partition the day exactly (nothing lost or
double-counted, including foods whose meal is not one of the coach's six slots);
a fully-eaten day consumes exactly the prescribed total; and `eaten`/`partial`/
`skipped` weight 1 / 0.5 / 0 consistently.

## 4. The journey, step by step

| Step | Verdict |
|---|---|
| Coach creates diet | ✓ upstream, certified separately |
| Coach assigns diet | ✓ items snapshotted onto the assignment; single-active enforced |
| Member receives diet | ✓ `getMyTraining` → `buildDiet`; no member-side food reads |
| Member views meals | ✓ grouped by meal, canonical order, unknown labels kept and sorted last |
| Member tracks meals | ✓ per-food eaten / partial / skipped, tap-again to clear |
| Member marks complete | ✓ persisted per change; adherence recomputed |
| Member views nutrition | ✓ day totals, consumed vs target, and now per-meal totals |
| Coach updates diet | ✓ per-client edits reach the member |
| Member receives updates | ✓ on app open, Home reload, or pull-to-refresh — `getMyTraining` is one-shot by design, not realtime |

## 5. Synchronization

| Scenario | Behaviour | Verdict |
|---|---|---|
| Coach edits the member's assignment | Next fetch serves the new items; existing marks remap by identity | ✓ *(D1)* |
| Coach edits the library template | Does **not** reach an assigned member — the assignment holds its own snapshot | ✓ by design; now stated in the coach's builder |
| Coach assigns a replacement | Atomic end-old + create-new; the member fetches the active one | ✓ |
| Coach archives the template | No effect — the member reads the assignment snapshot | ✓ |
| Member logs out / back in | `TrainingController.onInit` refetches; marks restore by identity from `client_diet_logs` | ✓ |
| App lives past midnight | `ensureFreshDay` rebinds to the new date key, so yesterday's marks cannot be stamped onto today | ✓ |
| Offline, then reconnect | Marks apply locally and replay; the member is told which state they are in | ✓ *(D2)* |

## 6. Performance

| Concern | Finding |
|---|---|
| Large diet | Meal grouping is one pass; totals are one pass per meal. A 40-food day is ~80 numeric operations per build. |
| Rebuild cost | Each food card's status row is its own `Obx`, so marking one food repaints one chip row, not the list. |
| Slow network | `getMyTraining` has a distinct error state with Retry, kept separate from "no diet assigned" so a timeout never reads as an unassigned plan. |
| Offline | Reads serve from Firestore's cache; writes queue and replay; the UI states which. |
| Scrolling | The list is built eagerly (`ListView(children:)`) rather than lazily. Fine at realistic sizes (8–20 foods); the honest note is that it is not lazy. |

## 7. Open items (reported, not fixed)

1. **The coach's plan `description` never reaches the member.** `buildDiet`
   returns `{name, items, targets}` only — the plan's description, the sole
   free-text coaching field on a diet plan, is dropped at the serving boundary,
   and no member screen references it. So a coach who writes *"3 L water, no oil
   after 7 pm"* is writing into a void. **This is the highest-value gap in the
   whole diet chain**, and it is genuinely cross-boundary: it needs an additive
   field on `buildDiet` (backend), a decision about which description a
   *customized* assignment should show, and a member surface. I did not make
   that change because the serving function and the builder are both frozen for
   this pass, and the customized-assignment question is a product decision.
2. **No diet history.** The member sees today only; `client_progress_screen`
   contains no diet, adherence or nutrition reference. There is no yesterday, no
   week, no trend — despite every day being permanently recorded in
   `client_diet_logs` with a full consumed-nutrition snapshot (V2B). The data is
   already there; only the surface is missing. This is a feature build with real
   product choices (window, metric, adherence vs macros), not a defect fix.
3. **`LifestyleLogService` carries D2's exact defect.** `setMetric` and
   `setSupplements` both `await set()` then `return true`, so water, steps and
   sleep logging hangs identically offline. Same shape, same one-line remedy. I
   did not fix it: lifestyle is a different domain from diet consumption and
   deserves its own audited pass rather than a partial change made in passing.
4. **Meal taxonomy is duplicated across the two apps.** TrainerHQ owns
   `kDietMeals` + `kMealAliases`; AlphaSerena owns `_mealOrder` + `_mealAliases`.
   They agree today (this pass aligned the alias), and AlphaSerena's list is the
   more permissive of the two — it already contains a `Pre-Workout` slot the
   coach app cannot yet produce. Two hand-maintained copies of one contract will
   drift; the parity test now covers the behaviour, not the lists.
5. **The list is not lazily built** (§6). Immaterial at realistic plan sizes.

## 8. Verification

| Suite | Result |
|---|---|
| `flutter analyze` (alphaserena) | **No issues found** |
| `flutter test` (alphaserena) | **211 / 211** (189 baseline + **22 new**) |
| — `diet_plan_change_remap_test` | 12 new — D1: delete-above, reorder, insert, deletion, same-food-two-meals, freehand |
| — `diet_trainerhq_parity_test` | 10 new — cross-app totals, meal partitioning, alias merge, consumed weighting |
| `flutter build apk --debug` | **Built** `app-debug.apk` |
| TrainerHQ (unchanged this pass) | 931 / 931, analyze clean |
| Backend rules (unchanged this pass) | 196 / 196 |

## 9. Certification

**1 · Can members reliably consume assigned diets?**
**Yes.** The diet arrives fully resolved through one server callable with no
member-side food access; meals render grouped and ordered; every food is
markable; loading, error, expired-membership and no-plan states are distinct
rather than collapsed. And a mid-session plan change no longer silently
misattributes what the member ate.

**2 · Do calculations match TrainerHQ?**
**Yes — pinned by a shared fixture, not by inspection.** Identical day totals to
two decimal places, meal totals that provably partition the day, and parity that
holds structurally because neither side re-derives anything.

**3 · Are updates synchronized correctly?**
**Yes, under the existing product rules.** Per-client edits reach the member on
the next fetch (open, Home reload, or pull-to-refresh); template edits
deliberately do not; replacement, archive, logout and midnight rollover all
behave correctly. `getMyTraining` is one-shot by design — the member is never
left without a way to refresh, but this is not a push channel.

**4 · Is the workflow production ready?**
**Yes**, with §7 understood as scope rather than defects. The one I would put in
front of a product owner today is §7.1: a coach can type dietary instructions
that no member will ever see.

**5 · Would I personally use this app every day as an athlete?**
**Yes — now.** Two things would have stopped me before this pass, and neither
was arithmetic. Logging a meal on gym wifi and watching "Saving…" spin forever
teaches you not to trust the app, and that is fatal to a daily habit. And a
plan change silently re-attributing what I ate corrupts the one record my coach
judges me on. Both are closed.

What I would still want, in order: the coach's instructions actually delivered
(§7.1), and somewhere to see yesterday (§7.2). Neither blocks daily use; both
are the difference between a logger and a training app.

The same caveat as the two certifications before this one applies: **no
authenticated live run.** Every link — build, assign, serve, mark, remap,
refresh — is covered by a test, but nobody has yet driven the composed sequence
against live Firestore with a real coach and a real member.

---

*Verified 2026-07-28: analyze clean · 211/211 AlphaSerena · debug APK built.
Nothing committed.*
