import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/workout_session.dart';

/// WORKOUT EXPERIENCE Phase 1 — local persistence of the in-progress session.
///
/// One slot: a member has at most one workout on the bench. Saved on every
/// meaningful change (debounced by the screen for keystrokes), restored on
/// open, cleared on finish — so battery death, a phone call, a restart or a
/// navigation slip loses NOTHING. Corrupt or stale JSON reads as null; a
/// draft can never invent a session.
class WorkoutDraftStore {
  static const _key = 'workout_session_draft_v1';

  Future<void> save(WorkoutDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(draft.toJson()));
  }

  Future<WorkoutDraft?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return WorkoutDraft.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
