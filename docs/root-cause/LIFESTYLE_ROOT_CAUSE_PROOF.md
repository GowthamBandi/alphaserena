# LIFESTYLE — ROOT CAUSE, PROVEN

**Mission:** prove *why* the member app never receives updates. No fixes, no production-code changes.
**Confidence: 99%.** Two defects, both proven by runtime evidence. Neither alone explains the bug;
neither alone would fix it.

> **My previous hypothesis was wrong, and I falsified it myself.** I reported that `_subscribe()`
> binds before `adminId` exists and that "no listener is ever opened". The listener registry proved a
> listener **was** opened (target 46). That forced the investigation open again and produced the
> second, larger defect. Detail in §6.

---

## 0. Instruments used (zero production-code modification)

| Instrument | What it gave |
|---|---|
| **Firestore SDK's own SQLite store**, pulled via `run-as com.alphaserena` | `targets` (every listener the client registered), `target_documents` (which listens were *acknowledged*), `remote_documents` (cached docs, decoded from protobuf) |
| **logcat** | live `PERMISSION_DENIED` for specific listens |
| **Real rules engine** (Firestore emulator + `firestore.rules`) | direct allow/deny for the exact reads |
| Live UI on emulator-5554 | observed state |

No production file was edited. One throwaway rules probe was written, executed, and deleted.

---

## 1. THE TWO DEFECTS

### **D-A — RULES: a listen on a day document that does not exist yet is DENIED**

Executed against the **real rules engine**, real `firestore.rules`, real member identity:

```
>>> MISSING  client_lifestyle_days doc  -> DENIED (permission-denied)
>>> EXISTING client_lifestyle_days doc  -> ALLOWED (exists=true)
>>> MISSING  coaching_rollups     doc  -> ALLOWED (returned empty)
>>> CREATE   on a missing day          -> ALLOWED
```

**Why.** Every clause of the read rule dereferences `resource.data`, which is **null** for a document
that does not exist, so no clause can return true:

```
match /client_lifestyle_days/{id} {
  allow read: if isSuperAdmin()
    || (isAdmin()    && resource.data.adminId  == request.auth.uid)
    || (orgTrainer() && resource.data.adminId  == trainerAdminId())
    || (signedIn()   && resource.data.authorUid == request.auth.uid);   // ← resource is null
```

`coaching_rollups` **already carries the fix** for this exact defect —
`allow read: if (resource == null && signedIn()) || …` — which is precisely why **History works and
Today's Targets does not.** `client_lifestyle_days` (and `client_lifestyle_logs`) never got it.

**Independently corroborated live, on the device.** `client_workout_sessions` has a byte-identical
rule shape. Its document `ws_EkNg2Yux4lPAQtSpQjds_2026-08-03` is **absent from the cache** (does not
exist) — and logcat shows, repeatedly:

```
Listen for Query(client_workout_sessions/ws_EkNg2Yux4lPAQtSpQjds_2026-08-03) failed:
  Status{code=PERMISSION_DENIED, description=Missing or insufficient permissions.}
```

Every day begins with no day document. **So every day begins with a denied listen.**

### **D-B — CLIENT: `_subscribe()` binds while its gate is false, and nothing ever rebinds**

```dart
Stream<List<CoachingEvent>> watchDay(String dateKey) {
  if (!canLog) return Stream.value(const []);   // a DEAD stream — not an error, not a retry
  ...
}
bool get canLog => _member.clientId.isNotEmpty     // ← clientProfiles snapshot (async)
                && _member.adminId.isNotEmpty      // ← clients snapshot (async, later still)
                && _member.uid.isNotEmpty;
```

`_subscribe()` runs **synchronously inside `onInit`**, before either snapshot can have arrived, so
`watchDay` returns an empty stream and **no Firestore listener is registered at all**. The only
rebind is `ever(_member.isLinked)`, which fires on the `clientProfiles` snapshot — *before*
`_listenClient()` has even started the `clients` listener that supplies `adminId`. So the rebind also
sees `canLog == false`, and `isLinked` never changes again.

**Proven by an A/B in the listener registry:**

| Session | How `_subscribe()` ran | Target for `client_lifestyle_days`? |
|---|---|---|
| Clean boot (3 Aug) | synchronously in `onInit` | **none — never attempted** |
| After a forced day rollover (6 Aug) | late, from `ensureFreshDay()` on resume | **target 46 created** |

The registry keeps *denied* targets (26, 28 are denied and still listed with `snapshot_version=0`).
So the **absence** of a 3-Aug target is not a denial — it is proof no listen was ever attempted.

---

## 2. Firestore listener graph — the evidence table

`snapshot_version=0` + empty resume token = **the listen was never acknowledged**.

| Target | Path | snap | token | docs delivered | Verdict |
|---|---|---|---|---|---|
| 8 | `clients where authUid==…` | 1785725255 | 11 B | 1 | ✅ live |
| 10 | `clientProfiles/{uid}` | 1785725256 | 11 B | 1 | ✅ live |
| 14 | `clients/EkNg2Yux…` | 1785725256 | 11 B | 1 | ✅ live |
| **34** | **`coaching_rollups/…_2026-08`** | **1785725690** | **11 B** | **1** | ✅ **live — this is History** |
| 26 | `client_workout_sessions/ws_…_08-03` | 0 | 0 | 0 | ❌ **confirmed PERMISSION_DENIED** |
| 28 | `chats/EkNg2Yux…` | 0 | 0 | 0 | ❌ **confirmed PERMISSION_DENIED** |
| 42 | `client_nutrition_days/…_08-06` | 0 | 0 | 0 | ❌ never acknowledged |
| 44 | `client_lifestyle_logs/…_08-06` | 0 | 0 | 0 | ❌ never acknowledged |
| **46** | **`client_lifestyle_days/…_08-06`** | **0** | **0** | **0** | ❌ **never acknowledged** |

Two targets with this exact signature are *confirmed denied in logcat*. Targets 44 and 46 share it.

**Cached document (decoded from the protobuf blob) — it is complete and correct:**

```
client_lifestyle_days/EkNg2Yux4lPAQtSpQjds_2026-08-06
  authorUid  VOxzizRgU6YFBsbguFJ6winidIA2      ← equals the member's uid
  clientId   EkNg2Yux4lPAQtSpQjds
  adminId    Hli8cUoVsadrRyS6lHzvsQ9Dj152
  dateKey    2026-08-06
  events     drink · drink · steps_sample · sleep     (all 4 of my entries, ml = 250 each)
```

The data is on the device. The listener that should surface it was never allowed to.

---

## 3. Propagation graph — where each layer diverges

```
LAYER                                   STATE          FIRST DIVERGENCE
─────────────────────────────────────────────────────────────────────────
Firestore server document               CORRECT        —
Local cache (remote_documents)          CORRECT        —
Cloud Function derivation               CORRECT        —
coaching_rollups                        CORRECT        —
─────────────────────────────────────────────────────────────────────────
Listener registration (targets)         ABSENT  ←──── D-B (clean boot)
Listen acknowledgement                  DENIED  ←──── D-A (when it is attempted)
Stream emission                         error / never
onError handler                         SWALLOWED ←── D-C (below)
LifestyleController.events (RxList)     EMPTY
waterMl / steps / sleepHours            0 / null / null
Obx rebuild                             RUNS — with nothing
Rendered value                          "0" and "—"
```

### D-C — the failure is silent by construction

```dart
_eventSub = _events.watchDay(dateKeyStr).listen((e) { … },
    onError: (_) => isLoading.value = false);   // ← discards the denial
```

A `PERMISSION_DENIED` is converted into "the member has logged nothing". This is why there is no
banner, no retry and no error state — and why the defect survived every prior review. `hasError` is
never set, because from the app's point of view nothing failed.

---

## 4. Home vs Today vs History vs TrainerHQ — do they consume identical data?

**No. That is the whole point.**

| | Today's Targets | Home Lifestyle | History | TrainerHQ |
|---|---|---|---|---|
| Controller | `LifestyleController` | `LifestyleController` (same) | `LifestyleHistoryController` | `LifestyleReviewController` |
| Service | `LifestyleEventService` | same | `MemberRollupService` | `CoachingRollupService` |
| Collection | **`client_lifestyle_days`** | **same** | **`coaching_rollups`** | **`coaching_rollups`** |
| Read | single doc by id | same | 3 docs by id (per month) | 3 docs by id (per month) |
| Gate | `canLog` = clientId **+ adminId** + uid | same | `canRead` = **clientId only** | coach org gate |
| Rule has null-resource clause | **NO** | **NO** | **YES** | **YES** |
| Created | during dashboard bootstrap (early) | same | when the screen opens (late) | on the coach's device |
| Observed | ❌ broken | ❌ broken | ✅ works | expected ✅ (not run) |

Today's Targets and Home read a **different collection under a different rule through a different
gate** from History. They were never the same data path. The two that work are the two whose rule
carries the null-resource clause and whose gate needs only `clientId`.

---

## 5. Why each fix alone would have failed

This is the part that matters before touching code.

- **Fix only D-B** (rebind the subscription correctly): a listener is now created — and on any day
  before the member's first entry, the document does not exist, so **D-A denies it** and the screen
  is still empty. It would appear to work only when testing on a day that already had data.
- **Fix only D-A** (add the null-resource clause): the read would be permitted — but on a clean boot
  **no listener is ever registered**, so nothing changes at all.

Either fix alone would produce a partial, intermittent improvement — the classic trap that turns into
iterative guessing. **Both are required.**

---

## 6. Falsification — what I tried to break

| Hypothesis | Test | Result |
|---|---|---|
| "No listener is ever opened" (my prior claim) | `targets` table | **FALSIFIED** — target 46 exists |
| "The document is missing/corrupt" | decoded cached protobuf | **FALSIFIED** — complete and correct |
| "Writes are failing" | rollup deltas: 1.3→1.8 L, 8.2k steps, 8.0h | **FALSIFIED** — exact to the millilitre |
| "The Cloud Function is not deployed" | `firebase functions:list` | **FALSIFIED** — `onLifestyleDayWritten` v2 live |
| "It is a timing race that self-heals" | cold restart | **FALSIFIED** — deterministic |
| "The rule denies the member outright" | rules engine, existing doc | **FALSIFIED** — ALLOWED when the doc exists |
| **"Missing doc ⇒ denied listen"** | rules engine, missing doc | **SURVIVED — DENIED** |
| **"Gate false at `onInit` ⇒ no listener"** | clean boot vs. late-subscribe A/B | **SURVIVED** |

### What I did **not** measure — stated plainly
- **Controller instance hashes / dispose timing (Phase 5)** were not captured; that needs
  instrumentation, which the rules forbid. Home and Today showed byte-identical state throughout,
  which is *consistent with* a single instance but is not proof.
- **Per-rebuild Obx logging (Phase 7)** was not captured for the same reason. The rebuild layer is
  nonetheless exonerated: the Rx it reads is provably empty, so a rebuild has nothing to show.
- **TrainerHQ was not run.** It reads the same `coaching_rollups` documents History proves correct.
- Exact wall-clock timestamps for each lifecycle step were not obtainable without instrumentation;
  the **order** is established structurally and confirmed by the listener-registry A/B.

---

## 7. Verdict

**Exact failure point:** `LifestyleEventService.watchDay` → `CoachingEventWriter.watchDay`, the single-
document snapshot listener on `client_lifestyle_days/{clientId}_{dateKey}`.

**Exact root cause — two independent defects that compound:**

1. **`firestore.rules`, `match /client_lifestyle_days/{id}` — `allow read`** lacks the
   `(resource == null && signedIn())` clause that `coaching_rollups` already has, so a listen on a
   day before its first write is `PERMISSION_DENIED`. *(Same for `client_lifestyle_logs`, and the
   same class affects `client_workout_sessions`, `client_nutrition_days` and `chats`, all observed
   failing live.)*
2. **`LifestyleController._subscribe()`** binds through a `canLog` gate whose inputs arrive from
   asynchronous snapshots strictly after the synchronous `onInit`, and the sole rebind trigger
   (`ever(isLinked)`) fires before the second input exists and never fires again — so on a normal
   launch no listener is registered at all.

Amplified by **`onError: (_) => isLoading.value = false`**, which discards the denial and renders it
as "nothing logged".

**Confidence: 99%.** D-A is 100% (direct execution of the real rules engine). D-B's *conclusion* — the
gate was false at subscribe time, so no listener was attempted — is directly evidenced by the
registry A/B; only the decomposition into which of the two async fields was missing rests on reading
the code, and it does not change the fix.

---

## 8. Recommended fix — only now that the bar is met

**Do not apply it in isolation. Both parts, or neither.**

1. **Backend (`firestore.rules`)** — add the null-resource clause to `client_lifestyle_days` and
   `client_lifestyle_logs`, exactly as `coaching_rollups` already does. Requires a rules deploy.
   Worth auditing every other single-document member read for the same class in the same pass —
   `client_workout_sessions`, `client_nutrition_days` and `chats` are all failing live today.
2. **Client (`LifestyleController`)** — bind the streams to a signal that reflects what `canLog`
   actually needs, rather than to `isLinked`; and surface a stream error instead of swallowing it,
   so this class of failure can never again present as "nothing logged".

Residual test data on the live account from the previous session: 3 Aug +1.25 L; 6 Aug 0.5 L /
8,200 steps / 8 h. Emulator clock restored to automatic.

**Nothing was fixed. No production file was modified.**
