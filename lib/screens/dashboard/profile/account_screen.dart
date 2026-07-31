import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../controllers/auth_controller.dart';
import '../../../core/constants/app_legal.dart';
import '../../../core/services/account_deletion_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_text.dart';

/// Account & legal — the production-store foundation.
///
/// Everything here was missing entirely. The login screen states that continuing
/// accepts the Terms of Service and Privacy Policy, as untappable grey text, and
/// no screen in the app could open either document. There was no account
/// deletion anywhere in the codebase — a hard blocker under Google Play's
/// account-deletion policy and Apple's Guideline 5.1.1(v), both of which require
/// an in-app deletion route for any app that lets a user create an account. And
/// there was no version string, which makes a support report untriageable.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  String _version = '';
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  /// The REAL version from the platform bundle, never a hardcoded literal that
  /// would drift from the shipped binary at the first release.
  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = '${info.version} (${info.buildNumber})');
    } catch (_) {
      // Unknown stays unknown — the row reports that rather than guessing.
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {
      // Fall through to the honest failure below.
    }
    Get.snackbar('Could not open', 'Please try again in a moment.');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        elevation: 0,
        iconTheme: IconThemeData(color: p.textPrimary),
        title: Text(
          'Account & legal',
          style: AppText.title(size: 17).copyWith(color: p.textPrimary),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            // Legal links render ONLY when a URL is actually configured
            // (`AppLegal`). An unset URL means the row is absent rather than
            // present-and-broken: a link that resolves to nothing is the same
            // class of untruth as a fabricated name.
            if (AppLegal.hasAny) ...[
              _sectionLabel(p, 'Legal'),
              const SizedBox(height: 8),
              _card(p, [
                if (AppLegal.hasTerms)
                  _row(
                    p,
                    Icons.description_outlined,
                    'Terms of Service',
                    onTap: () => _open(AppLegal.termsUrl),
                  ),
                if (AppLegal.hasTerms && AppLegal.hasPrivacyPolicy) _divider(p),
                if (AppLegal.hasPrivacyPolicy)
                  _row(
                    p,
                    Icons.privacy_tip_outlined,
                    'Privacy Policy',
                    onTap: () => _open(AppLegal.privacyPolicyUrl),
                  ),
              ]),
              const SizedBox(height: 18),
            ],

            _sectionLabel(p, 'About'),
            const SizedBox(height: 8),
            _card(p, [
              _row(
                p,
                Icons.info_outline,
                'App version',
                trailing: _version.isEmpty ? 'Unknown' : _version,
              ),
              _divider(p),
              _row(
                p,
                Icons.article_outlined,
                'Open source licences',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'AlphaSerena',
                  applicationVersion: _version,
                ),
              ),
            ]),

            const SizedBox(height: 18),
            _sectionLabel(p, 'Your account'),
            const SizedBox(height: 8),
            _card(p, [
              _row(
                p,
                Icons.delete_outline,
                'Delete account',
                subtitle: 'Permanently delete your profile and sign-in',
                destructive: true,
                onTap: _deleting ? null : _confirmDelete,
              ),
            ]),
            const SizedBox(height: 12),
            Text(
              'Deleting your account removes your profile and your sign-in from '
              'AlphaSerena. It cannot be undone.',
              style: GoogleFonts.poppins(
                color: p.textMuted,
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Deletion ─────────────────────────────────────────────────────────

  Future<void> _confirmDelete() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _DeleteAccountSheet(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);

    final auth = Get.find<AuthController>();
    // Suppress the revoked-session sentinel BEFORE the auth user disappears, so
    // a deliberate deletion is never reported as "Your session ended".
    auth.beginAccountDeletion();

    final result = await AccountDeletionService().deleteAccount();

    if (!mounted) return;
    setState(() => _deleting = false);

    switch (result) {
      case AccountDeletionResult.deleted:
        await auth.finishAccountDeletion();
        Get.snackbar(
          'Account deleted',
          'Your profile and sign-in have been removed.',
          snackPosition: SnackPosition.BOTTOM,
        );
      case AccountDeletionResult.needsRecentLogin:
        // Firebase requires a fresh credential. Say exactly that, and exactly
        // what to do — never a generic failure for a recoverable condition.
        Get.snackbar(
          'Please sign in again',
          'For your security, sign out and sign back in, then delete your '
              'account. Nothing has been deleted.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 6),
        );
      case AccountDeletionResult.failed:
        Get.snackbar(
          'Could not delete your account',
          'Check your connection and try again. Nothing has been deleted.',
          snackPosition: SnackPosition.BOTTOM,
        );
    }
  }

  // ── Small shared widgets ─────────────────────────────────────────────

  Widget _sectionLabel(AppPalette p, String text) => Text(
    text.toUpperCase(),
    style: GoogleFonts.poppins(
      color: p.textMuted,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    ),
  );

  Widget _card(AppPalette p, List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: p.surface,
      borderRadius: AppRadii.cardR,
      border: Border.all(color: p.border),
    ),
    child: Column(children: children),
  );

  Widget _divider(AppPalette p) =>
      Divider(color: p.border, height: 1, indent: 14, endIndent: 14);

  Widget _row(
    AppPalette p,
    IconData icon,
    String title, {
    String? subtitle,
    String? trailing,
    bool destructive = false,
    VoidCallback? onTap,
  }) {
    final fg = destructive ? p.error : p.textPrimary;
    return Semantics(
      button: onTap != null,
      label: title,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: destructive ? p.error : p.textMuted, size: 18),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        color: fg,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.poppins(
                          color: p.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                Text(
                  trailing,
                  style: GoogleFonts.poppins(
                    color: p.textMuted,
                    fontSize: 12.5,
                  ),
                )
              else if (onTap != null)
                Icon(Icons.chevron_right, color: p.textMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// The deletion confirmation.
///
/// It states BOTH halves of the truth before the member can proceed: what is
/// actually deleted, and what their organization keeps. Presenting only the
/// first half would promise an erasure the client cannot perform and the
/// organization is not obliged to make — the coach's client record, membership
/// and payment history are their business records.
///
/// The acknowledgement checkbox exists so the second half cannot be skipped past.
class _DeleteAccountSheet extends StatefulWidget {
  const _DeleteAccountSheet();

  @override
  State<_DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<_DeleteAccountSheet> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: p.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Delete your account?',
              style: AppText.title(size: 18).copyWith(color: p.textPrimary),
            ),
            const SizedBox(height: 12),
            _block(
              p,
              Icons.delete_outline,
              p.error,
              'What is deleted',
              'Your AlphaSerena profile — your name, photo, date of birth, '
                  'contact details, body measurements and notification '
                  'settings — and your sign-in. This cannot be undone.',
            ),
            const SizedBox(height: 10),
            _block(
              p,
              Icons.business_outlined,
              p.textMuted,
              'What your organization keeps',
              AccountDeletionService.retentionNotice(
                AccountDeletionService.orgName,
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => setState(() => _acknowledged = !_acknowledged),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _acknowledged,
                    activeColor: p.accent,
                    onChanged: (v) =>
                        setState(() => _acknowledged = v ?? false),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'I understand my account will be permanently deleted '
                        'and that my coaching record stays with my '
                        'organization.',
                        style: GoogleFonts.poppins(
                          color: p.textSecondary,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _acknowledged
                    ? () => Navigator.of(context).pop(true)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: p.error,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: p.error.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'Delete my account',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.poppins(color: p.textMuted, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _block(
    AppPalette p,
    IconData icon,
    Color iconColor,
    String title,
    String body,
  ) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: AppRadii.smR,
        border: Border.all(color: p.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 17),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: p.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: GoogleFonts.poppins(
                    color: p.textMuted,
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
