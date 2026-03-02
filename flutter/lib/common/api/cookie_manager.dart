/// 쿠키 관리 클래스
/// HTTP 요청/응답에서 쿠키를 관리하고 영구 저장합니다.
library;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 쿠키 관리자 싱글톤
class CookieManager {
  static final CookieManager _instance = CookieManager._internal();
  factory CookieManager() => _instance;
  CookieManager._internal();

  /// 쿠키 저장소 (메모리)
  final Map<String, Map<String, Cookie>> _cookies = {};

  /// SharedPreferences 키 접두사
  static const String _cookiePrefix = 'cookie_';

  /// 초기화 - SharedPreferences에서 쿠키 로드
  Future<void> init() async {
    if (kIsWeb) return; // 웹에서는 브라우저가 쿠키 관리

    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_cookiePrefix));

      for (final key in keys) {
        final domain = key.substring(_cookiePrefix.length);
        final cookieString = prefs.getString(key);
        if (cookieString != null) {
          _parseCookieString(domain, cookieString);
        }
      }
      debugPrint('[CookieManager] Loaded ${_cookies.length} domain cookies');
    } catch (e) {
      debugPrint('[CookieManager] Failed to load cookies: $e');
    }
  }

  /// 쿠키 문자열 파싱
  void _parseCookieString(String domain, String cookieString) {
    final parts = cookieString.split('; ');
    for (final part in parts) {
      final idx = part.indexOf('=');
      if (idx > 0) {
        final name = part.substring(0, idx);
        final value = part.substring(idx + 1);
        setCookie(domain, name, value, save: false);
      }
    }
  }

  /// 쿠키 설정
  void setCookie(String domain, String name, String value, {bool save = true}) {
    _cookies[domain] ??= {};
    _cookies[domain]![name] = Cookie(name, value);

    if (save) {
      _saveCookies(domain);
    }
  }

  /// 쿠키 가져오기
  String? getCookie(String domain, String name) {
    return _cookies[domain]?[name]?.value;
  }

  /// 도메인의 모든 쿠키 가져오기
  Map<String, Cookie>? getCookiesForDomain(String domain) {
    return _cookies[domain];
  }

  /// 쿠키 삭제
  void removeCookie(String domain, String name) {
    _cookies[domain]?.remove(name);
    _saveCookies(domain);
  }

  /// 도메인의 모든 쿠키 삭제
  void clearCookies(String domain) {
    _cookies.remove(domain);
    _removeSavedCookies(domain);
  }

  /// 모든 쿠키 삭제
  Future<void> clearAllCookies() async {
    _cookies.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys =
          prefs.getKeys().where((k) => k.startsWith(_cookiePrefix)).toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (e) {
      debugPrint('[CookieManager] Failed to clear cookies: $e');
    }
  }

  /// Set-Cookie 헤더 파싱
  void parseSetCookieHeader(String domain, String setCookieHeader) {
    try {
      final cookie = Cookie.fromSetCookieValue(setCookieHeader);
      setCookie(domain, cookie.name, cookie.value);
    } catch (e) {
      // 간단한 파싱 시도
      final parts = setCookieHeader.split(';');
      if (parts.isNotEmpty) {
        final nameValue = parts[0].trim();
        final idx = nameValue.indexOf('=');
        if (idx > 0) {
          final name = nameValue.substring(0, idx);
          final value = nameValue.substring(idx + 1);
          setCookie(domain, name, value);
        }
      }
    }
  }

  /// 여러 Set-Cookie 헤더 파싱
  void parseSetCookieHeaders(String domain, List<String> headers) {
    for (final header in headers) {
      parseSetCookieHeader(domain, header);
    }
  }

  /// Cookie 헤더 문자열 생성
  String getCookieHeader(String domain) {
    final cookies = _cookies[domain];
    if (cookies == null || cookies.isEmpty) {
      return '';
    }

    return cookies.entries.map((e) => '${e.key}=${e.value.value}').join('; ');
  }

  /// 쿠키를 SharedPreferences에 저장
  Future<void> _saveCookies(String domain) async {
    if (kIsWeb) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cookies = _cookies[domain];

      if (cookies == null || cookies.isEmpty) {
        await prefs.remove('$_cookiePrefix$domain');
      } else {
        final cookieString =
            cookies.entries.map((e) => '${e.key}=${e.value.value}').join('; ');
        await prefs.setString('$_cookiePrefix$domain', cookieString);
      }
    } catch (e) {
      debugPrint('[CookieManager] Failed to save cookies: $e');
    }
  }

  /// 저장된 쿠키 삭제
  Future<void> _removeSavedCookies(String domain) async {
    if (kIsWeb) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_cookiePrefix$domain');
    } catch (e) {
      debugPrint('[CookieManager] Failed to remove saved cookies: $e');
    }
  }

  /// 디버그: 모든 쿠키 출력
  void printCookies() {
    debugPrint('[CookieManager] ===== All Cookies =====');
    for (final domain in _cookies.keys) {
      debugPrint('Domain: $domain');
      for (final entry in _cookies[domain]!.entries) {
        debugPrint('  ${entry.key}=${entry.value.value}');
      }
    }
    debugPrint('[CookieManager] =======================');
  }
}

/// 전역 CookieManager 인스턴스
final cookieManager = CookieManager();
