/// Kakao OAuth 로그인 서비스 (데스크톱)
/// 로컬 HTTP 서버를 사용하여 OAuth 콜백을 처리합니다.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_service.dart';
import 'session_service.dart';
import 'models.dart';
import '../../models/platform_model.dart';

/// Kakao OAuth 로그인 결과
class KakaoAuthResult {
  final bool success;
  final String? error;
  final UserInfo? userInfo;

  KakaoAuthResult({
    required this.success,
    this.error,
    this.userInfo,
  });
}

/// Kakao OAuth 서비스 (데스크톱)
class KakaoAuthService {
  static const int _port = 57403;
  static const String _callbackPath = '/auth/';
  static const Duration _timeout = Duration(seconds: 60);

  HttpServer? _server;
  final String _baseUrl;

  KakaoAuthService(this._baseUrl);

  /// Kakao OAuth URL
  String get kakaoAuthUrl => '$_baseUrl/oauth2/authorization/kakao';

  /// 콜백 URL
  String get callbackUrl => 'http://localhost:$_port$_callbackPath';

  /// Kakao 로그인 시작
  Future<KakaoAuthResult> login() async {
    try {
      // 1. 로컬 HTTP 서버 시작
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
      debugPrint('[KakaoAuth] Local server started on port $_port');

      // 2. 브라우저에서 Kakao OAuth 페이지 열기
      final uri = Uri.parse(kakaoAuthUrl);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await _stopServer();
        return KakaoAuthResult(
          success: false,
          error: 'Bad Request',
        );
      }

      // 3. 콜백 대기 (타임아웃 포함)
      final result = await _waitForCallback().timeout(
        _timeout,
        onTimeout: () {
          debugPrint('[KakaoAuth] Timeout waiting for callback');
          return KakaoAuthResult(
            success: false,
            error: 'Bad Request',
          );
        },
      );

      return result;
    } catch (e) {
      debugPrint('[KakaoAuth] Error: $e');
      return KakaoAuthResult(
        success: false,
        error: 'Bad Request',
      );
    } finally {
      await _stopServer();
    }
  }

  /// 콜백 대기
  Future<KakaoAuthResult> _waitForCallback() async {
    final completer = Completer<KakaoAuthResult>();

    _server!.listen((request) async {
      final path = request.uri.path;

      debugPrint('[KakaoAuth] ========================================');
      debugPrint('[KakaoAuth] 콜백 요청 수신');
      debugPrint('[KakaoAuth] 전체 URI: ${request.uri}');
      debugPrint('[KakaoAuth] Path: $path');
      debugPrint('[KakaoAuth] Query String: ${request.uri.query}');
      debugPrint(
          '[KakaoAuth] Query Parameters: ${request.uri.queryParameters}');
      debugPrint('[KakaoAuth] ========================================');

      // favicon.ico 등 관계없는 요청 무시
      if (path == '/favicon.ico' || path == '/robots.txt') {
        debugPrint('[KakaoAuth] 무시하는 요청: $path');
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
        return;
      }

      // lt 토큰 추출
      final lt = request.uri.queryParameters['lt'];
      final error = request.uri.queryParameters['error'];

      debugPrint('[KakaoAuth] 추출된 lt: "$lt"');
      debugPrint('[KakaoAuth] 추출된 error: "$error"');

      // HTML 응답 전송
      final html = '''
<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>Kakao Login</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: #fff;
        }
        .container {
            text-align: center;
            background: white;
            padding: 40px 60px;
            border-radius: 16px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
        }
        h2 {
            color: #333;
            margin-bottom: 10px;
        }
        p {
            color: #666;
            font-size: 14px;
        }
        .success { color: #FEE500; }
        .error { color: #f44336; }
    </style>
</head>
<body>
    <div class="container">
        ${error != null ? '<h2 class="error">로그인 실패</h2><p>$error</p>' : '<h2 class="success">로그인 성공</h2><p>창을 닫아도 됩니다.</p>'}
    </div>
    <script>
        setTimeout(() => {
            try { window.close(); } catch(e) {}
        }, 2000);
    </script>
</body>
</html>
''';

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(html);
      await request.response.close();

      // 에러 체크
      if (error != null) {
        if (!completer.isCompleted) {
          completer.complete(KakaoAuthResult(
            success: false,
            error: error,
          ));
        }
        return;
      }

      // lt 토큰 체크
      if (lt == null || lt.isEmpty) {
        debugPrint('[KakaoAuth] lt 토큰이 없음! URI: ${request.uri}');
        if (!completer.isCompleted) {
          completer.complete(KakaoAuthResult(
            success: false,
            error: 'Bad Request',
          ));
        }
        return;
      }

      // 4. pickup API 호출
      try {
        final authService = getAuthService();
        final pickupRes = await authService.pickup(lt);

        if (!pickupRes.success) {
          if (!completer.isCompleted) {
            completer.complete(KakaoAuthResult(
              success: false,
              error: 'Bad Request',
            ));
          }
          return;
        }

        // 5. 사용자 정보 조회
        final meRes = await authService.me();
        if (!meRes.success || meRes.data == null) {
          if (!completer.isCompleted) {
            completer.complete(KakaoAuthResult(
              success: false,
              error: 'Bad Request',
            ));
          }
          return;
        }

        final userInfo = UserInfo.fromJson(meRes.data!);

        // 6. 세션 등록 및 활성화
        if (isSessionServiceInitialized()) {
          final sessionService = getSessionService();
          final version = await bind.mainGetVersion();

          final registerRes =
              await sessionService.registerSession(
                version,
                deviceId: platformFFI.deviceId,
                deviceName: platformFFI.deviceName,
              );
          if (registerRes.success) {
            final deviceKey = registerRes.extract('deviceKey') ?? '';
            userInfo.deviceKey = deviceKey;

            if (deviceKey.isNotEmpty) {
              // 세션 활성화 (약간의 딜레이 추가 - 서버 동기화 대기)
              await Future.delayed(const Duration(milliseconds: 500));
              final activateRes =
                  await sessionService.activateSession(deviceKey);
              if (activateRes.success) {
                userInfo.sessionKey = activateRes.extract('sessionKey');
              }
            }
          }
        }

        // loginType을 kakao(2)로 설정
        userInfo.loginType = 2;

        if (!completer.isCompleted) {
          completer.complete(KakaoAuthResult(
            success: true,
            userInfo: userInfo,
          ));
        }
      } catch (e) {
        debugPrint('[KakaoAuth] Pickup error: $e');
        if (!completer.isCompleted) {
          completer.complete(KakaoAuthResult(
            success: false,
            error: 'Bad Request',
          ));
        }
      }
    });

    return completer.future;
  }

  /// 서버 중지
  Future<void> _stopServer() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      debugPrint('[KakaoAuth] Local server stopped');
    }
  }

  /// 로그인 취소
  Future<void> cancel() async {
    await _stopServer();
  }
}

/// 전역 KakaoAuthService 인스턴스
KakaoAuthService? _kakaoAuthService;

/// KakaoAuthService 초기화
void initKakaoAuthService(String baseUrl) {
  _kakaoAuthService = KakaoAuthService(baseUrl);
}

/// KakaoAuthService 가져오기
KakaoAuthService getKakaoAuthService() {
  if (_kakaoAuthService == null) {
    throw StateError(
        'KakaoAuthService not initialized. Call initKakaoAuthService first.');
  }
  return _kakaoAuthService!;
}

/// KakaoAuthService 초기화 여부
bool isKakaoAuthServiceInitialized() => _kakaoAuthService != null;
