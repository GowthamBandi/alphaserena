import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/discover_controller.dart';
import '../../core/models/organization_profile_model.dart';
import 'coach_storefront_screen.dart';

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
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _c = Get.put(DiscoverController());
    _searchFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    if (Get.isRegistered<DiscoverController>()) {
      Get.delete<DiscoverController>();
    }
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _open(OrganizationProfileModel o) =>
      Get.to(() => CoachStorefrontScreen(org: o));

  // ── Filter helpers ───────────────────────────────────────────────────────────

  void _clearAll() {
    _search.clear();
    _c.clearFilters();
  }

  /// Dropdown anchored just below the tapped filter [anchor] chip. Single-select;
  /// tapping the active value again clears it.
  Future<void> _showFilterDropdown(
    BuildContext anchor,
    List<String> options,
    Rxn<String> active,
  ) async {
    final box = anchor.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(anchor).context.findRenderObject() as RenderBox?;
    if (box == null || overlayBox == null) return;

    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset(0, box.size.height + 6), ancestor: overlayBox),
        box.localToGlobal(
          box.size.bottomRight(Offset.zero),
          ancestor: overlayBox,
        ),
      ),
      Offset.zero & overlayBox.size,
    );

    final selected = await showMenu<String>(
      context: anchor,
      position: position,
      color: _card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF2A2A2A)),
      ),
      constraints: const BoxConstraints(minWidth: 180, maxHeight: 340),
      items: options.isEmpty
          ? [
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  'No options available',
                  style: GoogleFonts.poppins(color: _muted, fontSize: 13),
                ),
              ),
            ]
          : [
              for (final opt in options)
                PopupMenuItem<String>(
                  value: opt,
                  height: 44,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          opt,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      if (active.value == opt)
                        const Icon(Icons.check, color: _red, size: 18),
                    ],
                  ),
                ),
            ],
    );

    if (selected != null) {
      active.value = active.value == selected ? null : selected;
    }
  }

  // ── Code entry sheet (+ FAB) ─────────────────────────────────────────────────

  void _showCodeSheet() {
    final codeCtrl = TextEditingController();
    // Sheet-local state so the lookup shows a spinner + inline error without
    // closing the sheet first (the old version popped, then awaited blind).
    bool busy = false;
    String? errorText;

    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> find() async {
            final code = codeCtrl.text.trim();
            if (code.isEmpty || busy) return;
            FocusScope.of(ctx).unfocus();
            setSheet(() {
              busy = true;
              errorText = null;
            });
            try {
              final org = await _c.lookupByHandle(code);
              if (org == null) {
                setSheet(() {
                  busy = false;
                  errorText = 'No organization found for that code.';
                });
                return;
              }
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              Get.to(() => CoachStorefrontScreen(org: org));
            } catch (_) {
              setSheet(() {
                busy = false;
                errorText = "Couldn't check that code. Please try again.";
              });
            }
          }

          return Padding(
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
                    fontWeight: FontWeight.w700,
                  ),
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
                    border: Border.all(
                      color: errorText != null ? _red : const Color(0xFF2C2C2C),
                    ),
                  ),
                  child: TextField(
                    controller: codeCtrl,
                    enabled: !busy,
                    autofocus: true,
                    onSubmitted: (_) => find(),
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'e.g. ALPHA123',
                      hintStyle: GoogleFonts.poppins(
                        color: _muted,
                        fontSize: 13,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.error_outline, color: _red, size: 15),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          errorText!,
                          style: GoogleFonts.poppins(color: _red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _red,
                      disabledBackgroundColor: _red.withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: busy ? null : find,
                    child: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.4,
                            ),
                          )
                        : Text(
                            'Find',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() => codeCtrl.dispose());
  }

  // ── Sign-out menu ────────────────────────────────────────────────────────────

  void _menu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.logout, color: _red),
              title: Text(
                'Sign out',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
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
        child: Obx(() {
          final loading = _c.isLoading.value;
          final hasError = _c.error.value.isNotEmpty;
          final noOrgsAtAll = !loading && !hasError && _c.all.isEmpty;
          final noMatches =
              !loading && !hasError && _c.all.isNotEmpty && _c.visible.isEmpty;

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
                    ? _skeletonList()
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
              // No name known → the greeting stands alone rather than being
              // completed with an invented one.
              if (_c.memberName.value.isNotEmpty) ...[
                Text(
                  'Welcome,',
                  style: GoogleFonts.poppins(color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _c.memberName.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('👋', style: TextStyle(fontSize: 18)),
                  ],
                ),
              ] else
                Row(
                  children: [
                    Text(
                      'Welcome',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('👋', style: TextStyle(fontSize: 18)),
                  ],
                ),
              const SizedBox(height: 6),
              Text(
                'Find the best fitness organizations\nand start your transformation.',
                style: GoogleFonts.poppins(
                  color: _muted,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        // Enter a coach's code (replaces the old inert bell)
        Semantics(
          button: true,
          label: 'Enter coach code',
          child: GestureDetector(
            onTap: _showCodeSheet,
            child: _circleIcon(Icons.vpn_key_outlined),
          ),
        ),
        const SizedBox(width: 10),
        Semantics(
          button: true,
          label: 'Menu',
          child: GestureDetector(
            onTap: _menu,
            child: _circleIcon(Icons.menu_rounded),
          ),
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
    final focused = _searchFocus.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 50,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: focused ? _red : const Color(0xFF222222),
          width: focused ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(Icons.search, color: focused ? _red : _muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              cursorColor: _red,
              textInputAction: TextInputAction.search,
              onChanged: (v) => _c.query.value = v,
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Search organization, coach, or specialty...',
                hintStyle: GoogleFonts.poppins(color: _muted, fontSize: 13),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isCollapsed: true,
              ),
            ),
          ),
          // In-field clear (standard search affordance) — one tap instead of
          // select-all + delete. Only visible while there is a query.
          if (_c.query.value.isNotEmpty)
            IconButton(
              tooltip: 'Clear search',
              onPressed: () {
                _search.clear();
                _c.query.value = '';
              },
              icon: const Icon(Icons.close_rounded, color: _muted, size: 18),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }

  // ── Filters row ──────────────────────────────────────────────────────────────

  Widget _filters() {
    final noFilters =
        _c.locationFilter.value == null &&
        _c.specializationFilter.value == null &&
        _c.languageFilter.value == null &&
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
            onTap: (_) => _clearAll(),
          ),
          // Language filter
          _filterChip(
            _c.languageFilter.value ?? 'Language',
            active: _c.languageFilter.value != null,
            dropdown: true,
            onTap: (ctx) =>
                _showFilterDropdown(ctx, _c.languages, _c.languageFilter),
          ),
          // Location filter
          _filterChip(
            _c.locationFilter.value ?? 'Location',
            active: _c.locationFilter.value != null,
            dropdown: true,
            onTap: (ctx) =>
                _showFilterDropdown(ctx, _c.locations, _c.locationFilter),
          ),
          // Specialization filter (Gender removed per brief)
          _filterChip(
            _c.specializationFilter.value ?? 'Specialization',
            active: _c.specializationFilter.value != null,
            dropdown: true,
            onTap: (ctx) => _showFilterDropdown(
              ctx,
              _c.specializations,
              _c.specializationFilter,
            ),
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
    void Function(BuildContext)? onTap,
  }) {
    // Builder gives each chip its own context so the dropdown anchors to it.
    return Builder(
      builder: (ctx) => GestureDetector(
        onTap: onTap == null ? null : () => onTap(ctx),
        child: Container(
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? _red : _card,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: active ? _red : const Color(0xFF242424)),
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
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (dropdown) ...[
                const SizedBox(width: 2),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: _muted,
                  size: 18,
                ),
              ],
            ],
          ),
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
                  horizontal: 28,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => _c.load(),
              child: Text(
                'Retry',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
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
                fontWeight: FontWeight.w600,
              ),
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
                fontWeight: FontWeight.w600,
              ),
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
                  color: _red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Lightweight placeholder rows matching the real card geometry, so the list
  /// doesn't jump when data lands (skeleton > spinner for perceived speed).
  Widget _skeletonList() {
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      itemCount: 6,
      itemBuilder: (_, _) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1E1E1E)),
        ),
        child: Row(
          children: [
            bar(52, 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(140, 14),
                  const SizedBox(height: 8),
                  bar(90, 11),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _populatedList() {
    return RefreshIndicator(
      color: _red,
      backgroundColor: _card,
      onRefresh: _c.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ..._c.visible.map(_orgCard),
          const SizedBox(height: 6),
          _verifiedBanner(),
        ],
      ),
    );
  }

  // ── Org card ─────────────────────────────────────────────────────────────────

  /// Compact, scalable list row — one organization. Whole row tappable.
  /// Designed to stay clean with hundreds of entries (rich detail lives on the
  /// storefront). Shows: logo · name (+verified) · "specialization · city" ·
  /// rating · chevron.
  Widget _orgCard(OrganizationProfileModel o) {
    final imageUrl = o.coverImageUrl ?? o.logoUrl;
    final subtitle = <String>[
      if (o.specializations.isNotEmpty) o.specializations.first,
      if (orgLocation(o).isNotEmpty) orgLocation(o),
    ].join('  ·  ');

    return Semantics(
      button: true,
      label:
          '${o.name}${o.verified ? ', verified' : ''}'
          '${o.hasRating ? ', rated ${o.rating.toStringAsFixed(1)}' : ''}',
      child: GestureDetector(
        onTap: () => _open(o),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E1E1E)),
          ),
          child: Row(
            children: [
              // Logo / cover thumbnail with placeholder fallback
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                // Disk+memory cached: scrolling back up (or reopening Discover)
                // never re-downloads thumbnails.
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => _imagePlaceholder(),
                        errorWidget: (_, _, _) => _imagePlaceholder(),
                      )
                    : _imagePlaceholder(),
              ),
              const SizedBox(width: 12),

              // Name + subtitle
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            o.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (o.verified) ...[
                          const SizedBox(width: 5),
                          const Icon(Icons.verified, color: _red, size: 14),
                        ],
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(color: _muted, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Rating (conditional) + chevron
              if (o.hasRating) ...[
                const Icon(Icons.star_rounded, color: Colors.amber, size: 15),
                const SizedBox(width: 2),
                Text(
                  o.rating.toStringAsFixed(1),
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              const Icon(Icons.chevron_right_rounded, color: _muted, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      width: 52,
      height: 52,
      color: const Color(0xFF1E1E1E),
      child: const Icon(Icons.fitness_center, color: _muted, size: 22),
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
            child: const Icon(Icons.workspace_premium, color: _red, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Look for the verified badge',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Verified organizations are vetted by AlphaSerena.',
                  style: GoogleFonts.poppins(color: _muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
