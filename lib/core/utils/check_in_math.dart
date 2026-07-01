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
