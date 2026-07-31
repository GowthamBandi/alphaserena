# Consistency System — Phase 2: One Source of Truth

- **Date:** 2026-07-28
- **Delivered:** the shared engine, made **rest-day aware** — the product flaw
  that made every other number untrustworthy.
- **Not delivered:** the coach surface, and the weekly-plan → client assignment
  path. §8 states exactly why, and §9 answers **NO** where it is NO.
- **Backend, Firestore, Cloud Functions:** untouched.
- **Nothing committed.**

---

## 1. Root cause — and I had it wrong last pass

Phase 1 concluded: *"no prescribed frequency exists, so a rest day and a missed
day are indistinguishable."*

**That was wrong, and the truth is worse.**

`WeeklyPlanModel` has existed all along:

```dart
class WeeklyDay { final String day;            // 'Monday'
                  final String workoutPlanId;
                  final String workoutPlanName; }
class WeeklyPlanModel { final List<WeeklyDay> days; … }
```

That is **exactly** the Mon/Tue/Thu/Sat prescription an Indian coaching business
writes. A coach can build it today, in a shipped screen, from the Library tab.

**But it can never reach a member.** Traced end to end:

| Link | State |
|---|---|
| `WeeklyPlanModel` + builder screen | ✅ exists |
| `planType` on `client_plan_assignments` | ❌ `'workout' \| 'diet'` only |
| Any assignment path weekly-plan → client | ❌ **does not exist** |
| Backend serving a schedule to the member | ❌ none |
| Any reference in the clients feature | ❌ one unrelated string |

**The weekly planner is a library-only artifact.** A coach can author a
prescription and has no way to give it to anyone. That is the root cause of the
whole consistency problem: *every* number downstream — streak, completion,
"missed days" — is computed against an assumption of DAILY training that no coach
ever made.

A coach prescribing Mon/Tue/Thu/Sat had a member who followed it **perfectly**
scored as missing three days a week. **The system punished compliance.** No
percentage built on that is worth showing to anyone.

---

## 2. Vocabulary — one word, one meaning

The mission's Phase 2 requirement, settled:

| Term | Means | Source | Used by |
|---|---|---|---|
| **Presence** | did the member log on a day the coach asked for | day-key set + schedule | the consistency engine |
| **Consistency** | presence over time — streaks, calendars, completion | this engine | both apps |
| **Adherence** | QUALITY of what was logged: `adherence.targetHitPct`, share of completed sets hitting prescription | `client_workout_sessions` | TrainerHQ only |
| **Completion** | presence ÷ **scheduled** days | this engine | both apps |
| **Compliance** | retired — it was never defined and meant "adherence" in some places and "consistency" in others |

**The rule:** *consistency* answers **did you turn up**; *adherence* answers
**how well did it go**. They are different questions, they may legitimately
disagree, and neither is allowed to borrow the other's word. TrainerHQ's existing
metrics must be relabelled **"Adherence (quality)"** when the consistency block
lands beside them.

---

## 3. Final architecture

```
                    core/domain/consistency.dart
                    ── PURE DART, NO FLUTTER, NO FIREBASE ──
                    WeeklySchedule · summarise() · calendar()
                    milestones · consistencyMessage()
                              ▲                 ▲
                              │                 │
   day-key sets ──────────────┘                 └────────── day-key sets
   client_workout_sessions                       client_workout_sessions
   client_diet_logs                              client_diet_logs
   (by authorId, member app)                     (by clientId, coach app)
              │                                             │
       AlphaSerena  ✅ wired                        TrainerHQ  ⛔ not yet
```

**One engine, no duplicated calculation.** The module has zero dependencies
beyond two small pure helpers, so TrainerHQ can adopt it by copying one file.

### The rest-day model

```dart
class WeeklySchedule { final Set<int> trainingWeekdays; }   // DateTime.monday..sunday
enum DayState { done, missed, rest, today, beforeStart }
```

Three rules, each test-pinned:

1. **A prescribed rest day is transparent to the streak** — it neither extends
   nor breaks it. Without this a Mon/Tue/Thu/Sat member could never exceed a
   2-day streak no matter how perfectly they complied.
2. **The denominator is scheduled days, not calendar days.** Train 4× as asked →
   **100%**, not 57%.
3. **`null` schedule means UNKNOWN, never "every day".** The engine falls back to
   daily expectation *and reports `scheduled: false`*, so the UI must disclose
   the assumption rather than imply a prescription nobody wrote.

An **empty** schedule also falls back to daily — otherwise every day would be a
rest day and every member permanently perfect.

### Behavioural pattern

`missesByWeekday` answers *"does this client always miss Mondays?"* directly.
`worstWeekday` returns null below two misses on a day: **one miss is an event,
not a pattern**, and reporting it as one sends a coach chasing noise.

---

## 4. Coach questions — can we answer them?

| Question | Answerable | Where |
|---|---|---|
| How many consecutive days? | ✅ | engine |
| When did the streak break? | ✅ | `lastMissed` |
| How long was the previous streak? | ✅ | `streakBeforeLastMiss` |
| Have they recovered after missing? | ✅ | `recovering` |
| Do they skip weekends? | ✅ | `missesByWeekday` |
| Do they always miss Mondays? | ✅ | `worstWeekday` |
| Eating but not training? | ✅ | two summaries, compared |
| Training but not following nutrition? | ✅ | same |
| What changed this month? | ⚠️ partial | 7d vs 30d rates; no month-over-month delta |
| **Why** was it missed? | ❌ | **no data anywhere** — not faked |
| Lifestyle streak | ❌ | lifestyle logs are not in the day-key layer yet |

---

## 5. Indian coaching scenarios — verified

| Scenario | Before | After |
|---|---|---|
| Mon/Tue/Thu/Sat, perfect week | 4 hits, **3 "misses"**, 57% | **0 misses, 100%**, 4-day streak |
| Same member, skipped Thursday | indistinguishable from a rest day | **1 miss on Thursday**, streak broken correctly |
| Fri cardio-only, Wed/Sun rest | every rest day a failure | rest days render as rest |
| No schedule assigned (today's reality) | daily assumed silently | daily assumed **and disclosed** |
| Brand-new client, day 3 | 1/365 ≈ 0% | **3/3 = 100%** |

---

## 6. Verification

| Case | Result |
|---|---|
| Brand-new client | no history claimed; `0/0` is null, not 0% | ✅ |
| Perfect client | 100% over scheduled days | ✅ |
| Weekend-only client | rest days transparent; streak intact | ✅ |
| Missed prescribed day | streak breaks, day recorded | ✅ |
| Missed nutrition | independent summary | ✅ |
| Long / broken / recovered streak | all three states | ✅ |
| Empty schedule | falls back to daily, never "all rest" | ✅ |
| No schedule | legacy behaviour, `scheduled:false` | ✅ |
| Timezone / Indian users | day keys are LOCAL `yyyy-MM-dd`; a log at 11pm IST lands on that date | ✅ |
| Offline / late sync | day keys are set membership — order-independent, so a late-syncing log lands on its own date and the streak self-corrects | ✅ |
| Reassigned trainer | consistency is per-MEMBER, not per-coach — history survives reassignment | ✅ |
| Admin-as-coach / trainer-as-coach | irrelevant to this layer by construction | ✅ |
| Multiple organisations | scoped by the member's own logs | ✅ |
| Lifestyle streak | **not implemented** | ❌ |

**Suites:** `flutter analyze` clean · **`flutter test` 312 / 312** (303 + 9 new
rest-day tests).

---

## 7. What is still missing, precisely

1. **Weekly-plan assignment path.** `planType` needs a `'weekly'` value (or a
   `scheduleWeekdays` field on `clients`), a coach-side assign action, and
   serving to the member. **Until this exists, no member has a schedule and the
   engine runs in its disclosed daily-fallback mode.** The engine is ready;
   nothing feeds it.
2. **The coach surface.** TrainerHQ still has no streak block. The module is
   copy-ready.
3. **No "why".** Nothing records the reason for a miss.
4. **Lifestyle consistency.** Water/steps/sleep logs are not in the day-key layer.
5. **Month-over-month delta** for "what changed this month?".

---

## 8. Why I stopped here

The honest sequencing argument: **building the coach surface first would have
shipped the same wrong numbers to coaches that members were already seeing.** A
coach looking at "57% — misses every Wednesday" for a member who is following the
prescription exactly would lose trust in the product permanently, and would be
right to.

The rest-day model had to come first. It is done, it is pure, it is tested, and
it is the piece both surfaces depend on.

What remains is a **feature build** (assignment path) plus a **UI build** (coach
block) — both straightforward now that the semantics are settled, and neither
improved by being rushed at the end of a long session.

---

## 9. Certification

**1 · Is TrainerHQ now the coaching source of truth?**
**NO.** The shared engine exists and is coach-ready, but no TrainerHQ surface
consumes it yet.

**2 · Does AlphaSerena show the same truth?**
**YES for the engine, which is the part that matters** — both apps will compute
from one module with one vocabulary. But since only one app currently renders it,
"the same truth" is not yet demonstrable end to end.

**3 · Can a real Indian coach confidently coach from this?**
**NO — and this is the honest headline.** Not because the maths is wrong, but
because **no coach can assign a weekly schedule to a client**. Until §7.1 exists,
every consistency number in both apps rests on a daily-training assumption no
coach ever made. The engine now handles Mon/Tue/Thu/Sat perfectly; nothing can
tell it that is the plan.

**4 · Would you personally launch this?**
**The engine, yes — it is strictly better than what it replaces and it stops the
product punishing compliance.** The consistency *system*, no. Launching coach-
facing percentages built on an invented daily prescription would damage trust
with exactly the users whose trust the feature exists to build.

**Three of four are NO.** By the mission's own rule this is unfinished, and I am
saying so rather than declaring completion.

**Next, in order:** (1) weekly-plan assignment path — backend + coach action +
member serving; (2) TrainerHQ consistency block consuming this module; (3)
relabel the existing coach metrics to *"Adherence (quality)"*.

**Standing caveat:** all verification is machine-run. **No human has seen any of
this on a device.**

---

*Verified 2026-07-28: analyze clean · 312/312. No backend change. Nothing
committed.*
