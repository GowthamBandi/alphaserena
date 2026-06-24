import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../controllers/auth_controller.dart';
import '../../../core/widgets/brand.dart';

/// Profile — member card, partner, subscription, quick access, account.
class ClientProfileScreen extends StatelessWidget {
  const ClientProfileScreen({super.key});

  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _card = Color(0xFF141414);
  static const Color _muted = Color(0xFF8E8E8E);
  static const Color _red = Color(0xFFE10600);
  static const Color _green = Color(0xFF2EBD59);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            _header(),
            const SizedBox(height: 16),
            _memberCard(),
            const SizedBox(height: 12),
            _statsRow(),
            const SizedBox(height: 16),
            _partnerCard(),
            const SizedBox(height: 16),
            _subscriptionCard(),
            const SizedBox(height: 18),
            _quickAccess(),
            const SizedBox(height: 18),
            _account(),
            const SizedBox(height: 16),
            _logout(),
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
              Text('Profile',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('Manage your profile and preferences.',
                  style: GoogleFonts.poppins(color: _muted, fontSize: 12)),
            ],
          ),
        ),
        _iconBtn(Icons.settings_outlined),
        const SizedBox(width: 10),
        _bell(),
      ],
    );
  }

  Widget _iconBtn(IconData icon) => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFF242424)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      );

  Widget _bell() => Stack(
        clipBehavior: Clip.none,
        children: [
          _iconBtn(Icons.notifications_none_rounded),
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration:
                  const BoxDecoration(color: _red, shape: BoxShape.circle),
              child: Text('3',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      );

  Widget _memberCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A0E0E), Color(0xFF141414)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A1414)),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _red, width: 2),
                ),
                child: ClipOval(
                  child: Image.asset('assets/images/avatar.png',
                      width: 64, height: 64, fit: BoxFit.cover),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1C),
                    shape: BoxShape.circle,
                    border: Border.all(color: _bg, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt,
                      color: Colors.white, size: 11),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('John Doe',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _red,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('Pro Member',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.mail_outline, color: _muted, size: 12),
                    const SizedBox(width: 6),
                    Text('john.doe@email.com',
                        style:
                            GoogleFonts.poppins(color: _muted, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.call, color: _muted, size: 12),
                    const SizedBox(width: 6),
                    Text('+91 98765 43210',
                        style:
                            GoogleFonts.poppins(color: _muted, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1C),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xFF2E2E2E)),
            ),
            child: Text('Edit Profile',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _statsRow() {
    final s = [
      (Icons.cake_outlined, 'Age', '28'),
      (Icons.straighten, 'Height', '178 cm'),
      (Icons.monitor_weight_outlined, 'Weight', '72.5 kg'),
      (Icons.verified_outlined, 'Member Since', 'May 2024'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Row(
        children: s
            .map((e) => Expanded(
                  child: Column(
                    children: [
                      Icon(e.$1, color: _red, size: 15),
                      const SizedBox(height: 5),
                      Text(e.$2,
                          style:
                              GoogleFonts.poppins(color: _muted, fontSize: 9)),
                      Text(e.$3,
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _partnerCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const AlphaAMark(size: 24),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Transformation Partner',
                          style:
                              GoogleFonts.poppins(color: _muted, fontSize: 8)),
                      Text('Alpha Strength Co.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                      Text('Your journey, our expertise',
                          style: GoogleFonts.poppins(
                              color: _muted, fontSize: 8.5)),
                      const SizedBox(height: 2),
                      Text('View Organization →',
                          style: GoogleFonts.poppins(
                              color: _red,
                              fontSize: 9,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 56, color: const Color(0xFF1E1E1E)),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your Trainer',
                          style: GoogleFonts.poppins(
                              color: _red,
                              fontSize: 8,
                              fontWeight: FontWeight.w600)),
                      Text('Rahul Sharma',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      Text('Strength & Performance Coach',
                          maxLines: 2,
                          style: GoogleFonts.poppins(
                              color: _muted, fontSize: 8, height: 1.2)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                ClipOval(
                  child: Image.asset('assets/images/trainer.png',
                      width: 34, height: 34, fit: BoxFit.cover),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _subscriptionCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Subscription Plan',
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E1E1E)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF9B5DE5).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.workspace_premium,
                    color: Color(0xFF9B5DE5), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Premium Transformation',
                            style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('Active',
                              style: GoogleFonts.poppins(
                                  color: _green,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    Text('12 Weeks Program',
                        style:
                            GoogleFonts.poppins(color: _muted, fontSize: 10)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Valid Till',
                      style: GoogleFonts.poppins(color: _muted, fontSize: 8.5)),
                  Text('15 Aug 2024',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  Text('24 Days Left',
                      style: GoogleFonts.poppins(color: _green, fontSize: 8.5)),
                ],
              ),
              const Icon(Icons.chevron_right, color: _muted, size: 18),
            ],
          ),
        ),
      ],
    );
  }

  Widget _quickAccess() {
    final items = [
      (Icons.assignment_outlined, 'My Plans'),
      (Icons.show_chart, 'Progress'),
      (Icons.calendar_month_outlined, 'Workout\nCalendar'),
      (Icons.restaurant_menu, 'Nutrition Log'),
      (Icons.description_outlined, 'Reports'),
      (Icons.chat_bubble_outline, 'Messages'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Access',
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E1E1E)),
          ),
          child: Row(
            children: items
                .map((e) => Expanded(
                      child: Column(
                        children: [
                          const SizedBox(height: 6),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: _red.withValues(alpha: 0.4)),
                            ),
                            child: Icon(e.$1, color: _red, size: 18),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 24,
                            child: Text(e.$2,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                    color: const Color(0xFFCFCFCF),
                                    fontSize: 8.5,
                                    height: 1.15)),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _account() {
    final items = [
      (Icons.person_outline, 'Personal Information', 'Update your personal details'),
      (Icons.favorite_border, 'Health Information', 'Medical info, goals, and more'),
      (Icons.settings_outlined, 'Preferences', 'Units, notifications, app settings'),
      (Icons.lock_outline, 'Privacy & Security', 'Manage your privacy and security'),
      (Icons.devices_other, 'Connected Devices', 'Manage your connected devices'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Account',
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E1E1E)),
          ),
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                if (i > 0)
                  const Divider(
                      color: Color(0xFF1E1E1E), height: 1, indent: 14, endIndent: 14),
                _accountRow(items[i].$1, items[i].$2, items[i].$3),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _accountRow(IconData icon, String title, String sub) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Icon(icon, color: _muted, size: 18),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
                Text(sub,
                    style: GoogleFonts.poppins(color: _muted, fontSize: 10)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: _muted, size: 18),
        ],
      ),
    );
  }

  Widget _logout() {
    return GestureDetector(
      onTap: () => Get.find<AuthController>().signOut(),
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _red.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.logout, color: _red, size: 18),
            const SizedBox(width: 8),
            Text('Log Out',
                style: GoogleFonts.poppins(
                    color: _red, fontSize: 13.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
