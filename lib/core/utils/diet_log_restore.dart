// Pure meal-log restore (Nutrition Foundation V2A): re-attach each logged mark
// to its food by STABLE IDENTITY (foodId + meal), not by array position. No
// Flutter/Firebase — unit-testable in isolation. See diet_log_restore_test.dart.
library;

/// A mark the member previously logged: which food (by [foodId] + [meal]), the
/// plan [idx] it held when logged (a legacy fallback only), and its
/// eaten/partial/skipped [status].
typedef LoggedMark = ({String foodId, String meal, int idx, String status});

/// A food in the CURRENT plan, addressed by its stable identity
/// ([foodId] + [meal]).
typedef PlanFood = ({String foodId, String meal});

/// Restores the member's per-food marks against the CURRENT plan by identity.
///
/// Returns CURRENT-plan index → status. Each logged mark binds to the food
/// carrying the same ([foodId], [meal]) — so a coach reordering or editing the
/// plan moves the mark WITH the food instead of reattaching it to whatever now
/// sits at the old index (the V1 index-restore bug). A food may legitimately
/// repeat (same food, same meal); matches are consumed left-to-right so N
/// logged marks fill N current slots.
///
/// Legacy/freehand marks (empty [foodId] — pre-V2A logs) fall back to their
/// stored [idx] when it is still in range and unclaimed. Identity marks resolve
/// FIRST so a legacy index can never steal a slot an identity mark owns. A mark
/// whose food is no longer in the plan is dropped.
Map<int, String> restoreStatusesByIdentity(
  List<LoggedMark> logged,
  List<PlanFood> currentFoods,
) {
  final result = <int, String>{};
  final used = <int>{};

  int? claimByIdentity(String foodId, String meal) {
    for (var i = 0; i < currentFoods.length; i++) {
      if (used.contains(i)) continue;
      final f = currentFoods[i];
      if (f.foodId == foodId && f.meal == meal) return i;
    }
    return null;
  }

  // Pass 1 — identity marks (non-empty foodId) bind to their food.
  final legacy = <LoggedMark>[];
  for (final m in logged) {
    if (m.foodId.isEmpty) {
      legacy.add(m);
      continue;
    }
    final i = claimByIdentity(m.foodId, m.meal);
    if (i != null) {
      used.add(i);
      result[i] = m.status;
    }
  }

  // Pass 2 — legacy/freehand marks fall back to their stored index.
  for (final m in legacy) {
    final i = m.idx;
    if (i >= 0 && i < currentFoods.length && !used.contains(i)) {
      used.add(i);
      result[i] = m.status;
    }
  }

  return result;
}

/// The one-time restore decision, as a pure state machine — extracted so the
/// load-order race between the plan and the day's log snapshot is testable.
enum RestoreAction {
  /// Already restored, or the member is actively marking — do nothing.
  noop,

  /// A prerequisite isn't ready yet (log snapshot / doc / plan still loading) —
  /// leave the restore un-run and retry when more data arrives.
  wait,

  /// Restore the persisted marks against the current plan by identity.
  restore,
}

/// Decides whether the member's marks can be restored yet.
///
/// The restore fires exactly once, only when a document exists AND the plan has
/// loaded AND the member has not started marking. Every not-ready state resolves
/// to [wait] (never a terminal latch) so late-arriving data still restores:
///  * [logArrived] distinguishes "the log stream has not emitted" from "the log
///    document does not exist" — a plan that loads before the first log snapshot
///    must wait, not conclude "nothing to restore".
///  * an absent document ([logExists] false) also waits, because a cold/offline
///    cache miss can emit null first and the real document moments later.
/// The wait ends naturally: either the document + plan arrive (→ [restore]) or
/// the member starts marking (→ [noop]); an absent document with no marks simply
/// never restores, which is correct (there is nothing to restore).
RestoreAction restoreAction({
  required bool alreadyRestored,
  required bool hasLocalMarks,
  required bool logArrived,
  required bool logExists,
  required bool planLoaded,
}) {
  if (alreadyRestored || hasLocalMarks) return RestoreAction.noop;
  if (!logArrived) return RestoreAction.wait;
  if (!logExists) return RestoreAction.wait;
  if (!planLoaded) return RestoreAction.wait;
  return RestoreAction.restore;
}
