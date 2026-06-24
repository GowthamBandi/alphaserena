import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/gradient_button.dart';
import '../dashboard/dashboard_screen.dart';
import 'discover_models.dart';

/// Purchase Success — order summary + what's next.
class PaymentSuccessScreen extends StatelessWidget {
  final DiscoverOrg org;
  final MembershipPlan plan;
  final int total;
  PaymentSuccessScreen({
    super.key,
    required this.org,
    required this.plan,
    required this.total,
  });

  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _card = Color(0xFF141414);
  static const Color _muted = Color(0xFF8E8E8E);
  static const Color _red = Color(0xFFE10600);
  static const Color _green = Color(0xFF2EBD59);

  final String _paymentId =
      'pay_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
  final String _date = DateFormat('d MMM yyyy, hh:mm a').format(DateTime.now());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () =>
                        Get.offAll(() => const ClientDashboard()),
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 18),
                  ),
                  IconButton(
                    onPressed: () =>
                        Get.offAll(() => const ClientDashboard()),
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                children: [
                  const SizedBox(height: 8),
                  Center(child: _successCheck()),
                  const SizedBox(height: 20),
                  Center(
                    child: Text('Payment Successful!',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text('Welcome to ${org.name}',
                        style:
                            GoogleFonts.poppins(color: _muted, fontSize: 13)),
                  ),
                  const SizedBox(height: 24),
                  _orderDetails(),
                  const SizedBox(height: 16),
                  _whatsNext(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: GradientButton(
                label: 'Go to My Plans',
                onPressed: () =>
                    Get.offAll(() => const ClientDashboard(initialIndex: 1)),
              ),
            ),
            TextButton(
              onPressed: () => Get.offAll(() => const ClientDashboard()),
              child: Text('Back to Home',
                  style: GoogleFonts.poppins(
                      color: _red, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _successCheck() {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _green.withValues(alpha: 0.15),
        border: Border.all(color: _green, width: 2),
      ),
      child: Center(
        child: Container(
          width: 60,
          height: 60,
          decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
          child: const Icon(Icons.check, color: Colors.white, size: 34),
        ),
      ),
    );
  }

  Widget _orderDetails() {
    Widget row(String l, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l, style: GoogleFonts.poppins(color: _muted, fontSize: 12.5)),
              Flexible(
                child: Text(v,
                    textAlign: TextAlign.right,
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order Details',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          row('Plan', plan.name),
          row('Duration', '${plan.weeks} Weeks'),
          row('Amount Paid', '₹${inr(total)}'),
          row('Payment ID', _paymentId),
          row('Date', _date),
        ],
      ),
    );
  }

  Widget _whatsNext() {
    Widget item(String t) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: _green, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(t,
                    style: GoogleFonts.poppins(
                        color: const Color(0xFFCFCFCF), fontSize: 12.5)),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("What's Next?",
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          item('Check your inbox for confirmation'),
          item('Our team will contact you within 24 hrs'),
          item('Get ready to transform your life!'),
        ],
      ),
    );
  }
}
