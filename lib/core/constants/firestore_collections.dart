/// Canonical Firestore collection names — SHARED with trainersHQ + the founder
/// console. Never hardcode collection strings; never fork these names.
class FsCollections {
  FsCollections._();

  // ── Member identity ────────────────────────────────────────────────
  /// Gym-created member record (written by trainersHQ / verifyAndActivateMembership CF).
  static const String clients = 'clients';

  /// Member's own app profile (written by this app). docId == auth uid.
  static const String clientProfiles = 'clientProfiles';

  // NIP PHASE A — a phantom `nutritionLogs` constant used to be declared here
  // (a clientProfiles subcollection that was never read or written by anyone).
  // Removed: daily adherence lives in `client_diet_logs` today, and Phase B's
  // real day store will be `client_nutrition_days` — a constant naming a
  // collection that never existed only invites writes to the wrong place.

  /// NIP PHASE 3A — the Food Log day document, `{clientId}_{yyyy-MM-dd}`.
  ///
  /// The member's record of what they ACTUALLY ate, as distinct from
  /// [clientDietLogs], which records adherence to what the coach PRESCRIBED.
  /// Two different questions, so two different documents: a recommendation
  /// never changes, and a log must be free to record a food no plan mentions.
  ///
  /// `entries` is a MAP keyed by entryId (never an array) so one tap writes one
  /// field path — offline replay is idempotent and two devices adding
  /// different foods never clobber each other. `computed` and `coachReview`
  /// are SERVER-owned and the rules reject any client write to them.
  static const String clientNutritionDays = 'client_nutrition_days';

  // ── Member performance logs (member-written, trainer-read) ─────────
  /// One doc per logged workout session (per-set prescribed-vs-actual).
  /// Top-level; keep name in sync with trainersHQ FsCollections.
  static const String clientWorkoutSessions = 'client_workout_sessions';

  /// One doc per day of diet adherence. docId == '{clientId}_{yyyy-MM-dd}'.
  static const String clientDietLogs = 'client_diet_logs';

  /// One doc per day of lifestyle metrics (water ml / steps / sleep / supplements).
  /// docId == '{clientId}_{yyyy-MM-dd}'. Keep in sync with trainersHQ FsCollections.
  static const String clientLifestyleLogs = 'client_lifestyle_logs';

  /// WS-6 — the member's lifestyle EVENTS for one day
  /// (`{clientId}_{yyyy-MM-dd}`). Drinks, sleep, doses and step samples, each
  /// with a time and a provenance. Every metric a coach sees is derived from
  /// these by the server; `computed` on the document is server-owned and the
  /// rules reject any client write to it.
  ///
  /// [clientLifestyleLogs] above is the legacy totals document. It is still
  /// mirrored during the migration window because TrainerHQ's lifestyle review
  /// reads it, and it retires when TrainerHQ reads `coaching_rollups`.
  static const String clientLifestyleDays = 'client_lifestyle_days';

  /// WS-7 — the server-derived coaching read model, one document per
  /// member-MONTH (`{clientId}_{yyyy-MM}`) holding a cell per day per track.
  ///
  /// The member reads their OWN rollups for Lifestyle history, which is the
  /// same collection TrainerHQ reads: member and coach then see identical
  /// server-derived numbers rather than two apps deriving history separately
  /// from raw events. Permitted by the rules' own member clause and proven in
  /// `trainershq-backend/tests/rules/member_rollup_read.mjs`. CF-written only.
  static const String coachingRollups = 'coaching_rollups';

  /// The server-derived NUTRITION read model, one document per member-MONTH
  /// (`{clientId}_{yyyy-MM}`) holding a cell per day.
  ///
  /// Written by `onNutritionDayWritten` since NIP Phase A and, until Progress
  /// V2, read by NOBODY in any of the three apps — a computed, indexed,
  /// rules-protected collection the platform paid to maintain and never opened.
  /// The member now reads their OWN months for long-range nutrition trends,
  /// which is both bounded (12 document reads for a year, versus 365 day
  /// listeners) and canonical: the member and their coach quote the same
  /// server-computed number rather than deriving it twice.
  ///
  /// Permitted by the rules' member clause (`clients.authUid`), the same clause
  /// [coachingRollups] already relies on. CF-written only.
  static const String nutritionRollups = 'nutrition_rollups';

  /// Member-submitted weekly check-in packets (coach reviews + responds).
  /// Keep in sync with trainersHQ FsCollections.
  static const String clientCheckInSubmissions = 'client_check_in_submissions';

  /// Member-logged body progress (weight/measurements/photos). One doc per entry.
  /// Ownership field is `authUid` (not authorId). Keep in sync with trainersHQ.
  static const String clientProgress = 'client_progress';

  /// Member → owning-admin feedback/complaints (trainers cannot read). One doc
  /// per submission. Ownership field is `authUid`. Keep in sync with trainersHQ.
  static const String clientFeedback = 'client_feedback';

  // ── Org / staff (read-only for member) ────────────────────────────
  static const String admins = 'admins';
  static const String trainers = 'trainers';

  /// Platform staff. Read ONLY by the login role gate
  /// ([AccountRoleService]), which asks "is this uid a professional account?"
  /// before admitting anyone to the member app. Keep in sync with trainersHQ
  /// FsCollections.masterAdmins.
  static const String masterAdmins = 'master_admins';
  static const String organizationProfiles = 'organizationProfiles';
  static const String coachProfiles = 'coach_profiles';

  // ── Assigned training content ──────────────────────────────────────
  static const String clientPlanAssignments = 'client_plan_assignments';
  static const String workoutPlans = 'workoutPlans';
  static const String weeklyWorkoutPlans = 'weeklyWorkoutPlans';
  static const String exercises = 'exercises';

  // FOOD PLATFORM V1 — `dietPlans` and `foodDatabase` are DELIBERATELY ABSENT.
  //
  // A member never reads food. The served diet arrives fully resolved from the
  // getMyTraining callable, which reads the assignment snapshot server-side and
  // emits per-item name, quantity and macros. The security rules match that:
  // a client is neither an admin nor a trainer, so every branch of the
  // foodDatabase read rule denies them.
  //
  // These two constants used to be declared here and referenced by nothing —
  // dead declarations that implied a member-side food dependency that has never
  // existed. Removing them makes the boundary explicit: if a future member
  // feature genuinely needs food, it needs a rules change and a design decision,
  // not a constant that was already lying in wait.

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
  static const String coachReviews = 'coach_reviews';
  static const String coachAssignmentHistory = 'coach_assignment_history';

  // ── In-app notification center ────────────────────────────────────
  /// Summary doc `notifications/{uid}` ({unread, updatedAt}) + subcollection
  /// `notifications/{uid}/items/{id}`. CF-written; client may only zero the
  /// unread counter and stamp readAt/archivedAt (server timestamps).
  static const String notifications = 'notifications';
  static const String notificationItems = 'items';

  // ── Coach onboarding ───────────────────────────────────────────────
  /// The coach's onboarding form (member reads; per-org by adminId).
  static const String onboardingQuestions = 'onboarding_questions';

  /// The member's submitted answers. docId == clientId (one per member).
  static const String onboardingResponses = 'onboarding_responses';
}
