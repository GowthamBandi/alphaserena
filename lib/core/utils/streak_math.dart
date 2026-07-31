// Pure, Firebase-free streak math over 'yyyy-MM-dd' day keys. A streak is the
// run of CONSECUTIVE calendar days with a qualifying log, ending today or —
// while today is still unlogged — yesterday (an in-progress day never breaks a
// streak until it is actually missed). Unit-tests in isolation.

import 'lifestyle_math.dart' show dayKey;

/// Length of the current streak given the set of logged [dayKeys].
///
/// Anchors on [today]: if today is logged the run starts there; otherwise it
/// starts at yesterday (today is still open, not yet a miss). A gap ends the
/// count. [cap] bounds the walk so an unbounded set can't loop forever.
int currentStreak(Set<String> dayKeys, DateTime today, {int cap = 365}) {
  var anchor = DateTime(today.year, today.month, today.day);
  if (!dayKeys.contains(dayKey(anchor))) {
    anchor = anchor.subtract(const Duration(days: 1));
  }
  var streak = 0;
  var d = anchor;
  while (streak < cap && dayKeys.contains(dayKey(d))) {
    streak++;
    d = d.subtract(const Duration(days: 1));
  }
  return streak;
}

/// How many of the last [window] days (ending [today], inclusive) are logged.
int daysLoggedInWindow(Set<String> dayKeys, DateTime today, int window) {
  final t = DateTime(today.year, today.month, today.day);
  var count = 0;
  for (var i = 0; i < window; i++) {
    if (dayKeys.contains(dayKey(t.subtract(Duration(days: i))))) count++;
  }
  return count;
}

/// Whether [today] itself has a qualifying log (the streak's "today's
/// contribution" indicator).
bool loggedToday(Set<String> dayKeys, DateTime today) =>
    dayKeys.contains(dayKey(DateTime(today.year, today.month, today.day)));

/// The LONGEST consecutive run within the last [window] days (ending [today],
/// inclusive). Honest by construction: it can only see the fetched window, so
/// callers cap the display at the window size rather than implying all-time.
int bestStreakInWindow(Set<String> dayKeys, DateTime today, int window) {
  final t = DateTime(today.year, today.month, today.day);
  var best = 0, run = 0;
  for (var i = window - 1; i >= 0; i--) {
    if (dayKeys.contains(dayKey(t.subtract(Duration(days: i))))) {
      run++;
      if (run > best) best = run;
    } else {
      run = 0;
    }
  }
  return best;
}
