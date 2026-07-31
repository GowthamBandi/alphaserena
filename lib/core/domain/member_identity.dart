/// THE member-and-organisation attribution rule for the member app — the
/// identity counterpart of `coach_identity.dart`, and the single place any
/// screen may resolve *who the member is* and *which organisation they belong
/// to*.
///
/// One law, applied to every identity fact on both Home and Profile:
///
///   **A value is either real, or it is absent. It is never invented.**
///
/// Every resolver here returns `''`/`null` when nothing can be honestly
/// claimed, and callers render their own "not set yet" copy. This is the same
/// contract `resolveCoachName` established after placeholder coach names shipped
/// to production; the member's own name, photo, age and organisation had no such
/// rule, which is how `'Alpha'`, `'Alpha Arena'` and a permanently blank age
/// tile reached the Profile screen.
///
/// Precedence, wherever two sources exist, is always **live before mirrored**:
/// a mirror on `clientProfiles` is written once by `claimClientAccount` and
/// cannot reflect a later rename, so a freshly-read value outranks it. This is
/// identical to `resolveCoachName`'s `liveName`-over-`mirroredName` rule.
library;

/// The member's display name, or `''` when none can be honestly claimed.
///
/// Precedence:
///  1. [canonicalDisplayName] — `clientProfiles.profile.identity.displayName`,
///     authored by the member in Identity Setup. The member owns this document;
///     no one else can write it.
///  2. [legacyClientName] — `clientProfiles.clientName`, the transitional
///     dual-write of the same value (UMHIPP P2→P5). Same author, same value.
///  3. [coachRecordName] — `clients.name`, typed by the coach when they created
///     the member's record. Real data, but the coach's label for the member
///     rather than the member's own name, so it ranks last.
///
/// Never returns a placeholder. The previous chain ended in the literal string
/// `'Alpha'`, which flowed from `MemberController.name` into review authorship
/// (`org_reviews.memberName`) and feedback authorship (`client_feedback.clientName`)
/// — so an un-set-up member could be recorded in their coach's inbox under a
/// name the app made up for them.
String resolveMemberName({
  String canonicalDisplayName = '',
  String legacyClientName = '',
  String coachRecordName = '',
}) {
  final canonical = canonicalDisplayName.trim();
  if (canonical.isNotEmpty) return canonical;

  final legacy = legacyClientName.trim();
  if (legacy.isNotEmpty) return legacy;

  return coachRecordName.trim();
}

/// The member's own profile photo, or `''` when they have not set one.
///
/// [canonicalPhotoUrl] is `clientProfiles.profile.identity.photoUrl`, uploaded
/// by the member to their own uid-scoped Storage path. `''` → the caller renders
/// [initialsOf], never a stock avatar: the app must not show a member a picture
/// of a person who is not them, for the same reason `resolveCoachPhoto` refuses
/// to show a stranger as their coach.
String resolveMemberPhoto({String canonicalPhotoUrl = ''}) =>
    canonicalPhotoUrl.trim();

/// The member's age in whole years, or `null` when it cannot be derived.
///
/// Precedence:
///  1. [dob] — `profile.identity.dob`, `yyyy-MM-dd`, member-authored. Preferred
///     because it is exact and stays correct as the member gets older.
///  2. [coachRecordAge] — `clients.age`, an integer the coach typed once. Real,
///     but frozen at the moment of entry.
///
/// The Profile screen previously read `age` from `clientProfiles`, where nothing
/// writes it — the coach authors `age` on `clients`, and cannot write to the
/// member's private document at all. The tile therefore rendered `--` for every
/// member in production. This is that bug's fix: read both real sources, prefer
/// the one that does not go stale.
int? resolveMemberAge({
  String dob = '',
  Object? coachRecordAge,
  DateTime? now,
}) {
  final fromDob = _ageFromDob(dob, now ?? DateTime.now());
  if (fromDob != null) return fromDob;

  if (coachRecordAge is int) return _sane(coachRecordAge);
  if (coachRecordAge is num) return _sane(coachRecordAge.toInt());
  if (coachRecordAge is String) {
    final parsed = int.tryParse(coachRecordAge.trim());
    if (parsed != null) return _sane(parsed);
  }
  return null;
}

/// Whole years between [dob] and [now], counted on the birthday boundary so
/// someone whose birthday has not yet arrived this year is not aged up early.
int? _ageFromDob(String dob, DateTime now) {
  final trimmed = dob.trim();
  if (trimmed.isEmpty) return null;
  final born = DateTime.tryParse(trimmed);
  if (born == null) return null;
  if (born.isAfter(now)) return null; // a future birth date is not an age

  var years = now.year - born.year;
  final hadBirthday =
      now.month > born.month || (now.month == born.month && now.day >= born.day);
  if (!hadBirthday) years -= 1;
  return _sane(years);
}

/// Rejects values no living member can hold, so corrupt data reads as unknown
/// rather than as a confident absurdity.
int? _sane(int years) => (years < 0 || years > 120) ? null : years;

/// The organisation's display name, or `''` when none can be honestly claimed.
///
/// Precedence is **live before mirrored**, which is the fix for a renamed
/// organisation:
///  1. [liveName] — `organizationProfiles/{adminId}.name`, fetched per session.
///  2. [mirroredName] — `clientProfiles.gymName`, written ONCE by
///     `claimClientAccount` and never re-derived. An organisation that renames
///     itself updates the storefront immediately while this mirror keeps the old
///     name indefinitely.
///
/// The previous chain preferred the mirror, so a member whose gym rebranded kept
/// seeing the former name on Home even after the current one had been fetched
/// and was sitting in memory. Profile did worse still and fell back to the
/// literal `'Alpha Arena'` — a string that reads as a real gym.
String resolveOrgName({String liveName = '', String mirroredName = ''}) {
  final live = liveName.trim();
  if (live.isNotEmpty) return live;
  return mirroredName.trim();
}

/// Up to two initials for [name], or `''` when no letter can be taken.
///
/// Used wherever a photo is genuinely absent — the member's own avatar and the
/// coach's. Initials are derived from a real name, so they claim nothing that
/// is not already known; a stock portrait claims a face.
String initialsOf(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '';

  String firstLetter(String word) {
    for (final rune in word.runes) {
      final ch = String.fromCharCode(rune);
      if (RegExp(r'[A-Za-z0-9]').hasMatch(ch)) return ch.toUpperCase();
    }
    return '';
  }

  if (words.length == 1) return firstLetter(words.first);
  final first = firstLetter(words.first);
  final last = firstLetter(words.last);
  return '$first$last';
}
