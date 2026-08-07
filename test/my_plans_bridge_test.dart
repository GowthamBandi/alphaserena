/// EXECUTION BRIDGE — makes `flutter test` run the My Plans widget suite.
///
/// THE GAP THIS CLOSES. `patrol test -t integration_test/my_plans_patrol_test.dart`
/// reported `Total: 0, exit 0` — a green run that executed nothing. The file
/// uses `patrolWidgetTest`, a HOST widget test that produces no native entry
/// point, so Patrol's runner cannot see it; and it lives in `integration_test/`,
/// which `flutter test` does not scan. So the member's My Plans screen — the
/// most important member surface of the Plans module — had 34 tests running in
/// NO pipeline at all.
///
/// WHY A BRIDGE RATHER THAN A MOVE: relocating the file was declined
/// previously; importing its `main()` executes it where it stands. The suite's
/// own `boot()` calls the real `Firebase.initializeApp()` (it was written for a
/// device), which never resolves on a bare host — so the bridge installs the
/// firebase_core platform mocks first, the same setup every host suite in
/// `test/` uses.
///
/// ONE suite per bridge file: see membership_lifecycle_bridge_test.dart.
/// Converting the suite to `patrolTest` for true device coverage remains the
/// better end state; this closes the runs-nowhere gap today.
library;

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';

import '../integration_test/my_plans_patrol_test.dart' as my_plans;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  my_plans.main();
}
