/// EXECUTION BRIDGE — makes `flutter test` run the membership lifecycle
/// widget suite (`patrolWidgetTest`, invisible to both `patrol test` and a
/// plain `flutter test` in its integration_test/ home — see
/// my_plans_bridge_test.dart for the full story).
///
/// This suite was RED when first executed: its hand-written mirror of
/// `MembershipController._parseExpiry` had kept the pre-`.toLocal()` behaviour
/// after production was fixed, so it asserted the very timezone defect the fix
/// removed. A suite that runs nowhere hides red exactly as well as green.
library;

import '../integration_test/membership_lifecycle_patrol_test.dart'
    as membership_lifecycle;

void main() => membership_lifecycle.main();
