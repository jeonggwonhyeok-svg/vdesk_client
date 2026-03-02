/// 세션 서비스
/// 세션 관리, 디바이스 등록, 버전 체크 등
library;

import 'api_client.dart';
import 'models.dart';

/// 세션 서비스 클래스
class SessionService {
  final ApiClient _api;

  SessionService(this._api);

  /// 내 세션 목록 조회
  Future<ApiResponse> getMySessions() async {
    return await _api.get('api/sessions/me');
  }

  /// 현재 세션 상태 조회
  Future<ApiResponse> getCurrentSessions(
      String deviceKey, String sessionKey) async {
    return await _api.postJson('api/devices/sessions/status/me/current', data: {
      'deviceKey': deviceKey,
      'sessionKey': sessionKey,
    });
  }

  /// 세션 등록 (디바이스 등록)
  Future<ApiResponse> registerSession(String version, {required String deviceId, String? deviceName}) async {
    return await _api.postJson('api/devices/register', data: {
      'localBox': deviceId,
      'deviceName': deviceName ?? deviceId,
      'deviceId': deviceId,
      'deviceVersion': version,
    });
  }

  /// 세션 활성화
  Future<ApiResponse> activateSession(String deviceKey) async {
    return await _api.postJson('api/devices/sessions/activate', data: {
      'deviceKey': deviceKey,
    });
  }

  /// 세션 종료
  Future<ApiResponse> endSession(String sessionKey) async {
    return await _api.postJson('api/devices/sessions/end', data: {
      'sessionKey': sessionKey,
    });
  }

  /// 버전 체크
  Future<ApiResponse> checkVersion(String version) async {
    return await _api.postJson('api/devices/version/update/check', data: {
      'currentVersion': version,
    });
  }
}

/// 전역 SessionService 인스턴스 (나중에 초기화)
SessionService? _globalSessionService;

/// 전역 SessionService 가져오기
SessionService getSessionService() {
  if (_globalSessionService == null) {
    throw StateError(
        'SessionService not initialized. Call initSessionService() first.');
  }
  return _globalSessionService!;
}

/// SessionService 초기화
SessionService initSessionService(ApiClient apiClient) {
  _globalSessionService = SessionService(apiClient);
  return _globalSessionService!;
}

/// SessionService 설정 여부 확인
bool isSessionServiceInitialized() {
  return _globalSessionService != null;
}
