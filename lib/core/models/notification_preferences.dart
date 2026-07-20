/// The member's notification preferences — mirrors the backend v2 contract
/// (`trainershq-backend/functions/src/lib/notification_center.ts`
/// `parseNotificationPrefs`): stored on `clientProfiles/{uid}.notificationPreferences`
/// as `{version: 2, global: {...}, categories: {<cat>: {push}}, events: {}}`.
/// `calls` + `security` are the server's immutable safety floor — always on
/// regardless of what's written here, so this model doesn't even carry a
/// toggle for them (the settings screen just shows them locked).
class MemberNotificationPrefs {
  final bool enabled;
  final bool quietHoursEnabled;
  final int quietHoursStart; // 0-23
  final int quietHoursEnd; // 0-23
  final bool communication; // "Messages" — coach chat
  final bool coaching; // check-ins, plans, trainer changes
  final bool membership;
  final bool billing;
  final bool announcements;
  final bool marketing; // opt-in; defaults OFF

  const MemberNotificationPrefs({
    this.enabled = true,
    this.quietHoursEnabled = true,
    this.quietHoursStart = 22,
    this.quietHoursEnd = 7,
    this.communication = true,
    this.coaching = true,
    this.membership = true,
    this.billing = true,
    this.announcements = true,
    this.marketing = false,
  });

  /// Parses both the v2 shape and an absent/legacy map — every missing key
  /// falls back to the safe default (everything on except marketing),
  /// matching the server parser exactly.
  factory MemberNotificationPrefs.fromMap(Map<String, dynamic>? raw) {
    final map = raw ?? const <String, dynamic>{};
    final isV2 = (map['version'] is num && (map['version'] as num) >= 2) ||
        map.containsKey('global') ||
        map.containsKey('categories');

    final globalRaw = isV2 ? map['global'] : map;
    final g = globalRaw is Map ? Map<String, dynamic>.from(globalRaw) : const <String, dynamic>{};
    bool gb(String k, bool d) => g[k] is bool ? g[k] as bool : d;
    int gi(String k, int d) {
      final v = g[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return d;
    }

    final categoriesRaw = isV2 ? map['categories'] : null;
    final categories =
        categoriesRaw is Map ? Map<String, dynamic>.from(categoriesRaw) : const <String, dynamic>{};
    bool cat(String key, bool def) {
      final c = categories[key];
      if (c is Map && c['push'] is bool) return c['push'] as bool;
      return def;
    }

    return MemberNotificationPrefs(
      enabled: gb('enabled', true),
      quietHoursEnabled: gb('quietHoursEnabled', true),
      quietHoursStart: gi('quietHoursStart', 22),
      quietHoursEnd: gi('quietHoursEnd', 7),
      communication: cat('communication', true),
      coaching: cat('coaching', true),
      membership: cat('membership', true),
      billing: cat('billing', true),
      announcements: cat('announcements', true),
      marketing: cat('marketing', false),
    );
  }

  /// Always writes the full v2 shape (merge-written into the doc). `calls`
  /// and `security` are included as always-on for display parity even
  /// though the server ignores them (immutable categories).
  Map<String, dynamic> toMap() => {
        'version': 2,
        'global': {
          'enabled': enabled,
          'quietHoursEnabled': quietHoursEnabled,
          'quietHoursStart': quietHoursStart,
          'quietHoursEnd': quietHoursEnd,
        },
        'categories': {
          'communication': {'push': communication},
          'coaching': {'push': coaching},
          'membership': {'push': membership},
          'billing': {'push': billing},
          'announcements': {'push': announcements},
          'marketing': {'push': marketing},
          'calls': {'push': true},
          'security': {'push': true},
        },
        'events': {},
      };

  MemberNotificationPrefs copyWith({
    bool? enabled,
    bool? quietHoursEnabled,
    int? quietHoursStart,
    int? quietHoursEnd,
    bool? communication,
    bool? coaching,
    bool? membership,
    bool? billing,
    bool? announcements,
    bool? marketing,
  }) =>
      MemberNotificationPrefs(
        enabled: enabled ?? this.enabled,
        quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
        quietHoursStart: quietHoursStart ?? this.quietHoursStart,
        quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
        communication: communication ?? this.communication,
        coaching: coaching ?? this.coaching,
        membership: membership ?? this.membership,
        billing: billing ?? this.billing,
        announcements: announcements ?? this.announcements,
        marketing: marketing ?? this.marketing,
      );
}
