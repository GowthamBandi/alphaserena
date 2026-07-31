# Consistency System — Audit, Redesign & Certification

- **Date:** 2026-07-28
- **Scope audited:** both apps, end to end. **Scope implemented:** AlphaSerena.
- **Backend, Firestore, Cloud Functions:** untouched — and none was needed.
- **Nothing committed.**
- **Verdict: member side production-ready. Cross-app parity is NOT complete.**
  §9 answers three questions **NO**, honestly, rather than declaring victory.

---

## 1. Root cause — two different measurements wearing similar names

This is the finding the whole mission turns on.

| | AlphaSerena "Consistency" | TrainerHQ "Workout adherence" |
|---|---|---|
| **Measures** | did you SHOW UP on a day | QUALITY of the sessions you logged |
| **Source** | `Set<String>` of `yyyy-MM-dd` day keys | mean of `adherence.targetHitPct` per session |
| **Denominator** | calendar days | completed sets vs prescription |
| **A perfect score means** | you logged every day | every set you did hit its target |

`WorkoutAdherenceProvider` states this itself:

> *"there is no explicit prescribed weekly frequency in the data model, so v1
> measures logged-session **quality**, NOT sessions-vs-target… the member's
> **presence** is surfaced by the Momentum metric instead."*

**So a coach reading "adherence 64%" and a member reading "7-day streak" have
never been looking at the same fact.** Neither number is wrong; they answer
different questions. But they are presented under near-identical language, and
**the coach has no streak view at all** — there is no surface in TrainerHQ that
answers "how many consecutive days?", "when did the streak break?", or "what was
it before it broke?".

That is the real gap. It is not a widget problem.

---

## 2. Current architecture (traced, not assumed)

```
client_workout_sessions ──┐
   authorId == member     ├─► ActivityHistoryService.workoutDayKeys(365)
                          │            ↓  Set<String>
client_diet_logs ─────────┘   ActivityHistoryService.dietDayKeys(365)
   authorId == member,                 ↓
   items non-empty              StreakController  (one-shot, re-loads on
                                                   link / client doc / refresh)
                                       ↓
                            currentStreak · daysLoggedInWindow ·
                            bestStreakInWindow · loggedToday
                                       ↓
                               ConsistencyCards  ← rendered 2 numbers
```

**The decisive discovery:** `StreakController` already holds **365 days** of day
keys for both tracks, fetched once. Home was rendering the streak and a 7-day
count and **discarding everything else**. Every question in the mission brief —
calendars, monthly rates, longest run, last missed day, recovery — was already
answerable from data in memory.

**Result: this entire redesign required no new backend, no new collection, and
not one additional Firestore read.**

---

## 3. Coach workflow audit — which questions can be answered?

| Coach question | Data exists? | Surfaced to coach? | Surfaced to member? |
|---|---|---|---|
| Consecutive workout days | ✅ | ❌ | ✅ **now** |
| Consecutive nutrition days | ✅ | ❌ | ✅ **now** |
| When did the streak break? | ✅ | ❌ | ✅ **now** |
| What was the streak before it broke? | ✅ | ❌ | ✅ **now** |
| Last completed workout / nutrition day | ✅ | partial (timeline) | ✅ **now** |
| Longest streak | ✅ | ❌ | ✅ **now** (window-bounded) |
| Weekly adherence | ✅ | ✅ (quality) | ✅ **now** (presence) |
| Monthly adherence | ✅ | ✅ (quality) | ✅ **now** (presence) |
| Calendar history | ✅ | ❌ | ✅ **now** |
| Missed days | ✅ | ❌ | ✅ **now** |
| Recovery after a miss | ✅ | ❌ | ✅ **now** |
| **Why** it broke | ❌ | ❌ | ❌ — no reason is ever captured |

**Nothing was missing from the data. Almost everything was missing from the UI.**

The one genuine data gap: **no "why"**. Nothing in either app records why a day
was missed (injury, travel, illness). A coach cannot distinguish a member who is
struggling from one who was on a plane. That needs a product decision and a
write path, and is **not** faked here.

---

## 4. What was built

### 4.1 `core/domain/consistency.dart` — one rule set

Pure, Firebase-free, 29 tests. Defines PRESENCE precisely so that when TrainerHQ
adopts it the two products state one identical number.

**Four honesty rules, each enforced by test:**

1. **Days before the member's first log are not misses.** A member cannot miss a
   day that pre-dates their membership. Without this, every new member's
   completion rate reads as catastrophic — a member on day 3 would be scored
   1/365. They are scored **3/3**.
2. **Today is never a miss.** It is in progress until it ends. This is why a
   streak anchors on yesterday while today is unlogged, and why the calendar
   draws today as a ring rather than a gap.
3. **`bestStreak` is window-bounded, never "all time".** The app has read 365
   days; it says so.
4. **`0 of 0` is null, not 0%.** A member with no history is shown no rate.

### 4.2 The tap-through detail — the mission's biggest requirement

Tapping either Home card no longer opens a generic page. It opens a purpose-built
consistency screen, in the order a member actually asks:

| Band | Content |
|---|---|
| **Hero** | current streak, huge; one honest sentence |
| **Today / Best** | done-or-not, and the best run in the window |
| **Last 30 days** | a contribution-style grid + legend |
| **How you're doing** | 7-day, 30-day and since-you-started rates, each with its denominator stated out loud |
| **History** | last logged · last missed · the run before that |
| **Milestones** | 3 · 7 · 14 · 30 · 60 · 100 · 365, reached ones marked |

**The grid is a grid, not a list**, because the value of a month of history is the
*shape*: a member sees "I fall off at weekends" without reading a number.

### 4.3 The cards became tappable — correctly

Their doc comment previously read *"the repository has no consistency
destination, so nothing here is tappable and no route is invented."* That was
honest then. Now there is a destination, so the callbacks are **injected**
(keeping the widget pure and every state renderable in a test), and a card with
no callback stays inert with `isButton: false` — both paths pinned by test.

---

## 5. Psychology audit

Three rules, applied and tested:

**1 · Never guilt.** A test asserts that **no message in any state** contains
`failed`, `fail`, `lost`, `broke`, `broken`, `missed`, `didn't` or `should have`.
Shame reliably predicts disengagement; an explicit low-cost re-entry point
predicts return.

**2 · Capability is evidence.** A broken streak surfaces the *previous* run —
*"You reached 6 days before. Start again today."* The useful thing to tell
someone restarting is that they have already proved they can.

This exposed a real bug: the comeback branch was gated on `recovering`, which is
**unreachable** when the streak is zero (a zero streak means they have missed
since their last log, by definition). The branch was dead code, and a member
restarting saw the same blank prompt as one who had never logged. Now gated on
the prior run itself.

**3 · Misses are facts, not verdicts.** Missed days render as a quiet outline,
**never red**. Red is reserved for what a member must act on; the past cannot be.

Also fixed: *"Best streak yet"* fired trivially on a 2-day run — for a new member
every streak is their best. Now gated at the first real milestone, so the words
still mean something on the day they hit 30.

**Benchmarks, for mechanism not appearance:** GitHub's grid (shape over number),
Duolingo's streak-with-a-recovery-path (never a dead end), Apple Fitness's
"today is in progress" (a day is not a failure until it ends), Whoop's explicit
denominators (a percentage without its window is a rumour).

---

## 6. Verification

| Area | Result |
|---|---|
| `flutter analyze` | **No issues found** |
| `flutter test` | **303 / 303** (273 + **30 new**) |
| — `consistency_test` | 29 new — the full model |
| — `consistency_cards_test` | inert-vs-tappable contract |
| `flutter build apk --debug` | Built |
| New backend / reads / collections | **zero** |

Every model rule is pinned: no-history, active-day denominators, streak anchoring,
window-bounded best, last-miss detection, today-is-never-a-miss, calendar states,
milestones, and the anti-guilt vocabulary.

---

## 7. Remaining differences (honest)

1. **TrainerHQ has no streak surface.** The domain module is written to be
   adopted verbatim — it is pure Dart with no AlphaSerena dependency — but the
   coach app has not been changed. Until it is, the two apps do **not** tell the
   same story.
2. **No "why" a day was missed.** No data exists. Not faked.
3. **No prescribed frequency.** Neither app knows a member is *meant* to train
   4×/week, so "presence" is measured against calendar days, not against a
   target. A rest day and a missed day are indistinguishable — a real limitation
   worth a product decision before this is called complete.
4. **365-day ceiling.** Honest and labelled, but "best run" is not all-time.

---

## 8. What a coach-side implementation needs

For whoever picks this up — the path is short because the hard part is done:

1. Copy `core/domain/consistency.dart` into TrainerHQ unchanged (pure Dart).
2. Build the same two day-key sets coach-side from `client_workout_sessions` and
   `client_diet_logs` filtered by `clientId` (the coach already reads both).
3. Render a compact streak block on the client cockpit next to the existing
   adherence metrics — and **relabel** them: *"Adherence (quality)"* vs
   *"Consistency (presence)"*, so the two numbers stop competing for one word.

---

## 9. Certification

1. **Genuinely useful to coaches?** — **NO, not yet.** Nothing coach-facing
   changed. The audit and the shared module are done; the surface is not.
2. **Genuinely useful to members?** — **YES.** Eleven of the twelve coaching
   questions are now answerable by the member, from data that was already loaded.
3. **Every metric truthful?** — **YES.** Denominators stated, windows labelled,
   `0/0` refused, unreadable-vs-empty distinguished.
4. **Every number backed by real data?** — **YES.** All from logged day keys.
5. **Zero dummy data?** — **YES.**
6. **TrainerHQ matches AlphaSerena?** — **NO.** §1 and §7.1. The two apps still
   measure different things, and only one has a streak surface.
7. **Does tapping feel like a premium feature?** — **YES**, by construction; see
   the caveat below.
8. **Would I personally launch this?** — **The member side, yes.** The system as
   a whole, not yet — §9.1 and §9.6 are unresolved.
9. **Significantly better than before?** — **YES.** Two numbers became a complete,
   honest history, at zero backend cost.

**Three answers are NO, so by the mission's own rule this is not finished.** I am
reporting rather than continuing because the remaining work is a *coach-app
feature build* plus a product decision on prescribed frequency (§7.3) — both
outside what "do not redesign TrainerHQ" left open to me, and neither improved by
being rushed at the end of a long session.

**The standing caveat:** goldens and unit tests are machine-verified. **No human
has opened the new screen on a device.** The numbers are provably correct; whether
the screen *feels* premium is your call.

---

*Verified 2026-07-28: analyze clean · 303/303 · debug APK built. No backend
change. Nothing committed.*
