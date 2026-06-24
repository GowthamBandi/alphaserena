import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import 'discover_models.dart';
import 'payment_success_screen.dart';

/// Processing Payment — a brief secured-processing beat before success.
class ProcessingPaymentScreen extends StatefulWidget {
  final DiscoverOrg org;
  final MembershipPlan plan;
  final int total;
  const ProcessingPaymentScreen({
    super.key,
    required this.org,
    required this.plan,
    required this.total,
  });

  @override
  State<ProcessingPaymentScreen> createState() =>
      _ProcessingPaymentScreenState();
}

class _ProcessingPaymentScreenState extends State<ProcessingPaymentScreen> {
  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _muted = Color(0xFF8E8E8E);
  static const Color _red = Color(0xFFE10600);

  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(const Duration(milliseconds: 2600), () {
      if (!mounted) return;
      Get.off(() => PaymentSuccessScreen(
            org: widget.org,
            plan: widget.plan,
            total: widget.total,
          ));
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _lockCard(),
            const SizedBox(height: 36),
            Text('Processing Payment',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Please wait while we securely\nprocess your payment',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    color: _muted, fontSize: 13, height: 1.4)),
            const SizedBox(height: 30),
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(color: _red, strokeWidth: 3),
            ),
            const SizedBox(height: 50),
            Row(
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
          ],
        ),
      ),
    );
  }

  Widget _lockCard() {
    return Container(
      width: 120,
      height: 100,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEC1C1C), Color(0xFF8A0000)],
        ),
        boxShadow: [
          BoxShadow(
              color: _red.withValues(alpha: 0.4),
              blurRadius: 30,
              offset: const Offset(0, 12)),
        ],
      ),
      child: const Icon(Icons.lock, color: Colors.white, size: 44),
    );
  }
}
