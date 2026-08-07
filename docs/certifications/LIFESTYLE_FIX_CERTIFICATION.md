# LIFESTYLE — DEFECT A & B: FIX CERTIFICATION

**Scope:** the two proven defects only. No redesign, no refactor, no optimisation.
**Status: CERTIFIED.** Every layer passes, including the live end-to-end loop on device.

---

## 1. What changed — the complete change set

| File | Change |
|---|---|
| `trainershq-backend/firestore.rules` | **Defect A** — one clause added to each of two `allow read` rules |
| `alphaserena/lib/controllers/lifestyle_controller.dart` | **Defect B** — bind gate + bind key; 3 call sites routed through it |
| `trainershq-backend/tests/rules/lifestyle_read_path_validation.mjs` | +5 rules tests |
| `alphaserena/test/lifestyle_controller_test.dart` | +7 lifecycle tests |

**Nothing else was touched.** No functions, no indexes, no models, no services, no widgets, no
architecture.

> One pre-existing uncommitted edit is visible in the rules diff — a comment-only correction to
> `validSupplementPlan` from the previous remediation session (LS-11). It is not part of this mission
> and changes no logic.

### Rules diff — the whole of Defect A

```diff
  match /client_lifestyle_days/{id} {
-   allow read: if isSuperAdmin()
+   allow read: if (resource == null && signedIn())
+     || isSuperAdmin()
      || (isAdmin()    && resource.data.adminId  == request.auth.uid)
      || (orgTrainer() && resource.data.adminId  == trainerAdminId())
      || (signedIn()   && resource.data.authorUid == request.auth.uid);

  match /client_lifestyle_logs/{id} {
-   allow read: if isSuperAdmin()
+   allow read: if (resource == null && signedIn())
+     || isSuperAdmin()
      || (isAdmin()    && resource.data.adminId == request.auth.uid)
      || (orgTrainer() && resource.data.adminId == trainerAdminId())
      || (signedIn()   && resource.data.authorId == request.auth.uid);
```

`client_lifestyle_logs` is included because **the same controller opens a listener on it** in the
same `_subscribe()`; its target was observed registered-and-never-acknowledged identically.

**Security is not weakened, and that is asserted, not claimed.** A null `resource` has no fields, so
the clause returns no data — it only lets a missing document read as empty. Every clause that
returns real data is byte-identical. Three new tests pin it:

- an **existing** foreign day is still denied to a rival org and to a signed-in stranger
- an **anonymous** caller is denied whether the document exists or not
- the coach and in-org trainer still read it

### Controller diff — the whole of Defect B

```dart
+ String? _boundKey;
+ String get _bindKey => '${_member.clientId}|$dateKeyStr';

  void onInit() {
    super.onInit();
-   _subscribe();
-   _linkWorker = ever(_member.isLinked, (_) => _subscribe());
+   _bindWhenReady();
+   _linkWorker = ever(_member.client, (_) => _bindWhenReady());
  }

+ void _bindWhenReady() {
+   if (!canLog) return;                 // never bind a dead stream
+   if (_boundKey == _bindKey) return;   // never duplicate
+   _subscribe();
+ }

  void _subscribe() {
    _sub?.cancel();
    _eventSub?.cancel();
+   _boundKey = _bindKey;   // stamped BEFORE opening, so a re-entrant call cannot double-bind
```

`ensureFreshDay()` and `selectDay()` now call `_bindWhenReady()` instead of `_subscribe()`, so there
is exactly **one** binding path.

**Requirements, and how each is met — by construction, not by convention:**

| Requirement | Mechanism |
|---|---|
| begins only after every prerequisite | `if (!canLog) return` — and `client` is the *last* input to arrive |
| exactly one active listener | one bind path, guarded by `_boundKey` |
| never zero | binds on the edge where prerequisites land, and immediately if already met |
| never duplicated | `_boundKey == _bindKey` short-circuits; stamped before opening |
| never stale | the key carries **member AND day**, so either change rebinds |
| deterministic | one signal (`client`), one edge, one bind |
| no polling / delay / retry / timer / force refresh | none used — verified by inspection of the diff |

---

## 2. Automated validation — every layer

| Layer | Result | Baseline |
|---|---|---|
| alphaserena `flutter analyze` | **0 issues** | 0 |
| alphaserena tests | **1076 pass** / 14 fail | 14 = documented pre-existing golden-image failures |
| trainersHQ `flutter analyze` | **26** | 26 (unchanged) |
| trainersHQ tests | **1793 pass** / 3 fail | 3 = documented pre-existing `serena/*` goldens |
| backend `tsc` + `npm test` | **1024 / 1024** | 1024 |
| **Firestore rules (real emulator)** | **380 / 380** | 375 → **+5** |
| **Patrol on emulator-5554** | **47 / 47** | lifestyle 20 · history 13 · home 14 |

The 7 new lifecycle tests were **proven to fail on the old code**: reverting `onInit` alone turns
6 of 7 red. The 5 new rules tests fail against the pre-fix rules by construction.

---

## 3. Live end-to-end validation — the three mandated proofs

Real app, real member (`EkNg2Yux4lPAQtSpQjds`), live `trainershq-f5ded`, rules deployed.

### Proof 1 — fresh install → log → every surface

The reinstall wiped app data, so this ran from a **clean cache with no local state**.

| Step | Observed |
|---|---|
| Home, first paint | Water **7 glasses (70%)** · Steps **2,000 (20%)** · Sleep **8h (100%)** — read back for the first time |
| Today's Targets | **7 of 10 glasses · 1,750 ml / 2,500 ml**, ring filled, "1 of 3 goals met", 63% |
| Tap **+** | **7 → 8 glasses · 1,750 → 2,000 ml**, ring advanced, summary 63% → 67% — **immediately** |
| Home | **8 glasses · 80%** |
| History | **Mon 3 Aug = 2.0 L** (was 1.8 L) |

`8 glasses = 2,000 ml = 2.0 L` — Today's Targets, Home and History agree exactly.

### Proof 2 — restart

| Check | Result |
|---|---|
| Same values after full restart | ✅ 8 glasses · 2,000 steps · 8h |
| No duplicates | ✅ exactly **1 listener per lifestyle path** |
| No stale cache | ✅ values match the server-derived rollup |
| No missing listener | ✅ both lifestyle targets present and acknowledged |

### Proof 3 — new day (the scenario that was broken)

Clock advanced to **9 Aug**, a day with **no document at all** — the exact condition that produced
`PERMISSION_DENIED` before.

| Check | Result |
|---|---|
| Listener attaches | ✅ targets 48 + 50 created |
| No permission denied | ✅ logcat grep for a lifestyle denial → **NONE** |
| Screen state | ✅ "Nothing logged yet", 0 of 10 glasses |
| **First glass works** | ✅ **0 → 1 · 250 ml / 2,500 ml**, ring advanced, 10% |

---

## 4. Firestore listener evidence — the instrument that proved the bug

Pulled from the Firestore SDK's own SQLite store (`run-as com.alphaserena`), zero app modification.
`snapshot_version = 0` with an empty resume token = **the listen was never acknowledged**.

**Before the fix**

| Target | Path | snap | token | docs |
|---|---|---|---|---|
| 46 | `client_lifestyle_days/…_2026-08-06` | **0** | **0 B** | **0** |
| 44 | `client_lifestyle_logs/…_2026-08-06` | **0** | **0 B** | **0** |

…and on a clean boot, **no target existed at all** for the current day.

**After the fix**

| Target | Path | snap | token |
|---|---|---|---|
| 24 | `client_lifestyle_days/…_2026-08-03` | **1785727976** | **11 B** |
| 22 | `client_lifestyle_logs/…_2026-08-03` | **1785727972** | **11 B** |
| 50 | `client_lifestyle_days/…_2026-08-09` (new day) | **1785728268** | **11 B** |
| 48 | `client_lifestyle_logs/…_2026-08-09` (new day) | **1785728268** | **11 B** |

**Counts:** 1 listener per path per day — 2 paths × 2 days = 4, zero duplicates. Every lifestyle
listen acknowledged. The only remaining unacknowledged targets on the device are
`client_workout_sessions` and `chats` — out of scope, see §6.

**Controller / stream counts:** one `LifestyleController` serves Home and Today's Targets (both
resolve `Get.isRegistered ? find : put`), and it opens exactly **2** streams — the events document
and the legacy projection — which is what the 2 targets per day show. `LifestyleHistoryController`
is separate and owns its 3 monthly rollup listeners.

---

## 5. Runtime propagation timeline — after the fix

```
clientProfiles snapshot   → clientId, isLinked          (canLog still false — correctly no bind)
clients snapshot          → adminId                     → ever(client) → _bindWhenReady()
                                                        → canLog true, _boundKey null → BIND
listener attaches         → target 24, acknowledged, 11-byte resume token
first snapshot            → events map → parseCoachingEvents → events RxList
Obx rebuild               → 7 glasses · 1,750 ml
─────────────────────────────────────────────────────────────────────────────
TAP +  → logDrink → Firestore write → local snapshot (latency compensation)
       → events RxList → Obx → 8 glasses · 2,000 ml            (immediate)
       → server ack → onLifestyleDayWritten → coaching_rollups
       → History listener → 2.0 L                              (seconds)
```

---

## 6. Deployed, and what remains

**Deployed to `trainershq-f5ded`** (authorised by you): `firebase deploy --only firestore:rules` —
rules compiled and released. No functions, no indexes.

**Deliberately NOT fixed — outside the two proven defects:**

1. **`client_workout_sessions`, `client_nutrition_days`, `chats`** carry the identical missing-document
   rule shape and are **failing live on this device right now** (`PERMISSION_DENIED` in logcat, targets
   unacknowledged). Same one-line class of fix. Not touched because you scoped this mission to the two
   proven defects — but they are real, observed, and worth their own pass.
2. **`onError: (_) => isLoading.value = false`** still discards a stream error, so a future denial
   would again present as "nothing logged" rather than as a failure. Not in scope; recommended next.

**Test residue on the live account:** 3 Aug now 2.0 L water; 9 Aug now 250 ml water (from advancing
the clock). Emulator clock restored to automatic.

---

## 7. Certification

| Gate | State |
|---|---|
| Defect A repaired, security proven unweakened | ✅ 380/380 rules tests incl. 3 explicit security assertions |
| Defect B repaired, all five lifecycle guarantees | ✅ 7 tests, proven failing on old code |
| Nothing outside the two defects changed | ✅ |
| analyze · Flutter tests · backend · rules · Patrol | ✅ all baselines held |
| Fresh → log → UI → Home → History | ✅ observed |
| Restart → same values, no duplicates, no stale | ✅ observed |
| New day → attach, no denial, first glass works | ✅ observed |

**Certified.**
