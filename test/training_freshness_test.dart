import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena/controllers/training_controller.dart';

/// THE COACH HAS NO PUSH CHANNEL — so the pull has to be right.
///
/// `getMyTraining` is a one-shot callable. TrainerHQ's `AssignmentService`
/// writes ONLY to `client_plan_assignments` — a collection the member app
/// cannot read, and which does not touch the `clients` document the member DOES
/// stream. Verified by reading both sides. So nothing in the member app
/// observes an assignment change; the plan is only ever as fresh as the last
/// pull.
///
/// Before this pass the only pulls were app start, pull-to-refresh, a day
/// rollover, and a `HomeController` worker gated on `!hasPlan` (so it could
/// only help a member with no plan at all). A coach who replaced, paused or
/// REMOVED a plan reached an open app never — the member could keep opening,
/// and starting, a workout that had been withdrawn.
///
/// `refreshIfStale` is now called on app resume and on entering the My Plans
/// tab. These tests pin the three properties that make that safe to do on a
/// hot path.
class _CountingTraining extends TrainingController {
  _CountingTraining() {
    // The real controller starts `isLoading = true` because `onInit` fires
    // `load()` in the same breath. This double overrides `onInit`, so it must
    // represent the state a controller is ACTUALLY in when resume or a tab
    // switch calls `refreshIfStale`: idle. (A controller genuinely mid-load is
    // covered by the in-flight test below.)
    isLoading.value = false;
  }

  int loads = 0;

  /// Whether the next load should succeed. A FAILED load must not be treated
  /// as a fresh one.
  bool succeed = true;

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> load() async {
    loads++;
    isLoading.value = true;
    await Future<void>.delayed(Duration.zero);
    if (succeed) {
      // Mirrors the real controller: the freshness stamp is written on the
      // success path only. Reached here by calling through the real setter.
      markLoadedForTest();
      error.value = '';
    } else {
      error.value = 'Could not load your training. Tap retry.';
    }
    isLoading.value = false;
  }
}

void main() {
  test('a fresh plan is NOT re-fetched — this runs on resume and tab entry',
      () async {
    final c = _CountingTraining();
    await c.refreshIfStale();
    expect(c.loads, 1, reason: 'nothing loaded yet, so it must load');

    await c.refreshIfStale();
    await c.refreshIfStale();
    expect(
      c.loads,
      1,
      reason: 'getMyTraining fans out to several document reads; a member '
          'flicking between tabs must not re-run it every time',
    );
  });

  test('a STALE plan is re-fetched', () async {
    final c = _CountingTraining();
    await c.refreshIfStale();
    expect(c.loads, 1);

    // The member came back later.
    await c.refreshIfStale(maxAge: Duration.zero);
    expect(c.loads, 2);
  });

  test('a FAILED load never counts as fresh', () async {
    // Otherwise the controller would sit out the whole freshness window after
    // exactly the failure that most needs retrying.
    final c = _CountingTraining()..succeed = false;
    await c.refreshIfStale();
    expect(c.loads, 1);

    await c.refreshIfStale();
    expect(c.loads, 2, reason: 'still nothing successfully loaded');

    c.succeed = true;
    await c.refreshIfStale();
    expect(c.loads, 3);

    // Now it is genuinely fresh.
    await c.refreshIfStale();
    expect(c.loads, 3);
  });

  test('a load already in flight is never doubled', () async {
    final c = _CountingTraining();
    final first = c.refreshIfStale();
    // Resume and tab-entry can land in the same frame.
    final second = c.refreshIfStale();
    await Future.wait([first, second]);
    expect(c.loads, 1);
  });
}
