/// Welcome 결제를 위한 로컬 HTTP 서버
/// INIStdPay.js (일회성) 및 웰컴 모바일 빌링 (P_* 필드) 결제 처리
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Welcome 로컬 서버 클래스
class WelcomeLocalServer {
  // 서버 포트 (C#과 동일하게 57423)
  static const int _port = 47423;

  // HTTP 서버
  HttpServer? _server;

  // 결제 정보
  Map<String, dynamic>? _paymentData;
  bool _isBilling = false;
  String? _orderName;
  String? _buyerEmail;
  String? _buyerName;
  String? _buyerTel;
  String? _serverHost;

  /// 서버 URL
  String get serverUrl => 'http://localhost:$_port/stdpay';

  /// 성공 URL 패턴 (WebView에서 감지용)
  static const String successUrlPattern = 'http://localhost:$_port/success';

  /// 취소 URL 패턴 (WebView에서 감지용)
  static const String cancelUrlPattern = 'http://localhost:$_port/cancel';

  /// 일회성 결제용 서버 시작
  Future<String> startCheckoutServer({
    required Map<String, dynamic> paymentData,
    required String serverHost,
    String? orderName,
    String? buyerEmail,
    String? buyerName,
    String? buyerTel,
  }) async {
    // 먼저 기존 서버 중지 (데이터도 초기화됨)
    await stop();

    // 그 다음 새 데이터 설정
    _paymentData = paymentData;
    _isBilling = false;
    _orderName = orderName;
    _buyerEmail = buyerEmail;
    _buyerName = buyerName;
    _buyerTel = buyerTel;
    _serverHost = serverHost;

    debugPrint(
        '[WelcomeLocalServer] Starting checkout server with mid=${paymentData['mid']}');

    await _startServer();
    return serverUrl;
  }

  /// 빌링(정기결제) 서버 시작
  Future<String> startBillingServer({
    required Map<String, dynamic> paymentData,
    required String serverHost,
  }) async {
    // 먼저 기존 서버 중지 (데이터도 초기화됨)
    await stop();

    // 그 다음 새 데이터 설정
    _paymentData = paymentData;
    _isBilling = true;
    _serverHost = serverHost;

    debugPrint(
        '[WelcomeLocalServer] Starting billing server with P_MID=${paymentData['P_MID']}');

    await _startServer();
    return serverUrl;
  }

  /// HTTP 서버 시작 (stop은 호출자에서 먼저 해야 함)
  Future<void> _startServer() async {
    // 기존 서버가 있으면 중지 (데이터는 유지)
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
    }

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
      debugPrint('[WelcomeLocalServer] Server started on port $_port');

      _server!.listen((HttpRequest request) {
        _handleRequest(request);
      });
    } catch (e) {
      debugPrint('[WelcomeLocalServer] Failed to start server: $e');
      rethrow;
    }
  }

  /// HTTP 요청 처리
  void _handleRequest(HttpRequest request) {
    final path = request.uri.path.toLowerCase();
    debugPrint('[WelcomeLocalServer] Request: $path');

    if (path == '/' || path.startsWith('/stdpay')) {
      // 결제 페이지
      final html = _isBilling ? _buildBillingHtml() : _buildCheckoutHtml();
      request.response
        ..headers.contentType = ContentType.html
        ..write(html)
        ..close();
    } else if (path == '/success') {
      // 성공 페이지 (WebView에서 감지)
      request.response
        ..headers.contentType = ContentType.html
        ..write(_buildSuccessHtml())
        ..close();
    } else if (path == '/cancel') {
      // 취소 페이지 (WebView에서 감지)
      request.response
        ..headers.contentType = ContentType.html
        ..write(_buildCancelHtml())
        ..close();
    } else {
      // 기타 요청은 OK 반환
      request.response
        ..statusCode = HttpStatus.ok
        ..write('OK')
        ..close();
    }
  }

  /// 일회성 결제 HTML 빌드 (INIStdPay.js)
  String _buildCheckoutHtml() {
    final data = _paymentData ?? {};

    // returnUrl 처리 - 서버 호스트로 대체
    String returnUrl = data['returnUrl'] ?? '';
    if (_serverHost != null && returnUrl.isNotEmpty) {
      returnUrl = returnUrl.replaceFirst(
        RegExp(r'^https?://[^/]+'),
        _serverHost!.replaceAll(RegExp(r'/$'), ''),
      );
    }

    // closeUrl 처리 - 서버 호스트로 대체
    String closeUrl = data['closeUrl'] ?? '';
    if (_serverHost != null && closeUrl.isNotEmpty) {
      closeUrl = closeUrl.replaceFirst(
        RegExp(r'^https?://[^/]+'),
        _serverHost!.replaceAll(RegExp(r'/$'), ''),
      );
    }

    return '''
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Welcome 결제</title>
    <script src="https://stdpay.paywelcome.co.kr/stdjs/INIStdPay.js" charset="UTF-8"></script>
    <style>
        body {
            font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, sans-serif;
            margin: 0;
            padding: 0;
            background: #f5f5f5;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            text-align: center;
        }
        h2 { color: #333; margin: 0 0 15px 0; }
        #status { color: #666; margin-top: 15px; }
        .error { color: #dc3545 !important; }
    </style>
</head>
<body>
    <div class="container">
        <h2>Welcome 결제</h2>
        <div id="status">결제창을 여는 중...</div>
    </div>

    <form id="SendPayForm_id" method="POST" style="display:none;">
        <input type="hidden" name="version" value="${_escapeHtml(data['version'] ?? '1.0')}" />
        <input type="hidden" name="mid" value="${_escapeHtml(data['mid'] ?? '')}" />
        <input type="hidden" name="oid" value="${_escapeHtml(data['oid'] ?? '')}" />
        <input type="hidden" name="goodname" value="${_escapeHtml(data['goodname'] ?? _orderName ?? '')}" />
        <input type="hidden" name="price" value="${_escapeHtml(data['price']?.toString() ?? '')}" />
        <input type="hidden" name="currency" value="${_escapeHtml(data['currency'] ?? 'WON')}" />
        <input type="hidden" name="buyername" value="${_escapeHtml(data['buyername'] ?? _buyerName ?? '홍길동')}" />
        <input type="hidden" name="buyertel" value="${_escapeHtml(data['buyertel'] ?? _buyerTel ?? '010-0000-0000')}" />
        <input type="hidden" name="buyeremail" value="${_escapeHtml(data['buyeremail'] ?? _buyerEmail ?? '')}" />
        <input type="hidden" name="timestamp" value="${_escapeHtml(data['timestamp'] ?? '')}" />
        <input type="hidden" name="signature" value="${_escapeHtml(data['signature'] ?? '')}" />
        <input type="hidden" name="returnUrl" value="${_escapeHtml(returnUrl)}" />
        <input type="hidden" name="closeUrl" value="${_escapeHtml(closeUrl)}" />
        <input type="hidden" name="mKey" value="${_escapeHtml(data['mKey'] ?? '')}" />
        <input type="hidden" name="gopaymethod" value="${_escapeHtml(data['gopaymethod'] ?? 'Card')}" />
        <input type="hidden" name="charset" value="${_escapeHtml(data['charset'] ?? 'UTF-8')}" />
        <input type="hidden" name="payViewType" value="${_escapeHtml(data['payViewType'] ?? 'overlay')}" />
        ${data['acceptmethod'] != null ? '<input type="hidden" name="acceptmethod" value="${_escapeHtml(data['acceptmethod'])}" />' : ''}
    </form>

    <script>
    var SUCCESS_URL = 'http://localhost:$_port/success';
    var CANCEL_URL = 'http://localhost:$_port/cancel';

    function setStatus(msg) {
        document.getElementById('status').textContent = msg;
    }

    function pay() {
        try {
            setStatus('결제창을 여는 중...');
            INIStdPay.pay('SendPayForm_id');
        } catch(e) {
            setStatus('결제 오류: ' + e.message);
            document.getElementById('status').className = 'error';
            console.error('INIStdPay error:', e);
        }
    }

    window.addEventListener('message', function(e) {
        console.log('[Welcome] Message:', e.data);
        if (e.data && e.data.result === 'success') {
            window.location.href = SUCCESS_URL;
        } else if (e.data && e.data.result === 'cancel') {
            window.location.href = CANCEL_URL;
        }
    });

    window.onload = function() {
        setTimeout(pay, 500);
    };
    </script>
</body>
</html>
''';
  }

  /// 빌링(정기결제) HTML 빌드 - 웰컴 모바일 결제창 방식 (actionUrl + P_* 필드 form submit)
  String _buildBillingHtml() {
    final data = _paymentData ?? {};

    // actionUrl 추출
    String actionUrl = data['actionUrl'] ?? '';

    return '''
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Welcome 정기결제</title>
    <style>
        body {
            font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, sans-serif;
            margin: 0;
            padding: 0;
            background: #f5f5f5;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            text-align: center;
        }
        h2 { color: #333; margin: 0 0 15px 0; }
        #status { color: #666; margin-top: 15px; }
        .error { color: #dc3545 !important; }
    </style>
</head>
<body>
    <div class="container">
        <h2>Welcome 정기결제</h2>
        <div id="status">빌링 인증창을 여는 중...</div>
    </div>

    <form id="billingForm" method="POST" action="${_escapeHtml(actionUrl)}">
        <input type="hidden" name="P_MID" value="${_escapeHtml(data['P_MID'] ?? '')}" />
        <input type="hidden" name="P_OID" value="${_escapeHtml(data['P_OID'] ?? '')}" />
        <input type="hidden" name="P_AMT" value="${_escapeHtml(data['P_AMT']?.toString() ?? '')}" />
        <input type="hidden" name="P_UNAME" value="${_escapeHtml(data['P_UNAME'] ?? '')}" />
        <input type="hidden" name="P_TIMESTAMP" value="${_escapeHtml(data['P_TIMESTAMP'] ?? '')}" />
        <input type="hidden" name="P_SIGNATURE" value="${_escapeHtml(data['P_SIGNATURE'] ?? '')}" />
        <input type="hidden" name="P_RESERVED" value="${_escapeHtml(data['P_RESERVED'] ?? '')}" />
        <input type="hidden" name="P_NEXT_URL" value="${_escapeHtml(data['P_NEXT_URL'] ?? '')}" />
    </form>

    <script>
    var SUCCESS_URL = 'http://localhost:$_port/success';
    var CANCEL_URL = 'http://localhost:$_port/cancel';

    function setStatus(msg) {
        document.getElementById('status').textContent = msg;
    }

    function startBilling() {
        try {
            setStatus('빌링 인증창을 여는 중...');
            document.getElementById('billingForm').submit();
        } catch(e) {
            setStatus('빌링 오류: ' + e.message);
            document.getElementById('status').className = 'error';
            console.error('Billing error:', e);
        }
    }

    // P_NEXT_URL에서 결과를 받아 처리하는 메시지 리스너
    window.addEventListener('message', function(e) {
        console.log('[Welcome Billing] Message:', e.data);
        if (e.data && e.data.result === 'success') {
            window.location.href = SUCCESS_URL;
        } else if (e.data && e.data.result === 'cancel') {
            window.location.href = CANCEL_URL;
        }
    });

    window.onload = function() {
        setTimeout(startBilling, 500);
    };
    </script>
</body>
</html>
''';
  }

  /// 성공 HTML
  String _buildSuccessHtml() {
    return '''
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <title>결제 완료</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
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
        .icon { font-size: 64px; margin-bottom: 20px; }
        h1 { color: #22c55e; margin: 0 0 10px 0; }
        p { color: #666; margin: 0; }
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

  /// 취소 HTML
  String _buildCancelHtml() {
    return '''
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <title>결제 취소</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
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
        .icon { font-size: 64px; margin-bottom: 20px; }
        h1 { color: #ef4444; margin: 0 0 10px 0; }
        p { color: #666; margin: 0; }
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

  /// HTML 이스케이프
  String _escapeHtml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  /// 서버 중지
  Future<void> stop() async {
    if (_server != null) {
      debugPrint('[WelcomeLocalServer] Stopping server...');
      await _server!.close(force: true);
      _server = null;
    }
    _paymentData = null;
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
