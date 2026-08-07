# LIFESTYLE — RUNTIME DIVERGENCE REPORT

**Method:** the running application on `emulator-5554`, live Firebase (`trainershq-f5ded`), real
signed-in member `EkNg2Yux4lPAQtSpQjds`. Previous certifications disregarded. **Report only — nothing
was changed.**

---

## THE HEADLINE

**Everything writes. Nothing reads back.**

The member's water, steps and sleep all reach Firestore, are derived by the Cloud Function, land in
the rollup, and render correctly in **History**. They never appear on **Today's Targets** or **Home**,
which sit at "0" and "—" forever.

**Propagation stops at exactly one point: the member app's own read of `client_lifestyle_days`.**
Everything upstream of that read and everything downstream of the rollup is healthy.

> ⚠️ My previous certification claimed Patrol 47/47 and "state propagation verified". That was
> false in the way that matters: **every one of those tests fakes the Firestore boundary**
> (`_Events`, `_Log`, `_Rollups`). Not one exercised a real listener. The suite proved the
> derivations, never the wiring.

---

## 1. What I did, and what I saw

Emulator clock started at **Mon 3 Aug 08:12**, later advanced to **Thu 6 Aug** to get a clean day.

| # | Action | Today's Targets | Home | History (rollup) |
|---|---|---|---|---|
| 1 | Baseline | `0 of 10 glasses`, `0 ml` | Water/Steps/Sleep all `—` | 3 Aug already held **0.55 L** |
| 2 | **+ × 3** (water) | **still 0** | — | **1.3 L** ✅ (= 0.55 + 3×250) |
| 3 | **+ × 2** more | **still 0** | — | **1.8 L** ✅ (= +2×250) |
| 4 | Cold restart | **still 0** | still `—` | 1.8 L retained |
| 5 | Clock → 6 Aug, relaunch, **+ × 2** | **still 0** | — | 6 Aug = **0.5 L** ✅ |
| 6 | **Steps 8200 → Save** | **still `—`** | — | 6 Aug best day **8.2k** ✅ |
| 7 | **Sleep 22:30 → 06:30 → Save** | **still `—`** | — | 6 Aug **8.0h, goal hit, 100%** ✅ |

Every arithmetic check ties out to the millilitre. The writes are not merely "landing" — they are
landing **exactly right**.

**No error banner, no offline banner, no exception, no red screen at any point.** The failure is
completely silent.

---

## 2. State-transition trace

```
TAP "+"
 │
 ├─ Widget         _GlassButton.onTap                                  ✅ fires
 ├─ Controller     LifestyleController.addGlass(1)                     ✅ runs
 ├─ Service        LifestyleEventService.logDrink → _append            ✅ canLog TRUE here
 ├─ Repository     CoachingEventWriter.appendEvent                     ✅
 ├─ FIRESTORE      set client_lifestyle_days/{cid}_{date} (merge)      ✅ PROVEN by rollup delta
 │
 ├─ CLOUD FN       onLifestyleDayWritten (deployed, v2, confirmed)     ✅ fires
 ├─ Derivation     deriveLifestyleMetrics                              ✅ exact values
 ├─ FIRESTORE      coaching_rollups/{cid}_2026-08                      ✅ written
 │
 ├─► HISTORY BRANCH
 │    MemberRollupService.watchDays → RollupDay → Rx → rebuild         ✅ LIVE AND CORRECT
 │
 └─► TODAY / HOME BRANCH
      CoachingEventWriter.watchDay(client_lifestyle_days)              ❌ ***NEVER DELIVERS***
      parseCoachingEvents                                              ❌ receives []
      LifestyleController.events (RxList)                              ❌ stays empty
      waterMl / steps / sleepHours getters                             ❌ 0 / null / null
      Obx rebuild                                                      ✅ rebuilds — with nothing
```

**First divergence: the `client_lifestyle_days` snapshot stream feeding `LifestyleController.events`.**

---

## 3. Why — root cause

`LifestyleController._subscribe()` runs **synchronously inside `onInit`**. Both streams it opens are
gated on `canLog`:

```dart
bool get canLog =>                       // LifestyleLogService / LifestyleEventService
    _member.clientId.isNotEmpty &&
    _member.adminId.isNotEmpty &&        // ← from the CLIENTS doc snapshot
    _member.uid.isNotEmpty;
```

```dart
Stream<List<CoachingEvent>> watchDay(String dateKey) {
  if (!canLog) return Stream.value(const []);   // ← a DEAD stream, not an error
  ...
}
```

`adminId` is read from `client.value?['adminId']` — the **`clients` document snapshot**, which is
asynchronous and therefore *always* arrives after the synchronous `onInit`. So at subscribe time
`canLog` is **false**, and `watchDay` returns `Stream.value(const [])`: no Firestore listener is ever
opened.

The only re-subscribe trigger is:

```dart
_linkWorker = ever(_member.isLinked, (_) => _subscribe());
```

`isLinked` flips when the **`clientProfiles`** snapshot resolves — which is *earlier* than the
`clients` snapshot that supplies `adminId`. So the rebind fires while `canLog` is **still false**,
and `isLinked` never changes again. **The stream is permanently dead for the life of the process.**

### The smoking gun is visible on screen

The card renders **"of 10 glasses", "goal 10,000", "goal 8h"** — those targets come from
`client.value['lifestyleTargets']`, i.e. **the very same `clients` document that supplies `adminId`.**
So the document demonstrably arrived and made the UI update reactively — while the events stream
stayed bound to the empty stream created before it landed.

### Every observation is explained

| Observation | Explanation |
|---|---|
| Writes succeed | `canLog` is true by the time a human taps — only `_subscribe()` ran too early |
| Reads never succeed | listener never opened |
| Survives cold restart | `_subscribe()` is synchronous in `onInit` **every** launch — deterministic, not a flaky race |
| No permission error in logcat | nothing was ever requested; there is no denied listen for this path |
| No error/offline banner | writes genuinely succeed, so nothing reports a failure |
| Skeleton doesn't hang | the dead streams still **emit once**, so `isLoading` correctly goes false |
| **History works** | `MemberRollupService.canRead` needs **only `clientId`** — not `adminId` — and is created later, when the screen is opened |

That last row is the clincher: the one lifestyle surface with a *different* gate is the one that works.

**Confidence:** the localisation (§2) is *proven* by execution. The mechanism (§3) is inferred from
code plus six independent behavioural signals; I did not attach a debugger to watch `canLog` at
subscribe time, so I am labelling it root cause **identified**, one step short of direct instrumentation.

---

## 4. Secondary observations (real, separate from the above)

1. **`PERMISSION_DENIED` on two unrelated collections**, repeatedly, for this member:
   `client_workout_sessions/ws_..._2026-08-03` and `chats/EkNg2Yux4lPAQtSpQjds`. Not lifestyle, but
   live rule failures on the member's own data.
2. **App Check is failing** (`Too many attempts`) and FCM registration fails
   (`AUTHENTICATION_FAILED`). Not implicated in this defect — Firestore writes succeed — but worth
   knowing before blaming the network for anything else.
3. **The sleep editor never closes.** `showEditor = _editing || !c.hasSleepRecord`, and
   `hasSleepRecord` reads the dead stream, so it is always false. A saved night can never present as
   saved — a direct consequence of the same root cause.
4. **The widget's own local state works.** "Duration 8h" computed and displayed correctly, because
   it lives in `_SleepCardState`, not in the controller. Only controller-derived values are dead.

---

## 5. Not observed — stated plainly

- **TrainerHQ (step 8) was NOT run.** It reads `coaching_rollups` — the *same documents* History
  reads and which are proven correct here — via `lifestyleDaysFromRollup`. The coach side is
  therefore *expected* healthy, but that is inference, not observation. It needs its own run with
  coach credentials.
- **Supplements** could not be exercised: this member's coach has prescribed no stack
  ("Your coach hasn't added supplements yet").

## 6. Test residue I created

Real data was written to this member's live records: **3 Aug +1.25 L water**; **6 Aug 0.5 L water,
8,200 steps, 8 h sleep** (6 Aug came from advancing the emulator clock). The emulator clock is
restored to automatic. Remove these if the account matters.

---

## 7. Bottom line

The pipeline is sound end to end — writes, trigger, derivation, rollup, History. **One dead stream**
in the member app makes the two screens the member actually uses look permanently empty, while their
coach sees everything. That is why the certification's "47/47" meant nothing here: the fakes replaced
precisely the component that is broken.

**No fix applied, as instructed.**
