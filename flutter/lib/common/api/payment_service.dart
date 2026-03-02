/// 결제 서비스
/// 가격 조회, 주문 생성, 결제 승인, 빌링키 발급, PayPal, Paddle 결제 등
library;

import 'api_client.dart';
import 'models.dart';

/// 결제 타입
enum PaymentType {
  oneTime,
  subscription,
}

/// 결제 서비스 클래스
class PaymentService {
  final ApiClient _api;

  PaymentService(this._api);

  /// 가격 조회
  Future<ApiResponse> getPrice() async {
    return await _api.postJson('api/products/list');
  }

  /// 주문 생성
  Future<ApiResponse> createOrder(String productCode) async {
    return await _api.postJson('api/payments/orders', data: {
      'productCode': productCode,
    });
  }

  /// 결제 승인
  Future<ApiResponse> confirmPayment(String paymentKey, String orderId) async {
    return await _api.postJson('api/payments/confirm', data: {
      'paymentKey': paymentKey,
      'orderId': orderId,
    });
  }

  /// 플랜 목록 조회
  Future<ApiResponse> getPlanList() async {
    return await _api.get('api/products/list');
  }

  /// 빌링키 발급
  Future<ApiResponse> issueBilling(String authKey, String customerKey) async {
    return await _api.postJson('api/payments/billing/issue', data: {
      'authKey': authKey,
      'customerKey': customerKey,
    });
  }

  /// 구독 취소
  Future<ApiResponse> cancelSubscription() async {
    return await _api.postJson('api/payments/billing/cancel');
  }

  // ===========================
  // Smartro 메서드들
  // ===========================

  /// Smartro 주문 생성
  Future<ApiResponse> createSmartroOrder(String productCode) async {
    return await _api.postJson('api/payments/smartro/orders', data: {
      'productCode': productCode.toUpperCase(),
    });
  }

  // ===========================
  // Welcome (토스페이먼츠) 메서드들
  // ===========================

  /// Welcome 주문 생성
  Future<ApiResponse> createWelcomeOrder(int addonUnitPrice, int addonCount) async {
    return await _api.postJson('api/payments/welcome/orders', data: {
      'addonUnitPrice': addonUnitPrice,
      'addonCount': addonCount,
    });
  }

  /// Welcome 빌링 파라미터 발급
  Future<ApiResponse> createWelcomeBilling(String productCode) async {
    return await _api
        .postJson('api/payments/welcome/billing/issue-params', data: {
      'productCode': productCode.toUpperCase(),
    });
  }

  // ===========================
  // PayPal 전용 메서드들
  // ===========================

  /// PayPal 주문 생성 (일회성 결제)
  Future<ApiResponse> createPayPalOrder(String productCode) async {
    return await _api.postJson('api/paypal/order', data: {
      'productCode': productCode.toUpperCase(),
    });
  }

  /// PayPal 결제 캡처
  Future<ApiResponse> capturePayPalPayment(
      String ourOrderId, String paypalOrderId) async {
    return await _api.postJson('api/paypal/order/capture', data: {
      'ourOrderId': ourOrderId,
      'paypalOrderId': paypalOrderId,
    });
  }

  Future<ApiResponse> createPayPalSubscription(String productCode) async {
    return await _api.postJson('api/paypal/subscription/create', data: {
      'productCode': productCode.toUpperCase(),
    });
  }

  /// PayPal 구독 활성화
  Future<ApiResponse> activatePayPalSubscription(String subscriptionId) async {
    return await _api.postJson('api/paypal/subscription/activate', data: {
      'subscriptionId': subscriptionId,
    });
  }

  // ===========================
  // Paddle 전용 메서드들
  // ===========================

  /// Paddle 체크아웃 생성 (결제 타입 지정)
  Future<ApiResponse> createPaddleCheckoutWithType(
      String productCode, PaymentType paymentType) async {
    return await _api.postJson('api/paddle/checkout', data: {
      'productCode': productCode.toUpperCase(),
      'paymentType':
          paymentType == PaymentType.oneTime ? 'oneTime' : 'subscription',
    });
  }

  /// Paddle 체크아웃 생성 (단순)
  Future<ApiResponse> createPaddleCheckout(String productCode) async {
    return await _api.postJson('api/paddle/order', data: {
      'productCode': productCode.toUpperCase(),
    });
  }

  /// Paddle 주문 상태 조회
  Future<ApiResponse> getPaddleOrderState(
      String orderId, PaymentType paymentType) async {
    if (paymentType == PaymentType.oneTime) {
      return await _api.get('api/paddle/orders/$orderId');
    } else {
      return await _api.get('api/paddle/subscription/orders/$orderId');
    }
  }

  /// Paddle 구독 체크아웃 생성
  Future<ApiResponse> createPaddleSubCheckout(String productCode) async {
    return await _api.postJson('api/paddle/subscription/checkout', data: {
      'productCode': productCode.toUpperCase(),
    });
  }
}

/// 전역 PaymentService 인스턴스 (나중에 초기화)
PaymentService? _globalPaymentService;

/// 전역 PaymentService 가져오기
PaymentService getPaymentService() {
  if (_globalPaymentService == null) {
    throw StateError(
        'PaymentService not initialized. Call initPaymentService() first.');
  }
  return _globalPaymentService!;
}

/// PaymentService 초기화
PaymentService initPaymentService(ApiClient apiClient) {
  _globalPaymentService = PaymentService(apiClient);
  return _globalPaymentService!;
}

/// PaymentService 설정 여부 확인
bool isPaymentServiceInitialized() {
  return _globalPaymentService != null;
}
