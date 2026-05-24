import 'package:flutter/foundation.dart';

/// Abstract base class for payment gateway integrations.
///
/// Future gateways (Billplz, ToyyibPay, Stripe, FPX, DuitNow)
/// should extend this class and override the methods.
abstract class PaymentService {
  /// Initialize the payment gateway SDK/session.
  Future<bool> initializePayment(Map<String, dynamic> params);

  /// Create a payment intent / invoice.
  Future<Map<String, dynamic>> createPaymentIntent({
    required double amount,
    required String currency,
    required String description,
    String? customerId,
  });

  /// Verify payment status from gateway callback.
  Future<bool> verifyPayment(String paymentId);

  /// Handle payment gateway callback response.
  Future<Map<String, dynamic>> handlePaymentCallback(
    Map<String, dynamic> callbackData,
  );

  /// Cancel/refund a payment.
  Future<bool> cancelPayment(String paymentId);
}

/// Mock payment service for development and testing.
///
/// Simulates a successful payment flow without any real gateway.
/// Replace with real implementations (BillplzPaymentService,
/// ToyyibPayPaymentService, etc.) when integrating real payments.
class MockPaymentService implements PaymentService {
  @override
  Future<bool> initializePayment(Map<String, dynamic> params) async {
    debugPrint('[MockPayment] Initializing payment...');
    await Future.delayed(const Duration(milliseconds: 500));
    debugPrint('[MockPayment] Payment initialized successfully');
    return true;
  }

  @override
  Future<Map<String, dynamic>> createPaymentIntent({
    required double amount,
    required String currency,
    required String description,
    String? customerId,
  }) async {
    debugPrint('[MockPayment] Creating payment intent: $description - RM$amount');
    await Future.delayed(const Duration(milliseconds: 800));
    return {
      'success': true,
      'paymentId': 'mock_pay_${DateTime.now().millisecondsSinceEpoch}',
      'amount': amount,
      'currency': currency,
      'status': 'success',
      'description': description,
    };
  }

  @override
  Future<bool> verifyPayment(String paymentId) async {
    debugPrint('[MockPayment] Verifying payment: $paymentId');
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  @override
  Future<Map<String, dynamic>> handlePaymentCallback(
    Map<String, dynamic> callbackData,
  ) async {
    debugPrint('[MockPayment] Handling callback: $callbackData');
    return {
      'success': true,
      'status': 'completed',
    };
  }

  @override
  Future<bool> cancelPayment(String paymentId) async {
    debugPrint('[MockPayment] Cancelling payment: $paymentId');
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  /// Singleton instance for app-wide use.
  static final MockPaymentService instance = MockPaymentService._();
  MockPaymentService._();
}
