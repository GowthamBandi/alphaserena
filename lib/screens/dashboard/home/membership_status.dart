import 'package:flutter/material.dart';

/// The membership state the Home header reports, derived only from the member's
/// own `clients` document. Ordering of the checks mirrors
/// `MembershipController.isActive` so the header can never contradict the
/// boolean the rest of the app gates on.
enum MembershipState {
  /// The clients document has not arrived yet. The header shows a placeholder
  /// rather than a date, because a wrong date is worse than no date.
  loading,

  /// `membershipFrozen == true` — a deliberate coach/admin action.
  frozen,

  /// An expiry exists and is in the past.
  expired,

  /// `membershipActive != true`, or active with no expiry date at all (which
  /// `MembershipController.isActive` also treats as not active).
  inactive,

  /// The document carries no membership fields whatsoever.
  none,

  /// Active, expiring today.
  endsToday,

  /// Active, expiring within [MembershipStatus.soonDays].
  endsSoon,

  /// Active with a comfortable runway.
  active,
}

/// One line of membership truth for the header. Construct with
/// [MembershipStatus.of] so the precedence lives in exactly one place.
@immutable
class MembershipStatus {
  /// Inside this many days the line switches to the urgent treatment. Matches
  /// `MembershipController.isExpiringSoon`, which drives the expiry banner.
  static const int soonDays = 7;

  final MembershipState state;

  /// Whole days until expiry. Only meaningful for [MembershipState.endsSoon]
  /// and [MembershipState.active].
  final int daysLeft;

  /// The expiry date itself. Carried so a healthy membership can state WHEN it
  /// runs out instead of counting down to it — see [text].
  final DateTime? expiry;

  const MembershipStatus(this.state, {this.daysLeft = 0, this.expiry});

  /// Derives the state from already-extracted primitives.
  ///
  /// Takes primitives rather than the raw document so the Timestamp/ISO parsing
  /// stays in `MembershipController._parseExpiry` — one parser, not two.
  factory MembershipStatus.of({
    required bool loading,
    required bool frozen,
    required bool activeFlag,
    required bool hasRecord,
    required DateTime? expiry,
    DateTime? now,
  }) {
    if (loading) return const MembershipStatus(MembershipState.loading);

    // Frozen is checked before expiry, exactly as `isActive` evaluates it: a
    // freeze is the current administrative reality, and a stale expiry behind
    // it should not be presented as the member's actionable state.
    if (frozen) return const MembershipStatus(MembershipState.frozen);

    if (!hasRecord) return const MembershipStatus(MembershipState.none);

    final today = now ?? DateTime.now();
    if (expiry != null && !expiry.isAfter(today)) {
      return const MembershipStatus(MembershipState.expired);
    }
    // No date, or the flag is off → not active. Mirrors `isActive`, which
    // requires BOTH the flag and a future expiry.
    if (!activeFlag || expiry == null) {
      return const MembershipStatus(MembershipState.inactive);
    }

    final days = _wholeDaysBetween(today, expiry);
    if (days <= 0) return const MembershipStatus(MembershipState.endsToday);
    if (days <= soonDays) {
      return MembershipStatus(
        MembershipState.endsSoon,
        daysLeft: days,
        expiry: expiry,
      );
    }
    return MembershipStatus(
      MembershipState.active,
      daysLeft: days,
      expiry: expiry,
    );
  }

  /// Calendar days from [from] to [to], counted on date boundaries so an expiry
  /// late tomorrow reads as "1 day", not "0" from a raw duration truncation.
  static int _wholeDaysBetween(DateTime from, DateTime to) {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }

  /// The line the header renders.
  ///
  /// TWO REGISTERS, chosen by proximity — because the member's information need
  /// genuinely changes as expiry approaches:
  ///
  ///   • **Healthy** (> [soonDays]) → a DATE: *"Active until 12 Dec 2026"*.
  ///     A countdown re-states the same non-news every single morning and
  ///     manufactures low-grade urgency 142 days early. A date is a calm fact a
  ///     member can plan around, and it is what Apple, Whoop and every premium
  ///     subscription surface state. It is also SHORTER in the common case.
  ///   • **Close** (≤ [soonDays]) → a COUNTDOWN: *"Ends in 3 days"*. Here the
  ///     number IS the actionable fact, and a date would make the member do the
  ///     arithmetic themselves.
  ///
  /// The word "Membership" is dropped throughout. This line sits inside the
  /// membership card, directly under the organisation that issued it — spending
  /// the strongest word position on a noun the member already knows is exactly
  /// the padding that makes a product read as corporate rather than considered.
  String get text {
    switch (state) {
      case MembershipState.loading:
        return '';
      case MembershipState.frozen:
        return 'Paused';
      case MembershipState.expired:
        return 'Expired';
      case MembershipState.inactive:
        return 'Inactive';
      case MembershipState.none:
        return 'No membership';
      case MembershipState.endsToday:
        return 'Ends today';
      case MembershipState.endsSoon:
        return daysLeft == 1 ? 'Ends tomorrow' : 'Ends in $daysLeft days';
      case MembershipState.active:
        final e = expiry;
        // No date should be unreachable for `active` (the factory requires one),
        // but a silent fallback beats a crash in a header.
        return e == null ? 'Active' : 'Active until ${formatExpiry(e)}';
    }
  }

  /// `12 Dec 2026`. Day-first, no comma, three-letter month — the shortest form
  /// that is unambiguous across regions (a numeric 12/06 is not).
  static String formatExpiry(DateTime d) =>
      '${d.day} ${_shortMonths[d.month - 1]} ${d.year}';

  static const List<String> _shortMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// The same verdict in a form that fits a badge beside a name.
  ///
  /// [text] is written for a full-width header line and reaches
  /// *"Active until 12 Dec 2026"*, which would overflow a chip. Rather than let
  /// a second surface invent its own shorter wording — which is precisely how
  /// Profile ended up with an Active/Inactive binary that contradicted this
  /// engine — the compact register lives here too. Same states, same source,
  /// fewer characters.
  ///
  /// The two registers agree by construction: nothing here says "Active" for a
  /// state [text] calls paused, expired or absent.
  String get shortText {
    switch (state) {
      case MembershipState.loading:
        return '';
      case MembershipState.frozen:
        return 'Paused';
      case MembershipState.expired:
        return 'Expired';
      case MembershipState.inactive:
        return 'Inactive';
      case MembershipState.none:
        return 'No membership';
      case MembershipState.endsToday:
        return 'Ends today';
      case MembershipState.endsSoon:
        return daysLeft == 1 ? 'Ends tomorrow' : 'Ends in ${daysLeft}d';
      case MembershipState.active:
        return 'Active';
    }
  }

  /// Whether the line needs the attention treatment. Kept separate from colour
  /// so the header can pair it with an icon — the state is never signalled by
  /// colour alone.
  bool get isUrgent {
    switch (state) {
      case MembershipState.frozen:
      case MembershipState.expired:
      case MembershipState.inactive:
      case MembershipState.none:
      case MembershipState.endsToday:
      case MembershipState.endsSoon:
        return true;
      case MembershipState.loading:
      case MembershipState.active:
        return false;
    }
  }

  /// A glyph for the urgent states so the meaning survives without colour.
  IconData? get icon {
    switch (state) {
      case MembershipState.frozen:
        return Icons.pause_circle_outline_rounded;
      case MembershipState.expired:
      case MembershipState.inactive:
      case MembershipState.none:
        return Icons.error_outline_rounded;
      case MembershipState.endsToday:
      case MembershipState.endsSoon:
        return Icons.schedule_rounded;
      case MembershipState.loading:
      case MembershipState.active:
        return null;
    }
  }
}
