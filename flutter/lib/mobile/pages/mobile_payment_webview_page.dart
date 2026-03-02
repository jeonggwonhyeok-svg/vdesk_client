/// 모바일 결제 WebView 페이지
/// flutter_inappwebview를 사용하여 결제 URL을 표시하고
/// URL 변경을 모니터링하여 결제 성공/실패를 감지합니다.
/// PayPal 팝업은 windowId를 사용하여 별도 WebView로 처리합니다.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/api/payment_service.dart';

/// 결제 결과 타입
enum MobilePaymentResult {
  success,
  cancel,
  fail,
}

/// 모바일 결제 WebView 페이지
class MobilePaymentWebViewPage extends StatefulWidget {
  final String? url;
  final String? htmlContent;
  final String planName;
  final String providerName;
  final String? orderId; // Paddle 폴링용

  const MobilePaymentWebViewPage({
    Key? key,
    this.url,
    this.htmlContent,
    required this.planName,
    required this.providerName,
    this.orderId,
  }) : super(key: key);

  factory MobilePaymentWebViewPage.withUrl({
    Key? key,
    required String url,
    required String planName,
    required String providerName,
    String? orderId,
  }) {
    return MobilePaymentWebViewPage(
      key: key,
      url: url,
      planName: planName,
      providerName: providerName,
      orderId: orderId,
    );
  }

  factory MobilePaymentWebViewPage.withHtml({
    Key? key,
    required String htmlContent,
    required String planName,
    required String providerName,
    String? orderId,
  }) {
    return MobilePaymentWebViewPage(
      key: key,
      htmlContent: htmlContent,
      planName: planName,
      providerName: providerName,
      orderId: orderId,
    );
  }

  @override
  State<MobilePaymentWebViewPage> createState() =>
      _MobilePaymentWebViewPageState();
}

class _MobilePaymentWebViewPageState extends State<MobilePaymentWebViewPage> {
  int _progress = 0;
  bool _isLoading = true;
  bool _showPopup = false;
  int? _popupWindowId;
  bool _resultHandled = false;
  Completer<bool>? _popupCompleter;
  InAppWebViewController? _mainController; // 메인 WebView 컨트롤러
  Timer? _pollingTimer; // Paddle 주문 상태 폴링용

  static const Color _primaryColor = Color(0xFF5F71FF);
  static const Color _textColor = Color(0xFF454447);

  @override
  void initState() {
    super.initState();
    // Paddle orderId가 있으면 주문 상태 폴링 시작
    if (widget.orderId != null && widget.orderId!.isNotEmpty) {
      _startOrderPolling();
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  /// Paddle 주문 상태 폴링 (로컬 서버 없이 직접 API 호출)
  void _startOrderPolling() {
    int elapsedSeconds = 0;
    const maxSeconds = 180; // 3분

    debugPrint('[Payment] Paddle 주문 상태 폴링 시작: orderId=${widget.orderId}');

    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      elapsedSeconds += 2;

      if (_resultHandled) {
        debugPrint('[Payment] Polling 종료 (already handled)');
        timer.cancel();
        return;
      }

      if (elapsedSeconds > maxSeconds || _resultHandled) {
        debugPrint('[Payment] Polling 타임아웃 ($maxSeconds초)');
        timer.cancel();
        return;
      }

      try {
        if (!isPaymentServiceInitialized()) return;
        final paymentService = getPaymentService();
        final response = await paymentService.getPaddleOrderState(
          widget.orderId!,
          PaymentType.subscription,
        );

        if (response.success) {
          final status = (response.extract('status')
                  ?? response.extract('state')
                  ?? response.extract('orderStatus')
                  ?? response.extract('paymentStatus'))
              ?.toUpperCase();

          debugPrint('[Payment] Poll #${elapsedSeconds ~/ 2} - Status: $status');

          if (status == 'PAID' || status == 'ACTIVE' || status == 'COMPLETED') {
            debugPrint('[Payment] Paddle 결제 확인됨!');
            timer.cancel();
            _handlePaymentResult(MobilePaymentResult.success);
          } else if (status == 'CANCELLED') {
            debugPrint('[Payment] Paddle 결제 취소됨');
            timer.cancel();
            _handlePaymentResult(MobilePaymentResult.cancel);
          } else if (status == 'FAILED' || status == 'EXPIRED') {
            debugPrint('[Payment] Paddle 결제 실패: $status');
            timer.cancel();
            _handlePaymentResult(MobilePaymentResult.fail);
          }
          // PENDING이면 계속 폴링
        }
      } catch (e) {
        debugPrint('[Payment] Polling error: $e');
        // 에러 시에도 계속 폴링
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _resultHandled,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_resultHandled) {
          if (_showPopup) {
            setState(() => _showPopup = false);
          } else {
            // 다이얼로그 없이 바로 취소 처리
            _handlePaymentResult(MobilePaymentResult.cancel);
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: _textColor, size: 20),
            onPressed: () {
              if (_showPopup) {
                setState(() => _showPopup = false);
              } else {
                // 다이얼로그 없이 바로 취소 처리
                _handlePaymentResult(MobilePaymentResult.cancel);
              }
            },
          ),
          title: Text(
            translate('Cancel Payment'),
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
            // 메인 WebView
            Column(
              children: [
                // 프로그레스 바
                if (_isLoading || _progress < 100)
                  LinearProgressIndicator(
                    value: _progress / 100,
                    backgroundColor: Colors.grey[200],
                    valueColor: const AlwaysStoppedAnimation<Color>(_primaryColor),
                  ),

                // 메인 WebView
                Expanded(
                  child: InAppWebView(
                    initialUrlRequest: widget.htmlContent == null && widget.url != null
                        ? URLRequest(url: WebUri(widget.url!))
                        : null,
                    initialData: widget.htmlContent != null
                        ? InAppWebViewInitialData(
                            data: widget.htmlContent!,
                            mimeType: 'text/html',
                            encoding: 'utf-8',
                          )
                        : null,
                    initialSettings: InAppWebViewSettings(
                      useShouldOverrideUrlLoading: true,
                      mediaPlaybackRequiresUserGesture: false,
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      databaseEnabled: true,
                      supportZoom: false,
                      allowFileAccess: true,
                      allowContentAccess: true,
                      useHybridComposition: true,
                      // ★ 팝업 허용
                      supportMultipleWindows: true,
                      javaScriptCanOpenWindowsAutomatically: true,
                    ),
                    onWebViewCreated: (controller) {
                      _mainController = controller;
                      debugPrint('[Main] WebView created');
                    },
                    onLoadStart: (controller, url) {
                      debugPrint('[Main] Load start: $url');
                      setState(() => _isLoading = true);
                      if (url != null) {
                        _checkPaymentResultUrl(url.toString());
                      }
                    },
                    onLoadStop: (controller, url) {
                      debugPrint('[Main] Load stop: $url');
                      setState(() => _isLoading = false);
                      if (url != null) {
                        _checkPaymentResultUrl(url.toString());
                      }
                    },
                    onProgressChanged: (controller, progress) {
                      setState(() => _progress = progress);
                    },
                    onUpdateVisitedHistory: (controller, url, androidIsReload) {
                      debugPrint('[Main] URL changed: $url');
                      if (url != null) {
                        _checkPaymentResultUrl(url.toString());
                      }
                    },
                    shouldOverrideUrlLoading: (controller, navigationAction) async {
                      final url = navigationAction.request.url?.toString();
                      debugPrint('[Main] Navigation: $url');
                      if (url != null && _checkPaymentResultUrl(url)) {
                        return NavigationActionPolicy.CANCEL;
                      }
                      return NavigationActionPolicy.ALLOW;
                    },
                    onReceivedError: (controller, request, error) {
                      debugPrint('[Main] Error: ${error.description}');
                    },
                    // ★ JavaScript 콘솔 메시지 캡처
                    onConsoleMessage: (controller, consoleMessage) {
                      debugPrint('[JS Console] ${consoleMessage.messageLevel}: ${consoleMessage.message}');
                    },
                    // ★ 팝업 요청 - PayPal URL이면 메인 WebView에서 직접 열기
                    onCreateWindow: (controller, createWindowAction) async {
                      final url = createWindowAction.request.url?.toString();
                      debugPrint('[Main] onCreateWindow: $url, windowId: ${createWindowAction.windowId}');

                      // PayPal 승인 URL인 경우 메인 WebView에서 직접 열기
                      if (url != null && url.contains('paypal.com')) {
                        debugPrint('[Main] PayPal URL detected, navigating main WebView to: $url');
                        _mainController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
                        return false; // 팝업 열지 않음
                      }

                      // 기타 팝업은 오버레이로 처리
                      _popupCompleter = Completer<bool>();

                      setState(() {
                        _popupWindowId = createWindowAction.windowId;
                        _showPopup = true;
                      });

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        debugPrint('[Main] Popup WebView should be ready now');
                        if (_popupCompleter != null && !_popupCompleter!.isCompleted) {
                          _popupCompleter!.complete(true);
                        }
                      });

                      return _popupCompleter!.future;
                    },
                    onCloseWindow: (controller) {
                      debugPrint('[Main] onCloseWindow');
                      setState(() => _showPopup = false);
                    },
                  ),
                ),
              ],
            ),

            // ★ 팝업 WebView 오버레이
            if (_showPopup && _popupWindowId != null)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  child: SafeArea(
                    child: Column(
                      children: [
                        // 팝업 헤더
                        Container(
                          color: const Color(0xFF0070BA),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white),
                                onPressed: () => setState(() => _showPopup = false),
                              ),
                              const Expanded(
                                child: Text(
                                  'PayPal',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 48),
                            ],
                          ),
                        ),
                        // 팝업 WebView
                        Expanded(
                          child: Container(
                            color: Colors.white,
                            child: InAppWebView(
                              windowId: _popupWindowId,
                              initialSettings: InAppWebViewSettings(
                                useShouldOverrideUrlLoading: true,
                                javaScriptEnabled: true,
                                domStorageEnabled: true,
                                databaseEnabled: true,
                                supportZoom: false,
                                useHybridComposition: true,
                                supportMultipleWindows: false,
                                javaScriptCanOpenWindowsAutomatically: false,
                              ),
                              onWebViewCreated: (controller) {
                                debugPrint('[Popup] WebView created with windowId: $_popupWindowId');
                              },
                              onLoadStart: (controller, url) {
                                debugPrint('[Popup] Load start: $url');
                                if (url != null) {
                                  _checkPopupUrl(url.toString());
                                }
                              },
                              onLoadStop: (controller, url) {
                                debugPrint('[Popup] Load stop: $url');
                                if (url != null) {
                                  _checkPopupUrl(url.toString());
                                }
                              },
                              onUpdateVisitedHistory: (controller, url, androidIsReload) {
                                debugPrint('[Popup] URL changed: $url');
                                if (url != null) {
                                  _checkPopupUrl(url.toString());
                                }
                              },
                              shouldOverrideUrlLoading: (controller, navigationAction) async {
                                final url = navigationAction.request.url?.toString();
                                debugPrint('[Popup] Navigation: $url');
                                if (url != null && _checkPopupUrl(url)) {
                                  return NavigationActionPolicy.CANCEL;
                                }
                                return NavigationActionPolicy.ALLOW;
                              },
                              onCloseWindow: (controller) {
                                debugPrint('[Popup] onCloseWindow');
                                setState(() => _showPopup = false);
                              },
                              onReceivedError: (controller, request, error) {
                                debugPrint('[Popup] Error: ${error.description}');
                              },
                              // ★ 팝업 JavaScript 콘솔 메시지 캡처
                              onConsoleMessage: (controller, consoleMessage) {
                                debugPrint('[Popup JS] ${consoleMessage.messageLevel}: ${consoleMessage.message}');
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 팝업 URL 체크
  bool _checkPopupUrl(String urlStr) {
    if (_resultHandled) return false;

    final urlStrLower = urlStr.toLowerCase();
    debugPrint('[Popup] 체크 URL: $urlStr');

    // PayPal 리턴 URL 감지
    if (urlStrLower.contains('paypal.com/webapps/hermes/return') ||
        (urlStrLower.contains('return') && urlStrLower.contains('token='))) {
      debugPrint('[Popup] PayPal return detected - closing popup');
      setState(() => _showPopup = false);
      return false;
    }

    // PayPal 취소 URL 감지
    if (urlStrLower.contains('paypal.com/webapps/hermes/cancel')) {
      debugPrint('[Popup] PayPal cancel detected');
      setState(() => _showPopup = false);
      return false;
    }

    return _checkPaymentResultUrl(urlStr);
  }

  /// 결제 결과 URL 체크
  bool _checkPaymentResultUrl(String urlStr) {
    if (_resultHandled) return false;

    final urlStrLower = urlStr.toLowerCase();

    debugPrint('========================================');
    debugPrint('[Payment] 체크 URL: $urlStr');
    debugPrint('========================================');

    // Welcome 에러/취소 파라미터 체크
    if (urlStrLower.contains('p_status=') && !urlStrLower.contains('p_status=00')) {
      debugPrint('[Payment] FAIL (P_STATUS)');
      _handlePaymentResult(MobilePaymentResult.fail);
      return true;
    }
    if (urlStrLower.contains('errcode=') || urlStrLower.contains('errmsg=')) {
      debugPrint('[Payment] FAIL (errcode/errmsg)');
      _handlePaymentResult(MobilePaymentResult.fail);
      return true;
    }
    if (urlStrLower.contains('isblockback=err')) {
      debugPrint('[Payment] FAIL (isBlockBack)');
      _handlePaymentResult(MobilePaymentResult.fail);
      return true;
    }

    // localhost:8080은 스킵
    if (urlStrLower.contains('localhost:8080')) {
      debugPrint('[Payment] Server callback URL, waiting...');
      return false;
    }

    // status 파라미터 체크
    if (urlStrLower.contains('status=fail') || urlStrLower.contains('status=error')) {
      debugPrint('[Payment] FAIL (status param)');
      _handlePaymentResult(MobilePaymentResult.fail);
      return true;
    }
    if (urlStrLower.contains('status=cancel')) {
      debugPrint('[Payment] CANCEL (status param)');
      _handlePaymentResult(MobilePaymentResult.cancel);
      return true;
    }
    if (urlStrLower.contains('status=success')) {
      debugPrint('[Payment] SUCCESS (status param)');
      _handlePaymentResult(MobilePaymentResult.success);
      return true;
    }

    // localhost URL 체크
    if (urlStrLower.contains('localhost')) {
      if (urlStrLower.contains('/fail')) {
        debugPrint('[Payment] FAIL (localhost)');
        _handlePaymentResult(MobilePaymentResult.fail);
        return true;
      }
      if (urlStrLower.contains('/cancel')) {
        debugPrint('[Payment] CANCEL (localhost)');
        _handlePaymentResult(MobilePaymentResult.cancel);
        return true;
      }
      if (urlStrLower.contains('/success')) {
        debugPrint('[Payment] SUCCESS (localhost)');
        _handlePaymentResult(MobilePaymentResult.success);
        return true;
      }
    }

    // PayPal 구독 return/cancel URL 체크 (onedesk.co.kr/api/paypal/...)
    if (urlStrLower.contains('onedesk.co.kr/api/paypal/return') ||
        urlStrLower.contains('onedesk.co.kr/api/paypal/success')) {
      debugPrint('[Payment] SUCCESS (PayPal return URL)');
      _handlePaymentResult(MobilePaymentResult.success);
      return true;
    }
    if (urlStrLower.contains('onedesk.co.kr/api/paypal/cancel')) {
      debugPrint('[Payment] CANCEL (PayPal cancel URL)');
      _handlePaymentResult(MobilePaymentResult.cancel);
      return true;
    }

    // PayPal 구독 승인 완료 체크 (subscription_id 파라미터)
    if (urlStrLower.contains('subscription_id=') && urlStrLower.contains('ba_token=')) {
      debugPrint('[Payment] SUCCESS (PayPal subscription approved)');
      _handlePaymentResult(MobilePaymentResult.success);
      return true;
    }

    return false;
  }

  /// 결제 결과 처리
  void _handlePaymentResult(MobilePaymentResult result) {
    if (_resultHandled) return;
    _resultHandled = true;

    setState(() => _showPopup = false);
    Navigator.of(context).pop(result);
  }

}
