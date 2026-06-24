import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import 'discover_models.dart';
import 'processing_payment_screen.dart';

/// A faithful stand-in for the Razorpay Secure payment sheet (sample flow).
class RazorpaySecureScreen extends StatelessWidget {
  final DiscoverOrg org;
  final MembershipPlan plan;
  final int total;
  const RazorpaySecureScreen({
    super.key,
    required this.org,
    required this.plan,
    required this.total,
  });

  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _card = Color(0xFF141414);
  static const Color _muted = Color(0xFF8E8E8E);
  static const Color _red = Color(0xFFE10600);

  void _pay() => Get.to(() => ProcessingPaymentScreen(
        org: org,
        plan: plan,
        total: total,
      ));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.lock, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Razorpay Secure',
                            style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        Text('Razorpay Trusted Business',
                            style: GoogleFonts.poppins(
                                color: _muted, fontSize: 11)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Get.back(),
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF1E1E1E)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('₹${inr(total)}',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('View Details',
                            style: GoogleFonts.poppins(
                                color: _red, fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text('Recommended',
                      style: GoogleFonts.poppins(
                          color: _muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _tile(Icons.qr_code_2, 'UPI', 'Pay with any UPI app',
                      highlight: true),
                  const SizedBox(height: 18),
                  Text('Cards, Wallets & More',
                      style: GoogleFonts.poppins(
                          color: _muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _tile(Icons.credit_card, 'Card', 'Visa, MasterCard, RuPay'),
                  _tile(Icons.account_balance_wallet_outlined, 'UPI',
                      'Google Pay, PhonePe, Paytm'),
                  _tile(Icons.account_balance, 'Netbanking',
                      'All Indian Banks'),
                  _tile(Icons.wallet_outlined, 'Wallet',
                      'Paytm, Amazon Pay, Mobikwik'),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF1E1E1E))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock, color: _muted, size: 13),
                  const SizedBox(width: 6),
                  Text('Secured by ',
                      style: GoogleFonts.poppins(color: _muted, fontSize: 11.5)),
                  Text('Razorpay',
                      style: GoogleFonts.poppins(
                          color: const Color(0xFF528FF0),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(IconData icon, String title, String sub,
      {bool highlight = false}) {
    return GestureDetector(
      onTap: _pay,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: highlight ? _red : const Color(0xFF1E1E1E),
              width: highlight ? 1.3 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: highlight ? _red : Colors.white, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600)),
                  Text(sub,
                      style:
                          GoogleFonts.poppins(color: _muted, fontSize: 11.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: _muted, size: 20),
          ],
        ),
      ),
    );
  }
}
