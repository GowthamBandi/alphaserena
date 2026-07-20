import 'member_profile.dart';

/// Compatibility adapter (UMHIPP P2) between the current member `clientProfiles`
/// document map and the canonical [MemberProfile]. ADDITIVE + NOT WIRED — nothing
/// calls it yet; it exists so a later approved migration (P3+) has a single,
/// tested mapping and existing code keeps working unchanged.
class MemberProfileDocAdapter {
  const MemberProfileDocAdapter._();

  /// Reads the canonical profile out of a raw `clientProfiles/{uid}` doc map.
  /// Backward-compat bridge: if the doc still carries a legacy
  /// `notificationPreferences` map and has no canonical `preferences` section
  /// yet, surface it under the `preferences` section so the canonical view
  /// reflects existing settings without any migration write.
  static MemberProfile fromDoc(Map<String, dynamic>? doc) {
    final base = MemberProfile.fromMap(doc);
    if (doc == null) return base;
    final legacyPrefs = doc['notificationPreferences'];
    if (legacyPrefs is Map && !base.has('preferences')) {
      return base.withSection(
        'preferences',
        {'notificationPreferences': Map<String, dynamic>.from(legacyPrefs)},
      );
    }
    return base;
  }

  /// The ADDITIVE fields to merge into the `clientProfiles/{uid}` doc for a
  /// canonical profile — `profile` + `privacy` maps ONLY. Legacy top-level fields
  /// (`notificationPreferences`, `linkedClientId`, `fcmTokens`, …) are untouched;
  /// a future migration writes this with `SetOptions(merge: true)`.
  static Map<String, dynamic> toDocPatch(MemberProfile p) => p.toMap();
}
