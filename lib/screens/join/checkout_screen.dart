import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/client_razorpay_controller.dart';
import '../../core/widgets/gradient_button.dart';
import 'discover_models.dart';
import 'payment_success_screen.dart';

/// Checkout — apply a real (server-validated) coupon, then pay via Razorpay.
/// Coupon is previewed by `previewMembershipCoupon`; the actual discounted
/// charge is recomputed server-side in `createMembershipOrder` (the coupon code
/// is passed through), so the client can never under-charge itself.
class CheckoutScreen extends StatefulWidget {
  final DiscoverOrg org;
  final PlanVM plan;
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

  final _coupon = TextEditingController();
  final _functions = FirebaseFunctions.instance;
  late final ClientRazorpayController _razor =
      Get.isRegistered<ClientRazorpayController>()
          ? Get.find<ClientRazorpayController>()
          : Get.put(ClientRazorpayController());

  bool _checking = false; // validating coupon
  String? _appliedCode; // the accepted coupon code
  int _discount = 0;
  String? _couponMessage; // success or error message
  bool _couponValid = false;

  PlanVM get plan => widget.plan;
  int get _total => (plan.price - _discount).clamp(0, plan.price);

  @override
  void dispose() {
    // Leaving checkout: clear any captured-but-unverified payment state so a
    // future checkout opens with a normal Pay button (no-op if mid-verify).
    _razor.resetVerifyState();
    _coupon.dispose();
    super.dispose();
  }

  Future<void> _applyCoupon() async {
    final code = _coupon.text.trim().toUpperCase();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _checking = true;
      _couponMessage = null;
    });
    try {
      final res = await _functions
          .httpsCallable('previewMembershipCoupon')
          .call({'planId': plan.id, 'code': code});
      final d = Map<String, dynamic>.from(res.data as Map);
      final valid = d['valid'] == true;
      setState(() {
        _couponValid = valid;
        if (valid) {
          _appliedCode = (d['couponCode'] ?? code).toString();
          _discount = ((d['discount'] as num?) ?? 0).round();
          _couponMessage =
              (d['message'] ?? 'Coupon applied!').toString();
        } else {
          _appliedCode = null;
          _discount = 0;
          _couponMessage =
              (d['message'] ?? 'This coupon is not valid.').toString();
        }
      });
    } catch (_) {
      setState(() {
        _couponValid = false;
        _appliedCode = null;
        _discount = 0;
        _couponMessage = 'Could not check this coupon. Try again.';
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _pay() {
    _razor.buy(
      planId: plan.id,
      planName: plan.name,
      couponCode: _appliedCode,
      contact: FirebaseAuth.instance.currentUser?.phoneNumber ?? '',
      onSuccess: (paymentId, amountPaid) {
        Get.off(() => PaymentSuccessScreen(
              org: widget.org,
              planName: plan.name,
              durationLabel: plan.durationLabel,
              amountPaid: amountPaid,
              paymentId: paymentId,
            ));
      },
    );
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
      body: Stack(
        children: [
          Column(
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
                    if (_couponMessage != null) ...[
                      const SizedBox(height: 10),
                      _couponResult(),
                    ],
                    const SizedBox(height: 16),
                    _summary(),
                    const SizedBox(height: 20),
                    _label('Payment Method'),
                    const SizedBox(height: 10),
                    _razorpayCard(),
                    const SizedBox(height: 18),
                    _trustRow(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                child: Obx(() {
                  final processing = _razor.isProcessing.value;
                  final retry = _razor.needsVerifyRetry.value;
                  return GradientButton(
                    label: retry
                        ? 'Retry Confirmation'
                        : 'Proceed to Pay ₹${inr(_total)}',
                    isLoading: processing,
                    onPressed: processing
                        ? null
                        : (retry ? _razor.retryVerification : _pay),
                  );
                }),
              ),
            ],
          ),
          // Full-screen processing overlay — covers the gap before the Razorpay
          // sheet opens AND the verify step after it closes, so the user always
          // sees clear progress (never a frozen screen).
          Obx(() => _razor.isProcessing.value
              ? const _ProcessingOverlay()
              : const SizedBox.shrink()),
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
          OrgThumb(org: widget.org, size: 50),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.name,
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text(plan.program,
                    style: GoogleFonts.poppins(color: _muted, fontSize: 11.5)),
                const SizedBox(height: 4),
                Text('₹${inr(plan.price)}',
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
              enabled: !_checking,
              textCapitalization: TextCapitalization.characters,
              onSubmitted: (_) => _applyCoupon(),
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Enter coupon code',
                hintStyle: GoogleFonts.poppins(color: _muted, fontSize: 13),
                // Kill the theme's inner outline — the red border is the
                // surrounding container, the field itself is borderless.
                filled: false,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
              ),
            ),
          ),
          _checking
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _red),
                  ),
                )
              : TextButton(
                  onPressed: _applyCoupon,
                  child: Text('Apply',
                      style: GoogleFonts.poppins(
                          color: _red,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
        ],
      ),
    );
  }

  Widget _couponResult() {
    final ok = _couponValid;
    final color = ok ? _green : _red;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.error_outline,
              color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_couponMessage ?? '',
                    style: GoogleFonts.poppins(
                        color: color,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
                if (ok && _discount > 0)
                  Text('You saved ₹${inr(_discount)}',
                      style: GoogleFonts.poppins(color: _green, fontSize: 11.5)),
              ],
            ),
          ),
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
          row('Subtotal', '₹${inr(plan.price)}'),
          if (_couponValid && _discount > 0)
            row('Discount ($_appliedCode)', '- ₹${inr(_discount)}',
                color: _green),
          const Divider(color: Color(0xFF262626), height: 18),
          row('Total Amount', '₹${inr(_total)}', bold: true),
        ],
      ),
    );
  }

  Widget _razorpayCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _red, width: 1.3),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock, color: _red, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pay securely via Razorpay',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600)),
                Text('UPI · Cards · NetBanking · Wallets',
                    style: GoogleFonts.poppins(color: _muted, fontSize: 11)),
              ],
            ),
          ),
          const Icon(Icons.radio_button_checked, color: _red, size: 20),
        ],
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

/// Blocking overlay shown while a payment is being started + verified — a dimmed
/// barrier + spinner so the user always sees progress and can't accidentally
/// leave mid-transaction.
class _ProcessingOverlay extends StatelessWidget {
  const _ProcessingOverlay();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Container(
        color: Colors.black.withValues(alpha: 0.72),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF262626)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: Color(0xFFE10600)),
              ),
              const SizedBox(height: 18),
              Text('Processing payment',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Please don\'t close this screen…',
                  style: GoogleFonts.poppins(
                      color: const Color(0xFF8E8E8E), fontSize: 11.5)),
            ],
          ),
        ),
      ),
    );
  }
}
