/// IS THIS DAY KEY POSSIBLE? — the member-app half of the rule.
///
/// ── WHY THIS FILE EXISTS ────────────────────────────────────────────────────
///
/// A member-day document is named `{clientId}_{yyyy-MM-dd}`, and that day key is
/// minted by `dayKey(DateTime.now())` — the DEVICE clock. Nothing checked the
/// result, at any layer. On 3 August 2026 a device running fast produced two
/// real production documents, 43 minutes apart:
///
///   client_lifestyle_days/EkNg…_2026-08-06   server receipt 2026-08-03 08:24 IST (+3.18 d)
///   client_lifestyle_days/EkNg…_2026-08-09   server receipt 2026-08-03 09:07 IST (+6.00 d)
///
/// Three days later the first became "today" on the coach's dashboard, showing
/// a member as having logged water, steps and sleep on a day they had not lived.
///
/// This is a BYTE-FOR-BYTE MIRROR of the server's
/// `functions/src/lib/day_key_plausibility.ts`. Both sides must agree, or the
/// app refuses writes the server would accept (or, far worse, the reverse).
///
/// ── WHAT THIS LAYER CAN AND CANNOT DO ───────────────────────────────────────
///
/// It cannot be the guarantee. A device with a wrong clock has, by definition,
/// no trustworthy local notion of "now", so the app cannot rule on its own
/// correctness from first principles. The GUARANTEE is `firestore.rules`, which
/// compares against `request.time` — the server's clock, the one value in a
/// write the device cannot influence.
///
/// What this layer adds is real, though: once the app has seen ANY server
/// instant, it holds a lower bound on real time that the device cannot argue
/// with, and a day key beyond that bound plus a day is refused BEFORE upload —
/// with a message naming the actual problem, instead of an opaque
/// permission-denied the member cannot act on.
library;

/// How far ahead of a known server instant a local day key may legitimately be.
///
/// ONE DAY IS THE WIDTH OF THE WORLD, not a fudge factor. The key is LOCAL and
/// the reference is UTC: at UTC+14 (Kiritimati) a member's local date really is
/// the UTC date plus one, and at UTC-12 really is minus one. Beyond +1 there is
/// no timezone on earth in which that key is anybody's today.
const int kDayKeyFutureToleranceDays = 1;

/// `yyyy-MM-dd` with BOUNDED components — month 01–12, day 01–31.
///
/// Was `^\d{4}-\d{2}-\d{2}$`, which admits `0000-00-00`. The PAST is unbounded
/// by design, so a past key is checked by shape ALONE — and an impossible date
/// sorts below every ceiling, so it passed every layer. The identical regex is
/// in `firestore.rules` and `day_key_plausibility.ts`: all three must agree on
/// what a day key IS before they can agree on which ones are possible.
final RegExp _dayKeyShape =
    RegExp(r'^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$');

/// Whether [dateKey] names a day that EXISTS on the calendar.
///
/// The check no regex can make: `2026-02-30` and `2027-02-29` have the right
/// digits, the right bounds and the right sort order. Parsing and re-formatting
/// is what separates them — `DateTime.utc` normalises February 30th to March
/// 2nd, which no longer matches the string it came from.
///
/// A BYTE-FOR-BYTE MIRROR of `isRealCalendarDay` in
/// `functions/src/lib/day_key_plausibility.ts`.
bool isRealCalendarDay(String dateKey) {
  if (!_dayKeyShape.hasMatch(dateKey)) return false;
  final y = int.parse(dateKey.substring(0, 4));
  final m = int.parse(dateKey.substring(5, 7));
  final d = int.parse(dateKey.substring(8, 10));
  return utcDayKey(DateTime.utc(y, m, d)) == dateKey;
}

/// The UTC calendar day of [at] as a `yyyy-MM-dd` key.
String utcDayKey(DateTime at) {
  final u = at.toUtc();
  final m = u.month.toString().padLeft(2, '0');
  final d = u.day.toString().padLeft(2, '0');
  return '${u.year}-$m-$d';
}

/// The member's LOCAL calendar day as a `yyyy-MM-dd` key — the one canonical
/// implementation in this app.
///
/// ── WHY IT LIVES HERE, AND WHY THERE IS ONLY ONE ───────────────────────────
///
/// This app had FIVE copies of this four-line function: `dayKey` in
/// `lifestyle_math`, `nutritionDayKey`, `localDayKey` in `today_expectation`,
/// `_dayKey` in `workout_history`, and one inlined into `workoutSessionIdFor`.
/// They were not identical — four zero-padded the YEAR and one did not — so the
/// app had two different notions of what a day key IS, differing only for years
/// below 1000. Latent, not live, and exactly the shape of the defect this whole
/// workstream exists to close: one rule, several copies, one of them drifting.
///
/// The unpadded form WINS, because it is what `utcDayKey` above does and what
/// the backend's `utcDayKey` does. That is load-bearing rather than cosmetic:
/// `isRealCalendarDay` decides a key is real by formatting it back and
/// comparing, so a formatter that padded the year would quietly make
/// `0000-01-01` a real calendar day on one side of the mirror and not the other.
///
/// LOCAL, not UTC, and that is the point of having both. The day key names the
/// day the MEMBER lived; [utcDayKey] names the server's reference day. The gap
/// between them is the ±1 tolerance the whole guard is built around, so
/// collapsing the two would erase the distinction the rule depends on.
String localDayKey(DateTime at) {
  final m = at.month.toString().padLeft(2, '0');
  final d = at.day.toString().padLeft(2, '0');
  return '${at.year}-$m-$d';
}

/// [from] moved by [days] CALENDAR days — the only correct way to walk days
/// whose keys are then read with [localDayKey].
///
/// `at.add(Duration(days: n))` is NOT this. A Duration is exact elapsed time,
/// so stepping across a DST transition lands on 23:00 the previous day or
/// 01:00 the next one, and [localDayKey] then names the WRONG day. Executed
/// under `TZ=America/New_York`, a 30-day walk back from 9 Mar 2026 skipped
/// 8 March entirely, and a November month grid rendered 1 Nov twice while
/// 30 Nov was never drawn at all — a logged session on that day was invisible.
///
/// `DateTime(y, m, d + days)` normalises through the calendar (Dart handles the
/// month/year overflow) and always lands on local midnight, so every step is
/// exactly one day whatever the clocks do.
DateTime addCalendarDays(DateTime from, int days) =>
    DateTime(from.year, from.month, from.day + days);

/// A reusable day-walker anchored on one date.
///
/// [addCalendarDays] reads `.year`, `.month` and `.day` on every call, and Dart
/// derives each of those from the instant's microseconds — so walking 365 days
/// paid that conversion 1,095 times. The anchor's fields are fixed for the whole
/// walk, so they are read ONCE here and only the day component moves.
///
/// Same calendar arithmetic, same DST safety; it just stops re-deriving a
/// constant. Use it wherever a loop steps day by day.
class CalendarWalk {
  final int _year;
  final int _month;
  final int _day;

  CalendarWalk(DateTime anchor)
      : _year = anchor.year,
        _month = anchor.month,
        _day = anchor.day;

  /// The day [offset] calendar days from the anchor (negative walks back).
  DateTime operator [](int offset) => DateTime(_year, _month, _day + offset);
}

/// The newest day key that could belong to a member anywhere on earth at
/// [serverNow].
String maxPlausibleDayKey(
  DateTime serverNow, {
  int toleranceDays = kDayKeyFutureToleranceDays,
}) =>
    utcDayKey(serverNow.toUtc().add(Duration(days: toleranceDays)));

/// Whether [dateKey] could describe a real day for a real member at [serverNow].
///
/// String comparison is exact for `yyyy-MM-dd`: the format is fixed-width and
/// zero-padded, so lexicographic order IS chronological order. No parsing, and
/// therefore nothing that can introduce its own off-by-one.
///
/// THE PAST IS DELIBERATELY UNBOUNDED. An offline device replays its queue on
/// reconnect, sometimes days later, and that write describes a day the member
/// really lived — bounding the past would discard exactly the data the offline
/// queue exists to protect. Only the future is impossible.
bool isPlausibleDayKey(
  String dateKey,
  DateTime serverNow, {
  int toleranceDays = kDayKeyFutureToleranceDays,
}) {
  if (!isRealCalendarDay(dateKey)) return false;
  return dateKey.compareTo(
          maxPlausibleDayKey(serverNow, toleranceDays: toleranceDays)) <=
      0;
}

/// A LOWER BOUND on real time, learned from the server itself.
///
/// Firestore resolves `FieldValue.serverTimestamp()` on the server and returns
/// the resolved value on the next snapshot. Every instant seen that way is a
/// moment that has definitely happened — regardless of what the device clock
/// believes. Real time only moves forward from there, so the newest one is the
/// strongest bound the app can hold.
///
/// This is deliberately a LOWER bound and nothing more. It cannot prove the
/// device is correct (time passes between observations), but it can prove a day
/// key is impossible: a key more than a day beyond an instant that has already
/// occurred cannot be today.
///
/// Session-scoped on purpose — persisting it would mean trusting a stored value
/// against an untrusted clock, and a fresh session re-learns the bound on its
/// first snapshot anyway.
class ServerClockBound {
  ServerClockBound._();
  static final ServerClockBound instance = ServerClockBound._();

  DateTime? _latest;

  /// The newest server instant observed, or null before the first snapshot.
  DateTime? get latest => _latest;

  /// Records a server-resolved instant. Ignores nulls and anything older than
  /// what is already held, so the bound only ever tightens.
  void observe(DateTime? serverInstant) {
    if (serverInstant == null) return;
    final current = _latest;
    if (current == null || serverInstant.isAfter(current)) {
      _latest = serverInstant;
    }
  }

  /// Whether [dateKey] may be written, given everything the app can prove.
  ///
  /// Returns true when no server instant has been seen yet: refusing on an
  /// unknown clock would block a member's first log of a fresh install for a
  /// reason the app cannot actually substantiate. The rules remain the
  /// backstop for that window.
  bool permits(String dateKey) {
    final bound = _latest;
    if (bound == null) return true;
    return isPlausibleDayKey(dateKey, bound);
  }

  /// Test seam — a singleton that cannot be reset makes every test order-dependent.
  void resetForTest() => _latest = null;
}
