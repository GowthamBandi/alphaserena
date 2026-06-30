import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/coach_service.dart';
import '../../core/widgets/brand.dart';
import 'discover_models.dart';
import 'plan_details_screen.dart';

/// Plans screen — the organization's REAL membership plans (from Firestore
/// `membershipPlans` where adminId == org.id, active only, cheapest first).
class PlansScreen extends StatefulWidget {
  final DiscoverOrg org;
  const PlansScreen({super.key, required this.org});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _muted = Color(0xFF8E8E8E);
  static const Color _red = Color(0xFFE10600);

  final CoachService _service = CoachService();
  late Future<List<PlanVM>> _future;

  DiscoverOrg get org => widget.org;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<PlanVM>> _load() async {
    final raw = await _service.plans(org.id);
    return raw.map(PlanVM.fromMap).toList();
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 18),
          onPressed: () => Get.back(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            org.logoUrl.isNotEmpty
                ? ClipOval(
                    child: Image.network(org.logoUrl,
                        width: 20, height: 20, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Icon(org.logoIcon, color: org.logoColor, size: 18)),
                  )
                : (org.id == 'alpha'
                    ? const AlphaAMark(size: 18)
                    : Icon(org.logoIcon, color: org.logoColor, size: 18)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(org.name,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
      body: FutureBuilder<List<PlanVM>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: _red));
          }
          if (snap.hasError) {
            return _stateMessage(
              Icons.wifi_off_rounded,
              'Could not load plans',
              'Please check your connection and try again.',
              action: _reload,
            );
          }
          final plans = snap.data ?? const [];
          if (plans.isEmpty) {
            return _stateMessage(
              Icons.inventory_2_outlined,
              'No plans yet',
              '${org.name} hasn\'t published any membership plans yet.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            children: [
              Center(
                child: Text('Available Plans',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text('Choose the plan that fits your fitness journey',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(color: _muted, fontSize: 12.5)),
              ),
              const SizedBox(height: 20),
              ...plans.map(_planCard),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _red.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _red.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.workspace_premium, color: _red, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'All plans include access to our community & resources',
                        style:
                            GoogleFonts.poppins(color: _muted, fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _planCard(PlanVM p) {
    final highlighted = p.featured;
    return GestureDetector(
      onTap: () => Get.to(() => PlanDetailsScreen(org: org, plan: p)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: highlighted ? const Color(0xFF1A0E0E) : const Color(0xFF141414),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlighted ? _red : const Color(0xFF1E1E1E),
            width: highlighted ? 1.4 : 1,
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (highlighted) const SizedBox(height: 8),
                  Text(p.name,
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(p.program,
                      style: GoogleFonts.poppins(
                          color: _red,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('₹${inr(p.price)}',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(width: 4),
                      Text('/ ${p.durationLabel}',
                          style: GoogleFonts.poppins(
                              color: _muted, fontSize: 12)),
                    ],
                  ),
                  if (p.points.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ...p.points.map(_feature),
                  ],
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('View details',
                            style: GoogleFonts.poppins(
                                color: _red,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        const Icon(Icons.chevron_right, color: _red, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (highlighted)
              Positioned(
                top: 0,
                left: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: const BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: Text('MOST POPULAR',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _feature(String f) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.check_circle, color: _red, size: 14),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(f,
                  style: GoogleFonts.poppins(
                      color: const Color(0xFFCFCFCF), fontSize: 12, height: 1.3)),
            ),
          ],
        ),
      );

  Widget _stateMessage(IconData icon, String title, String sub,
      {VoidCallback? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _muted, size: 44),
            const SizedBox(height: 14),
            Text(title,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(sub,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: _muted, fontSize: 12.5)),
            if (action != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: action,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _red,
                  side: const BorderSide(color: _red),
                ),
                child: Text('Retry', style: GoogleFonts.poppins()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
