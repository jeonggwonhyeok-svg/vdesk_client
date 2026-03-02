/// PayPal 결제를 위한 로컬 HTTP 서버
/// PayPal JS SDK는 실제 HTTP 서버 origin이 필요하므로 로컬 서버 사용
/// 서버 API 방식: createSubscription → 서버에서 subscriptionId 생성 → PayPal 승인 → activate
library;

import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 파일 로거 (디버그용)
class PaymentFileLogger {
  static File? _logFile;
  static bool _initialized = false;

  static Future<void> _init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/onedesk_payment.log');
      _initialized = true;
      await _logFile!.writeAsString(
        '\n\n========== New Session: ${DateTime.now()} ==========\n',
        mode: FileMode.append,
      );
    } catch (e) {
      print('[PaymentFileLogger] Init error: $e');
    }
  }

  static Future<void> log(String tag, String message) async {
    final timestamp = DateTime.now().toIso8601String();
    final logLine = '[$timestamp] [$tag] $message';
    print(logLine);

    try {
      await _init();
      await _logFile?.writeAsString('$logLine\n', mode: FileMode.append);
    } catch (e) {
      // 파일 쓰기 실패 무시
    }
  }

  static Future<String?> getLogFilePath() async {
    await _init();
    return _logFile?.path;
  }
}

/// PayPal 로컬 서버 클래스 (서버 API 방식)
class PayPalLocalServer {
  static const String _clientId =
      'ASK9Um9ZtYD2PUEX4AEo-sZN4Nh3MNeh8D1eEYYwrkXvPCparbowwrhjZFDoVZmTTHvGfhPrYH3snFD4';

  // 서버 포트
  static const int _port = 47423;

  // HTTP 서버
  HttpServer? _server;

  // 결제 정보
  String? _subscriptionId; // 구독용 (Dart에서 미리 발급)
  String? _ourOrderId; // 일회성 결제용
  String? _paypalOrderId; // 일회성 결제용
  String? _approvalUrl; // PayPal 승인 URL (리디렉트용)
  bool _isSubscription = false;

  /// 서버 URL
  String get serverUrl => 'http://localhost:$_port/paypal';

  /// 성공 URL 패턴 (WebView에서 감지용)
  static const String successUrlPattern = 'http://localhost:$_port/success';

  /// 취소 URL 패턴 (WebView에서 감지용)
  static const String cancelUrlPattern = 'http://localhost:$_port/cancel';

  Future<String?> startSubscriptionServer({
    required String subscriptionId,
  }) async {
    _subscriptionId = subscriptionId;
    _isSubscription = true;
    await _startServer();
    return serverUrl;
  }

  /// 일회성 결제용 서버 시작
  Future<String> startOneTimeServer({
    required String ourOrderId,
    required String paypalOrderId,
    String? approvalUrl,
  }) async {
    _ourOrderId = ourOrderId;
    _paypalOrderId = paypalOrderId;
    _approvalUrl = approvalUrl;
    _isSubscription = false;
    await _startServer();
    return serverUrl;
  }

  /// HTTP 서버 시작
  Future<void> _startServer() async {
    // 기존 서버가 있으면 중지
    await stop();

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
      print('[PayPalLocalServer] Server started on port $_port');

      _server!.listen((HttpRequest request) {
        _handleRequest(request);
      });
    } catch (e) {
      print('[PayPalLocalServer] Failed to start server: $e');
      rethrow;
    }
  }

  /// HTTP 요청 처리
  void _handleRequest(HttpRequest request) {
    final path = request.uri.path;
    print('[PayPalLocalServer] Request: $path');

    if (path == '/paypal' || path == '/paypal/') {
      // PayPal 결제 페이지
      String html;
      if (_approvalUrl != null && _approvalUrl!.isNotEmpty) {
        // 리디렉트 방식 (approvalUrl이 있으면 직접 리디렉트)
        html = _buildRedirectHtml();
      } else {
        // JS SDK + 서버 API 방식
        html = _isSubscription ? _buildSubscriptionHtml() : _buildOneTimeHtml();
      }
      request.response
        ..headers.contentType = ContentType.html
        ..write(html)
        ..close();
    } else if (path == '/success') {
      // 성공 페이지 (WebView에서 감지)
      request.response
        ..headers.contentType = ContentType.html
        ..write('<html><body>Success</body></html>')
        ..close();
    } else if (path == '/cancel') {
      // 취소 페이지 (WebView에서 감지)
      request.response
        ..headers.contentType = ContentType.html
        ..write('<html><body>Cancelled</body></html>')
        ..close();
    } else {
      // 404
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not Found')
        ..close();
    }
  }

  /// 리디렉트 방식 HTML 빌드 (팝업 없이 직접 이동)
  String _buildRedirectHtml() {
    final subtitle = _isSubscription ? '구독 결제' : '일회성 결제';
    final escapedUrl = _escapeJs(_approvalUrl ?? '');

    return '''
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>PayPal 결제</title>
    <style>
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 0;
            padding: 40px 20px;
            background: #f5f7fa;
            display: flex;
            justify-content: center;
            align-items: flex-start;
            min-height: 100vh;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 12px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.1);
            max-width: 450px;
            width: 100%;
            text-align: center;
        }
        h2 { margin: 0 0 8px 0; color: #333; font-size: 24px; }
        .subtitle { color: #666; margin-bottom: 24px; font-size: 14px; }
        .paypal-btn {
            display: inline-block;
            background: #0070ba;
            color: white;
            padding: 14px 32px;
            border-radius: 8px;
            text-decoration: none;
            font-size: 16px;
            font-weight: 600;
            transition: background 0.2s;
            cursor: pointer;
            border: none;
        }
        .paypal-btn:hover { background: #005ea6; }
        .loading { color: #666; margin-top: 20px; }
        .spinner {
            width: 24px;
            height: 24px;
            border: 3px solid #e0e0e0;
            border-top-color: #0070ba;
            border-radius: 50%;
            animation: spin 1s linear infinite;
            margin: 0 auto 10px;
        }
        @keyframes spin { to { transform: rotate(360deg); } }
    </style>
</head>
<body>
    <div class="container">
        <h2>PayPal 결제</h2>
        <div class="subtitle">$subtitle</div>
        <div id="content">
            <div class="loading">
                <div class="spinner"></div>
                PayPal로 이동 중...
            </div>
        </div>
    </div>
    <script>
        (function() {
            var approvalUrl = '$escapedUrl';
            console.log('PayPal redirect mode, URL:', approvalUrl);

            setTimeout(function() {
                var content = document.getElementById('content');
                if (content) {
                    content.innerHTML = '<a href="' + approvalUrl + '" class="paypal-btn">PayPal로 결제하기</a>' +
                        '<p style="color:#999;margin-top:15px;font-size:12px;">자동으로 이동하지 않으면 버튼을 클릭하세요</p>';
                }
            }, 3000);

            if (approvalUrl && approvalUrl.length > 0) {
                window.location.href = approvalUrl;
            }
        })();
    </script>
</body>
</html>
''';
  }

  /// 구독 결제 HTML 빌드 (subscriptionId 전달 방식)
  /// Dart에서 미리 발급받은 subscriptionId를 사용
  String _buildSubscriptionHtml() {
    final escapedSubscriptionId = _escapeJs(_subscriptionId ?? '');

    return '''
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>PayPal 구독 결제</title>
    <style>
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 0;
            padding: 40px 20px;
            background: #f5f7fa;
            display: flex;
            justify-content: center;
            align-items: flex-start;
            min-height: 100vh;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 12px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.1);
            max-width: 450px;
            width: 100%;
        }
        h2 { margin: 0 0 8px 0; color: #333; text-align: center; font-size: 24px; }
        .subtitle { color: #666; text-align: center; margin-bottom: 24px; font-size: 14px; }
        #status { color: #666; text-align: center; margin-bottom: 15px; font-size: 14px; }
        #paypal-button-container { min-height: 150px; }
        .error { color: #dc3545 !important; }
        .loading { display: flex; justify-content: center; align-items: center; padding: 20px; }
        .spinner {
            width: 24px; height: 24px;
            border: 3px solid #e0e0e0;
            border-top-color: #0070ba;
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }
        @keyframes spin { to { transform: rotate(360deg); } }
    </style>
    <script src="https://www.paypal.com/sdk/js?client-id=$_clientId&vault=true&intent=subscription&currency=USD"></script>
</head>
<body>
    <div class="container">
        <h2>PayPal 결제</h2>
        <div class="subtitle">구독 결제</div>
        <div id="status">
            <div class="loading"><div class="spinner"></div></div>
            PayPal 버튼 로딩 중...
        </div>
        <div id="paypal-button-container"></div>
    </div>
    <script>
        var subscriptionId = '$escapedSubscriptionId';
        var statusEl = document.getElementById('status');

        function setStatus(msg) {
            statusEl.textContent = msg;
            statusEl.className = '';
        }

        function setError(msg) {
            statusEl.textContent = msg;
            statusEl.className = 'error';
        }

        if (window.paypal && paypal.Buttons) {
            setStatus('');
            paypal.Buttons({
                style: {
                    layout: 'vertical',
                    color: 'blue',
                    shape: 'rect',
                    label: 'subscribe'
                },
                createSubscription: function(data, actions) {
                    setStatus('PayPal 승인 창 여는 중...');
                    return subscriptionId;
                },
                onApprove: function(data) {
                    setStatus('승인 완료!');
                    window.location.href = '$successUrlPattern?mode=sub&subscriptionId=' + encodeURIComponent(data.subscriptionID || subscriptionId);
                },
                onCancel: function(data) {
                    setStatus('결제가 취소되었습니다');
                    window.location.href = '$cancelUrlPattern?mode=cancel';
                },
                onError: function(err) {
                    setError('결제 오류: ' + err);
                }
            }).render('#paypal-button-container');
        } else {
            setError('PayPal SDK 로드 실패');
        }
    </script>
</body>
</html>
''';
  }

  /// 일회성 결제 HTML 빌드
  String _buildOneTimeHtml() {
    final escapedPaypalOrderId = _escapeJs(_paypalOrderId ?? '');
    final escapedOurOrderId = _escapeJs(_ourOrderId ?? '');

    return '''
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>PayPal 결제</title>
    <style>
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 0;
            padding: 40px 20px;
            background: #f5f7fa;
            display: flex;
            justify-content: center;
            align-items: flex-start;
            min-height: 100vh;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 12px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.1);
            max-width: 450px;
            width: 100%;
        }
        h2 { margin: 0 0 8px 0; color: #333; text-align: center; font-size: 24px; }
        .subtitle { color: #666; text-align: center; margin-bottom: 24px; font-size: 14px; }
        #status { color: #666; text-align: center; margin-bottom: 15px; font-size: 14px; }
        #paypal-button-container { min-height: 150px; }
        .error { color: #dc3545 !important; }
        .loading { display: flex; justify-content: center; align-items: center; padding: 20px; }
        .spinner {
            width: 24px; height: 24px;
            border: 3px solid #e0e0e0;
            border-top-color: #0070ba;
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }
        @keyframes spin { to { transform: rotate(360deg); } }
    </style>
    <script src="https://www.paypal.com/sdk/js?client-id=$_clientId&components=buttons&currency=USD&intent=capture"></script>
</head>
<body>
    <div class="container">
        <h2>PayPal 결제</h2>
        <div class="subtitle">일회성 결제</div>
        <div id="status">
            <div class="loading"><div class="spinner"></div></div>
            PayPal 버튼 로딩 중...
        </div>
        <div id="paypal-button-container"></div>
    </div>
    <script>
        var statusEl = document.getElementById('status');

        function setStatus(msg) {
            statusEl.textContent = msg;
            statusEl.className = '';
        }

        function setError(msg) {
            statusEl.textContent = msg;
            statusEl.className = 'error';
        }

        if (window.paypal && paypal.Buttons) {
            setStatus('');
            paypal.Buttons({
                style: {
                    layout: 'vertical',
                    color: 'gold',
                    shape: 'rect',
                    label: 'paypal'
                },
                createOrder: function(data, actions) {
                    return '$escapedPaypalOrderId';
                },
                onApprove: function(data, actions) {
                    var url = '$successUrlPattern' +
                        '?mode=oneTime' +
                        '&ourOrderId=' + encodeURIComponent('$escapedOurOrderId') +
                        '&paypalOrderId=' + encodeURIComponent(data.orderID);
                    window.location.href = url;
                },
                onCancel: function(data) {
                    window.location.href = '$cancelUrlPattern?mode=cancel';
                },
                onError: function(err) {
                    console.error('PayPal Error:', err);
                    window.location.href = '$cancelUrlPattern?mode=error&msg=' + encodeURIComponent(err.toString());
                }
            }).render('#paypal-button-container');
        } else {
            setError('PayPal SDK 로드 실패');
        }
    </script>
</body>
</html>
''';
  }

  /// JavaScript 문자열 이스케이프
  String _escapeJs(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
  }

  /// 서버 중지
  Future<void> stop() async {
    if (_server != null) {
      print('[PayPalLocalServer] Stopping server...');
      await _server!.close(force: true);
      _server = null;
    }
  }

  /// 결과 URL에서 파라미터 파싱
  static Map<String, String> parseResultUrl(String url) {
    final uri = Uri.parse(url);
    return uri.queryParameters;
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
