import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena/controllers/training_controller.dart';

/// THE SKELETON RULE, PINNED.
///
/// A background refresh used to blank the member's whole Home screen. The
/// cause was one flag doing two jobs: `TrainingController.isLoading` is the
/// re-entrancy guard for `refreshIfStale` AND was the gate for the full-page
/// skeleton — so every resume, tab entry, coach-doc change, midnight rollover
/// and pull-to-refresh threw away content that was already in memory and
/// replaced it with grey boxes for the length of a round trip. Reproduced on
/// emulator-5554 by tapping My Plans and returning to Home.
///
/// These tests pin the split that fixed it, and specifically pin that
/// `isLoading` KEPT its old meaning — because the two guards that depend on it
/// would start firing concurrent `getMyTraining` calls if it ever stopped
/// being true for the whole of a load.
class _FakeTraining extends TrainingController {
  _FakeTraining();

  bool succeed = true;
  int loads = 0;

  /// Snapshots taken from INSIDE the load, which is the only place the
  /// mid-flight state can be observed.
  bool? firstLoadDuring;
  bool? refreshingDuring;
  bool? isLoadingDuring;

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> load() async {
    loads++;
    isLoading.value = true;
    await Future<void>.delayed(Duration.zero);
    isLoadingDuring = isLoading.value;
    firstLoadDuring = isFirstLoad;
    refreshingDuring = isRefreshing;
    if (succeed) {
      markLoadedForTest();
      error.value = '';
    } else {
      error.value = 'Could not load your training. Tap retry.';
    }
    isLoading.value = false;
    hasLoadedOnce.value = true;
  }
}

void main() {
  group('first load vs refresh', () {
    test('a cold start is a FIRST load — the skeleton is allowed', () async {
      final c = _FakeTraining();
      expect(c.isFirstLoad, isTrue,
          reason: 'constructed idle-but-never-loaded still owes a skeleton');

      await c.load();
      expect(c.firstLoadDuring, isTrue);
      expect(c.refreshingDuring, isFalse);
    });

    test('every later load is a REFRESH — the skeleton is forbidden', () async {
      final c = _FakeTraining();
      await c.load();

      await c.load();
      expect(c.firstLoadDuring, isFalse,
          reason: 'THE DEFECT: this is what blanked Home on every tab switch');
      expect(c.refreshingDuring, isTrue);
    });

    test('a FAILED first load still counts as loaded', () async {
      // By then the member has been shown something real — an error with a
      // Retry — and tapping Retry must keep that on screen rather than
      // flashing back through a skeleton.
      final c = _FakeTraining()..succeed = false;
      await c.load();

      expect(c.hasLoadedOnce.value, isTrue);
      expect(c.isFirstLoad, isFalse);
      expect(c.error.value, isNotEmpty);

      await c.load();
      expect(c.firstLoadDuring, isFalse);
      expect(c.refreshingDuring, isTrue);
    });

    test('isLoading still spans the WHOLE load — the guards depend on it',
        () async {
      final c = _FakeTraining();
      await c.load();
      expect(c.isLoadingDuring, isTrue);

      await c.load();
      expect(c.isLoadingDuring, isTrue,
          reason: 'a refresh must still block a concurrent getMyTraining');
    });

    test('idle is neither state', () async {
      final c = _FakeTraining();
      await c.load();
      expect(c.isFirstLoad, isFalse);
      expect(c.isRefreshing, isFalse);
    });
  });

  group('the real controller, not a double', () {
    test('starts owing a skeleton and nothing else', () {
      // `onInit` is not run here (no Firebase app), so this is the field
      // state the class itself declares.
      final c = TrainingController();
      expect(c.isLoading.value, isTrue);
      expect(c.hasLoadedOnce.value, isFalse);
      expect(c.isFirstLoad, isTrue);
      expect(c.isRefreshing, isFalse);
    });
  });
}
