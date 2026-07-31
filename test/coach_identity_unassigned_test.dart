import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/coach_identity.dart';

/// "YOUR COACH" — the root cause, pinned.
///
/// Every member in production read "Your Coach" instead of their coach's name.
/// The chain:
///
///   1. `verifyAndActivateMembership` creates the `clients` record on purchase
///      with name/phone/adminId/authUid/status — and NO `trainerId`. Assignment
///      is a separate, deliberate act the owner performs later from their
///      Unassigned triage list, and a solo owner who IS the coach never
///      performs it at all.
///   2. `resolveTrainerName` opened with `if (!trainerId) return ""`.
///   3. `resolveCoachName` opened with the same guard.
///   4. `HomeController.coachName` fell back to the literal 'Your Coach'.
///
/// An empty `trainerId` never meant "this member has no coach". It means no
/// SPECIFIC trainer is delegated yet, and the org owner is responsible in the
/// meantime — which is already how the backend routes the member's
/// notifications (`resolveCoachRecipient`). The fix makes the name the member
/// SEES agree with the person who actually receives their messages.
///
/// Deliberately fixed at READ time, not by stamping `trainerId = adminId` at
/// creation: that would empty the owner's Unassigned filter and destroy the
/// triage workflow multi-trainer gyms depend on.
void main() {
  group('unassigned member — the org owner is the coach', () {
    test('the owner is named when no trainer is delegated', () {
      // The headline fix. Mirror derived for the owner, no trainer assigned.
      expect(
        resolveCoachName(
          trainerId: '',
          adminId: 'a1',
          mirroredName: 'Priya Nair',
          mirroredFor: 'a1',
        ),
        'Priya Nair',
      );
    });

    test('a delegated trainer still outranks the owner', () {
      expect(
        resolveCoachName(
          trainerId: 't1',
          adminId: 'a1',
          mirroredName: 'Ravi Kumar',
          mirroredFor: 't1',
        ),
        'Ravi Kumar',
      );
    });

    test('the admin-as-trainer case keeps working', () {
      // trainerId == adminId: the owner explicitly assigned themselves.
      expect(
        resolveCoachName(
          trainerId: 'a1',
          adminId: 'a1',
          mirroredName: 'Priya Nair',
          mirroredFor: 'a1',
        ),
        'Priya Nair',
      );
    });

    test('no organization at all → still no name', () {
      // A member with neither a trainer nor an admin has no one to attribute
      // to. Naming someone here would be an invention.
      expect(
        resolveCoachName(
          trainerId: '',
          adminId: '',
          mirroredName: 'Somebody',
          mirroredFor: '',
        ),
        isEmpty,
      );
    });
  });

  group('a REMOVED coach must never resurface', () {
    test('the departed trainer is suppressed until the re-claim lands', () {
      // The guard this fix had to preserve. Trainer removed → trainerId '' →
      // the effective coach becomes the owner, and a mirror derived for the
      // departed trainer no longer matches.
      expect(
        resolveCoachName(
          trainerId: '',
          adminId: 'a1',
          mirroredName: 'Ravi Kumar',
          mirroredFor: 't1',
        ),
        isEmpty,
      );
    });

    test('once the re-claim lands, the owner is named', () {
      expect(
        resolveCoachName(
          trainerId: '',
          adminId: 'a1',
          mirroredName: 'Priya Nair',
          mirroredFor: 'a1',
        ),
        'Priya Nair',
      );
    });

    test('a LEGACY mirror is not trusted once the trainer is removed', () {
      // The subtle one. A profile written before `trainerNameFor` existed
      // carries an unvalidatable name. While a trainer is assigned it is the
      // best evidence available — but after removal it is the departed coach's
      // name, and an equality check against '' would have let it through.
      expect(
        resolveCoachName(
          trainerId: '',
          adminId: 'a1',
          mirroredName: 'Ravi Kumar',
          mirroredFor: '',
        ),
        isEmpty,
      );
    });

    test('a legacy mirror IS trusted while a trainer is assigned', () {
      expect(
        resolveCoachName(
          trainerId: 't1',
          adminId: 'a1',
          mirroredName: 'Ravi Kumar',
          mirroredFor: '',
        ),
        'Ravi Kumar',
      );
    });

    test('a reassignment still suppresses the previous coach', () {
      expect(
        resolveCoachName(
          trainerId: 't2',
          adminId: 'a1',
          mirroredName: 'Ravi Kumar',
          mirroredFor: 't1',
        ),
        isEmpty,
      );
    });
  });

  group('coach photo', () {
    test('a photo is shown only alongside a resolved name', () {
      expect(
        resolveCoachPhoto(name: 'Priya Nair', mirroredPhoto: 'https://x/p.jpg'),
        'https://x/p.jpg',
      );
    });

    test('no name → no photo, so a stale face can never outlive its name', () {
      // The failure this prevents: a reassignment suppresses the departed
      // coach's NAME but leaves their FACE in the header next to the new
      // coach's name. Gating the photo on the name makes that impossible.
      expect(
        resolveCoachPhoto(name: '', mirroredPhoto: 'https://x/departed.jpg'),
        isEmpty,
      );
    });

    test('a named coach with no photo yields empty, not a placeholder URL', () {
      expect(resolveCoachPhoto(name: 'Priya Nair', mirroredPhoto: ''), isEmpty);
      expect(
        resolveCoachPhoto(name: 'Priya Nair', mirroredPhoto: '   '),
        isEmpty,
      );
    });
  });
}
