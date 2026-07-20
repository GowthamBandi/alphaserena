import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/utils/diet_log_restore.dart';

/// V2A meal-log identity: a logged mark is restored to its food by STABLE
/// IDENTITY (foodId + meal), not by array position — so a coach reordering or
/// editing the plan mid-day no longer reattaches a member's mark to a different
/// food. Legacy logs (no foodId) fall back to the stored index.
void main() {
  group('restoreStatusesByIdentity', () {
    test('follows a food to its new position after a plan reorder', () {
      final restored = restoreStatusesByIdentity(
        [(foodId: 'a', meal: 'Breakfast', idx: 0, status: 'eaten')],
        [(foodId: 'b', meal: 'Lunch'), (foodId: 'a', meal: 'Breakfast')],
      );
      expect(restored, {1: 'eaten'});
    });

    test('restores multiple marks by identity regardless of order', () {
      final restored = restoreStatusesByIdentity(
        [
          (foodId: 'a', meal: 'Breakfast', idx: 0, status: 'eaten'),
          (foodId: 'b', meal: 'Lunch', idx: 1, status: 'partial'),
        ],
        [(foodId: 'b', meal: 'Lunch'), (foodId: 'a', meal: 'Breakfast')],
      );
      expect(restored, {1: 'eaten', 0: 'partial'});
    });

    test('legacy mark with no foodId falls back to its stored index', () {
      final restored = restoreStatusesByIdentity(
        [(foodId: '', meal: '', idx: 2, status: 'eaten')],
        [
          (foodId: 'a', meal: 'B'),
          (foodId: 'b', meal: 'L'),
          (foodId: 'c', meal: 'D'),
        ],
      );
      expect(restored, {2: 'eaten'});
    });

    test('drops a legacy mark whose index is out of range', () {
      final restored = restoreStatusesByIdentity(
        [(foodId: '', meal: '', idx: 5, status: 'eaten')],
        [(foodId: 'a', meal: 'B')],
      );
      expect(restored, <int, String>{});
    });

    test('drops an identity mark whose food is no longer in the plan', () {
      final restored = restoreStatusesByIdentity(
        [(foodId: 'x', meal: 'Lunch', idx: 0, status: 'eaten')],
        [(foodId: 'a', meal: 'Breakfast')],
      );
      expect(restored, <int, String>{});
    });

    test('keys on meal too — same food in two meals stays distinct', () {
      final restored = restoreStatusesByIdentity(
        [
          (foodId: 'a', meal: 'Breakfast', idx: 0, status: 'eaten'),
          (foodId: 'a', meal: 'Dinner', idx: 1, status: 'partial'),
        ],
        [(foodId: 'a', meal: 'Dinner'), (foodId: 'a', meal: 'Breakfast')],
      );
      expect(restored, {1: 'eaten', 0: 'partial'});
    });

    test('duplicate food+meal consumes current positions in order', () {
      final restored = restoreStatusesByIdentity(
        [
          (foodId: 'a', meal: 'Lunch', idx: 0, status: 'eaten'),
          (foodId: 'a', meal: 'Lunch', idx: 1, status: 'partial'),
        ],
        [(foodId: 'a', meal: 'Lunch'), (foodId: 'a', meal: 'Lunch')],
      );
      expect(restored, {0: 'eaten', 1: 'partial'});
    });

    test('identity marks win before legacy index fallback claims a slot', () {
      // A post-migration log is all-identity; this locks that when both kinds
      // are present, identity resolution runs first so a legacy idx cannot
      // steal a slot an identity mark owns.
      final restored = restoreStatusesByIdentity(
        [
          (foodId: '', meal: '', idx: 0, status: 'skipped'),
          (foodId: 'a', meal: 'X', idx: 1, status: 'eaten'),
        ],
        [(foodId: 'a', meal: 'X'), (foodId: 'b', meal: 'Y')],
      );
      // 'a' claims index 0 by identity; the legacy idx-0 mark finds it taken.
      expect(restored, {0: 'eaten'});
    });

    test('empty inputs produce an empty restore map', () {
      expect(restoreStatusesByIdentity(const [], const []), <int, String>{});
    });
  });

  group('restoreAction (one-time restore state machine)', () {
    test('waits when the log snapshot has not arrived yet (plan-first race)', () {
      // The plan can load BEFORE the log stream emits. If we concluded
      // "nothing to restore" here, a real log arriving moments later would be
      // skipped and the member's marks would silently vanish. Must WAIT.
      expect(
        restoreAction(
          alreadyRestored: false,
          hasLocalMarks: false,
          logArrived: false,
          logExists: false,
          planLoaded: true,
        ),
        RestoreAction.wait,
      );
    });

    test('restores once the log exists and the plan has loaded', () {
      expect(
        restoreAction(
          alreadyRestored: false,
          hasLocalMarks: false,
          logArrived: true,
          logExists: true,
          planLoaded: true,
        ),
        RestoreAction.restore,
      );
    });

    test('keeps waiting when no doc exists yet — a doc may still appear', () {
      // "No doc" must NOT be latched as terminal: on a cold/offline cache miss
      // the stream can emit null first and the real document moments later.
      // Latching here would skip that late doc and never restore. The member
      // starting to mark (hasLocalMarks) is what ends the wait, not an absent
      // doc.
      expect(
        restoreAction(
          alreadyRestored: false,
          hasLocalMarks: false,
          logArrived: true,
          logExists: false,
          planLoaded: true,
        ),
        RestoreAction.wait,
      );
    });

    test('waits for the plan when the log exists but foods have not loaded', () {
      expect(
        restoreAction(
          alreadyRestored: false,
          hasLocalMarks: false,
          logArrived: true,
          logExists: true,
          planLoaded: false,
        ),
        RestoreAction.wait,
      );
    });

    test('is a no-op once already restored', () {
      expect(
        restoreAction(
          alreadyRestored: true,
          hasLocalMarks: false,
          logArrived: true,
          logExists: true,
          planLoaded: true,
        ),
        RestoreAction.noop,
      );
    });

    test('is a no-op once the member has local marks (never clobber)', () {
      expect(
        restoreAction(
          alreadyRestored: false,
          hasLocalMarks: true,
          logArrived: true,
          logExists: true,
          planLoaded: true,
        ),
        RestoreAction.noop,
      );
    });
  });
}
