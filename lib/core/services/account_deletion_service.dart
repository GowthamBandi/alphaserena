import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../constants/firestore_collections.dart';
import 'call_service.dart';
import 'member_push_service.dart';

/// The outcome of an account-deletion attempt. The caller renders a different,
/// honest message for each — a failed deletion must never look like a success.
enum AccountDeletionResult {
  /// The auth account and the member's own profile document are gone.
  deleted,

  /// Firebase requires a fresh credential before it will delete an account.
  /// The member must sign out, sign back in, and retry. Nothing was deleted.
  needsRecentLogin,

  /// Network or backend failure. Nothing can be assumed deleted.
  failed,
}

/// Deletes the member's account — the in-app deletion route required by Google
/// Play's account-deletion policy and Apple's Guideline 5.1.1(v).
///
/// **What this genuinely deletes, and why that is the correct boundary.**
///
/// The member OWNS exactly one document — `clientProfiles/{uid}` — and the
/// Firestore rules let precisely one party delete it: them
/// (`allow delete: if signedIn() && request.auth.uid == uid`). That document
/// holds everything the member authored: their canonical identity sections,
/// their contact details, their notification preferences, their measurement log.
/// It is deleted here, along with their Firebase Auth account, with no Cloud
/// Function and no elevated privilege.
///
/// What is deliberately NOT deleted is the organization's own record of them —
/// `clients/{id}`, their payments, and the training logs their coach reviewed.
/// That is not an oversight or a limitation to apologise for: it is the coach's
/// business record of a commercial relationship, it is subject to the
/// organization's own retention and tax obligations, and the member never had
/// write access to it. Conflating "delete my account" with "erase my coach's
/// books" would be both technically impossible from the client and wrong.
///
/// The confirmation UI states this distinction in plain language BEFORE the
/// member confirms, and points them at their organization for the rest.
class AccountDeletionService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Runs the deletion. Returns what actually happened — never a bare bool,
  /// because "you must sign in again" and "it failed" need different words.
  ///
  /// Ordering matters: every step that needs a live session runs BEFORE the auth
  /// account is destroyed, and the auth account is destroyed LAST so a failure
  /// at any earlier point leaves a member who can still sign in and retry rather
  /// than an orphaned, unreachable account.
  Future<AccountDeletionResult> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return AccountDeletionResult.failed;
    final uid = user.uid;

    // 1. Release this device's push token while the session is still valid, so
    //    the next member on this handset never inherits these notifications.
    if (Get.isRegistered<MemberPushService>()) {
      try {
        await Get.find<MemberPushService>().removeTokenOnSignOut();
      } catch (_) {
        // Best effort — a stuck token must not block the member from leaving.
      }
    }

    // 2. End any live call and release the call lock, same reasoning.
    if (Get.isRegistered<CallService>()) {
      try {
        await Get.find<CallService>().endForSignOut();
      } catch (_) {
        // Best effort.
      }
    }

    // 3. Best-effort removal of the profile photo.
    //
    //    KNOWN LIMITATION, not a silent failure: the Storage rule for
    //    `profile_photos/{uid}/{file}` is `allow write: ... && okMedia()`, and
    //    `okMedia()` dereferences `request.resource.size` / `.contentType`,
    //    which are null on a delete. The rule therefore denies the member
    //    deleting their own photo. This call is kept because it becomes correct
    //    the moment the rule separates delete from write, and because failing
    //    here must not stop the deletion. The orphaned object is recorded as an
    //    open item in the certification.
    //    Bounded for the same reason as step 4: a Storage call with no
    //    connectivity would otherwise stall the whole deletion here, before the
    //    step that actually matters.
    await _tryDeleteProfilePhoto(uid);

    // 4. Delete the member-owned document. This is the real data deletion, and
    //    it must succeed before the auth account goes — once the account is
    //    deleted the rules would deny this write forever, stranding the document.
    //
    //    THE TIMEOUT IS LOAD-BEARING, not defensive padding. A Firestore write
    //    issued with no connectivity is queued locally and its Future does NOT
    //    complete until the server acknowledges it — the same trap that left the
    //    diet logger showing "Saving…" forever. Without this, an offline member
    //    tapping Delete would sit on a spinner indefinitely while believing
    //    their account was being deleted. Failing honestly after 15 seconds is
    //    the only correct behaviour: the local delete may still flush later, but
    //    we must not claim an outcome we have not observed.
    try {
      await _db
          .collection(FsCollections.clientProfiles)
          .doc(uid)
          .delete()
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return AccountDeletionResult.failed;
    }

    // 5. Delete the auth account itself.
    try {
      await user.delete();
      return AccountDeletionResult.deleted;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        return AccountDeletionResult.needsRecentLogin;
      }
      return AccountDeletionResult.failed;
    } catch (_) {
      return AccountDeletionResult.failed;
    }
  }

  /// Deletes every object under the member's own photo folder, best effort and
  /// time-boxed so it can never stall the deletion that follows it.
  Future<void> _tryDeleteProfilePhoto(String uid) async {
    try {
      final folder = FirebaseStorage.instance.ref('profile_photos/$uid');
      final listing = await folder.listAll().timeout(
        const Duration(seconds: 8),
      );
      for (final item in listing.items) {
        try {
          await item.delete().timeout(const Duration(seconds: 5));
        } catch (_) {
          // See the note at the call site — the current rule denies this.
        }
      }
    } catch (_) {
      // Listing itself may be denied or unreachable; nothing here is
      // load-bearing.
    }
  }

  /// A short, honest description of what the member's organization keeps after
  /// deletion, for the confirmation sheet. Named rather than generic when the
  /// organization is actually known.
  static String retentionNotice(String orgName) {
    final who = orgName.trim().isNotEmpty ? orgName.trim() : 'your organization';
    return 'Your coaching record with $who — the details they entered, your '
        'membership and payment history, and the training logs they reviewed — '
        'belongs to them and stays in their books. Contact $who directly about '
        'that record.';
  }

  /// Whether a deletion can even be attempted right now.
  static bool get canAttempt => FirebaseAuth.instance.currentUser != null;

  /// The linked organization name, for [retentionNotice], when known.
  static String get orgName => Get.isRegistered<MemberController>()
      ? Get.find<MemberController>().orgName
      : '';
}
