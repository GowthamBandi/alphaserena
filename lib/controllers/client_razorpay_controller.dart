import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

/// Tier-2 membership checkout (member buys the GYM's membership plan).
///
/// createMembershipOrder CF → native Razorpay sheet → verifyAndActivateMembership
/// CF (server verifies signature + activates on the member's clients doc). The key
/// comes from the server secret, so test vs live needs no app change.
class ClientRazorpayController extends GetxController {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final RxBool isProcessing = false.obs;

  /// True after a payment is CAPTURED but server verification hasn't succeeded
  /// yet. While true the checkout shows "Retry Confirmation" instead of a live
  /// Pay button, so a charged member can never accidentally start a 2nd order.
  final RxBool needsVerifyRetry = false.obs;

  Razorpay? _razorpay;
  String? _pendingPlanId;
  String? _pendingOrderId;
  int _pendingAmountPaise = 0;
  // The captured payment being verified (kept across retries until it succeeds).
  String? _vPlanId;
  String? _vOrderId;
  String? _vPaymentId;
  String? _vSignature;
  void Function(String paymentId, int amountPaidRupees)? _onSuccess;

  @override
  void onInit() {
    super.onInit();
    _razorpay = Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _success)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _error)
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});
  }

  @override
  void onClose() {
    _razorpay?.clear();
    super.onClose();
  }

  Future<void> buy({
    required String planId,
    required String planName,
    String? couponCode,
    String email = '',
    String contact = '',
    void Function(String paymentId, int amountPaidRupees)? onSuccess,
  }) async {
    if (isProcessing.value) return;
    try {
      isProcessing.value = true;
      _onSuccess = onSuccess;
      final res = await _functions.httpsCallable('createMembershipOrder').call({
        'planId': planId,
        if (couponCode != null && couponCode.trim().isNotEmpty)
          'couponCode': couponCode.trim(),
      });
      final d = Map<String, dynamic>.from(res.data as Map);
      final orderId = (d['orderId'] ?? '').toString();
      final keyId = (d['keyId'] ?? '').toString();
      final amount = (d['amount'] as num?)?.toInt() ?? 0;
      if (orderId.isEmpty || keyId.isEmpty || amount <= 0) {
        throw Exception('Invalid order');
      }
      _pendingPlanId = planId;
      _pendingOrderId = orderId;
      _pendingAmountPaise = amount;
      _razorpay!.open(<String, dynamic>{
        'key': keyId,
        'order_id': orderId,
        'amount': amount,
        'currency': (d['currency'] ?? 'INR').toString(),
        'name': 'AlphaSerena',
        'description': planName,
        'prefill': {
          'email': email,
          'contact':
              contact.isNotEmpty ? contact : (FirebaseAuth.instance.currentUser?.phoneNumber ?? ''),
        },
        'theme': {'color': '#D50000'},
      });
    } on FirebaseFunctionsException catch (e) {
      isProcessing.value = false;
      Get.snackbar('Payment error', e.message ?? 'Could not start payment.');
    } catch (_) {
      isProcessing.value = false;
      Get.snackbar('Payment error', 'Could not start payment.');
    }
  }

  Future<void> _success(PaymentSuccessResponse r) async {
    final planId = _pendingPlanId;
    final orderId = r.orderId ?? _pendingOrderId ?? '';
    final paymentId = r.paymentId ?? '';
    final signature = r.signature ?? '';
    if (planId == null ||
        orderId.isEmpty ||
        paymentId.isEmpty ||
        signature.isEmpty) {
      isProcessing.value = false;
      Get.snackbar('Verification failed',
          'Incomplete payment response. Contact support if you were charged.');
      return;
    }
    // Stash the captured payment so verification can be retried without
    // re-charging (the server CF is idempotent on these identifiers).
    _vPlanId = planId;
    _vOrderId = orderId;
    _vPaymentId = paymentId;
    _vSignature = signature;
    await _runVerify();
  }

  /// Verify + activate the captured payment. On success → reports the
  /// server-charged amount and clears state. On failure → flips
  /// [needsVerifyRetry] so the user can retry without starting a new order.
  Future<void> _runVerify() async {
    isProcessing.value = true;
    try {
      await _functions.httpsCallable('verifyAndActivateMembership').call({
        'planId': _vPlanId,
        'razorpayOrderId': _vOrderId,
        'razorpayPaymentId': _vPaymentId,
        'razorpaySignature': _vSignature,
      });
      // Capture before reset: report the amount the SERVER charged (paise →
      // whole rupees), not the client's optimistic total, so the receipt is
      // always accurate.
      final paid = (_pendingAmountPaise / 100).round();
      final pid = _vPaymentId ?? '';
      needsVerifyRetry.value = false;
      _resetAll();
      isProcessing.value = false;
      _onSuccess?.call(pid, paid);
    } on FirebaseFunctionsException catch (e) {
      isProcessing.value = false;
      needsVerifyRetry.value = true;
      Get.snackbar("Couldn't confirm payment",
          e.message ?? 'Tap "Retry Confirmation" — you won\'t be charged again.');
    } catch (_) {
      isProcessing.value = false;
      needsVerifyRetry.value = true;
      Get.snackbar("Couldn't confirm payment",
          'Tap "Retry Confirmation" — you won\'t be charged again.');
    }
  }

  /// Re-attempt verification of an already-captured payment (no new charge).
  Future<void> retryVerification() async {
    if (isProcessing.value || _vPlanId == null) return;
    await _runVerify();
  }

  /// Clears the captured-but-unverified state. Called when the checkout screen
  /// is left so a fresh checkout starts with a normal Pay button.
  void resetVerifyState() {
    if (isProcessing.value) return;
    needsVerifyRetry.value = false;
    _resetAll();
  }

  void _error(PaymentFailureResponse r) {
    _resetAll();
    isProcessing.value = false;
    final msg = (r.message ?? '').trim();
    Get.snackbar('Payment', msg.isEmpty ? 'Payment cancelled.' : msg);
  }

  void _resetAll() {
    _pendingPlanId = null;
    _pendingOrderId = null;
    _pendingAmountPaise = 0;
    _vPlanId = null;
    _vOrderId = null;
    _vPaymentId = null;
    _vSignature = null;
  }
}
