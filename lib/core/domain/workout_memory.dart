/// WORKOUT EXPERIENCE — Phase 2: EXERCISE MEMORY.
///
/// "What did I do last time?" — the single most useful sentence in strength
/// training, and the one the member app has never been able to say despite
/// writing the data every session.
///
/// Pure Dart over the member's OWN past session documents. Nothing is
/// estimated, averaged into existence, or carried forward: if there is no
/// previous completed set for an exercise, the answer is null and the UI
/// stays silent. Identity is exerciseId-first (a renamed exercise keeps its
/// history — the same rule TrainerHQ's analytics use), name-fallback for
/// freehand items.
///
/// NOT in scope (later roadmap phase, deliberately): personal records,
/// 1RM estimation, progression trends. This module answers "last time",
/// nothing more.
library;

/// The identity an exercise's history is keyed by.
String exerciseMemoryKey(String exerciseId, String name) =>
    exerciseId.isNotEmpty ? 'id:$exerciseId' : 'name:${name.trim().toLowerCase()}';

/// What the member did for one exercise, the last time they actually did it.
class ExerciseMemory {
  /// The day that session happened.
  final DateTime date;

  /// Completed sets in that session (skipped/unfinished are not "did").
  final int setCount;

  /// The heaviest completed set of that session — described, never claimed
  /// as a record.
  final String topReps;
  final String topWeight;

  const ExerciseMemory({
    required this.date,
    required this.setCount,
    this.topReps = '',
    this.topWeight = '',
  });

  /// "3 sets · top 10 × 40 kg" — omits what it does not know.
  String get summary {
    final parts = <String>[
      setCount == 1 ? '1 set' : '$setCount sets',
      if (topReps.isNotEmpty || topWeight.isNotEmpty)
        'top ${[
          if (topReps.isNotEmpty) topReps,
          if (topWeight.isNotEmpty) '${topWeight}kg',
        ].join(' × ')}',
    ];
    return parts.join(' · ');
  }

  /// "yesterday" / "3 days ago" / "on 12 Jul" — relative only while it stays
  /// meaningful.
  String ago(DateTime today) {
    final t = DateTime(today.year, today.month, today.day);
    final d = DateTime(date.year, date.month, date.day);
    final days = t.difference(d).inDays;
    if (days <= 0) return 'earlier today';
    if (days == 1) return 'yesterday';
    if (days < 14) return '$days days ago';
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return 'on ${d.day} ${months[d.month]}';
  }
}

double? _numOf(String s) {
  final m = RegExp(r'-?\d+(\.\d+)?').firstMatch(s);
  return m == null ? null : double.tryParse(m.group(0)!);
}

/// Builds the per-exercise memory map from raw past session documents.
///
/// [sessions] are `client_workout_sessions` maps (any order). [excludeId]
/// drops the session currently being trained so today's own sets never
/// masquerade as "last time". Only COMPLETED sets count.
Map<String, ExerciseMemory> buildExerciseMemory(
  List<Map<String, dynamic>> sessions, {
  String excludeId = '',
}) {
  final out = <String, ExerciseMemory>{};

  // Newest first, so the first hit for a key IS the most recent.
  final ordered = [...sessions];
  ordered.sort((a, b) {
    final da = _dateOf(a['date']);
    final db = _dateOf(b['date']);
    if (da == null || db == null) return 0;
    return db.compareTo(da);
  });

  for (final s in ordered) {
    if ((s['id'] ?? '').toString() == excludeId && excludeId.isNotEmpty) {
      continue;
    }
    final date = _dateOf(s['date']);
    if (date == null) continue;
    final entries = s['entries'];
    if (entries is! List) continue;

    for (final rawEntry in entries.whereType<Map>()) {
      final e = Map<String, dynamic>.from(rawEntry);
      final key = exerciseMemoryKey(
        (e['exerciseId'] ?? '').toString(),
        (e['exerciseName'] ?? '').toString(),
      );
      if (out.containsKey(key)) continue; // an older session cannot win

      final sets = (e['sets'] as List?)?.whereType<Map>() ?? const [];
      final completed = sets
          .map((x) => Map<String, dynamic>.from(x))
          .where((x) => x['completed'] == true)
          .toList();
      if (completed.isEmpty) continue; // nothing was actually done

      String topReps = '';
      String topWeight = '';
      double bestWeight = double.negativeInfinity;
      double bestReps = double.negativeInfinity;
      for (final set in completed) {
        final reps = (set['actualReps'] ?? '').toString();
        final weight = (set['actualWeight'] ?? '').toString();
        final w = _numOf(weight);
        final r = _numOf(reps);
        // Heaviest set wins; with no weights at all, the longest set does.
        final betterByWeight = w != null && w > bestWeight;
        final noWeightsYet = bestWeight == double.negativeInfinity;
        final betterByReps = w == null && noWeightsYet && r != null &&
            r > bestReps;
        if (betterByWeight || betterByReps) {
          if (w != null) bestWeight = w;
          if (r != null) bestReps = r;
          topReps = reps;
          topWeight = weight;
        }
      }

      out[key] = ExerciseMemory(
        date: date,
        setCount: completed.length,
        topReps: topReps,
        topWeight: topWeight,
      );
    }
  }
  return out;
}

DateTime? _dateOf(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  try {
    final d = (v as dynamic).toDate();
    if (d is DateTime) return d;
  } catch (_) {}
  return null;
}
