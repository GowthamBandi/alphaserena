import 'package:alphaserena/core/domain/coach_identity.dart';
import 'package:flutter_test/flutter_test.dart';

/// Coach attribution — the consumer side of TrainersHQ's trainer-directory rule.
///
/// The cases that matter: an admin coaching their own client (valid per the
/// security rules' `assignableCoach`, but with no `trainers` doc), a mirror that
/// has gone stale across a reassignment, and a removed coach.
void main() {
  group('assignment truth comes from the live client doc', () {
    test('no trainerId → no name, even with a populated mirror', () {
      expect(
        resolveCoachName(
          trainerId: '',
          mirroredName: 'Sam Rivera',
          mirroredFor: 'trainer-1',
        ),
        '',
      );
    });

    test('coach removed → the mirror must not resurface them', () {
      // clients.trainerId cleared; clientProfiles still holds the old name.
      expect(
        resolveCoachName(
          trainerId: '   ',
          mirroredName: 'Sam Rivera',
          mirroredFor: 'trainer-1',
        ),
        '',
      );
    });
  });

  group('normal trainer', () {
    test('mirror derived for the current assignment is trusted', () {
      expect(
        resolveCoachName(
          trainerId: 'trainer-1',
          mirroredName: 'Sam Rivera',
          mirroredFor: 'trainer-1',
        ),
        'Sam Rivera',
      );
    });

    test('whitespace is trimmed', () {
      expect(
        resolveCoachName(
          trainerId: 'trainer-1',
          mirroredName: '  Sam Rivera  ',
          mirroredFor: 'trainer-1',
        ),
        'Sam Rivera',
      );
    });
  });

  group('admin assigned as the trainer', () {
    // The admin's uid IS the trainerId; claimClientAccount now resolves the
    // name from `admins/{uid}.name` because there is no trainers doc.
    test('resolves once the server mirrors the admin name', () {
      expect(
        resolveCoachName(
          trainerId: 'admin-uid',
          mirroredName: 'Gowtham Bandi',
          mirroredFor: 'admin-uid',
        ),
        'Gowtham Bandi',
      );
    });

    test(
      'assigned but server could not name them → empty, not a placeholder',
      () {
        // The caller renders "Not assigned yet"/"Your coach" copy itself; this
        // function never invents an identity.
        expect(
          resolveCoachName(
            trainerId: 'admin-uid',
            mirroredName: '',
            mirroredFor: 'admin-uid',
          ),
          '',
        );
      },
    );
  });

  group('stale mirror across a reassignment', () {
    test('mirror derived for a DIFFERENT trainer is rejected', () {
      // Reassigned trainer-1 → trainer-2; the re-claim has not landed yet.
      // Showing "Sam Rivera" here would name the wrong coach.
      expect(
        resolveCoachName(
          trainerId: 'trainer-2',
          mirroredName: 'Sam Rivera',
          mirroredFor: 'trainer-1',
        ),
        '',
      );
    });

    test('normal trainer replaced by the admin', () {
      expect(
        resolveCoachName(
          trainerId: 'admin-uid',
          mirroredName: 'Sam Rivera',
          mirroredFor: 'trainer-1',
        ),
        '',
      );
    });

    test('admin replaced by a normal trainer', () {
      expect(
        resolveCoachName(
          trainerId: 'trainer-9',
          mirroredName: 'Gowtham Bandi',
          mirroredFor: 'admin-uid',
        ),
        '',
      );
    });

    test('once the re-claim lands, the new name is trusted', () {
      expect(
        resolveCoachName(
          trainerId: 'trainer-2',
          mirroredName: 'Alex Stone',
          mirroredFor: 'trainer-2',
        ),
        'Alex Stone',
      );
    });
  });

  group('legacy profiles written before trainerNameFor existed', () {
    test('unvalidatable mirror is still used while a coach is assigned', () {
      expect(
        resolveCoachName(
          trainerId: 'trainer-1',
          mirroredName: 'Sam Rivera',
          mirroredFor: '',
        ),
        'Sam Rivera',
      );
    });

    test('but never when no coach is assigned', () {
      expect(
        resolveCoachName(
          trainerId: '',
          mirroredName: 'Sam Rivera',
          mirroredFor: '',
        ),
        '',
      );
    });
  });

  group('a live name on the client doc outranks the mirror', () {
    test('used even when the mirror is stale', () {
      expect(
        resolveCoachName(
          trainerId: 'trainer-2',
          mirroredName: 'Sam Rivera',
          mirroredFor: 'trainer-1',
          liveName: 'Alex Stone',
        ),
        'Alex Stone',
      );
    });

    test('but not when no coach is assigned', () {
      expect(
        resolveCoachName(
          trainerId: '',
          mirroredName: '',
          mirroredFor: '',
          liveName: 'Alex Stone',
        ),
        '',
      );
    });
  });

  group('long names are passed through untouched', () {
    test('no truncation in the domain layer — that is the UI\'s job', () {
      const long = 'Bartholomew Featherstonehaugh-Cholmondeley';
      expect(
        resolveCoachName(trainerId: 't', mirroredName: long, mirroredFor: 't'),
        long,
      );
    });
  });
}
