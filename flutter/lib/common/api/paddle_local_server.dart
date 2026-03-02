/// Paddle 결제를 위한 로컬 HTTP 서버
/// 결제 성공/취소 리디렉션 처리 및 주문 상태 폴링
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common/api/payment_service.dart';

/// Paddle 결제 결과
enum PaddlePaymentResult {
  success,
  cancel,
  error,
  timeout,
}

/// Paddle 로컬 서버 클래스
class PaddleLocalServer {
  // 서버 포트
  static const int _port = 47423;

  // HTTP 서버
  HttpServer? _server;

  // 결제 정보
  String? _orderId;

  // 폴링 관련
  Timer? _pollingTimer;
  bool _isPolling = false;

  // 결제 결과 콜백
  Function(PaddlePaymentResult, String?)? onPaymentResult;

  /// 서버 URL (성공 리디렉션용)
  String get successUrl => 'http://localhost:$_port/success';

  /// 서버 URL (취소 리디렉션용)
  String get cancelUrl => 'http://localhost:$_port/cancel';

  /// 성공 URL 패턴 (WebView에서 감지용)
  static const String successUrlPattern = 'http://localhost:$_port/success';

  /// 취소 URL 패턴 (WebView에서 감지용)
  static const String cancelUrlPattern = 'http://localhost:$_port/cancel';

  /// 결제 서버 시작 및 폴링 시작
  /// [orderId] - 서버에서 받은 주문 ID (폴링용)
  Future<void> startServer({
    required String orderId,
    required Function(PaddlePaymentResult, String?) onResult,
  }) async {
    // 기존 서버/폴링 먼저 중지 (값 설정 전에!)
    await stop();

    // 값 설정
    _orderId = orderId;
    onPaymentResult = onResult;

    try {
      // HTTP 서버 시작
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
      debugPrint('[PaddleLocalServer] Server started on port $_port');

      _server!.listen((HttpRequest request) {
        _handleRequest(request);
      });

      // 폴링 시작 (1초 간격, 최대 180초)
      _startPolling();
    } catch (e) {
      debugPrint('[PaddleLocalServer] Failed to start server: $e');
      rethrow;
    }
  }

  /// HTTP 요청 처리
  void _handleRequest(HttpRequest request) {
    final path = request.uri.path;
    debugPrint('[PaddleLocalServer] Request: $path');

    if (path == '/success') {
      // 성공 페이지 (WebView에서 감지)
      request.response
        ..headers.contentType = ContentType.html
        ..write(_buildSuccessHtml())
        ..close();

      // 결제 성공 콜백 (폴링에서 이미 처리될 수 있음)
      _notifyResult(PaddlePaymentResult.success, null);
    } else if (path == '/cancel') {
      // 취소 페이지 (WebView에서 감지)
      request.response
        ..headers.contentType = ContentType.html
        ..write(_buildCancelHtml())
        ..close();

      // 결제 취소 콜백
      _notifyResult(PaddlePaymentResult.cancel, null);
    } else {
      // 404
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not Found')
        ..close();
    }
  }

  /// 폴링 시작 (C# 코드와 동일한 로직)
  void _startPolling() {
    if (_isPolling) {
      debugPrint('[PaddleLocalServer] Already polling, skip');
      return;
    }
    _isPolling = true;

    int elapsedSeconds = 0;
    const maxSeconds = 180; // 3분

    debugPrint('[PaddleLocalServer] Starting order status polling...');
    debugPrint('[PaddleLocalServer] orderId=$_orderId, callback=${onPaymentResult != null ? "set" : "NULL"}');

    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      elapsedSeconds++;

      if (elapsedSeconds > maxSeconds) {
        debugPrint('[PaddleLocalServer] Polling timeout after $maxSeconds seconds');
        timer.cancel();
        _isPolling = false;
        _notifyResult(PaddlePaymentResult.timeout, 'Polling timeout');
        return;
      }

      // 주문 상태 확인
      try {
        final status = await _checkOrderStatus();
        debugPrint('[PaddleLocalServer] Poll #$elapsedSeconds - Status: $status');

        if (status == 'PAID' || status == 'ACTIVE' || status == 'COMPLETED') {
          debugPrint('[PaddleLocalServer] Payment confirmed!');
          timer.cancel();
          _isPolling = false;
          _notifyResult(PaddlePaymentResult.success, status);
        } else if (status == 'CANCELLED') {
          // 취소는 에러가 아닌 취소로 처리 (결제창으로 돌아감)
          debugPrint('[PaddleLocalServer] Payment cancelled');
          timer.cancel();
          _isPolling = false;
          _notifyResult(PaddlePaymentResult.cancel, status);
        } else if (status == 'FAILED' || status == 'EXPIRED') {
          debugPrint('[PaddleLocalServer] Payment failed: $status');
          timer.cancel();
          _isPolling = false;
          _notifyResult(PaddlePaymentResult.error, status);
        }
        // PENDING 상태면 계속 폴링
      } catch (e) {
        debugPrint('[PaddleLocalServer] Polling error: $e');
        // 에러가 나도 계속 폴링 시도
      }
    });
  }

  /// 주문 상태 확인 API 호출
  Future<String?> _checkOrderStatus() async {
    if (_orderId == null || _orderId!.isEmpty) {
      debugPrint('[PaddleLocalServer] _orderId is null or empty');
      return null;
    }

    try {
      final paymentService = getPaymentService();
      final response = await paymentService.getPaddleOrderState(
        _orderId!,
        PaymentType.subscription,
      );

      debugPrint('[PaddleLocalServer] API response: success=${response.success}, data=${response.data}');

      if (response.success) {
        // 상태 추출 (여러 가능한 키 시도)
        final status = response.extract('status')
            ?? response.extract('state')
            ?? response.extract('orderStatus')
            ?? response.extract('paymentStatus');
        debugPrint('[PaddleLocalServer] Extracted status: $status');
        return status?.toUpperCase();
      } else {
        debugPrint('[PaddleLocalServer] API failed: ${response.message}');
      }
    } catch (e, stackTrace) {
      debugPrint('[PaddleLocalServer] Check status error: $e');
      debugPrint('[PaddleLocalServer] Stack trace: $stackTrace');
    }
    return null;
  }

  /// 결과 알림
  void _notifyResult(PaddlePaymentResult result, String? details) {
    // 이미 결과가 통보되었으면 무시
    if (onPaymentResult == null) return;

    final callback = onPaymentResult;
    onPaymentResult = null; // 중복 호출 방지

    callback?.call(result, details);
  }

  /// 성공 HTML 빌드
  String _buildSuccessHtml() {
    return '''
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>결제 완료</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 16px;
            text-align: center;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
        }
        .icon {
            font-size: 64px;
            margin-bottom: 20px;
        }
        h1 {
            color: #22c55e;
            margin: 0 0 10px 0;
        }
        p {
            color: #666;
            margin: 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon">✓</div>
        <h1>결제가 완료되었습니다</h1>
        <p>잠시 후 자동으로 창이 닫힙니다...</p>
    </div>
</body>
</html>
''';
  }

  /// 취소 HTML 빌드
  String _buildCancelHtml() {
    return '''
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>결제 취소</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: #f5f5f5;
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 16px;
            text-align: center;
            box-shadow: 0 4px 20px rgba(0,0,0,0.1);
        }
        .icon {
            font-size: 64px;
            margin-bottom: 20px;
        }
        h1 {
            color: #ef4444;
            margin: 0 0 10px 0;
        }
        p {
            color: #666;
            margin: 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon">✗</div>
        <h1>결제가 취소되었습니다</h1>
        <p>창을 닫고 다시 시도해주세요.</p>
    </div>
</body>
</html>
''';
  }

  /// 서버 및 폴링 중지
  Future<void> stop() async {
    // 폴링 중지
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isPolling = false;

    // 서버 중지
    if (_server != null) {
      debugPrint('[PaddleLocalServer] Stopping server...');
      await _server!.close(force: true);
      _server = null;
    }

    // 상태 초기화
    _orderId = null;
    onPaymentResult = null;
  }

  /// 성공 URL인지 확인
  static bool isSuccessUrl(String url) {
    return url.contains('/success') || url.contains('localhost:$_port/success');
  }

  /// 취소 URL인지 확인
  static bool isCancelUrl(String url) {
    return url.contains('/cancel') || url.contains('localhost:$_port/cancel');
  }
}
