/// THE coach-attribution rule for the member app — the consumer-side mirror of
/// TrainersHQ's `lib/core/domain/trainer_directory.dart`.
///
/// Two facts, one rule (identical to the producer's):
///   • is a coach ASSIGNED? → the LIVE `clients.trainerId` is non-empty.
///     Nothing else. The security rules define the same thing:
///     `assignableCoach()` accepts an empty trainerId, `trainerId == adminId`,
///     or an active trainer doc owned by that admin.
///   • can we NAME them?    → the server-resolved mirror on `clientProfiles`.
///
/// The member app cannot resolve names itself: naming a coach requires reading
/// `trainers/{id}` or `admins/{id}`, which the rules correctly deny a member.
/// `claimClientAccount` is therefore the source of truth for the NAME, and it
/// handles the admin-as-trainer case (an admin has no `trainers` doc).
///
/// Assignment truth, however, always comes from the live client document — the
/// mirror can lag a reassignment by one round trip.
library;

/// Resolves the coach's display name from the live assignment plus the
/// server-written mirror. Returns `''` when no name can be honestly claimed;
/// callers render their own "not assigned" copy rather than a placeholder name.
///
/// [trainerId] — live `clients.trainerId`.
/// [mirroredName] — `clientProfiles.trainerName` (written by
/// `claimClientAccount`).
/// [mirroredFor] — `clientProfiles.trainerNameFor`: the trainerId the mirrored
/// name was derived for. Empty on profiles written before that field existed.
/// [liveName] — `clients.trainerName`, if the producer ever writes it. TrainersHQ
/// does not today (`assignTrainer` writes only `trainerId`), but honouring it
/// costs nothing and makes a future producer-side snapshot authoritative.
String resolveCoachName({
  required String trainerId,
  required String mirroredName,
  required String mirroredFor,
  String adminId = '',
  String liveName = '',
}) {
  final assignedTo = trainerId.trim();
  final owner = adminId.trim();

  // THE EFFECTIVE COACH: the delegated trainer, or the org owner when no
  // trainer has been delegated yet.
  //
  // This line is the fix for "Your Coach". A `clients` record is created on
  // purchase WITHOUT a `trainerId` — assignment is a later, deliberate act the
  // owner performs from their Unassigned triage list, and a solo owner who is
  // themselves the coach never performs it at all. The previous rule treated an
  // empty `trainerId` as "no coach exists" and refused to name anyone, which
  // fired for essentially every member in production.
  //
  // An empty `trainerId` never meant coachless: it means no SPECIFIC trainer is
  // delegated, and the owner is responsible meanwhile — which is already how
  // the backend routes the member's notifications (`resolveCoachRecipient`).
  final effective = assignedTo.isEmpty ? owner : assignedTo;

  // No organization at all → nothing can be honestly claimed.
  if (effective.isEmpty) return '';

  // A name on the live document outranks the mirror: it cannot be stale.
  final live = liveName.trim();
  if (live.isNotEmpty) return live;

  final mirrored = mirroredName.trim();
  if (mirrored.isEmpty) return '';

  final derivedFor = mirroredFor.trim();

  // Derived for the CURRENT effective coach → trustworthy.
  if (derivedFor == effective) return mirrored;

  // Derived for SOMEONE ELSE → stale. Report no name and let the re-claim
  // triggered by the trainer change supply the new one, rather than showing the
  // previous coach. This is what still protects the removed-coach case: the
  // trainer is cleared, `effective` becomes the owner, and the mirror derived
  // for the departed trainer no longer matches.
  if (derivedFor.isNotEmpty) return '';

  // Legacy profile with no `trainerNameFor` — it predates the field and cannot
  // be validated. Trust it ONLY while a trainer is actually assigned, which was
  // the original intent: "a coach IS assigned, so the cached name is the best
  // available evidence". If the trainer has since been REMOVED, that cached
  // name is the departed coach's and must not be shown.
  return assignedTo.isEmpty ? '' : mirrored;
}

/// The coach's avatar URL, mirrored by `claimClientAccount` under the SAME
/// `trainerNameFor` guard as the name.
///
/// Returns `''` when no photo can be honestly attributed — callers render
/// initials, never a stranger's face. Gated on [name] so a photo can never
/// outlive the name it belongs to: if the name is suppressed as stale, the
/// picture is too.
String resolveCoachPhoto({
  required String name,
  required String mirroredPhoto,
}) {
  if (name.isEmpty) return '';
  return mirroredPhoto.trim();
}
