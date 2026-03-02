/// 모바일용 Naver OAuth 로그인 서비스
/// InAppWebView를 사용하여 OAuth 콜백을 처리합니다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common.dart';
import 'auth_service.dart';
import 'session_service.dart';
import 'models.dart';
import '../../models/platform_model.dart';

/// Naver OAuth 로그인 결과
class MobileNaverAuthResult {
  final bool success;
  final String? error;
  final UserInfo? userInfo;

  MobileNaverAuthResult({
    required this.success,
    this.error,
    this.userInfo,
  });
}

/// 모바일용 Naver OAuth 서비스
class MobileNaverAuthService {
  final String _baseUrl;

  MobileNaverAuthService(this._baseUrl);

  /// Naver OAuth URL
  String get naverAuthUrl => '$_baseUrl/oauth2/authorization/naver';

  /// Naver 로그인 시작
  Future<MobileNaverAuthResult> login(BuildContext context) async {
    final completer = Completer<MobileNaverAuthResult>();

    try {
      // InAppWebView를 전체 화면 다이얼로그로 표시
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => _NaverLoginWebView(
            initialUrl: naverAuthUrl,
            onSuccess: (lt) async {
              // lt 토큰으로 pickup API 호출
              try {
                final authService = getAuthService();
                final pickupRes = await authService.pickup(lt);

                if (!pickupRes.success) {
                  completer.complete(MobileNaverAuthResult(
                    success: false,
                    error: 'Bad Request',
                  ));
                  return;
                }

                // 사용자 정보 조회
                final meRes = await authService.me();
                if (!meRes.success || meRes.data == null) {
                  completer.complete(MobileNaverAuthResult(
                    success: false,
                    error: 'Bad Request',
                  ));
                  return;
                }

                final userInfo = UserInfo.fromJson(meRes.data!);

                // 세션 등록 및 활성화
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
                      await Future.delayed(const Duration(milliseconds: 500));
                      final activateRes =
                          await sessionService.activateSession(deviceKey);
                      if (activateRes.success) {
                        userInfo.sessionKey = activateRes.extract('sessionKey');
                      }
                    }
                  }
                }

                // loginType을 naver(3)로 설정
                userInfo.loginType = 3;

                completer.complete(MobileNaverAuthResult(
                  success: true,
                  userInfo: userInfo,
                ));
              } catch (e) {
                debugPrint('[MobileNaverAuth] Pickup error: $e');
                completer.complete(MobileNaverAuthResult(
                  success: false,
                  error: 'Bad Request',
                ));
              }
            },
            onError: (error) {
              completer.complete(MobileNaverAuthResult(
                success: false,
                error: error,
              ));
            },
          ),
        ),
      );

      return await completer.future;
    } catch (e) {
      debugPrint('[MobileNaverAuth] Error: $e');
      return MobileNaverAuthResult(
        success: false,
        error: 'Bad Request',
      );
    }
  }
}

/// Naver 로그인 WebView 위젯
class _NaverLoginWebView extends StatefulWidget {
  final String initialUrl;
  final Function(String lt) onSuccess;
  final Function(String error) onError;

  const _NaverLoginWebView({
    required this.initialUrl,
    required this.onSuccess,
    required this.onError,
  });

  @override
  State<_NaverLoginWebView> createState() => _NaverLoginWebViewState();
}

class _NaverLoginWebViewState extends State<_NaverLoginWebView> {
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _clearCookies();
  }

  Future<void> _clearCookies() async {
    await CookieManager.instance().deleteAllCookies();
    debugPrint('[MobileNaverAuth] Cookies cleared');
  }

  static const Color _textColor = Color(0xFF454447);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: _textColor, size: 20),
          onPressed: () {
            if (!_isProcessing) {
              Navigator.of(context).pop();
              widget.onError('User cancelled');
            }
          },
        ),
        title: Text(
          translate('Cancel Login'),
          style: const TextStyle(
            color: _textColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(widget.initialUrl),
            ),
            initialSettings: InAppWebViewSettings(
              useShouldOverrideUrlLoading: true,
              javaScriptEnabled: true,
              useHybridComposition: true,
              userAgent: 'Mozilla/5.0 (Linux; Android 14; SM-S928B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
            ),
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final uri = navigationAction.request.url;

              debugPrint('[MobileNaverAuth] URL loading: $uri');

              // naverapp:// 스킴 처리 (네이버 앱 열기)
              if (uri != null && (uri.scheme == 'naverapp' || uri.scheme == 'naver')) {
                debugPrint('[MobileNaverAuth] Opening Naver app: $uri');
                try {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (e) {
                  debugPrint('[MobileNaverAuth] Failed to open Naver: $e');
                }
                return NavigationActionPolicy.CANCEL;
              }

              // intent:// 스킴 처리 (앱 설치 유도 등)
              if (uri != null && uri.scheme == 'intent') {
                debugPrint('[MobileNaverAuth] Intent scheme detected: $uri');
                // Play Store로 리다이렉트 시도
                final fallbackUrl = uri.queryParameters['browser_fallback_url'];
                if (fallbackUrl != null) {
                  await controller.loadUrl(urlRequest: URLRequest(url: WebUri(fallbackUrl)));
                }
                return NavigationActionPolicy.CANCEL;
              }

              // localhost:57403/auth 리다이렉트 감지
              if (uri != null &&
                  uri.host == 'localhost' &&
                  uri.port == 57403 &&
                  (uri.path == '/auth' || uri.path.startsWith('/auth'))) {
                final lt = uri.queryParameters['lt'];
                final error = uri.queryParameters['error'];

                debugPrint('[MobileNaverAuth] lt: $lt, error: $error');

                if (error != null) {
                  if (!_isProcessing) {
                    setState(() => _isProcessing = true);
                    Navigator.of(context).pop();
                    widget.onError(error);
                  }
                  return NavigationActionPolicy.CANCEL;
                }

                if (lt != null && lt.isNotEmpty) {
                  if (!_isProcessing) {
                    setState(() => _isProcessing = true);
                    await widget.onSuccess(lt);
                    if (mounted) {
                      Navigator.of(context).pop();
                    }
                  }
                  return NavigationActionPolicy.CANCEL;
                }
              }

              return NavigationActionPolicy.ALLOW;
            },
            onLoadStart: (controller, url) {
              setState(() => _isLoading = true);
            },
            onLoadStop: (controller, url) {
              setState(() => _isLoading = false);
            },
            onReceivedError: (controller, request, error) {
              debugPrint('[MobileNaverAuth] WebView error: $error');
            },
          ),
          if (_isLoading || _isProcessing)
            Container(
              color: Colors.white,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}

/// 전역 MobileNaverAuthService 인스턴스
MobileNaverAuthService? _mobileNaverAuthService;

/// MobileNaverAuthService 초기화
void initMobileNaverAuthService(String baseUrl) {
  _mobileNaverAuthService = MobileNaverAuthService(baseUrl);
}

/// MobileNaverAuthService 가져오기
MobileNaverAuthService getMobileNaverAuthService() {
  if (_mobileNaverAuthService == null) {
    throw StateError(
        'MobileNaverAuthService not initialized. Call initMobileNaverAuthService first.');
  }
  return _mobileNaverAuthService!;
}

/// MobileNaverAuthService 초기화 여부
bool isMobileNaverAuthServiceInitialized() => _mobileNaverAuthService != null;
