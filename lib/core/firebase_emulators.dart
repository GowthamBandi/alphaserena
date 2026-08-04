import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// LOCAL FIREBASE EMULATOR SUITE — test infrastructure, never a product path.
///
/// Points Auth, Firestore and Functions at a locally running emulator suite so
/// the REAL application — real controllers, real streams, real GetX wiring,
/// real security rules and real Cloud Functions — can be driven end to end by a
/// genuine signed-in member. Nothing here is mocked: only the endpoint moves.
///
/// It exists because this project's phone OTP cannot complete on a device (SMS
/// is externally blocked), which left every member-facing read path unprovable
/// on real hardware. The Auth emulator issues verification codes over its own
/// REST API, so a member can actually sign in and be observed.
///
/// OFF unless explicitly asked for, and IMPOSSIBLE in a release build:
///
///   flutter run --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2
///
/// `10.0.2.2` is how an Android emulator reaches the host machine's localhost.
///
/// Release builds short-circuit on [kReleaseMode] before reading the flag at
/// all, so a shipped APK cannot be pointed at a developer's machine even if the
/// define were somehow baked in.
const String kFirebaseEmulatorHost =
    String.fromEnvironment('FIREBASE_EMULATOR_HOST');

/// Ports mirror `trainershq-backend/firebase.json`. They are the suite's
/// defaults; if that file changes, this must change with it.
const int kAuthEmulatorPort = 9099;
const int kFirestoreEmulatorPort = 8080;
const int kFunctionsEmulatorPort = 5001;

/// True when this build is talking to a local emulator suite.
bool get usingFirebaseEmulators =>
    !kReleaseMode && kFirebaseEmulatorHost.isNotEmpty;

/// Wires the SDKs to the local suite. Call once, immediately after
/// `Firebase.initializeApp()` and before anything touches Firestore.
///
/// No-op — and not merely a skipped branch but an unreachable one — in release.
Future<void> connectFirebaseEmulators() async {
  if (!usingFirebaseEmulators) return;

  final host = kFirebaseEmulatorHost;

  // DATA ENDPOINTS FIRST, and nothing that can throw before them. If a later
  // step failed and aborted this function, an app that believed it was on the
  // emulator would be reading and WRITING PRODUCTION — the one outcome a
  // validation harness must make impossible.
  FirebaseFirestore.instance.useFirestoreEmulator(host, kFirestoreEmulatorPort);
  FirebaseFunctions.instance
      .useFunctionsEmulator(host, kFunctionsEmulatorPort);
  await FirebaseAuth.instance.useAuthEmulator(host, kAuthEmulatorPort);

  // Android phone auth runs Play Integrity / reCAPTCHA app verification before
  // it will send a code. That check cannot succeed against a local emulator, so
  // `verifyPhoneNumber` fails with "Verification failed" however valid the
  // number is. Disabling it is the documented emulator path, and is why the
  // Auth emulator can hand out codes over its REST API at all.
  //
  // Best-effort: if this ever fails, phone sign-in is unavailable but the data
  // endpoints above are already safely redirected.
  try {
    await FirebaseAuth.instance
        .setSettings(appVerificationDisabledForTesting: true);
  } catch (e) {
    debugPrint('⚠️  appVerificationDisabledForTesting failed: $e');
  }

  // Loud on purpose: a run that silently talked to the wrong backend would
  // make every observation in a validation pass meaningless.
  debugPrint('🔌 Firebase EMULATOR SUITE @ $host '
      '(auth $kAuthEmulatorPort · firestore $kFirestoreEmulatorPort · '
      'functions $kFunctionsEmulatorPort)');
}
