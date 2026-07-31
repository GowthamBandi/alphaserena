/// The app's legal + support endpoints, in ONE place.
///
/// Google Play's *Data safety / account deletion* policy and Apple's App Store
/// Review Guideline 5.1.1(v) both require an app that lets a user create an
/// account to publish a reachable Privacy Policy and to offer an in-app route to
/// delete that account. The login screen already states that continuing accepts
/// these documents — as plain, untappable grey text — while nothing anywhere in
/// the app could open them.
///
/// **Deliberately unset.** No brand URL exists anywhere in this repository, and
/// inventing one would ship a link that resolves to nothing — the exact class of
/// fabrication this foundation removes. Every consumer below is gated on
/// [hasTerms] / [hasPrivacyPolicy], so while these are empty the corresponding
/// rows simply do not render: the app makes no promise it cannot keep.
///
/// **To finish store compliance,** set the two constants here. Nothing else in
/// the codebase needs to change — the Profile rows appear on their own.
class AppLegal {
  AppLegal._();

  /// Public Terms of Service URL. Empty → the Terms row is not rendered.
  static const String termsUrl = '';

  /// Public Privacy Policy URL. Empty → the Privacy Policy row is not rendered.
  ///
  /// This one is a hard store requirement: Play Console will not accept a
  /// production release of an app with accounts without it.
  static const String privacyPolicyUrl = '';

  /// Optional public account-deletion page. Play additionally accepts (and for
  /// web-initiated deletion requires) a URL where a user can request deletion
  /// without installing the app. The in-app flow is implemented regardless.
  static const String accountDeletionUrl = '';

  static bool get hasTerms => termsUrl.trim().isNotEmpty;
  static bool get hasPrivacyPolicy => privacyPolicyUrl.trim().isNotEmpty;
  static bool get hasAccountDeletionPage =>
      accountDeletionUrl.trim().isNotEmpty;

  /// Whether ANY legal link can be shown. False → Profile omits the whole legal
  /// group rather than rendering an empty card.
  static bool get hasAny => hasTerms || hasPrivacyPolicy;
}
