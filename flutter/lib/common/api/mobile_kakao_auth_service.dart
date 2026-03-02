/// 모바일용 Kakao OAuth 로그인 서비스
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

/// Kakao OAuth 로그인 결과
class MobileKakaoAuthResult {
  final bool success;
  final String? error;
  final UserInfo? userInfo;

  MobileKakaoAuthResult({
    required this.success,
    this.error,
    this.userInfo,
  });
}

/// 모바일용 Kakao OAuth 서비스
class MobileKakaoAuthService {
  final String _baseUrl;

  MobileKakaoAuthService(this._baseUrl);

  /// Kakao OAuth URL
  String get kakaoAuthUrl => '$_baseUrl/oauth2/authorization/kakao';

  /// Kakao 로그인 시작
  Future<MobileKakaoAuthResult> login(BuildContext context) async {
    final completer = Completer<MobileKakaoAuthResult>();

    try {
      // InAppWebView를 전체 화면 다이얼로그로 표시
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => _KakaoLoginWebView(
            initialUrl: kakaoAuthUrl,
            onSuccess: (lt) async {
              // lt 토큰으로 pickup API 호출
              try {
                final authService = getAuthService();
                final pickupRes = await authService.pickup(lt);

                if (!pickupRes.success) {
                  completer.complete(MobileKakaoAuthResult(
                    success: false,
                    error: 'Bad Request',
                  ));
                  return;
                }

                // 사용자 정보 조회
                final meRes = await authService.me();
                if (!meRes.success || meRes.data == null) {
                  completer.complete(MobileKakaoAuthResult(
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

                // loginType을 kakao(2)로 설정
                userInfo.loginType = 2;

                completer.complete(MobileKakaoAuthResult(
                  success: true,
                  userInfo: userInfo,
                ));
              } catch (e) {
                debugPrint('[MobileKakaoAuth] Pickup error: $e');
                completer.complete(MobileKakaoAuthResult(
                  success: false,
                  error: 'Bad Request',
                ));
              }
            },
            onError: (error) {
              completer.complete(MobileKakaoAuthResult(
                success: false,
                error: error,
              ));
            },
          ),
        ),
      );

      return await completer.future;
    } catch (e) {
      debugPrint('[MobileKakaoAuth] Error: $e');
      return MobileKakaoAuthResult(
        success: false,
        error: 'Bad Request',
      );
    }
  }
}

/// Kakao 로그인 WebView 위젯
class _KakaoLoginWebView extends StatefulWidget {
  final String initialUrl;
  final Function(String lt) onSuccess;
  final Function(String error) onError;

  const _KakaoLoginWebView({
    required this.initialUrl,
    required this.onSuccess,
    required this.onError,
  });

  @override
  State<_KakaoLoginWebView> createState() => _KakaoLoginWebViewState();
}

class _KakaoLoginWebViewState extends State<_KakaoLoginWebView> {
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _clearCookies();
  }

  Future<void> _clearCookies() async {
    await CookieManager.instance().deleteAllCookies();
    debugPrint('[MobileKakaoAuth] Cookies cleared');
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

              debugPrint('[MobileKakaoAuth] URL loading: $uri');

              // kakaotalk:// 스킴 처리 (카카오톡 앱 열기)
              if (uri != null && uri.scheme == 'kakaotalk') {
                debugPrint('[MobileKakaoAuth] Opening KakaoTalk app: $uri');
                try {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (e) {
                  debugPrint('[MobileKakaoAuth] Failed to open KakaoTalk: $e');
                }
                return NavigationActionPolicy.CANCEL;
              }

              // intent:// 스킴 처리 (앱 설치 유도 등)
              if (uri != null && uri.scheme == 'intent') {
                debugPrint('[MobileKakaoAuth] Intent scheme detected: $uri');
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

                debugPrint('[MobileKakaoAuth] lt: $lt, error: $error');

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
              debugPrint('[MobileKakaoAuth] WebView error: $error');
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

/// 전역 MobileKakaoAuthService 인스턴스
MobileKakaoAuthService? _mobileKakaoAuthService;

/// MobileKakaoAuthService 초기화
void initMobileKakaoAuthService(String baseUrl) {
  _mobileKakaoAuthService = MobileKakaoAuthService(baseUrl);
}

/// MobileKakaoAuthService 가져오기
MobileKakaoAuthService getMobileKakaoAuthService() {
  if (_mobileKakaoAuthService == null) {
    throw StateError(
        'MobileKakaoAuthService not initialized. Call initMobileKakaoAuthService first.');
  }
  return _mobileKakaoAuthService!;
}

/// MobileKakaoAuthService 초기화 여부
bool isMobileKakaoAuthServiceInitialized() => _mobileKakaoAuthService != null;
