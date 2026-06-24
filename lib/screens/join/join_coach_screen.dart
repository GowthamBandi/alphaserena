import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/auth_controller.dart';
import 'coach_storefront_screen.dart';
import 'discover_models.dart';

/// Organizations Discovery — the member browses fitness organizations and opens
/// one to subscribe. (Pre-membership gate; replaces the old "find your coach".)
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

  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<DiscoverOrg> get _orgs {
    if (_query.trim().isEmpty) return kSampleOrgs;
    final q = _query.toLowerCase();
    return kSampleOrgs
        .where((o) =>
            o.name.toLowerCase().contains(q) ||
            o.tags.any((t) => t.toLowerCase().contains(q)) ||
            o.location.toLowerCase().contains(q))
        .toList();
  }

  void _open(DiscoverOrg org) =>
      Get.to(() => CoachStorefrontScreen(org: org));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  _header(),
                  const SizedBox(height: 16),
                  _searchBar(),
                  const SizedBox(height: 14),
                  _filters(),
                  const SizedBox(height: 20),
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
                  ..._orgs.map(_orgCard),
                  const SizedBox(height: 6),
                  _verifiedBanner(),
                ],
              ),
            ),
            _bottomNav(),
          ],
        ),
      ),
    );
  }

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
                  Text('John Doe',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
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
        _circleIcon(Icons.notifications_none_rounded, badge: '2'),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _menu,
          child: _circleIcon(Icons.menu_rounded),
        ),
      ],
    );
  }

  Widget _circleIcon(IconData icon, {String? badge}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _card,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF242424)),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        if (badge != null)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              decoration: const BoxDecoration(color: _red, shape: BoxShape.circle),
              child: Text(badge,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
          ),
      ],
    );
  }

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
              onChanged: (v) => setState(() => _query = v),
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Search organization, coach, or specialty...',
                hintStyle: GoogleFonts.poppins(color: _muted, fontSize: 13),
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

  Widget _filters() {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip('All', active: true, icon: Icons.tune),
          _filterChip('Gender', dropdown: true),
          _filterChip('Location', dropdown: true),
          _filterChip('Specialization', dropdown: true),
        ],
      ),
    );
  }

  Widget _filterChip(String label,
      {bool active = false, bool dropdown = false, IconData? icon}) {
    return Container(
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
          Text(label,
              style: GoogleFonts.poppins(
                  color: active ? Colors.white : Colors.white,
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500)),
          if (dropdown) ...[
            const SizedBox(width: 2),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: _muted, size: 18),
          ],
        ],
      ),
    );
  }

  Widget _orgCard(DiscoverOrg org) {
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(org.thumb,
                      width: 92, height: 118, fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (org.verified)
                        Row(
                          children: [
                            const Icon(Icons.verified, color: _red, size: 13),
                            const SizedBox(width: 4),
                            Text('Verified',
                                style: GoogleFonts.poppins(
                                    color: _red,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(right: 26),
                        child: Text(org.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 2),
                      Text(org.tagline,
                          style: GoogleFonts.poppins(
                              color: _muted, fontSize: 12)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              color: _muted, size: 13),
                          const SizedBox(width: 4),
                          Text(org.location,
                              style: GoogleFonts.poppins(
                                  color: _muted, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _clientsRow(org),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: org.tags.map(_tagChip).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Positioned(
            top: 14,
            right: 12,
            child: Icon(Icons.favorite_border, color: _muted, size: 20),
          ),
          Positioned(
            right: 12,
            bottom: 14,
            child: GestureDetector(
              onTap: () => _open(org),
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

  Widget _clientsRow(DiscoverOrg org) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          height: 22,
          child: Stack(
            children: [
              for (int i = 0; i < 3; i++)
                Positioned(
                  left: i * 14.0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Color(0xFF3A3A3A + i * 0x080808),
                      shape: BoxShape.circle,
                      border: Border.all(color: _card, width: 1.5),
                    ),
                    child: const Icon(Icons.person, color: Colors.white54, size: 12),
                  ),
                ),
              Positioned(
                left: 40,
                child: Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _red,
                    shape: BoxShape.rectangle,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: _card, width: 1.5),
                  ),
                  child: Text('+${org.plusAvatars}',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Text('${org.clientsLabel} Clients',
            style: GoogleFonts.poppins(color: _muted, fontSize: 11.5)),
      ],
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
      child: Text(label,
          style: GoogleFonts.poppins(color: const Color(0xFFB0B0B0), fontSize: 10.5)),
    );
  }

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
                Text('All organizations are verified and trusted',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('Your fitness journey is safe with us.',
                    style: GoogleFonts.poppins(color: _muted, fontSize: 11.5)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: _muted, size: 20),
        ],
      ),
    );
  }

  Widget _bottomNav() {
    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 18, left: 8, right: 8),
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
          : () => Get.snackbar('Coming up', 'Join an organization to unlock $label.'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(label,
              style: GoogleFonts.poppins(
                  color: color,
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
        ],
      ),
    );
  }

  Widget _navFab() {
    return Container(
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
    );
  }
}
