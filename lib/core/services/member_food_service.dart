import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/member_controller.dart';
import '../models/member_food.dart';

/// The outcome of one food search — a result set OR a reason there isn't one.
///
/// A search that fails and a search that legitimately found nothing must never
/// render the same: "no foods match 'quinoa'" invites the member to try
/// another word, while "couldn't reach the library" invites them to retry. The
/// old pattern of returning an empty list for both is what produces an app
/// that quietly claims a gym has no foods whenever the network hiccups.
class FoodSearchOutcome {
  final List<MemberFood> foods;
  final bool failed;

  /// The query was below the indexable minimum, so BROWSE was served instead.
  /// The UI keeps the rows and says "keep typing" rather than blanking.
  final bool tooShort;

  /// The org tier was answered by the un-indexed fallback — the gym's library
  /// predates the `searchTokens` backfill and results may be incomplete.
  final bool orgFallback;

  const FoodSearchOutcome({
    this.foods = const [],
    this.failed = false,
    this.tooShort = false,
    this.orgFallback = false,
  });

  const FoodSearchOutcome.failure() : this(failed: true);

  bool get isEmpty => foods.isEmpty && !failed;
}

/// NIP PHASE 3A — the member's food library access.
///
/// Every read goes through the `searchMemberFoods` callable: a member has no
/// Firestore read access to `foodDatabase`, deliberately, because the rules
/// grant the org library to its owning organization alone. See
/// `functions/src/member_food.ts` for why this is a callable and not a rules
/// change.
class MemberFoodService {
  MemberFoodService({FirebaseFunctions? functions, String Function()? cacheOwner})
      : _injected = functions,
        _cacheOwner = cacheOwner;

  final FirebaseFunctions? _injected;

  /// Resolves WHO the recents cache on this device belongs to. Injectable so
  /// the isolation property is assertable without Firebase — see [_owner].
  final String Function()? _cacheOwner;

  /// Resolved LAZILY, not in the constructor.
  ///
  /// `FirebaseFunctions.instance` throws when no Firebase app exists, and a
  /// constructor that touches it runs even for a subclass that overrides every
  /// method — so an eager field made this class impossible to fake in a unit
  /// test without booting Firebase. Nothing here needs the instance until a
  /// search actually goes out.
  FirebaseFunctions get _functions => _injected ?? FirebaseFunctions.instance;

  /// Per-session result cache, keyed by the normalized query.
  ///
  /// A member types "chi" → "chick" → "chicken" and then backspaces; without
  /// this, every backspace is another round trip for a page the app already
  /// holds. Session-scoped on purpose: a coach adding a food mid-session
  /// should become visible on the next app open, not be cached out for days.
  final Map<String, List<MemberFood>> _cache = {};

  static const _recentsKey = 'nutrition_recent_foods_v1';
  static const int maxRecents = 12;

  /// How long to wait for the callable before giving up on one keystroke.
  ///
  /// Shorter than a default function timeout on purpose: a search is a
  /// disposable request behind a debounce. Holding a spinner for 60s while
  /// three newer queries have already been typed helps nobody.
  static const Duration searchTimeout = Duration(seconds: 12);

  String _key(String query) => query.trim().toLowerCase();

  /// Searches the two tiers. An empty [query] returns the BROWSE page
  /// (organization foods first, then the platform library).
  Future<FoodSearchOutcome> search(String query, {int limit = 24}) async {
    final key = _key(query);
    final cached = _cache[key];
    if (cached != null) return FoodSearchOutcome(foods: cached);

    try {
      final res = await _functions
          .httpsCallable('searchMemberFoods')
          .call({'query': query.trim(), 'limit': limit})
          .timeout(searchTimeout);

      final data = Map<String, dynamic>.from(res.data as Map);
      final raw = data['foods'];
      final foods = raw is List
          ? raw
              .whereType<Map>()
              .map((f) => MemberFood.fromMap(Map<String, dynamic>.from(f)))
              .where((f) => f.foodId.isNotEmpty && f.name.isNotEmpty)
              .toList()
          : <MemberFood>[];

      _cache[key] = foods;
      return FoodSearchOutcome(
        foods: foods,
        tooShort: data['tooShort'] == true,
        orgFallback: data['orgFallback'] == true,
      );
    } catch (_) {
      // Includes TimeoutException, offline (`unavailable`) and an expired
      // membership (`not-found`). The screen distinguishes offline from failed
      // using the app-wide ConnectivityController rather than by parsing codes
      // — one source of truth for "is there internet".
      return const FoodSearchOutcome.failure();
    }
  }

  /// Drops the cache — called when the member's organization changes, since
  /// the org tier of every cached page belonged to the previous gym.
  void invalidate() => _cache.clear();

  // ── RECENTS ──────────────────────────────────────────────────────────────
  //
  // Local, not server-side, and that is a deliberate trade.
  //
  // A server-backed recents list would need either a new denormalized document
  // or a cross-day query over `client_nutrition_days` (an index, plus reads on
  // every screen open) to produce a CONVENIENCE affordance. Recents are not
  // data — the logged entries are, and those are already durable, server-owned
  // and coach-visible. Losing a recents list costs a member three taps; it
  // loses nothing.
  //
  // ACCEPTED CONSEQUENCE: recents are per-device. A member logging on a phone
  // and a tablet sees two different shortcut lists. Their FOOD LOG is
  // identical on both, which is the part that must not diverge.
  //
  // N17 — THE CACHE CARRIES ITS OWNER, and that is not optional.
  //
  // Being device-local made this the ONE member-scoped store that controller
  // teardown cannot reach. Every other one is an in-memory Rx field destroyed
  // by `AuthController._teardownToLogin`; this one is a file. So a device-
  // GLOBAL slot outlived the member who filled it: the next member to sign in
  // on the same handset was served the previous member's shortcuts, and if
  // the two belonged to different organizations, the previous gym's PRIVATE
  // library — cards `searchMemberFoods` authorized against the FIRST member's
  // `clients.adminId` and no later layer ever re-checks. Proven loggable end
  // to end: the write is identity-correct in every way the rules examine, so
  // the leak lands as durable data in the receiving organization.
  //
  // The stamp is the repair rather than a call to [forgetRecents], because a
  // call site only covers the paths that RUN. A force-stop, an OS kill or a
  // crash signs nobody out, and a coach-side org transfer signs nobody out
  // either. An owner the cache has to match is checked on every read, on
  // every path, including the ones nobody thought of.

  /// `uid|adminId` — the identity a cached recents list belongs to.
  ///
  /// BOTH halves are load-bearing. The uid separates two members sharing a
  /// device; the adminId separates one member's two organizations, which is
  /// the transfer case where no sign-out happens at all.
  ///
  /// Empty means UNRESOLVED (no member yet, or the `clients` document still in
  /// flight), and unresolved fails CLOSED — see [recents].
  String get _owner {
    final resolve = _cacheOwner;
    if (resolve != null) return resolve();
    if (!Get.isRegistered<MemberController>()) return '';
    final m = Get.find<MemberController>();
    final uid = m.uid;
    final admin = m.adminId;
    if (uid.isEmpty || admin.isEmpty) return '';
    return '$uid|$admin';
  }

  Future<List<MemberFood>> recents() async {
    try {
      final owner = _owner;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_recentsKey);
      if (raw == null || raw.isEmpty) return const [];

      // FAIL CLOSED while the identity is unknown. Serving a list nobody can
      // be proven to own is exactly how this reopens on a slow `clients`
      // fetch. Nothing is deleted here — the rightful owner's shortcuts must
      // still be waiting when their identity lands a moment later.
      if (owner.isEmpty) return const [];

      final decoded = jsonDecode(raw);
      // A bare List is the PRE-N17 format: no owner, therefore unprovable,
      // therefore not this member's. Purging it is what removes an already
      // leaked library from the disks of devices that upgrade into the fix.
      final stored = decoded is Map ? decoded : null;
      if (stored == null || stored['owner'] != owner) {
        await forgetRecents();
        return const [];
      }

      final list = stored['foods'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((m) => MemberFood.fromMap(Map<String, dynamic>.from(m)))
          .where((f) => f.foodId.isNotEmpty && f.name.isNotEmpty)
          .toList();
    } catch (_) {
      // Corrupt JSON reads as "no recents", never as a crash on a screen the
      // member opens to log lunch.
      return const [];
    }
  }

  /// Promotes [food] to the front of the recents list (most-recent-first,
  /// de-duplicated by foodId, bounded to [maxRecents]).
  Future<void> remember(MemberFood food) async {
    if (food.foodId.isEmpty) return;
    try {
      final owner = _owner;
      // An unowned write would be a list the next reader cannot attribute —
      // which is the defect, re-created from the other side.
      if (owner.isEmpty) return;
      // [recents] already returns EMPTY for a foreign or unstamped slot, so
      // this can only ever prepend onto a list this owner earned.
      final current = await recents();
      final next = [
        food,
        ...current.where((f) => f.foodId != food.foodId),
      ].take(maxRecents).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _recentsKey,
        jsonEncode({
          'owner': owner,
          'foods': [for (final f in next) f.toCache()],
        }),
      );
    } catch (_) {
      // A recents write is best-effort by design: it must never be able to
      // fail the log it is a side effect of.
    }
  }

  /// Clears recents. Called on sign-out so the previous member's shortcuts are
  /// destroyed at the moment they stop being theirs, rather than surviving on
  /// disk until the next read notices the owner has changed. The owner stamp
  /// is what makes the leak impossible; this is what makes it brief.
  Future<void> forgetRecents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentsKey);
    } catch (_) {/* best effort */}
  }
}
