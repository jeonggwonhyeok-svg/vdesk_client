/// 인증 서비스
/// 회원가입, 로그인, 로그아웃, 이메일 인증, 비밀번호 재설정 등
library;

import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'models.dart';

/// 인증 서비스 클래스
class AuthService {
  final ApiClient _api;

  AuthService(this._api);

  /// 기본 URL
  String get baseUrl => _api.baseUrl;

  /// IP 확인 및 한국 여부 체크
  Future<bool> checkIsKorea() async {
    try {
      // ip-api.com 사용 (ipapi.co는 rate limit 문제)
      final locationResponse = await _api.get('http://ip-api.com/json/');
      debugPrint('[AuthService] locationResponse: ${locationResponse.success}, data: ${locationResponse.data}');
      if (!locationResponse.success) return false;

      final countryCode = locationResponse.extract('countryCode');
      debugPrint('[AuthService] countryCode: $countryCode, isKorea: ${countryCode?.toUpperCase() == 'KR'}');
      return countryCode?.toUpperCase() == 'KR';
    } catch (e) {
      debugPrint('[AuthService] checkIsKorea error: $e');
      return false;
    }
  }

  /// 회원가입
  Future<ApiResponse> signup(String userName, String email, String password,
      String confirmPassword) async {
    return await _api.postJson('api/auth/signup', data: {
      'userName': userName,
      'email': email,
      'password': password,
      'confirmPassword': confirmPassword,
    });
  }

  /// 로그인
  Future<ApiResponse> login(String email, String password) async {
    return await _api.postJson('api/auth/login', data: {
      'email': email,
      'password': password,
    });
  }

  /// 박스명 생성 (암호화)
  Future<ApiResponse> generateBox(String boxName) async {
    return await _api.postJson('api/devices/register/encrypt', data: {
      'encryptLocalBox': boxName,
    });
  }

  /// 쿠키 픽업 (Google OAuth 콜백 처리)
  Future<ApiResponse> pickup(String lt) async {
    return await _api.postJson('api/auth/cookie/pickup', data: {
      'lt': lt,
    });
  }

  /// 로그아웃
  Future<ApiResponse> logout() async {
    return await _api.postJson('api/auth/logout');
  }

  /// 사용자 정보 조회 (me)
  Future<ApiResponse> me() async {
    return await _api.get('api/auth/me');
  }

  /// 이메일 인증코드 발송
  Future<ApiResponse> sendVerificationEmail(String email) async {
    return await _api.postJson('api/auth/email/verification', data: {
      'email': email,
    });
  }

  /// 이메일 인증코드 검증
  Future<ApiResponse> verifyEmailCode(String email, String code) async {
    return await _api.postJson('api/auth/email/verify', data: {
      'email': email,
      'code': code,
    });
  }

  /// 비밀번호 재설정/변경
  Future<ApiResponse> resetPassword(String email, String userName,
      String password, String confirmPassword) async {
    return await _api.postJson('api/auth/password/reset', data: {
      'email': email,
      'userName': userName,
      'password': password,
      'confirmPassword': confirmPassword,
    });
  }

  /// 이메일 중복 확인
  Future<ApiResponse> checkEmailDuplicate(String email) async {
    return await _api.postJson('api/auth/duplications/email', data: {
      'email': email,
    });
  }

  /// 박스명 가져오기 (유료 사용자용)
  Future<ApiResponse> getBoxName(String version, {required String deviceId, String? deviceName}) async {
    return await _api.postJson('api/devices/register/paid', data: {
      'localBox': deviceId,
      'deviceName': deviceName ?? deviceId,
      'deviceId': deviceId,
      'deviceVersion': version,
    });
  }

  /// 구독 취소
  Future<ApiResponse> cancelSubscription() async {
    return await _api.postJson('api/payments/billing/cancel');
  }

  /// 회원 탈퇴
  Future<ApiResponse> signOut(String password) async {
    return await _api.postJson('api/auth/withdraw', data: {
      'password': password,
    });
  }

  /// 광고 상품 목록 가져오기
  Future<ApiResponse> getAdProductList() async {
    return await _api.postJson('api/ad/list');
  }

  // ===========================
  // 구독 재개 메서드들
  // ===========================

  /// Welcome 구독 재개
  Future<ApiResponse> resumeWelcomeSub() async {
    return await _api.postJson('api/payments/welcome/billing/resume');
  }

  /// Paddle 구독 재개
  Future<ApiResponse> resumePaddleSub() async {
    return await _api.postJson('api/paddle/subscription/uncancel');
  }

  /// PayPal 구독 재개
  Future<ApiResponse> resumePaypalSub() async {
    return await _api.postJson('api/paypal/subscription/uncancel');
  }

  // ===========================
  // 구독 취소 메서드들
  // ===========================

  /// Welcome 구독 취소
  Future<ApiResponse> cancelWelcomeSub() async {
    return await _api.postJson('api/payments/welcome/billing/cancel');
  }

  /// PayPal 구독 취소
  Future<ApiResponse> cancelPaypalSub({String reason = '사용자 해지'}) async {
    return await _api.postJson('api/paypal/subscription/cancel', data: {
      'reason': reason,
    });
  }

  /// Paddle 구독 취소
  Future<ApiResponse> cancelPaddleSub({String reason = '사용자 해지'}) async {
    return await _api.postJson('api/paddle/subscription/cancel', data: {
      'reason': reason,
    });
  }

  // ===========================
  // 통계 메서드들
  // ===========================

  /// 광고 노출 카운트
  Future<ApiResponse> setCountAdShow(
      String sessionKey, String deviceKey) async {
    return await _api.postJson('api/stats/ads/impression', data: {
      'sessionKey': sessionKey,
      'deviceKey': deviceKey,
    });
  }

  /// 광고 클릭 카운트
  Future<ApiResponse> setCountAdClick(
      String sessionKey, String deviceKey, String clickedUrl) async {
    return await _api.postJson('api/stats/ads/click', data: {
      'sessionKey': sessionKey,
      'deviceKey': deviceKey,
      'clickedUrl': clickedUrl,
    });
  }

  /// 결제 시도 카운트
  Future<ApiResponse> setCountPayClick(
      String provider, String productCode, String orderId) async {
    return await _api.postJson('api/stats/payments/attempt', data: {
      'provider': provider,
      'productCode': productCode,
      'orderId': orderId,
    });
  }
}

/// 전역 AuthService 인스턴스 (나중에 초기화)
AuthService? _globalAuthService;

/// 전역 AuthService 가져오기
AuthService getAuthService() {
  if (_globalAuthService == null) {
    throw StateError(
        'AuthService not initialized. Call initAuthService() first.');
  }
  return _globalAuthService!;
}

/// AuthService 초기화
AuthService initAuthService(ApiClient apiClient) {
  _globalAuthService = AuthService(apiClient);
  return _globalAuthService!;
}

/// AuthService 설정 여부 확인
bool isAuthServiceInitialized() {
  return _globalAuthService != null;
}
