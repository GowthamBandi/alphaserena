import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/widgets/gradient_button.dart';
import 'discover_models.dart';
import 'razorpay_secure_screen.dart';

/// Checkout — apply a coupon and choose a payment method.
class CheckoutScreen extends StatefulWidget {
  final DiscoverOrg org;
  final MembershipPlan plan;
  const CheckoutScreen({super.key, required this.org, required this.plan});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _card = Color(0xFF141414);
  static const Color _muted = Color(0xFF8E8E8E);
  static const Color _red = Color(0xFFE10600);
  static const Color _green = Color(0xFF2EBD59);

  final _coupon = TextEditingController(text: 'FIT20');
  bool _applied = true; // matches the mockup's applied state
  int _method = 0;

  int get _discount => _applied ? 800 : 0;
  int get _total => widget.plan.price - _discount;

  @override
  void dispose() {
    _coupon.dispose();
    super.dispose();
  }

  void _apply() {
    final code = _coupon.text.trim().toUpperCase();
    setState(() => _applied = code == 'FIT20');
    if (!_applied) {
      Get.snackbar('Invalid coupon', 'Try code FIT20 for ₹800 off.');
    }
  }

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
        title: Text('Checkout',
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
              children: [
                _orderCard(),
                const SizedBox(height: 20),
                _label('Apply Coupon'),
                const SizedBox(height: 10),
                _couponField(),
                if (_applied) ...[
                  const SizedBox(height: 10),
                  _couponSuccess(),
                ],
                const SizedBox(height: 16),
                _summary(),
                const SizedBox(height: 20),
                _label('Choose Payment Method'),
                const SizedBox(height: 10),
                _payMethod(0, 'Razorpay', '(UPI, Cards, NetBanking)'),
                _payMethod(1, 'Card Payment', ''),
                _payMethod(2, 'UPI', ''),
                const SizedBox(height: 18),
                _trustRow(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
            child: GradientButton(
              label: 'Proceed to Pay ₹${inr(_total)}',
              onPressed: () => Get.to(() => RazorpaySecureScreen(
                    org: widget.org,
                    plan: widget.plan,
                    total: _total,
                  )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: GoogleFonts.poppins(
          color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600));

  Widget _orderCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(widget.org.thumb,
                width: 50, height: 50, fit: BoxFit.cover),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.plan.name,
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text(widget.plan.program,
                    style: GoogleFonts.poppins(color: _muted, fontSize: 11.5)),
                const SizedBox(height: 4),
                Text('₹${inr(widget.plan.price)}',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _couponField() {
    return Container(
      height: 50,
      padding: const EdgeInsets.only(left: 14, right: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _red.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _coupon,
              textCapitalization: TextCapitalization.characters,
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Enter coupon code',
                hintStyle: GoogleFonts.poppins(color: _muted, fontSize: 13),
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          TextButton(
            onPressed: _apply,
            child: Text('Apply',
                style: GoogleFonts.poppins(
                    color: _red, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _couponSuccess() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_coupon.text.trim().toUpperCase()} Applied Successfully!',
                    style: GoogleFonts.poppins(
                        color: _green,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
                Text('You saved ₹$_discount',
                    style: GoogleFonts.poppins(color: _green, fontSize: 11.5)),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: _green, size: 22),
        ],
      ),
    );
  }

  Widget _summary() {
    Widget row(String l, String v, {Color? color, bool bold = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l,
                  style: GoogleFonts.poppins(
                      color: color ?? _muted,
                      fontSize: bold ? 14 : 12.5,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
              Text(v,
                  style: GoogleFonts.poppins(
                      color: color ?? Colors.white,
                      fontSize: bold ? 15 : 12.5,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Column(
        children: [
          row('Subtotal', '₹${inr(widget.plan.price)}'),
          if (_applied)
            row('Discount (${_coupon.text.trim().toUpperCase()})',
                '- ₹$_discount',
                color: _green),
          const Divider(color: Color(0xFF262626), height: 18),
          row('Total Amount', '₹${inr(_total)}', bold: true),
        ],
      ),
    );
  }

  Widget _payMethod(int i, String title, String sub) {
    final selected = _method == i;
    return GestureDetector(
      onTap: () => setState(() => _method = i),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? _red : const Color(0xFF1E1E1E),
              width: selected ? 1.3 : 1),
        ),
        child: Row(
          children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? _red : _muted, size: 20),
            const SizedBox(width: 12),
            Text(title,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600)),
            if (sub.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(sub,
                  style: GoogleFonts.poppins(color: _muted, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _trustRow() {
    Widget item(IconData icon, Color color, String t, String s) => Expanded(
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 6),
              Text(t,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(s,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(color: _muted, fontSize: 9.5)),
            ],
          ),
        );
    return Row(
      children: [
        item(Icons.verified_user, _green, 'Secure Payment',
            '100% secure transactions'),
        item(Icons.local_offer, const Color(0xFFEF9F27), 'Best Price',
            'Guaranteed best offers'),
        item(Icons.flash_on, const Color(0xFF9B5DE5), 'Instant Access',
            'Get started immediately'),
      ],
    );
  }
}
