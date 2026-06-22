import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
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

  Razorpay? _razorpay;
  String? _pendingPlanId;
  String? _pendingOrderId;
  VoidCallback? _onSuccess;

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
    String email = '',
    String contact = '',
    VoidCallback? onSuccess,
  }) async {
    if (isProcessing.value) return;
    try {
      isProcessing.value = true;
      _onSuccess = onSuccess;
      final res = await _functions
          .httpsCallable('createMembershipOrder')
          .call({'planId': planId});
      final d = Map<String, dynamic>.from(res.data as Map);
      final orderId = (d['orderId'] ?? '').toString();
      final keyId = (d['keyId'] ?? '').toString();
      final amount = (d['amount'] as num?)?.toInt() ?? 0;
      if (orderId.isEmpty || keyId.isEmpty || amount <= 0) {
        throw Exception('Invalid order');
      }
      _pendingPlanId = planId;
      _pendingOrderId = orderId;
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
    try {
      final planId = _pendingPlanId;
      final orderId = r.orderId ?? _pendingOrderId ?? '';
      final paymentId = r.paymentId ?? '';
      final signature = r.signature ?? '';
      if (planId == null ||
          orderId.isEmpty ||
          paymentId.isEmpty ||
          signature.isEmpty) {
        throw Exception('Incomplete response');
      }
      await _functions.httpsCallable('verifyAndActivateMembership').call({
        'planId': planId,
        'razorpayOrderId': orderId,
        'razorpayPaymentId': paymentId,
        'razorpaySignature': signature,
      });
      Get.snackbar('Membership active', 'Welcome to the arena! 💪');
      _onSuccess?.call();
    } on FirebaseFunctionsException catch (e) {
      Get.snackbar('Verification failed', e.message ?? 'Contact your gym if charged.');
    } catch (_) {
      Get.snackbar('Verification failed', 'Contact your gym if you were charged.');
    } finally {
      _pendingPlanId = null;
      _pendingOrderId = null;
      isProcessing.value = false;
    }
  }

  void _error(PaymentFailureResponse r) {
    _pendingPlanId = null;
    _pendingOrderId = null;
    isProcessing.value = false;
    final msg = (r.message ?? '').trim();
    Get.snackbar('Payment', msg.isEmpty ? 'Payment cancelled.' : msg);
  }
}
