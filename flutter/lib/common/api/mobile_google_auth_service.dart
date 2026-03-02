/// 모바일용 Google OAuth 로그인 서비스
/// InAppWebView를 사용하여 OAuth 콜백을 처리합니다.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../common.dart';
import 'auth_service.dart';
import 'session_service.dart';
import 'models.dart';
import '../../models/platform_model.dart';

/// Google OAuth 로그인 결과
class MobileGoogleAuthResult {
  final bool success;
  final String? error;
  final UserInfo? userInfo;

  MobileGoogleAuthResult({
    required this.success,
    this.error,
    this.userInfo,
  });
}

/// 모바일용 Google OAuth 서비스
class MobileGoogleAuthService {
  final String _baseUrl;

  MobileGoogleAuthService(this._baseUrl);

  /// Google OAuth URL
  String get googleAuthUrl => '$_baseUrl/oauth2/authorization/google';

  /// Google 로그인 시작
  Future<MobileGoogleAuthResult> login(BuildContext context) async {
    final completer = Completer<MobileGoogleAuthResult>();

    try {
      // InAppWebView를 전체 화면 다이얼로그로 표시
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => _GoogleLoginWebView(
            initialUrl: googleAuthUrl,
            onSuccess: (lt) async {
              // lt 토큰으로 pickup API 호출
              try {
                final authService = getAuthService();
                final pickupRes = await authService.pickup(lt);

                if (!pickupRes.success) {
                  completer.complete(MobileGoogleAuthResult(
                    success: false,
                    error: 'Bad Request',
                  ));
                  return;
                }

                // 사용자 정보 조회
                final meRes = await authService.me();
                if (!meRes.success || meRes.data == null) {
                  completer.complete(MobileGoogleAuthResult(
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

                // loginType을 google(1)로 설정
                userInfo.loginType = 1;

                completer.complete(MobileGoogleAuthResult(
                  success: true,
                  userInfo: userInfo,
                ));
              } catch (e) {
                debugPrint('[MobileGoogleAuth] Pickup error: $e');
                completer.complete(MobileGoogleAuthResult(
                  success: false,
                  error: 'Bad Request',
                ));
              }
            },
            onError: (error) {
              completer.complete(MobileGoogleAuthResult(
                success: false,
                error: error,
              ));
            },
          ),
        ),
      );

      return await completer.future;
    } catch (e) {
      debugPrint('[MobileGoogleAuth] Error: $e');
      return MobileGoogleAuthResult(
        success: false,
        error: 'Bad Request',
      );
    }
  }
}

/// Google 로그인 WebView 위젯
class _GoogleLoginWebView extends StatefulWidget {
  final String initialUrl;
  final Function(String lt) onSuccess;
  final Function(String error) onError;

  const _GoogleLoginWebView({
    required this.initialUrl,
    required this.onSuccess,
    required this.onError,
  });

  @override
  State<_GoogleLoginWebView> createState() => _GoogleLoginWebViewState();
}

class _GoogleLoginWebViewState extends State<_GoogleLoginWebView> {
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _clearCookies();
  }

  Future<void> _clearCookies() async {
    await CookieManager.instance().deleteAllCookies();
    debugPrint('[MobileGoogleAuth] Cookies cleared');
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
              userAgent: Platform.isIOS
                  ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Mobile/15E148 Safari/604.1'
                  : 'Mozilla/5.0 (Linux; Android 14; SM-S928B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
            ),
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final uri = navigationAction.request.url;

              debugPrint('[MobileGoogleAuth] URL loading: $uri');

              // localhost:57403/auth 리다이렉트 감지
              if (uri != null &&
                  uri.host == 'localhost' &&
                  uri.port == 57403 &&
                  (uri.path == '/auth' || uri.path.startsWith('/auth'))) {
                final lt = uri.queryParameters['lt'];
                final error = uri.queryParameters['error'];

                debugPrint('[MobileGoogleAuth] lt: $lt, error: $error');

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
              debugPrint('[MobileGoogleAuth] WebView error: $error');
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

/// 전역 MobileGoogleAuthService 인스턴스
MobileGoogleAuthService? _mobileGoogleAuthService;

/// MobileGoogleAuthService 초기화
void initMobileGoogleAuthService(String baseUrl) {
  _mobileGoogleAuthService = MobileGoogleAuthService(baseUrl);
}

/// MobileGoogleAuthService 가져오기
MobileGoogleAuthService getMobileGoogleAuthService() {
  if (_mobileGoogleAuthService == null) {
    throw StateError(
        'MobileGoogleAuthService not initialized. Call initMobileGoogleAuthService first.');
  }
  return _mobileGoogleAuthService!;
}

/// MobileGoogleAuthService 초기화 여부
bool isMobileGoogleAuthServiceInitialized() => _mobileGoogleAuthService != null;
