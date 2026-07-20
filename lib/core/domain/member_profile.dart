/// Canonical Member Identity & Privacy — DART DOMAIN (UMHIPP Phase P2).
///
/// A faithful port of the verified reference
/// `trainershq-backend/functions/src/lib/member_profile.ts` (13/13 tests). Kept
/// BYTE-IDENTICAL with the trainersHQ copy (same convention as ChatAudioPlayer)
/// so both apps and the backend resolve visibility through ONE policy.
///
/// This is ADDITIVE and DELIBERATELY NOT WIRED into any screen, controller,
/// service, rule, or CF. It is the P2 foundation only; adoption (projection,
/// UI, migration, rules) is P3+ per the approved Design Spec
/// (`trainershq-backend/docs/specs/umhipp-member-identity-privacy-design.md`).
library;

/// Who a section may be shared with. Extensible.
enum SectionVisibility { onlyMe, emergency, coach, organization, aiSystem }

/// Who is the source of truth / who may edit a section.
enum EditableBy { member, coach, admin, system }

/// Handling class — drives retention, consent and rule strictness.
enum Sensitivity { low, medium, high }

/// How a section is populated.
enum SectionRequirement { mandatory, optional, derived, system }

/// A resolved viewer identity for a visibility check.
enum ViewerRole { member, coach, orgAdmin, emergency, aiSystem }

class SectionSpec {
  /// Stable key — the map key under `clientProfiles/{uid}.profile.<key>`.
  final String key;
  final EditableBy owner;
  final EditableBy editableBy;

  /// The widest audience this section is shared with by default.
  final SectionVisibility defaultVisibility;
  final Sensitivity sensitivity;
  final SectionRequirement requirement;

  /// May the member change this section's visibility at all?
  final bool memberControllable;

  /// The widest audience the member may grant when [memberControllable]. The
  /// member may pick any tier from `onlyMe` up to this. Null → [defaultVisibility]
  /// (most sections are tighten-only); a private-by-default section
  /// (medical/documents) sets this to `coach` so the member can OPT IN.
  final SectionVisibility? maxMemberVisibility;

  const SectionSpec({
    required this.key,
    required this.owner,
    required this.editableBy,
    required this.defaultVisibility,
    required this.sensitivity,
    required this.requirement,
    required this.memberControllable,
    this.maxMemberVisibility,
  });
}

/// The canonical sections. Grounded in current repository evidence (identity /
/// membership / diet-lifestyle targets / notification prefs already exist across
/// `clients` + `clientProfiles`); the rest are the designed extensions.
const List<SectionSpec> kMemberSections = [
  SectionSpec(key: 'identity', owner: EditableBy.member, editableBy: EditableBy.member, defaultVisibility: SectionVisibility.coach, sensitivity: Sensitivity.low, requirement: SectionRequirement.mandatory, memberControllable: false),
  SectionSpec(key: 'contact', owner: EditableBy.member, editableBy: EditableBy.member, defaultVisibility: SectionVisibility.coach, sensitivity: Sensitivity.medium, requirement: SectionRequirement.mandatory, memberControllable: true),
  SectionSpec(key: 'bodyMetrics', owner: EditableBy.member, editableBy: EditableBy.member, defaultVisibility: SectionVisibility.coach, sensitivity: Sensitivity.medium, requirement: SectionRequirement.optional, memberControllable: true),
  SectionSpec(key: 'bodyMeasurements', owner: EditableBy.member, editableBy: EditableBy.member, defaultVisibility: SectionVisibility.coach, sensitivity: Sensitivity.medium, requirement: SectionRequirement.optional, memberControllable: true),
  SectionSpec(key: 'fitness', owner: EditableBy.member, editableBy: EditableBy.member, defaultVisibility: SectionVisibility.coach, sensitivity: Sensitivity.low, requirement: SectionRequirement.optional, memberControllable: true),
  SectionSpec(key: 'goals', owner: EditableBy.member, editableBy: EditableBy.member, defaultVisibility: SectionVisibility.coach, sensitivity: Sensitivity.low, requirement: SectionRequirement.optional, memberControllable: true),
  SectionSpec(key: 'lifestyle', owner: EditableBy.member, editableBy: EditableBy.member, defaultVisibility: SectionVisibility.coach, sensitivity: Sensitivity.medium, requirement: SectionRequirement.optional, memberControllable: true),
  SectionSpec(key: 'nutrition', owner: EditableBy.member, editableBy: EditableBy.member, defaultVisibility: SectionVisibility.coach, sensitivity: Sensitivity.medium, requirement: SectionRequirement.optional, memberControllable: true),
  // PHI — private by default; the member may opt IN to coach (never wider).
  SectionSpec(key: 'medical', owner: EditableBy.member, editableBy: EditableBy.member, defaultVisibility: SectionVisibility.onlyMe, sensitivity: Sensitivity.high, requirement: SectionRequirement.optional, memberControllable: true, maxMemberVisibility: SectionVisibility.coach),
  SectionSpec(key: 'documents', owner: EditableBy.member, editableBy: EditableBy.member, defaultVisibility: SectionVisibility.onlyMe, sensitivity: Sensitivity.high, requirement: SectionRequirement.optional, memberControllable: true, maxMemberVisibility: SectionVisibility.coach),
  SectionSpec(key: 'emergencyContact', owner: EditableBy.member, editableBy: EditableBy.member, defaultVisibility: SectionVisibility.emergency, sensitivity: Sensitivity.high, requirement: SectionRequirement.optional, memberControllable: false),
  SectionSpec(key: 'preferences', owner: EditableBy.member, editableBy: EditableBy.member, defaultVisibility: SectionVisibility.onlyMe, sensitivity: Sensitivity.low, requirement: SectionRequirement.system, memberControllable: false),
  SectionSpec(key: 'coachNotes', owner: EditableBy.coach, editableBy: EditableBy.coach, defaultVisibility: SectionVisibility.coach, sensitivity: Sensitivity.medium, requirement: SectionRequirement.optional, memberControllable: false),
  SectionSpec(key: 'assessments', owner: EditableBy.coach, editableBy: EditableBy.coach, defaultVisibility: SectionVisibility.coach, sensitivity: Sensitivity.medium, requirement: SectionRequirement.optional, memberControllable: false),
  SectionSpec(key: 'membership', owner: EditableBy.admin, editableBy: EditableBy.admin, defaultVisibility: SectionVisibility.organization, sensitivity: Sensitivity.medium, requirement: SectionRequirement.system, memberControllable: false),
  SectionSpec(key: 'verification', owner: EditableBy.system, editableBy: EditableBy.system, defaultVisibility: SectionVisibility.organization, sensitivity: Sensitivity.medium, requirement: SectionRequirement.derived, memberControllable: false),
  SectionSpec(key: 'aiData', owner: EditableBy.system, editableBy: EditableBy.system, defaultVisibility: SectionVisibility.aiSystem, sensitivity: Sensitivity.high, requirement: SectionRequirement.system, memberControllable: false),
];

final Map<String, SectionSpec> _byKey = {
  for (final s in kMemberSections) s.key: s,
};

SectionSpec? sectionSpec(String key) => _byKey[key];

/// Which viewers a given visibility tier admits. `organization` supersedes
/// `coach`; `emergency` is a narrow break-glass audience the org can audit.
const Map<SectionVisibility, List<ViewerRole>> _audience = {
  SectionVisibility.onlyMe: [ViewerRole.member],
  SectionVisibility.emergency: [ViewerRole.member, ViewerRole.emergency, ViewerRole.orgAdmin],
  SectionVisibility.coach: [ViewerRole.member, ViewerRole.coach, ViewerRole.orgAdmin],
  SectionVisibility.organization: [ViewerRole.member, ViewerRole.coach, ViewerRole.orgAdmin],
  SectionVisibility.aiSystem: [ViewerRole.member, ViewerRole.aiSystem],
};

/// Tightness rank — lower = more private. A member may only pick a tier within
/// `[onlyMe … maxMemberVisibility]`.
const Map<SectionVisibility, int> _tightness = {
  SectionVisibility.onlyMe: 0,
  SectionVisibility.emergency: 1,
  SectionVisibility.coach: 2,
  SectionVisibility.organization: 3,
  SectionVisibility.aiSystem: 4,
};

/// True if [a] is at least as private (tight) as [b].
bool isAtLeastAsTight(SectionVisibility a, SectionVisibility b) =>
    _tightness[a]! <= _tightness[b]!;

/// The visibility actually in force: the member's override clamped to
/// `[onlyMe … maxMemberVisibility]`; a too-broad override clamps down to the max,
/// so the policy can never leak more than the design permits.
SectionVisibility effectiveVisibility(SectionSpec section,
    [SectionVisibility? memberOverride]) {
  if (!section.memberControllable || memberOverride == null) {
    return section.defaultVisibility;
  }
  final max = section.maxMemberVisibility ?? section.defaultVisibility;
  return isAtLeastAsTight(memberOverride, max) ? memberOverride : max;
}

/// THE authorization primitive. The member always sees their own sections except
/// pure AI-internal data. Unknown section → deny (fail-closed).
bool canViewSection(String sectionKey, ViewerRole viewer,
    [Map<String, SectionVisibility> overrides = const {}]) {
  final section = _byKey[sectionKey];
  if (section == null) return false;
  if (viewer == ViewerRole.member) return section.key != 'aiData';
  final vis = effectiveVisibility(section, overrides[sectionKey]);
  return _audience[vis]!.contains(viewer);
}

/// The section keys a viewer may see — what a future TrainerHQ workspace renders.
List<String> visibleSectionsFor(ViewerRole viewer,
    [Map<String, SectionVisibility> overrides = const {}]) {
  return kMemberSections
      .where((s) => canViewSection(s.key, viewer, overrides))
      .map((s) => s.key)
      .toList();
}

/// The coach-readable PROJECTION of a member's profile: only coach-visible,
/// member-owned, present sections. (P3 will stamp this onto
/// `clients/{id}.sharedProfile` via a CF; here it is the reference algorithm.)
Map<String, dynamic> coachProjection(Map<String, dynamic> fullProfile,
    [Map<String, SectionVisibility> overrides = const {}]) {
  final out = <String, dynamic>{};
  for (final key in visibleSectionsFor(ViewerRole.coach, overrides)) {
    if (fullProfile.containsKey(key) && _byKey[key]?.owner == EditableBy.member) {
      out[key] = fullProfile[key];
    }
  }
  return out;
}

/// Completion over member-owned, non-derived sections (for the progress ring).
double completionRatio(Map<String, dynamic> fullProfile) {
  final scorable = kMemberSections.where((s) =>
      s.owner == EditableBy.member &&
      s.requirement != SectionRequirement.system &&
      s.requirement != SectionRequirement.derived);
  if (scorable.isEmpty) return 1;
  final done = scorable.where((s) {
    final v = fullProfile[s.key];
    return v != null && v is Map && v.isNotEmpty;
  }).length;
  return done / scorable.length;
}

/// Parses a stored visibility string, or null if unrecognized.
SectionVisibility? parseVisibility(String? s) {
  switch (s) {
    case 'onlyMe':
      return SectionVisibility.onlyMe;
    case 'emergency':
      return SectionVisibility.emergency;
    case 'coach':
      return SectionVisibility.coach;
    case 'organization':
      return SectionVisibility.organization;
    case 'aiSystem':
      return SectionVisibility.aiSystem;
    default:
      return null;
  }
}

/// The canonical member profile container. Sections are `key → data map`
/// (referencing, not embedding, time-series logs); `privacy` holds the member's
/// per-section visibility overrides. Serializes to/from the `profile`/`privacy`
/// maps on `clientProfiles/{uid}` (additive — legacy top-level fields untouched).
class MemberProfile {
  final Map<String, Map<String, dynamic>> sections;
  final Map<String, SectionVisibility> privacy;

  const MemberProfile({this.sections = const {}, this.privacy = const {}});

  factory MemberProfile.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const MemberProfile();
    final sections = <String, Map<String, dynamic>>{};
    final rawSections = m['profile'];
    if (rawSections is Map) {
      rawSections.forEach((k, v) {
        if (v is Map) sections[k.toString()] = Map<String, dynamic>.from(v);
      });
    }
    final privacy = <String, SectionVisibility>{};
    final rawPrivacy = m['privacy'];
    if (rawPrivacy is Map) {
      rawPrivacy.forEach((k, v) {
        final vis = parseVisibility(v?.toString());
        if (vis != null) privacy[k.toString()] = vis;
      });
    }
    return MemberProfile(sections: sections, privacy: privacy);
  }

  /// The ADDITIVE patch to merge into `clientProfiles/{uid}` — `profile` +
  /// `privacy` only. Never clobbers legacy fields (write with SetOptions.merge).
  Map<String, dynamic> toMap() => {
        'profile': sections,
        if (privacy.isNotEmpty)
          'privacy': {for (final e in privacy.entries) e.key: e.value.name},
      };

  bool has(String key) => sections[key]?.isNotEmpty ?? false;
  Map<String, dynamic>? section(String key) => sections[key];
  double get completion => completionRatio(sections);
  bool canView(String key, ViewerRole viewer) =>
      canViewSection(key, viewer, privacy);
  List<String> visibleTo(ViewerRole viewer) =>
      visibleSectionsFor(viewer, privacy);

  MemberProfile withSection(String key, Map<String, dynamic> data) {
    final next = Map<String, Map<String, dynamic>>.from(sections)..[key] = data;
    return MemberProfile(sections: next, privacy: privacy);
  }

  MemberProfile withVisibility(String key, SectionVisibility v) {
    final next = Map<String, SectionVisibility>.from(privacy)..[key] = v;
    return MemberProfile(sections: sections, privacy: next);
  }
}
