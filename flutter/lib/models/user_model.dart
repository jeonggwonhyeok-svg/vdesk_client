import 'dart:async';
import 'dart:convert';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/common/api/models.dart' as api_models;
import 'package:flutter_hbb/common/api/auth_service.dart';
import 'package:flutter_hbb/common/api/session_service.dart';
import 'package:flutter_hbb/common/api/cookie_manager.dart';
import 'package:flutter_hbb/common/api/api_client.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:get/get.dart';

import '../common.dart';
import '../utils/http_service.dart' as http;
import 'model.dart';
import 'platform_model.dart';

bool refreshingUser = false;

class UserModel {
  final RxString userName = ''.obs;
  final RxString userEmail = ''.obs;
  final RxInt userType = 1.obs; // 0=FREE, 1=SOLO, 2=PRO, 3=TEAM, 4=BUSINESS
  final RxInt loginType = 0.obs; // 0=email, 1=google
  final RxString deviceKey = ''.obs;
  final RxString sessionKey = ''.obs;
  final RxBool isAdmin = false.obs;
  final RxString networkError = ''.obs;
  final RxString planType = 'FREE'.obs; // 반응형 플랜 타입 (FREE, SOLO, PRO, TEAM, BUSINESS)
  final RxInt connectionCount = 1.obs; // 동시 접속 가능 수
  bool get isLogin => userName.isNotEmpty || userEmail.isNotEmpty;
  WeakReference<FFI> parent;

  /// 현재 사용자 정보
  api_models.UserInfo? currentUserInfo;

  UserModel(this.parent) {
    userName.listen((p0) {
      // When user name becomes empty, show login button
      // When user name becomes non-empty:
      //  For _updateLocalUserInfo, network error will be set later
      //  For login success, should clear network error
      networkError.value = '';
    });
  }

  void refreshCurrentUser() async {
    if (bind.isDisableAccount()) return;
    networkError.value = '';
    final token = bind.mainGetLocalOption(key: 'access_token');
    if (token == '') {
      await updateOtherModels();
      return;
    }
    _updateLocalUserInfo();
    final url = await bind.mainGetApiServer();
    final body = {
      'id': await bind.mainGetMyId(),
      'uuid': await bind.mainGetUuid()
    };
    if (refreshingUser) return;
    try {
      refreshingUser = true;
      final http.Response response;
      try {
        response = await http.post(Uri.parse('$url/api/currentUser'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token'
            },
            body: json.encode(body));
      } catch (e) {
        networkError.value = e.toString();
        rethrow;
      }
      refreshingUser = false;
      final status = response.statusCode;
      if (status == 401 || status == 400) {
        reset(resetOther: status == 401);
        return;
      }
      final data = json.decode(decode_http_response(response));
      final error = data['error'];
      if (error != null) {
        throw error;
      }

      final user = UserPayload.fromJson(data);
      _parseAndUpdateUser(user);
    } catch (e) {
      debugPrint('Failed to refreshCurrentUser: $e');
    } finally {
      refreshingUser = false;
      await updateOtherModels();
    }
  }

  static Map<String, dynamic>? getLocalUserInfo() {
    final userInfo = bind.mainGetLocalOption(key: 'user_info');
    if (userInfo == '') {
      return null;
    }
    try {
      return json.decode(userInfo);
    } catch (e) {
      debugPrint('Failed to get local user info "$userInfo": $e');
    }
    return null;
  }

  _updateLocalUserInfo() {
    final userInfo = getLocalUserInfo();
    if (userInfo != null) {
      userName.value = userInfo['name'];
    }
  }

  Future<void> reset({bool resetOther = false}) async {
    await bind.mainSetLocalOption(key: 'access_token', value: '');
    await bind.mainSetLocalOption(key: 'user_info', value: '');
    if (resetOther) {
      await gFFI.abModel.reset();
      await gFFI.groupModel.reset();
    }

    // 새 API 시스템 관련 정리
    userName.value = '';
    userEmail.value = '';
    userType.value = 1;
    loginType.value = 0;
    deviceKey.value = '';
    sessionKey.value = '';
    planType.value = 'FREE';
    connectionCount.value = 1;
    currentUserInfo = null;

    // 쿠키 정리
    await cookieManager.clearAllCookies();

    // Rust 서비스용 인증 정보 정리
    await bind.mainSetLocalOption(key: 'auth_cookie', value: '');
    await bind.mainSetLocalOption(key: 'auth_user_agent', value: '');
    await bind.mainSetLocalOption(key: 'session_key', value: '');
    await bind.mainSetLocalOption(key: 'device_key', value: '');
  }

  _parseAndUpdateUser(UserPayload user) {
    userName.value = user.name;
    isAdmin.value = user.isAdmin;
    bind.mainSetLocalOption(key: 'user_info', value: jsonEncode(user));
    if (isWeb) {
      // ugly here, tmp solution
      bind.mainSetLocalOption(key: 'verifier', value: user.verifier ?? '');
    }
  }

  // update ab and group status
  // 기존 RustDesk API 비활성화 - 새 API 시스템 사용
  static Future<void> updateOtherModels() async {
    // TODO: 새 API 시스템으로 주소록/그룹 기능 구현 시 활성화
    // await Future.wait([
    //   gFFI.abModel.pullAb(force: ForcePullAb.listAndCurrent, quiet: false),
    //   gFFI.groupModel.pull()
    // ]);
  }

  Future<void> logOut({String? apiServer}) async {
    final tag = gFFI.dialogManager.showLoading(translate('Logging out...'));
    try {
      // 새 API 시스템을 사용하여 로그아웃 시도
      if (isAuthServiceInitialized()) {
        try {
          // 세션 종료
          if (isSessionServiceInitialized() && sessionKey.value.isNotEmpty) {
            await getSessionService().endSession(sessionKey.value);
          }
          // 로그아웃 API 호출
          await getAuthService().logout();
        } catch (e) {
          debugPrint("New API logout failed: $e");
        }
      }

      // 기존 API 시스템 로그아웃 (백워드 호환성)
      final url = apiServer ?? await bind.mainGetApiServer();
      final authHeaders = getHttpHeaders();
      authHeaders['Content-Type'] = "application/json";
      await http
          .post(Uri.parse('$url/api/logout'),
              body: jsonEncode({
                'id': await bind.mainGetMyId(),
                'uuid': await bind.mainGetUuid(),
              }),
              headers: authHeaders)
          .timeout(Duration(seconds: 2));
    } catch (e) {
      debugPrint("request /api/logout failed: err=$e");
    } finally {
      await reset(resetOther: true);
      gFFI.dialogManager.dismissByTag(tag);
    }
  }

  /// 새 API 시스템용 로그인 (UserInfo 사용)
  void loginWithUserInfo(api_models.UserInfo userInfo) {
    currentUserInfo = userInfo;
    userName.value = userInfo.nick ?? userInfo.email;
    userEmail.value = userInfo.email;
    userType.value = userInfo.type;
    loginType.value = userInfo.loginType;
    deviceKey.value = userInfo.deviceKey ?? '';
    sessionKey.value = userInfo.sessionKey ?? '';

    // ApiClient에 deviceKey 설정 (User-Agent에 반영)
    if (isApiClientInitialized() && deviceKey.value.isNotEmpty) {
      getApiClient().setDeviceKey(deviceKey.value);
    }
    planType.value = userInfo.planType ?? 'FREE'; // 반응형 플랜 타입 업데이트
    connectionCount.value = userInfo.connectionCount; // 동시 접속 가능 수 업데이트

    // 로컬 옵션에 사용자 정보 저장
    bind.mainSetLocalOption(
      key: 'user_info',
      value: jsonEncode(userInfo.toJson()),
    );

    // Rust 서비스에서 API 요청에 사용할 수 있도록 LocalConfig에 인증 정보 저장
    _saveAuthInfoToLocalConfig();

    debugPrint('User logged in: ${userInfo.email}, planType=${userInfo.planType}, connectionCount=${userInfo.connectionCount}');
  }

  /// Rust 서비스용 인증 정보를 LocalConfig에 저장
  void _saveAuthInfoToLocalConfig() {
    try {
      if (!isApiClientInitialized()) return;

      final apiClient = getApiClient();
      final domain = Uri.parse(apiClient.baseUrl).host;

      // 쿠키 헤더 저장
      final cookieHeader = cookieManager.getCookieHeader(domain);
      if (cookieHeader.isNotEmpty) {
        bind.mainSetLocalOption(key: 'auth_cookie', value: cookieHeader);
      }

      // User-Agent 저장
      final userAgent = ClientInfoHelper.getClientInfo(deviceKey.value.isNotEmpty ? deviceKey.value : null);
      bind.mainSetLocalOption(key: 'auth_user_agent', value: userAgent);

      // API 서버 URL 저장
      bind.mainSetLocalOption(key: 'api_server_url', value: apiClient.baseUrl);

      // sessionKey, deviceKey 저장
      if (sessionKey.value.isNotEmpty) {
        bind.mainSetLocalOption(key: 'session_key', value: sessionKey.value);
      }
      if (deviceKey.value.isNotEmpty) {
        bind.mainSetLocalOption(key: 'device_key', value: deviceKey.value);
      }

      debugPrint('[UserModel] Auth info saved to LocalConfig for Rust service');
    } catch (e) {
      debugPrint('[UserModel] Failed to save auth info to LocalConfig: $e');
    }
  }

  /// 저장된 사용자 정보로 세션 복원
  Future<bool> restoreSession() async {
    try {
      if (!isAuthServiceInitialized()) return false;

      final authService = getAuthService();
      final meRes = await authService.me();

      if (!meRes.success || meRes.data == null) {
        return false;
      }

      final userInfo = api_models.UserInfo.fromJson(meRes.data!);

      // 세션 등록 및 활성화
      if (isSessionServiceInitialized()) {
        final sessionService = getSessionService();
        final version = await bind.mainGetVersion();

        final registerRes = await sessionService.registerSession(
          version,
          deviceId: platformFFI.deviceId,
          deviceName: platformFFI.deviceName,
        );
        if (registerRes.success) {
          userInfo.deviceKey = registerRes.extract('deviceKey');

          final activateRes = await sessionService.activateSession(userInfo.deviceKey ?? '');
          if (activateRes.success) {
            userInfo.sessionKey = activateRes.extract('sessionKey');
          }
        }
      }

      loginWithUserInfo(userInfo);
      return true;
    } catch (e) {
      debugPrint('Failed to restore session: $e');
      return false;
    }
  }

  /// throw [RequestException]
  Future<LoginResponse> login(LoginRequest loginRequest) async {
    final url = await bind.mainGetApiServer();
    final resp = await http.post(Uri.parse('$url/api/login'),
        body: jsonEncode(loginRequest.toJson()));

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(decode_http_response(resp));
    } catch (e) {
      debugPrint("login: jsonDecode resp body failed: ${e.toString()}");
      if (resp.statusCode != 200) {
        BotToast.showText(
            contentColor: Colors.red, text: 'HTTP ${resp.statusCode}');
      }
      rethrow;
    }
    if (resp.statusCode != 200) {
      throw RequestException(resp.statusCode, body['error'] ?? '');
    }
    if (body['error'] != null) {
      throw RequestException(0, body['error']);
    }

    return getLoginResponseFromAuthBody(body);
  }

  LoginResponse getLoginResponseFromAuthBody(Map<String, dynamic> body) {
    final LoginResponse loginResponse;
    try {
      loginResponse = LoginResponse.fromJson(body);
    } catch (e) {
      debugPrint("login: jsonDecode LoginResponse failed: ${e.toString()}");
      rethrow;
    }

    final isLogInDone = loginResponse.type == HttpType.kAuthResTypeToken &&
        loginResponse.access_token != null;
    if (isLogInDone && loginResponse.user != null) {
      _parseAndUpdateUser(loginResponse.user!);
    }

    return loginResponse;
  }

  static Future<List<dynamic>> queryOidcLoginOptions() async {
    try {
      final url = await bind.mainGetApiServer();
      if (url.trim().isEmpty) return [];
      final resp = await http.get(Uri.parse('$url/api/login-options'));
      final List<String> ops = [];
      for (final item in jsonDecode(resp.body)) {
        ops.add(item as String);
      }
      for (final item in ops) {
        if (item.startsWith('common-oidc/')) {
          return jsonDecode(item.substring('common-oidc/'.length));
        }
      }
      return ops
          .where((item) => item.startsWith('oidc/'))
          .map((item) => {'name': item.substring('oidc/'.length)})
          .toList();
    } catch (e) {
      debugPrint(
          "queryOidcLoginOptions: jsonDecode resp body failed: ${e.toString()}");
      return [];
    }
  }
}
