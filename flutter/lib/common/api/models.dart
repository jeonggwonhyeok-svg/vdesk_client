/// API 응답 및 데이터 모델 정의
library;

import 'dart:convert';

/// API 응답 래퍼 클래스
class ApiResponse {
  final bool success;
  final String? message;
  final Map<String, dynamic>? data;
  final String rawBody;
  final int statusCode;

  ApiResponse({
    required this.success,
    this.message,
    this.data,
    required this.rawBody,
    this.statusCode = 0,
  });

  /// JSON 문자열에서 ApiResponse 생성
  factory ApiResponse.fromRawBody(String body, {int statusCode = 200}) {
    bool success = false;
    String? message;
    Map<String, dynamic>? data;

    try {
      // HTTP 2xx 상태 코드는 기본적으로 성공
      if (statusCode >= 200 && statusCode < 300) {
        success = true;
      }

      // 한국어 응답 메시지 기반 성공 여부 판단
      if (body.contains('성공') || body.contains('사용가능')) {
        success = true;
      }

      // JSON 파싱 시도
      if (body.startsWith('{') || body.startsWith('[')) {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          // result 필드가 있으면 그 내용을 data로 사용
          if (decoded.containsKey('result') && decoded['result'] is Map<String, dynamic>) {
            data = decoded['result'] as Map<String, dynamic>;
          } else {
            data = decoded;
          }
          message = decoded['message']?.toString();

          // 에러 필드가 있으면 실패로 판단
          if (decoded.containsKey('error') && decoded['error'] != null) {
            success = false;
          }

          // 상태 코드로 성공 여부 판단
          if (decoded.containsKey('status') || decoded.containsKey('code')) {
            final status = decoded['status'] ?? decoded['code'];
            if (status == 200 || status == '200') {
              success = true;
            } else if (status == 404 || status == '404' || status == 401 || status == '401') {
              success = false;
            }
          }
        }
      }
    } catch (e) {
      // JSON 파싱 실패 시
      success = false;
    }

    // 실패 시 통일된 에러 메시지 사용 (번역키)
    if (!success) {
      message = 'Bad Request';
    }

    return ApiResponse(
      success: success,
      message: message,
      data: data,
      rawBody: body,
      statusCode: statusCode,
    );
  }

  /// 특정 키의 값 추출
  String? extract(String key) {
    if (data == null) return null;
    return data![key]?.toString();
  }

  /// 에러 응답 생성
  factory ApiResponse.error(String errorMessage) {
    return ApiResponse(
      success: false,
      message: 'Bad Request',
      data: null,
      rawBody: 'ERROR: $errorMessage',
      statusCode: -1,
    );
  }

  @override
  String toString() {
    return 'ApiResponse(success: $success, statusCode: $statusCode, message: $message, rawBody: $rawBody)';
  }
}

/// 사용자 정보 모델
class UserInfo {
  String email;
  String? nick;
  int type; // 1=FREE, 2=SOLO/PRO, 3=TEAM/BUSINESS
  int loginType; // 0=email, 1=google
  String? lastPay; // 결제 일시 (paidAt)
  String? deviceKey;
  String? sessionKey;
  String? password;
  String? planType; // 플랜 타입 문자열 (FREE, SOLO, PRO, TEAM, BUSINESS)
  String? billingProvider; // 빌링 결제 타입 (WELCOME, PAYPAL, PADDLE)
  String? paymentStatus; // 결제 상태 (ACTIVE, CANCELLED, PAUSED, EXPIRED, FAILED)
  String? nextChargeDate; // 다음 결제 일시
  int connectionCount; // 동시 접속 가능 수

  UserInfo({
    required this.email,
    this.nick,
    this.type = 1,
    this.loginType = 0,
    this.lastPay,
    this.deviceKey,
    this.sessionKey,
    this.password,
    this.planType,
    this.billingProvider,
    this.paymentStatus,
    this.nextChargeDate,
    this.connectionCount = 1,
  });

  /// 서버 planType 정규화 (SOLO_PLAN → SOLO, PRO_PLAN → PRO 등)
  static String _normalizePlanType(dynamic value) {
    if (value == null) return 'FREE';
    final str = value.toString().toUpperCase();
    // _PLAN 접미사 제거
    if (str.endsWith('_PLAN')) {
      return str.replaceAll('_PLAN', '');
    }
    return str;
  }

  /// JSON에서 UserInfo 생성
  factory UserInfo.fromJson(Map<String, dynamic> json) {
    int type = 1;
    final planTypeStr = json['planType'] as String?;
    switch (planTypeStr) {
      case 'FREE':
        type = 1;
        break;
      case 'PERSONAL':
        type = 2;
        break;
      case 'ENTERPRISE':
        type = 3;
        break;
    }

    // 날짜 파싱 헬퍼
    String? parseDate(dynamic value) {
      if (value == null) return null;
      final str = value.toString();
      if (str.contains('T')) {
        return str.split('T')[0];
      }
      return str;
    }

    return UserInfo(
      email: json['email'] ?? '',
      nick: json['userName'],
      type: type,
      loginType: _parseLoginType(json['loginType']),
      lastPay: parseDate(json['paidAt']) ?? parseDate(json['createdAt']),
      deviceKey: json['deviceKey'],
      sessionKey: json['sessionKey'],
      planType: _normalizePlanType(json['planType']),
      billingProvider: json['billingProvider'],
      paymentStatus: json['paymentStatus'],
      nextChargeDate: parseDate(json['nextChargeDate']),
      connectionCount: json['connectionCount'] ?? ((json['planSessionCount'] ?? 0) + (json['addonSessionCount'] ?? 0)).clamp(1, 9999),
    );
  }

  /// UserInfo를 JSON으로 변환
  Map<String, dynamic> toJson() {
    final planTypeValue = planType ?? (type == 2 ? 'PERSONAL' : (type == 3 ? 'ENTERPRISE' : 'FREE'));

    return {
      'email': email,
      'nick': nick,
      'planType': planTypeValue,
      'loginType': _loginTypeToString(loginType),
      'lastPay': lastPay,
      'deviceKey': deviceKey,
      'sessionKey': sessionKey,
      'billingProvider': billingProvider,
      'paymentStatus': paymentStatus,
      'nextChargeDate': nextChargeDate,
      'connectionCount': connectionCount,
    };
  }

  /// 플랜 타입 문자열
  String get planTypeString {
    switch (type) {
      case 2:
        return 'PERSONAL';
      case 3:
        return 'ENTERPRISE';
      default:
        return 'FREE';
    }
  }

  /// 로그인 타입 문자열
  String get loginTypeString => _loginTypeToString(loginType);

  /// 일반(이메일) 로그인인지 여부
  bool get isNormalLogin => loginType == 0;

  static int _parseLoginType(dynamic value) {
    if (value == null) return 0;
    final str = value.toString().toLowerCase();
    switch (str) {
      case 'google': return 1;
      case 'kakao': return 2;
      case 'naver': return 3;
      default: return 0; // normal, email 등
    }
  }

  static String _loginTypeToString(int type) {
    switch (type) {
      case 1: return 'google';
      case 2: return 'kakao';
      case 3: return 'naver';
      default: return 'normal';
    }
  }
}

/// 세션 정보 모델
class SessionInfo {
  final String sessionKey;
  final String deviceKey;
  final String deviceName;
  final String? deviceVersion;
  final DateTime? createdAt;
  final DateTime? lastActiveAt;

  SessionInfo({
    required this.sessionKey,
    required this.deviceKey,
    required this.deviceName,
    this.deviceVersion,
    this.createdAt,
    this.lastActiveAt,
  });

  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    return SessionInfo(
      sessionKey: json['sessionKey'] ?? '',
      deviceKey: json['deviceKey'] ?? '',
      deviceName: json['deviceName'] ?? '',
      deviceVersion: json['deviceVersion'],
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,
      lastActiveAt: json['lastActiveAt'] != null
          ? DateTime.tryParse(json['lastActiveAt'])
          : null,
    );
  }
}

/// 상품/플랜 정보 모델
class ProductInfo {
  final String code;
  final String name;
  final int price;
  final String currency;
  final String? description;
  final int? durationDays;

  ProductInfo({
    required this.code,
    required this.name,
    required this.price,
    this.currency = 'KRW',
    this.description,
    this.durationDays,
  });

  factory ProductInfo.fromJson(Map<String, dynamic> json) {
    return ProductInfo(
      code: json['code'] ?? json['productCode'] ?? '',
      name: json['name'] ?? '',
      price: json['price'] ?? 0,
      currency: json['currency'] ?? 'KRW',
      description: json['description'],
      durationDays: json['durationDays'],
    );
  }
}

/// 주문 정보 모델
class OrderInfo {
  final String orderId;
  final String? orderName;
  final int amount;
  final String? customerKey;
  final String? status;

  OrderInfo({
    required this.orderId,
    this.orderName,
    required this.amount,
    this.customerKey,
    this.status,
  });

  factory OrderInfo.fromJson(Map<String, dynamic> json) {
    return OrderInfo(
      orderId: json['orderId'] ?? '',
      orderName: json['orderName'],
      amount: json['amount'] ?? 0,
      customerKey: json['customerKey'],
      status: json['status'],
    );
  }
}
