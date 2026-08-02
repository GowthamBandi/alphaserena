import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../controllers/member_controller.dart';
import '../../../core/domain/member_profile.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_text.dart';
import 'edit_profile_screen.dart';

/// "What your coach can see" — the member-facing disclosure of the UMHIPP
/// privacy projection.
///
/// **Why this screen exists.** The privacy engine has been live in production
/// since P3: on every write to `clientProfiles/{uid}`, the `onClientProfileWritten`
/// Cloud Function computes `coachProjection(...)` and stamps the coach-visible
/// sections onto `clients/{id}.sharedProfile`. The policy — tiers, the member
/// clamp, fail-closed defaults — is implemented and unit-tested. What never
/// existed was any surface where the member could SEE it. Identity Setup told
/// them "only what you choose to share is visible to your coach" while every
/// section was being shared on its default visibility and no choice had ever
/// been offered.
///
/// **Why it is read-only, deliberately.** Every state below is computed by
/// calling [coachProjection] — the same pure function the Cloud Function calls —
/// so this screen cannot drift from what is actually shared. Write controls
/// (per-section tighten-to-private) are intentionally NOT here: the coach app
/// does not yet read `sharedProfile` (UMHIPP P4), so a toggle would change a
/// stored value while changing nothing the member could observe. A control that
/// appears to do something and does nothing is worse than an honest statement of
/// fact. The toggles land with P4.
class PrivacyVisibilityScreen extends StatelessWidget {
  const PrivacyVisibilityScreen({super.key});

  /// Sections this app can actually write today (via `MemberIdentityService`).
  /// A section is listed below when it is writable OR already present in the
  /// member's document — never merely because it exists in the registry. That
  /// keeps the screen a statement about THIS member's real data instead of a
  /// preview of unbuilt features, and it grows on its own as later phases add
  /// writers.
  static const Set<String> _writableToday = {
    'identity',
    'contact',
    'bodyMetrics',
    'preferences',
  };

  /// Human labels for the canonical section keys. Presentation only — the
  /// authority on which sections exist, and who may see them, is
  /// `kMemberSections`.
  static const Map<String, (String, String)> _labels = {
    'identity': ('About you', 'Your name, photo, gender and date of birth'),
    'contact': ('Contact details', 'Your phone number and email'),
    'bodyMetrics': ('Height & weight', 'Your current height and weight'),
    'bodyMeasurements': (
      'Body measurements',
      'Chest, waist, hips, arms and thighs',
    ),
    'fitness': ('Training background', 'Your experience and activity level'),
    'goals': ('Your goals', 'What you are training towards'),
    'lifestyle': ('Lifestyle', 'Sleep, work pattern and daily activity'),
    'nutrition': ('Nutrition preferences', 'Diet type, allergies and dislikes'),
    'medical': ('Medical information', 'Conditions, medication and injuries'),
    'documents': ('Documents', 'Files you have uploaded'),
    'emergencyContact': ('Emergency contact', 'Who to reach in an emergency'),
    'preferences': ('App preferences', 'Notifications, units and appearance'),
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final member = Get.find<MemberController>();

    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        elevation: 0,
        iconTheme: IconThemeData(color: p.textPrimary),
        title: Text(
          'What your coach can see',
          style: AppText.title(size: 17).copyWith(color: p.textPrimary),
        ),
      ),
      body: SafeArea(
        child: Obx(() {
          final profile = MemberProfile.fromMap(member.profile.value);

          // THE SAME CALL THE CLOUD FUNCTION MAKES. Not a re-derivation, not an
          // approximation — the identical pure function over the identical
          // inputs, so this screen and the projection can never disagree.
          final shared = coachProjection(profile.sections, profile.privacy);

          final keys = <String>[
            for (final s in kMemberSections)
              if (s.owner == EditableBy.member &&
                  (_writableToday.contains(s.key) || profile.has(s.key)))
                s.key,
          ];

          final sharedKeys = keys.where(shared.containsKey).toList();
          final privateKeys = keys
              .where((k) => !shared.containsKey(k) && profile.has(k))
              .toList();
          final emptyKeys = keys.where((k) => !profile.has(k)).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            children: [
              _intro(p, sharedKeys.length),
              if (sharedKeys.isNotEmpty) ...[
                const SizedBox(height: 20),
                _sectionLabel(p, 'Shared with your coach'),
                const SizedBox(height: 8),
                _card(p, [
                  for (var i = 0; i < sharedKeys.length; i++) ...[
                    if (i > 0) _divider(p),
                    _row(p, sharedKeys[i], _RowState.shared),
                  ],
                ]),
              ],
              if (privateKeys.isNotEmpty) ...[
                const SizedBox(height: 18),
                _sectionLabel(p, 'Only you'),
                const SizedBox(height: 8),
                _card(p, [
                  for (var i = 0; i < privateKeys.length; i++) ...[
                    if (i > 0) _divider(p),
                    _row(p, privateKeys[i], _RowState.private),
                  ],
                ]),
              ],
              if (emptyKeys.isNotEmpty) ...[
                const SizedBox(height: 18),
                _sectionLabel(p, 'Not added yet'),
                const SizedBox(height: 8),
                _card(p, [
                  for (var i = 0; i < emptyKeys.length; i++) ...[
                    if (i > 0) _divider(p),
                    _row(p, emptyKeys[i], _RowState.empty),
                  ],
                ]),
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    // ONE maintenance editor. This used to open the onboarding
                    // wizard in an "edit" mode, which authored the same
                    // document with a different gender vocabulary, different
                    // bounds and a different set of fields — two owners for
                    // every value on it. The wizard is now first-run only.
                    onPressed: () => Get.to(() => const EditProfileScreen()),
                    child: Text(
                      'Add your details',
                      style: GoogleFonts.poppins(
                        color: p.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              _orgRecordNote(p, member.orgName),
            ],
          );
        }),
      ),
    );
  }

  Widget _intro(AppPalette p, int sharedCount) {
    final text = sharedCount == 0
        ? 'You have not added any details yet, so nothing from your profile is '
              'shared with your coach.'
        : 'Your coach can see the $sharedCount ${sharedCount == 1 ? 'item' : 'items'} '
              'below, and nothing else from your profile. Nobody outside your '
              'organization can see any of it.';
    return Text(
      text,
      style: GoogleFonts.poppins(color: p.textMuted, fontSize: 12.5, height: 1.45),
    );
  }

  /// The honest other half. A privacy screen that showed only the member's own
  /// sections would imply the member controls everything their coach knows about
  /// them. They do not: the organization independently authors `clients/{id}` —
  /// the name and contact details they typed, the membership, their coaching
  /// notes and targets — and the member can neither edit nor hide that record.
  /// Saying so is the difference between a privacy feature and privacy theatre,
  /// and it is the honest replacement for the old Profile row that told members
  /// to "edit it via your coach".
  Widget _orgRecordNote(AppPalette p, String orgName) {
    final who = orgName.isNotEmpty ? orgName : 'Your organization';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.business_outlined, color: p.textMuted, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What $who holds',
                  style: GoogleFonts.poppins(
                    color: p.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Separately from your profile, your coach keeps their own '
                  'business record of you as their client — the details they '
                  'entered when they added you, your membership and payments, '
                  'and their own coaching notes. That record belongs to them, '
                  'not to your profile. Ask your coach to correct anything '
                  'that is wrong.',
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

  Widget _row(AppPalette p, String key, _RowState state) {
    final label = _labels[key] ?? (key, '');
    final (chipText, chipColor, icon) = switch (state) {
      _RowState.shared => ('Shared', p.accent, Icons.visibility_outlined),
      _RowState.private => ('Only you', p.textMuted, Icons.lock_outline),
      _RowState.empty => ('Not added', p.textMuted, Icons.remove_circle_outline),
    };

    return Semantics(
      label: '${label.$1}. $chipText.',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Icon AND text carry the state — never colour alone.
            Icon(icon, color: chipColor, size: 18),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.$1,
                    style: GoogleFonts.poppins(
                      color: p.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (label.$2.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      label.$2,
                      style: GoogleFonts.poppins(
                        color: p.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              chipText,
              style: GoogleFonts.poppins(
                color: chipColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _RowState { shared, private, empty }
