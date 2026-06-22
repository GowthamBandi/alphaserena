/// Canonical Firestore collection names — SHARED with trainersHQ + the founder
/// console. Never hardcode collection strings; never fork these names.
class FsCollections {
  FsCollections._();

  // Member identity
  static const String clients = 'clients'; // gym-created member record
  static const String clientProfiles = 'clientProfiles'; // member's own app profile

  // Org / staff (read-only for the member)
  static const String admins = 'admins';
  static const String trainers = 'trainers';
  static const String organizationProfiles = 'organizationProfiles';

  // Assigned training content
  static const String clientPlanAssignments = 'client_plan_assignments';
  static const String workoutPlans = 'workoutPlans';
  static const String dietPlans = 'dietPlans';
  static const String weeklyWorkoutPlans = 'weeklyWorkoutPlans';
  static const String exercises = 'exercises';
  static const String foodDatabase = 'foodDatabase';

  // Chat (member ↔ trainer): chats/{clientId}/messages/{id}
  static const String chats = 'chats';
  static const String chatMessages = 'messages';

  // Tier-2 memberships (gym → member)
  static const String membershipPlans = 'membershipPlans';
  static const String memberPayments = 'memberPayments';
}
