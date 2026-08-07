// Pure, Firebase-free helpers for the weekly check-in. Unit-testable in isolation.

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// A check-in is submittable if the member entered at least one of: a note, a
/// rating, or a weight.
bool hasSubmittableContent({
  required String note,
  required Map<String, int> ratings,
  double? weightKg,
}) {
  if (note.trim().isNotEmpty) return true;
  if (ratings.isNotEmpty) return true;
  if (weightKg != null) return true;
  return false;
}

/// Human label for a submission's period, e.g. 'Week of 29 Jun' (display only).
String periodLabel(DateTime d) => 'Week of ${d.day} ${_months[d.month - 1]}';

// ═══════════════════════════════════════════════════════════════════════════
// THE WEEKLY WINDOW — the rule that was missing entirely
//
// Nothing in this stack had any concept of a WEEK. `canSubmit` asked only
// "has the member typed anything?", the service wrote to a fresh random
// document id whenever no open packet existed, the model carried no week
// field, and `firestore.rules` constrained ownership and `status` but never
// uniqueness or timing. So the editor was live every day, and a member could
// file any number of check-ins for the same week.
//
// A weekly review is a weekly artefact: one per week, authored in its own
// window, read-only once filed.
// ═══════════════════════════════════════════════════════════════════════════

/// The day the submission window is open. Sunday, per the product rule.
const int kCheckInWindowWeekday = DateTime.sunday;

/// `yyyy-Www` — the ISO-8601 week the LOCAL date [d] belongs to.
///
/// The identity of a weekly review, and therefore the thing that makes a
/// duplicate structurally impossible: it becomes the document id, so a second
/// submission for the same week addresses the same document instead of
/// creating a sibling.
///
/// ISO weeks run Monday→Sunday, so the Sunday window is the LAST day of its
/// own week — the member reviews a week that has finished, not one still
/// running. That is the whole reason Sunday was chosen, and it is why the key
/// is derived from the ISO week rather than from "the most recent Sunday".
String weekKeyFor(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  // The Thursday of this ISO week decides which YEAR the week belongs to —
  // the rule that stops 29 Dec 2025 and 1 Jan 2026 landing in different years
  // while sharing a week.
  final thursday = day.add(Duration(days: 4 - _isoWeekday(day)));
  final jan1 = DateTime(thursday.year, 1, 1);
  final week = 1 + (thursday.difference(jan1).inDays ~/ 7);
  return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
}

int _isoWeekday(DateTime d) => d.weekday; // Mon=1 … Sun=7, already ISO

/// Whether the editor may be opened at [now] — Sunday, in the MEMBER'S local
/// calendar.
///
/// Local deliberately: the member lives the week, and a UTC test would open
/// the window on Saturday evening for anyone west of Greenwich and close it
/// before Sunday ended for anyone east. `DateTime.weekday` is local.
bool isCheckInWindowOpen(DateTime now) =>
    now.weekday == kCheckInWindowWeekday;

/// Whether a review already exists for the week containing [now].
bool hasSubmittedThisWeek(Iterable<String> submittedWeekKeys, DateTime now) =>
    submittedWeekKeys.contains(weekKeyFor(now));

/// The single authority on whether the member may author right now.
///
/// Both conditions, in one place, so the screen, the controller and any future
/// surface cannot disagree: the window must be open AND this week must not
/// already be filed.
bool canAuthorCheckIn({
  required DateTime now,
  required Iterable<String> submittedWeekKeys,
}) =>
    isCheckInWindowOpen(now) &&
    !hasSubmittedThisWeek(submittedWeekKeys, now);

/// Why the editor is closed, phrased for the member. Null when it is open.
String? checkInLockReason({
  required DateTime now,
  required Iterable<String> submittedWeekKeys,
}) {
  if (hasSubmittedThisWeek(submittedWeekKeys, now)) {
    return 'This week\'s check-in is submitted. Your coach will review it.';
  }
  if (!isCheckInWindowOpen(now)) {
    final days = (DateTime.sunday - now.weekday + 7) % 7;
    return days == 1
        ? 'Your check-in opens tomorrow, Sunday.'
        : 'Your check-in opens on Sunday, in $days days.';
  }
  return null;
}
