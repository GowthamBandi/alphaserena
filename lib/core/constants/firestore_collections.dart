/// Canonical Firestore collection names — SHARED with trainersHQ + the founder
/// console. Never hardcode collection strings; never fork these names.
class FsCollections {
  FsCollections._();

  // ── Member identity ────────────────────────────────────────────────
  /// Gym-created member record (written by trainersHQ / verifyAndActivateMembership CF).
  static const String clients = 'clients';

  /// Member's own app profile (written by this app). docId == auth uid.
  static const String clientProfiles = 'clientProfiles';

  /// Daily nutrition logs: clientProfiles/{uid}/nutritionLogs/{dateKey}
  /// dateKey format: 'yyyy-MM-dd'. Each doc = one day's meals.
  static const String nutritionLogs = 'nutritionLogs';

  // ── Member performance logs (member-written, trainer-read) ─────────
  /// One doc per logged workout session (per-set prescribed-vs-actual).
  /// Top-level; keep name in sync with trainersHQ FsCollections.
  static const String clientWorkoutSessions = 'client_workout_sessions';

  /// One doc per day of diet adherence. docId == '{clientId}_{yyyy-MM-dd}'.
  static const String clientDietLogs = 'client_diet_logs';

  // ── Org / staff (read-only for member) ────────────────────────────
  static const String admins = 'admins';
  static const String trainers = 'trainers';
  static const String organizationProfiles = 'organizationProfiles';

  // ── Assigned training content ──────────────────────────────────────
  static const String clientPlanAssignments = 'client_plan_assignments';
  static const String workoutPlans = 'workoutPlans';
  static const String dietPlans = 'dietPlans';
  static const String weeklyWorkoutPlans = 'weeklyWorkoutPlans';
  static const String exercises = 'exercises';
  static const String foodDatabase = 'foodDatabase';

  // ── Chat (member ↔ trainer) ────────────────────────────────────────
  // Thread: chats/{clientId}/messages/{messageId}
  static const String chats = 'chats';
  static const String chatMessages = 'messages';

  // ── Tier-2 memberships (coach → member) ───────────────────────────
  static const String membershipPlans = 'membershipPlans';
  static const String memberPayments = 'memberPayments';

  // ── Member → organization rating + comment ────────────────────────
  /// One review per member per org. docId == '{adminId}_{clientId}'. The
  /// aggregate rating/reviewCount on organizationProfiles is recomputed by the
  /// onOrgReviewWritten Cloud Function (in trainersHQ).
  static const String orgReviews = 'org_reviews';

  // ── Coach onboarding ───────────────────────────────────────────────
  /// The coach's onboarding form (member reads; per-org by adminId).
  static const String onboardingQuestions = 'onboarding_questions';

  /// The member's submitted answers. docId == clientId (one per member).
  static const String onboardingResponses = 'onboarding_responses';
}
