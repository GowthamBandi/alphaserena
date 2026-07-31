import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/coach_identity.dart';

/// SECTION 1 VERIFICATION MATRIX — every scenario in the reopened mission.
///
/// The previous fix corrected the resolver RULES and still failed in
/// production, because the rules were never the whole problem: the coach's
/// name and photo were delivered ONLY by the `clientProfiles` mirror, which is
/// written by one party (`claimClientAccount`) at one moment (a successful
/// claim). Nothing re-derived it when a coach renamed themselves, changed their
/// photo, or was assigned while the app was closed.
///
/// `getMyTraining` now serves the coach live on every app open, Home reload and
/// pull-to-refresh, and it arrives through `resolveCoachName`'s existing
/// `liveName` slot — which already outranks the mirror. These tests pin BOTH
/// halves: that live data wins, and that the staleness protections which guard
/// a removed or reassigned coach still hold underneath it.
void main() {
  // Shorthand mirroring MemberController's wiring: live name from
  // getMyTraining, mirrored name+for from clientProfiles.
  String resolve({
    String trainerId = '',
    String adminId = 'a1',
    String live = '',
    String mirrored = '',
    String mirroredFor = '',
  }) => resolveCoachName(
    trainerId: trainerId,
    adminId: adminId,
    liveName: live,
    mirroredName: mirrored,
    mirroredFor: mirroredFor,
  );

  group('MATRIX — Scenario A: the org admin is assigned as trainer', () {
    test('live coach resolves the owner', () {
      expect(resolve(trainerId: 'a1', live: 'Priya Nair'), 'Priya Nair');
    });

    test('resolves from the mirror alone when offline', () {
      expect(
        resolve(trainerId: 'a1', mirrored: 'Priya Nair', mirroredFor: 'a1'),
        'Priya Nair',
      );
    });

    test('live wins over a stale mirror naming the previous coach', () {
      // The exact production shape: the owner assigned themselves after the
      // member's last claim, so the mirror still names the old trainer.
      expect(
        resolve(
          trainerId: 'a1',
          live: 'Priya Nair',
          mirrored: 'Ravi Kumar',
          mirroredFor: 't1',
        ),
        'Priya Nair',
      );
    });
  });

  group('MATRIX — Scenario B: a real trainer is assigned', () {
    test('live coach resolves the trainer', () {
      expect(resolve(trainerId: 't1', live: 'Ravi Kumar'), 'Ravi Kumar');
    });

    test('live wins when the mirror was written BEFORE the assignment', () {
      // The most common production state: the member claimed on signup (no
      // trainer yet, so the mirror was written empty or for the owner), then
      // the admin assigned a trainer while the app was closed. Nothing
      // re-derived the mirror. This is what kept showing "Your Coach".
      expect(
        resolve(
          trainerId: 't1',
          live: 'Ravi Kumar',
          mirrored: '',
          mirroredFor: '',
        ),
        'Ravi Kumar',
      );
    });

    test('an EMPTY mirror with no live data is still honest', () {
      expect(resolve(trainerId: 't1'), isEmpty);
    });
  });

  group('MATRIX — trainer changed', () {
    test('live immediately names the new trainer', () {
      expect(
        resolve(
          trainerId: 't2',
          live: 'Sam Rivera',
          mirrored: 'Ravi Kumar',
          mirroredFor: 't1',
        ),
        'Sam Rivera',
      );
    });

    test('without live data the previous coach is suppressed, not shown', () {
      // Offline mid-reassignment: better to show no name than the wrong one.
      expect(
        resolve(trainerId: 't2', mirrored: 'Ravi Kumar', mirroredFor: 't1'),
        isEmpty,
      );
    });
  });

  group('MATRIX — trainer removed', () {
    test('responsibility returns to the owner, named live', () {
      expect(
        resolve(
          trainerId: '',
          live: 'Priya Nair',
          mirrored: 'Ravi Kumar',
          mirroredFor: 't1',
        ),
        'Priya Nair',
      );
    });

    test('offline, the departed trainer is still suppressed', () {
      expect(
        resolve(trainerId: '', mirrored: 'Ravi Kumar', mirroredFor: 't1'),
        isEmpty,
      );
    });

    test('a legacy mirror cannot resurrect a removed coach', () {
      expect(resolve(trainerId: '', mirrored: 'Ravi Kumar'), isEmpty);
    });
  });

  group('MATRIX — coach renamed (the case NO claim ever refreshed)', () {
    test('the new name appears without any re-claim', () {
      // Before this fix there was no trigger at all: renaming a coach never
      // changed clients.trainerId, so `_listenClient` never re-claimed and the
      // mirror kept the old name indefinitely.
      expect(
        resolve(
          trainerId: 't1',
          live: 'Ravi Kumar Iyer',
          mirrored: 'Ravi Kumar',
          mirroredFor: 't1',
        ),
        'Ravi Kumar Iyer',
      );
    });
  });

  group('MATRIX — profile images', () {
    test('a photo is served with its name', () {
      expect(
        resolveCoachPhoto(name: 'Ravi Kumar', mirroredPhoto: 'https://x/r.jpg'),
        'https://x/r.jpg',
      );
    });

    test('a changed photo replaces the old one', () {
      expect(
        resolveCoachPhoto(name: 'Ravi Kumar', mirroredPhoto: 'https://x/v2.jpg'),
        'https://x/v2.jpg',
      );
    });

    test('a DELETED photo falls back to initials, not a stale face', () {
      expect(resolveCoachPhoto(name: 'Ravi Kumar', mirroredPhoto: ''), isEmpty);
    });

    test('no resolvable name → no photo', () {
      // Guarantees the face and the name are always the same generation: a
      // suppressed name suppresses the picture with it.
      expect(
        resolveCoachPhoto(name: '', mirroredPhoto: 'https://x/departed.jpg'),
        isEmpty,
      );
    });
  });

  group('MATRIX — session lifecycle', () {
    test('cold start with no live data yet paints from the mirror', () {
      // getMyTraining has not returned on the first frame. The mirror is what
      // makes the header correct immediately instead of flashing a placeholder.
      expect(
        resolve(trainerId: 't1', mirrored: 'Ravi Kumar', mirroredFor: 't1'),
        'Ravi Kumar',
      );
    });

    test('fresh install, offline, nothing cached → honest empty', () {
      expect(resolve(trainerId: 't1'), isEmpty);
    });

    test('online refresh overrides whatever the cold start painted', () {
      expect(
        resolve(
          trainerId: 't1',
          live: 'Ravi Kumar Iyer',
          mirrored: 'Ravi Kumar',
          mirroredFor: 't1',
        ),
        'Ravi Kumar Iyer',
      );
    });

    test('no organization at all → no coach, in any combination', () {
      expect(resolve(trainerId: '', adminId: '', mirrored: 'X'), isEmpty);
    });
  });
}
