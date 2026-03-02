/// API 클라이언트
/// HTTP 요청을 처리하고 쿠키를 관리합니다.
library;

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'cookie_manager.dart';
import 'models.dart';

/// API 로그 파일
File? _logFile;

/// API 로그 출력 (파일에 저장)
void _log(String message) {
  final timestamp = DateTime.now().toIso8601String();
  final logMessage = '[$timestamp] $message';

  // ignore: avoid_print
  print(logMessage);

  // 파일에도 저장
  _writeToLogFile(logMessage);
}

/// 로그 파일에 쓰기
Future<void> _writeToLogFile(String message) async {
  try {
    if (_logFile == null) {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/onedesk_api.log');
    }
    await _logFile!.writeAsString('$message\n', mode: FileMode.append);
  } catch (e) {
    // 로그 파일 쓰기 실패 무시
  }
}

/// API 요청 로깅
void _logRequest({
  required String method,
  required String url,
  required Map<String, String> headers,
  String? body,
}) {
  final buffer = StringBuffer();
  buffer.writeln('');
  buffer.writeln('╔══════════════════════════════════════════════════════════════');
  buffer.writeln('║ API 요청 [$method]');
  buffer.writeln('╠══════════════════════════════════════════════════════════════');
  buffer.writeln('║ URL: $url');
  buffer.writeln('╠──────────────────────────────────────────────────────────────');
  buffer.writeln('║ 헤더:');
  headers.forEach((key, value) {
    if (key.toLowerCase() == 'cookie') {
      buffer.writeln('║   $key: [쿠키 - 아래 참조]');
    } else {
      buffer.writeln('║   $key: $value');
    }
  });
  buffer.writeln('╠──────────────────────────────────────────────────────────────');
  buffer.writeln('║ 쿠키:');
  final cookie = headers['Cookie'] ?? '(없음)';
  if (cookie != '(없음)') {
    final cookies = cookie.split('; ');
    for (final c in cookies) {
      buffer.writeln('║   $c');
    }
  } else {
    buffer.writeln('║   (없음)');
  }
  if (body != null && body.isNotEmpty) {
    buffer.writeln('╠──────────────────────────────────────────────────────────────');
    buffer.writeln('║ 요청 데이터:');
    buffer.writeln('║   $body');
  }
  buffer.writeln('╚══════════════════════════════════════════════════════════════');
  _log(buffer.toString());
}

/// API 응답 로깅
void _logResponse({
  required String method,
  required String url,
  required int statusCode,
  required Map<String, String> headers,
  required String body,
}) {
  final buffer = StringBuffer();
  buffer.writeln('');
  buffer.writeln('┌──────────────────────────────────────────────────────────────');
  buffer.writeln('│ API 응답 [$method] - 상태: $statusCode');
  buffer.writeln('├──────────────────────────────────────────────────────────────');
  buffer.writeln('│ URL: $url');
  buffer.writeln('├──────────────────────────────────────────────────────────────');
  buffer.writeln('│ 응답 헤더:');
  headers.forEach((key, value) {
    if (key.toLowerCase() == 'set-cookie') {
      buffer.writeln('│   $key: [쿠키 - 아래 참조]');
    } else {
      buffer.writeln('│   $key: $value');
    }
  });
  buffer.writeln('├──────────────────────────────────────────────────────────────');
  buffer.writeln('│ Set-Cookie:');
  final setCookie = headers['set-cookie'];
  if (setCookie != null && setCookie.isNotEmpty) {
    // 쿠키 파싱
    final cookiePattern = RegExp(r',\s*(?=[A-Za-z_][A-Za-z0-9_]*=)');
    final cookies = setCookie.split(cookiePattern);
    for (final c in cookies) {
      buffer.writeln('│   ${c.trim()}');
    }
  } else {
    buffer.writeln('│   (없음)');
  }
  buffer.writeln('├──────────────────────────────────────────────────────────────');
  buffer.writeln('│ 응답 본문:');
  // 긴 응답은 잘라서 표시
  if (body.length > 500) {
    buffer.writeln('│   ${body.substring(0, 500)}...');
    buffer.writeln('│   (총 ${body.length}자, 일부만 표시)');
  } else {
    buffer.writeln('│   $body');
  }
  buffer.writeln('└──────────────────────────────────────────────────────────────');
  _log(buffer.toString());
}

/// 클라이언트 정보 헬퍼
class ClientInfoHelper {
  static String? _deviceId;

  /// 디바이스 ID 설정
  static void setDeviceId(String deviceId) {
    _deviceId = deviceId;
  }

  /// 디바이스 ID 가져오기
  static String getDeviceId() {
    return _deviceId ?? 'unknown-device';
  }

  /// 앱 버전 가져오기
  static String getAppVersion() {
    // TODO: 실제 앱 버전 가져오기
    return '1.0.0';
  }

  /// User-Agent 문자열 생성
  static String getClientInfo(String? deviceKey) {
    final os = Platform.operatingSystem;
    final osVersion = Platform.operatingSystemVersion;
    return 'OneDesk/$os ($osVersion) DeviceKey/${deviceKey ?? 'unknown'}';
  }
}

/// API 클라이언트 클래스
class ApiClient {
  final String _baseUrl;
  final http.Client _httpClient;
  String? _deviceKey;

  ApiClient(this._baseUrl) : _httpClient = http.Client();

  /// 기본 URL
  String get baseUrl => _baseUrl;

  /// 디바이스 키 설정
  void setDeviceKey(String deviceKey) {
    _deviceKey = deviceKey;
    ClientInfoHelper.setDeviceId(deviceKey);
  }

  /// URL에서 도메인 추출
  String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (e) {
      return url;
    }
  }

  /// 전체 URL 생성
  String _buildUrl(String endpoint) {
    if (endpoint.startsWith('http://') || endpoint.startsWith('https://')) {
      return endpoint;
    }
    final base = _baseUrl.endsWith('/') ? _baseUrl : '$_baseUrl/';
    final path = endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
    return '$base$path';
  }

  /// 기본 헤더 생성
  Map<String, String> _buildHeaders({bool isJson = true}) {
    final headers = <String, String>{
      'User-Agent': ClientInfoHelper.getClientInfo(_deviceKey),
    };

    if (isJson) {
      headers['Content-Type'] = 'application/json';
      headers['Accept'] = 'application/json';
    }

    // 쿠키 헤더 추가
    final domain = _extractDomain(_baseUrl);
    final cookieHeader = cookieManager.getCookieHeader(domain);
    if (cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }

    return headers;
  }

  /// 응답에서 쿠키 처리
  void _handleResponseCookies(http.Response response) {
    final domain = _extractDomain(_baseUrl);

    // Set-Cookie 헤더 처리
    final setCookieHeader = response.headers['set-cookie'];
    if (setCookieHeader != null && setCookieHeader.isNotEmpty) {
      // 여러 쿠키가 쉼표로 구분된 경우 (단, 쿠키 값 내의 쉼표는 제외)
      // 패턴: "name=value; attr, name2=value2; attr" -> 쉼표 다음에 공백과 알파벳=이 오는 경우
      final cookiePattern = RegExp(r',\s*(?=[A-Za-z_][A-Za-z0-9_]*=)');
      final cookies = setCookieHeader.split(cookiePattern);

      for (final cookie in cookies) {
        if (cookie.trim().isNotEmpty) {
          cookieManager.parseSetCookieHeader(domain, cookie.trim());
        }
      }
    }
  }

  /// GET 요청
  Future<ApiResponse> get(String endpoint) async {
    final url = _buildUrl(endpoint);
    final headers = _buildHeaders();

    try {
      _logRequest(method: 'GET', url: url, headers: headers);

      final response = await _httpClient.get(
        Uri.parse(url),
        headers: headers,
      );

      _handleResponseCookies(response);

      final body = utf8.decode(response.bodyBytes);
      _logResponse(
        method: 'GET',
        url: url,
        statusCode: response.statusCode,
        headers: response.headers,
        body: body,
      );

      return ApiResponse.fromRawBody(body, statusCode: response.statusCode);
    } catch (e) {
      _log('[API GET Error] $e');
      return ApiResponse.error(e.toString());
    }
  }

  /// POST 요청 (Form 데이터)
  Future<ApiResponse> post(String endpoint,
      {Map<String, String>? form}) async {
    final url = _buildUrl(endpoint);
    final headers = _buildHeaders(isJson: false);
    if (form != null && form.isNotEmpty) {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }

    try {
      _logRequest(
        method: 'POST (Form)',
        url: url,
        headers: headers,
        body: form?.toString(),
      );

      http.Response response;
      if (form != null && form.isNotEmpty) {
        response = await _httpClient.post(
          Uri.parse(url),
          headers: headers,
          body: form,
        );
      } else {
        response = await _httpClient.post(
          Uri.parse(url),
          headers: headers,
        );
      }

      _handleResponseCookies(response);

      final body = utf8.decode(response.bodyBytes);
      _logResponse(
        method: 'POST (Form)',
        url: url,
        statusCode: response.statusCode,
        headers: response.headers,
        body: body,
      );

      return ApiResponse.fromRawBody(body, statusCode: response.statusCode);
    } catch (e) {
      _log('[API POST Error] $e');
      return ApiResponse.error(e.toString());
    }
  }

  /// POST 요청 (JSON 데이터)
  Future<ApiResponse> postJson(String endpoint,
      {Map<String, dynamic>? data}) async {
    final url = _buildUrl(endpoint);
    final headers = _buildHeaders(isJson: true);
    final jsonBody = data != null ? jsonEncode(data) : '{}';

    try {
      _logRequest(
        method: 'POST (JSON)',
        url: url,
        headers: headers,
        body: jsonBody,
      );

      final response = await _httpClient.post(
        Uri.parse(url),
        headers: headers,
        body: jsonBody,
      );

      _handleResponseCookies(response);

      final body = utf8.decode(response.bodyBytes);
      _logResponse(
        method: 'POST (JSON)',
        url: url,
        statusCode: response.statusCode,
        headers: response.headers,
        body: body,
      );

      return ApiResponse.fromRawBody(body, statusCode: response.statusCode);
    } catch (e) {
      _log('[API POST JSON Error] $e');
      return ApiResponse.error(e.toString());
    }
  }

  /// 쿠키 설정
  void setCookie(String name, String value) {
    final domain = _extractDomain(_baseUrl);
    cookieManager.setCookie(domain, name, value);
  }

  /// 쿠키 가져오기
  String? getCookie(String name) {
    final domain = _extractDomain(_baseUrl);
    return cookieManager.getCookie(domain, name);
  }

  /// 쿠키 출력 (디버그)
  void printCookies() {
    cookieManager.printCookies();
  }

  /// 클라이언트 정리
  void dispose() {
    _httpClient.close();
  }
}

/// 전역 API 클라이언트 (나중에 초기화)
ApiClient? _globalApiClient;

/// 전역 API 클라이언트 가져오기
ApiClient getApiClient() {
  if (_globalApiClient == null) {
    throw StateError('API Client not initialized. Call initApiClient() first.');
  }
  return _globalApiClient!;
}

/// API 클라이언트 초기화
Future<ApiClient> initApiClient(String baseUrl) async {
  await cookieManager.init();
  _globalApiClient = ApiClient(baseUrl);
  return _globalApiClient!;
}

/// API 클라이언트 설정 여부 확인
bool isApiClientInitialized() {
  return _globalApiClient != null;
}
