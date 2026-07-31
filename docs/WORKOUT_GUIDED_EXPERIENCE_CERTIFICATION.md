# Workout Guided Experience — Certification

- **Date:** 2026-07-28
- **Delivered:** the workout journey a coached member actually needs —
  **Briefing → Guided Session → Rest → Finish** — with exercise memory,
  session flow and full coach parity, on top of the certified Phase-1
  integrity foundation.
- **Scope respected.** Not started (later roadmap): PRs/strength history,
  analytics, AI, video rework, supersets, tempo, warm-up builder, exercise
  substitutions.
- **Backend and security rules untouched.** All new fields ride the existing
  member-owned write path. **Nothing committed. Nothing deployed.**

---

## 0. Reconstruction — the lifecycle as it stood

Builder (flat ordered exercises; per-set reps/weight/rest strings, nothing
else in the schema) → assign (single-active, per-client snapshot) →
`getMyTraining` (hydrates `setRows` + library metadata) → Prescription Engine
decides whether today asks for a session → Home →
**session screen** → per-set logging → `client_workout_sessions` → coach's
Member Logs / Progress / Timeline.

**Dead, fake or unreachable, found and resolved:**

| Finding | Resolution |
|---|---|
| `MemberLogsSessionScreen` (TrainerHQ) — a complete prescribed-vs-actual breakdown, **never navigated to** | **Wired**: every Member Logs day card now opens it |
| `SessionEntry.note` — read and rendered by the coach app, **no writer existed** | **Written**: the member's closing message (`memberNote`) now exists and renders on both coach surfaces |
| `equipment`, `difficulty` — served by the backend, **consumed by nothing** | **Used**: both appear on the briefing |
| `instructions` held in session state, never rendered | Still rendered only in the exercise-detail screen; unchanged this phase (video/detail rework is a later roadmap item) — the dead field was removed from session state |
| Duplicate set-building logic (session vs briefing would each parse served items) | **One shared implementation** — `exercisesFromServedItems` in the domain |
| Placeholder "Strength & 1RM — coming soon" (member progress) | **Left alone deliberately** — it belongs to the excluded PR/strength phase |

## 1. Audit — what a coach would object to (and what changed)

| Coach's objection | Change |
|---|---|
| "My client starts a session with no idea what today is or why." | **Briefing screen**: plan, coach's own note, exercises, sets, muscles, equipment, level, week position, honest duration estimate. |
| "They retype the numbers I already gave them." | Targets **prefill** the inputs; the member confirms or corrects. |
| "They don't know what they lifted last week — so they can't progress." | **Exercise memory**: "Last time 3 days ago: 3 sets · top 8 × 50kg", from their own logs only. |
| "Where are they in the session?" | Exercise N of M, **Set N of M**, and a session-wide progress bar in the app bar. |
| "The timer pauses when the phone locks." | **Wall-clock rest overlay** with pause, +30s, skip and haptics. |
| "Finishing feels like nothing happened." | **Summary screen**: duration, sets, skips, volume, adherence, and one line to the coach. |
| "I can't see the detail of what they did." | The dead breakdown screen is wired, and now shows skips, reasons, edits, duration, lifecycle and the member's note. |
| "A rest day and a lazy day look the same to me." | (Phase 1) explicit skip reasons — surfaced everywhere the coach looks. |

## 2. Design decisions, and why

- **One exercise, one set, one decision.** The focus card holds the set
  number, the coach's target in 30pt type, two inputs and one full-width
  button. Everything else on screen is secondary and compact — a member
  mid-set should never scroll to find the button.
- **Prefill is not fabrication.** The coach's prescription fills the inputs
  *visibly*, and only ever fills an **empty** field on a pending set. The
  member sees the numbers and taps Complete — an affirmative act. Typed
  values are never overwritten. (Rejected the alternative — blank fields —
  because it makes the common case, "did exactly as prescribed", the slowest
  path.)
- **Rest is wall-clock, never tick-counted.** The countdown derives from a
  deadline, so a locked phone, a call, or a backgrounded app returns to the
  correct remaining time. Pinned by a test that advances the widget clock
  *without* advancing real time and asserts the display does **not** jump.
- **Rest reminders never impersonate the coach.** Generic coaching lines,
  rotating; the coach's actual note appears in the briefing where it is
  attributed. (Test asserts no reminder contains the word "coach".)
- **The summary celebrates without infantilising.** No confetti, no trophies;
  a clean record of real work. Skips are shown **only when they happened** —
  a "0 skipped" tile would turn an honest option into an accusation. Volume
  is **absent** for bodyweight work rather than displayed as zero.
- **"Exercise done" is a state, not a dead end** — it replaces the focus card
  with the single next action (Next Exercise / Finish Workout).
- **Duration estimate is the only modelled number on any screen.** It is
  prescribed rest + a documented 45s/set constant, rounded to 5 minutes, and
  it always wears "≈" and the label "(est.)".

**Spec conflict, resolved explicitly:** Phase 5 of the brief asks for
"Personal best" while the stop conditions forbid starting "PRs / Strength
history". I implemented the **"what did I do last time"** memory (the
coaching core, from real logs) and did **not** build PR detection, a records
board, or progression charts. Those remain in the later roadmap phase where
the stop conditions place them.

## 3. Bugs discovered

1. **Note-write would have destroyed the session (found by self-challenge,
   in my own new code).** The summary's "Send to coach" initially routed
   through `saveSession` with `entries: []` and a fresh `date`; with
   `merge: true` that **erases every logged set** and re-stamps the session's
   time. Fixed with a dedicated two-field `saveMemberNote` write. This is the
   single most dangerous defect of the phase and it existed for ~20 minutes.
2. **Rest overlay overflowed** on a 320pt screen at 1.6× text scale (12px
   vertical, 143px horizontal on the action row) — caught by the new
   accessibility test before shipping. Fixed: responsive ring/number sizing
   and a `Wrap` for the actions.
3. **Dead `instructions` field** in session state (loaded, never rendered) —
   removed rather than left as a decoy.

## 4. Files changed

**alphaserena**
| File | Change |
|---|---|
| `lib/core/domain/workout_memory.dart` | **new, pure** — "last time" from real logs, id-first identity |
| `lib/core/domain/workout_session.dart` | + `edited` sets, `SessionStats` (volume/adherence with coach parity), duration estimate, `exercisesFromServedItems`, `distinctLabels` |
| `lib/core/services/workout_log_service.dart` | + `fetchRecentSessions` (index-free), + `saveMemberNote` (minimal write) |
| `lib/screens/dashboard/workout_briefing_screen.dart` | **new** |
| `lib/screens/dashboard/workout_rest_overlay.dart` | **new** — wall-clock, pause/+30s/skip, haptics, responsive |
| `lib/screens/dashboard/workout_summary_screen.dart` | **new** |
| `lib/screens/dashboard/workout_session_screen.dart` | guided rework; Phase-1 integrity internals preserved exactly |
| `lib/screens/dashboard/home/client_home_screen.dart` | all three workout entry points route through the briefing |
| `test/workout_memory_test.dart`, `test/workout_guided_widgets_test.dart` | **new — 15 tests**; `test/workout_session_test.dart` **+21** |

**trainersHQ**
| File | Change |
|---|---|
| `lib/core/models/client_workout_session_model.dart` | + `SessionSet.edited`, + `memberNote` |
| `lib/features/member_logs/screens/member_logs_screen.dart` | card → **opens the breakdown**; member note; "edited" markers |
| `lib/features/member_logs/screens/member_logs_session_screen.dart` | duration + lifecycle, member note, skip reasons, skipped rows, "edited" |

## 5. TrainerHQ parity verification

| Member produces | Coach sees | Where |
|---|---|---|
| duration | `42 min` | day card + breakdown |
| completion / lifecycle | %, "In progress", "Not finished" | day card + breakdown |
| skipped sets | count stat, "Skipped" rows | day card + breakdown |
| skip reasons | "Skipped by member — No equipment" | day card + breakdown |
| corrected sets | "edited" marker | day card + breakdown |
| closing message | quoted block, attributed | day card + breakdown |
| adherence | % on target — **same arithmetic both sides** | day card + breakdown + progress |
| timestamps | session time, `startedAt`/`finishedAt` | day card / model |

**Nothing exists on one side only.** The adherence rule (`setHitTarget`) is a
deliberate port of the coach app's `SessionSet.hit`, pinned by test, so the
summary's "83% on target" is the same 83% the coach reads.

## 6. Edge cases (Phase 9 self-challenge)

Phone locked / backgrounded → wall-clock rest, draft intact · process death →
draft resume (Phase 1, tested) · rotation → State survives; draft is a second
net · offline → queued semantics + cache-tolerant resume · **spam-tap
Complete** → the set resolves and its button disappears; **double-tap Finish**
→ `_finishing` guard · **resume after midnight / after 3 days** → day-key
mismatch means a *new* session, and yesterday's unfinished one reads
"Not finished" to the coach · **plan edited mid-session** → the draft (what
they actually did) wins for this session; the next session picks up the new
plan · **exercise deleted from the plan mid-session** → hydration is
bounds-checked, logging continues · app updated mid-session → draft is
versioned and parses defensively · multiple devices → same doc id,
last-write-wins (documented, unchanged) · very long coach note → wraps freely
· zero notes → section hidden, never an empty box · no history → memory line
absent, never a guess · small phone at 1.6× → tested.

## 7. Verification

| Check | Result |
|---|---|
| AlphaSerena `flutter analyze` | **No issues** |
| AlphaSerena `flutter test` | **481 / 481** (36 new this phase) |
| TrainerHQ `flutter analyze` / `flutter test` | **clean · 992 / 992** |
| Backend / rules | untouched — 560/560 + 202/202 stand |
| Debug APK | **built** (rebuilt after the note-write fix) |
| Dead code | the three items found in §0 are wired, written or removed |

## 8. Honest limitations

- **No human has used any of this on a device.** Every behaviour is pinned by
  unit or widget tests; none is pinned by a person in a gym.
- **The briefing and session screens have no widget tests** — they construct
  Firebase-backed controllers. Their *logic* is fully covered at the pure
  layer (stats, estimate, memory, parsing); their *layout* is not. The rest
  overlay, which is pure, is tested including accessibility.
- **Exercise memory costs one extra read per session open** (up to 30 recent
  sessions, index-free, best-effort, non-blocking). For a member with years
  of history this fetches more than it needs; a date-windowed query is the
  optimisation, and it needs an index.
- **Large plans are not lazily built**: the briefing renders all exercises
  eagerly, and the draft serialises the whole workout on each debounced save.
  Fine for realistic plans (4–12 exercises); a 100-exercise plan would be
  sluggish.
- **Sound is not implemented** — haptics only. The hook is a single call site
  (`_pulse`); adding audio needs a dependency and a mute/volume contract.
- **The estimate's 45s/set constant is a model, not measurement.** Once real
  durations accumulate, the member's own median for a plan should replace it.

## 9. Remaining roadmap (unchanged, in order)

Memory phase proper (PRs, strength history, progression) · coach-side
adherence v2 on week verdicts + a completion event in the notification
centre · builder vocabulary (tempo, supersets, warm-up sets, per-exercise
coach notes — authored and rendered together) · exercise detail/video rework
absorbing `WorkoutPlayerScreen` · substitutions · AI (coach-in-the-loop).

---

*Verified 2026-07-28: analyze clean both apps · 481/481 · 992/992 · debug APK
built. Nothing committed, nothing deployed.*
