import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/discover_controller.dart';
import '../../core/models/organization_profile_model.dart';
import 'coach_storefront_screen.dart';
import 'discover_models.dart';

/// Organizations Discovery — the member browses published fitness organizations
/// and opens one to subscribe. (Pre-membership gate.)
class JoinCoachScreen extends StatefulWidget {
  const JoinCoachScreen({super.key});

  @override
  State<JoinCoachScreen> createState() => _JoinCoachScreenState();
}

class _JoinCoachScreenState extends State<JoinCoachScreen> {
  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _card = Color(0xFF141414);
  static const Color _muted = Color(0xFF8E8E8E);
  static const Color _red = Color(0xFFE10600);

  late final DiscoverController _c;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _c = Get.put(DiscoverController());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _open(OrganizationProfileModel o) =>
      Get.to(() => CoachStorefrontScreen(org: DiscoverOrg.fromProfile(o)));

  // ── Filter helpers ───────────────────────────────────────────────────────────

  void _clearAll() {
    _search.clear();
    _c.clearFilters();
  }

  void _showFilterSheet(
    String title,
    List<String> options,
    Rxn<String> active,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                title,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
            ),
            if (options.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No options available',
                  style: GoogleFonts.poppins(color: _muted, fontSize: 13),
                ),
              )
            else
              ...options.map(
                (opt) => ListTile(
                  title: Text(opt,
                      style: GoogleFonts.poppins(color: Colors.white)),
                  trailing: active.value == opt
                      ? const Icon(Icons.check, color: _red)
                      : null,
                  onTap: () {
                    active.value = active.value == opt ? null : opt;
                    Get.back();
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Code entry sheet (+ FAB) ─────────────────────────────────────────────────

  void _showCodeSheet() {
    final codeCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          left: 20,
          right: 20,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter Coach Code',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Enter the unique handle shared by your coach.',
              style: GoogleFonts.poppins(color: _muted, fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2C2C2C)),
              ),
              child: TextField(
                controller: codeCtrl,
                style:
                    GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'e.g. ALPHA123',
                  hintStyle:
                      GoogleFonts.poppins(color: _muted, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _red,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                  final code = codeCtrl.text.trim();
                  if (code.isEmpty) return;
                  Navigator.of(ctx).pop();
                  final org = await _c.lookupByHandle(code);
                  if (org != null) {
                    Get.to(() => CoachStorefrontScreen(
                        org: DiscoverOrg.fromProfile(org)));
                  } else {
                    Get.snackbar(
                        'Not found', 'No organization found for that code.');
                  }
                },
                child: Text(
                  'Find',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(() => codeCtrl.dispose());
  }

  // ── Sign-out menu ────────────────────────────────────────────────────────────

  void _menu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.logout, color: _red),
              title: Text('Sign out',
                  style: GoogleFonts.poppins(color: Colors.white)),
              onTap: () {
                Get.back();
                Get.find<AuthController>().signOut();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: Obx(() {
                final loading = _c.isLoading.value;
                final hasError = _c.error.value.isNotEmpty;
                final noOrgsAtAll =
                    !loading && !hasError && _c.all.isEmpty;
                final noMatches = !loading &&
                    !hasError &&
                    _c.all.isNotEmpty &&
                    _c.visible.isEmpty;

                return Column(
                  children: [
                    // ── Fixed header section ─────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _header(),
                          const SizedBox(height: 16),
                          _searchBar(),
                          const SizedBox(height: 14),
                          _filters(),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),

                    // ── Flexible body ────────────────────────────────────
                    Expanded(
                      child: loading
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFFE10600)),
                            )
                          : hasError
                              ? _errorState()
                              : noOrgsAtAll
                                  ? _emptyNoOrgs()
                                  : noMatches
                                      ? _emptyNoMatches()
                                      : _populatedList(),
                    ),
                  ],
                );
              }),
            ),
            _bottomNav(),
          ],
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────────

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome,',
                  style: GoogleFonts.poppins(color: _muted, fontSize: 13)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    _c.memberName.value,
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  const Text('👋', style: TextStyle(fontSize: 18)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Find the best fitness organizations\nand start your transformation.',
                style: GoogleFonts.poppins(
                    color: _muted, fontSize: 12.5, height: 1.35),
              ),
            ],
          ),
        ),
        // Bell — plain inert icon (no fake badge)
        _circleIcon(Icons.notifications_none_rounded),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _menu,
          child: _circleIcon(Icons.menu_rounded),
        ),
      ],
    );
  }

  Widget _circleIcon(IconData icon) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: _card,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }

  // ── Search bar ───────────────────────────────────────────────────────────────

  Widget _searchBar() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF222222)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.search, color: _muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (v) => _c.query.value = v,
              style:
                  GoogleFonts.poppins(color: Colors.white, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Search organization, coach, or specialty...',
                hintStyle:
                    GoogleFonts.poppins(color: _muted, fontSize: 13),
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  // ── Filters row ──────────────────────────────────────────────────────────────

  Widget _filters() {
    final noFilters = _c.locationFilter.value == null &&
        _c.specializationFilter.value == null &&
        _c.query.value.isEmpty;

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // "All" — active when no filters are set
          _filterChip(
            'All',
            active: noFilters,
            icon: Icons.tune,
            onTap: _clearAll,
          ),
          // Location filter
          _filterChip(
            _c.locationFilter.value ?? 'Location',
            active: _c.locationFilter.value != null,
            dropdown: true,
            onTap: () => _showFilterSheet(
                'Location', _c.locations, _c.locationFilter),
          ),
          // Specialization filter (Gender removed per brief)
          _filterChip(
            _c.specializationFilter.value ?? 'Specialization',
            active: _c.specializationFilter.value != null,
            dropdown: true,
            onTap: () => _showFilterSheet(
                'Specialization', _c.specializations, _c.specializationFilter),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
    String label, {
    bool active = false,
    bool dropdown = false,
    IconData? icon,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? _red : _card,
          borderRadius: BorderRadius.circular(11),
          border:
              Border.all(color: active ? _red : const Color(0xFF242424)),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 15),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight:
                      active ? FontWeight.w600 : FontWeight.w500),
            ),
            if (dropdown) ...[
              const SizedBox(width: 2),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  color: _muted, size: 18),
            ],
          ],
        ),
      ),
    );
  }

  // ── State widgets ────────────────────────────────────────────────────────────

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: _muted, size: 48),
            const SizedBox(height: 16),
            Text(
              _c.error.value,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: _muted, fontSize: 13.5),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _red,
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _c.load(),
              child: Text(
                'Retry',
                style: GoogleFonts.poppins(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyNoOrgs() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_outline, color: _muted, size: 48),
            const SizedBox(height: 16),
            Text(
              'No organizations yet',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              "Check back soon or enter a coach's code.",
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: _muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyNoMatches() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, color: _muted, size: 48),
            const SizedBox(height: 16),
            Text(
              'No matches',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search or filters.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: _muted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: _clearAll,
              child: Text(
                'Clear filters',
                style: GoogleFonts.poppins(
                    color: _red, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _populatedList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      children: [
        Row(
          children: [
            const Text('🔥', style: TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
            Text(
              'Top Rated Organizations',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ..._c.visible.map(_orgCard),
        const SizedBox(height: 6),
        _verifiedBanner(),
      ],
    );
  }

  // ── Org card ─────────────────────────────────────────────────────────────────

  Widget _orgCard(OrganizationProfileModel o) {
    final imageUrl = o.coverImageUrl ?? o.logoUrl;
    final locationText =
        '${o.city ?? ''}${o.city != null && o.state != null ? ', ' : ''}${o.state ?? ''}';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cover / logo image with placeholder fallback
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: imageUrl != null && imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          width: 92,
                          height: 118,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, prog) =>
                              prog == null ? child : _imagePlaceholder(),
                          errorBuilder: (_, __, ___) => _imagePlaceholder(),
                        )
                      : _imagePlaceholder(),
                ),
                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Verified badge — conditional
                      if (o.verified)
                        Row(
                          children: [
                            const Icon(Icons.verified,
                                color: _red, size: 13),
                            const SizedBox(width: 4),
                            Text(
                              'Verified',
                              style: GoogleFonts.poppins(
                                  color: _red,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      const SizedBox(height: 2),

                      // Name
                      Padding(
                        padding: const EdgeInsets.only(right: 26),
                        child: Text(
                          o.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700),
                        ),
                      ),

                      // Tagline — conditional
                      if (o.tagline != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          o.tagline!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              color: _muted, fontSize: 12),
                        ),
                      ],

                      // Location — conditional
                      if (orgLocation(o).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.location_on,
                                color: _muted, size: 13),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                locationText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                    color: _muted, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],

                      // Clients stat — conditional (no fake avatar stack)
                      if (o.statClientsTrained != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${o.statClientsTrained} Clients',
                          style: GoogleFonts.poppins(
                              color: _muted, fontSize: 11.5),
                        ),
                      ],

                      // Rating pill — conditional
                      if (o.hasRating) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color:
                                Colors.amber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded,
                                  color: Colors.amber, size: 13),
                              const SizedBox(width: 4),
                              Text(
                                '${o.rating.toStringAsFixed(1)} (${o.reviewCount})',
                                style: GoogleFonts.poppins(
                                    color: Colors.amber,
                                    fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Specialization chips
                      if (o.specializations.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: o.specializations
                              .map(_tagChip)
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Navigate button (bottom-right)
          Positioned(
            right: 12,
            bottom: 14,
            child: GestureDetector(
              onTap: () => _open(o),
              child: Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                    color: _red, shape: BoxShape.circle),
                child: const Icon(Icons.chevron_right_rounded,
                    color: Colors.white, size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      width: 92,
      height: 118,
      color: const Color(0xFF1E1E1E),
      child: const Icon(Icons.fitness_center, color: _muted, size: 32),
    );
  }

  Widget _tagChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
            color: const Color(0xFFB0B0B0), fontSize: 10.5),
      ),
    );
  }

  // ── Trust footer ─────────────────────────────────────────────────────────────

  Widget _verifiedBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _red.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _red.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _red.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.workspace_premium, color: _red, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'All organizations are verified and trusted',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your fitness journey is safe with us.',
                  style:
                      GoogleFonts.poppins(color: _muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: _muted, size: 20),
        ],
      ),
    );
  }

  // ── Bottom navigation ────────────────────────────────────────────────────────

  Widget _bottomNav() {
    return Container(
      padding:
          const EdgeInsets.only(top: 8, bottom: 18, left: 8, right: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        border: Border(top: BorderSide(color: Color(0xFF1E1E1E))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _navItem(Icons.search, 'Discover', active: true),
          _navItem(Icons.calendar_today_outlined, 'My Plans'),
          _navFab(),
          _navItem(Icons.chat_bubble_outline, 'Messages'),
          _navItem(Icons.person_outline, 'Profile'),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, {bool active = false}) {
    final color = active ? _red : _muted;
    return GestureDetector(
      onTap: active
          ? null
          : () => Get.snackbar(
              'Coming up', 'Join an organization to unlock $label.'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
                color: color,
                fontSize: 11,
                fontWeight:
                    active ? FontWeight.w600 : FontWeight.w400),
          ),
        ],
      ),
    );
  }

  Widget _navFab() {
    return GestureDetector(
      onTap: _showCodeSheet,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: _red,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: _red.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 6)),
          ],
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }
}
