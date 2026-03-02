/// 인증 래퍼 위젯
/// 로그인 상태에 따라 LoginPage 또는 메인 화면을 표시합니다.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import '../../common.dart';
import '../../models/platform_model.dart';
import '../../common/api/auth_service.dart';
import '../../common/api/session_service.dart';
import '../../common/widgets/styled_form_widgets.dart';
import '../../utils/multi_window_manager.dart';
import './login_page.dart';
import './desktop_tab_page.dart';

/// 트레이 종료 시 사용하는 플래그 파일 경로
const _kQuitFlagPath = '/tmp/onedesk_quit';

/// 인증 상태에 따라 적절한 페이지를 표시하는 래퍼 위젯
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WindowListener {
  bool _isLoading = true;
  Timer? _quitCheckTimer;
  Timer? _sessionCheckTimer;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // 시작 시 이전 종료 플래그 정리
    try { File(_kQuitFlagPath).deleteSync(); } catch (_) {}
    // 트레이 종료 플래그를 주기적으로 확인
    if (Platform.isMacOS) {
      _quitCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (File(_kQuitFlagPath).existsSync()) {
          try { File(_kQuitFlagPath).deleteSync(); } catch (_) {}
          _handleQuit();
        }
      });
    }
    _initCheck();
  }

  @override
  void dispose() {
    _quitCheckTimer?.cancel();
    _sessionCheckTimer?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _handleQuit() async {
    final isAutoLogin = bind.mainGetLocalOption(key: 'auto_login') == 'Y';
    final isLoggedIn = gFFI.userModel.userName.isNotEmpty ||
                       gFFI.userModel.userEmail.isNotEmpty;

    if (!isAutoLogin && isLoggedIn) {
      // 세션 종료 API (에러 무시, 로딩 다이얼로그 없음)
      try {
        if (isSessionServiceInitialized() && gFFI.userModel.sessionKey.value.isNotEmpty) {
          await getSessionService().endSession(gFFI.userModel.sessionKey.value);
        }
      } catch (_) {}
      // 로그아웃 API (에러 무시)
      try {
        if (isAuthServiceInitialized()) {
          await getAuthService().logout();
        }
      } catch (_) {}
      // 로컬 데이터 정리
      await gFFI.userModel.reset(resetOther: true);
    }
    exit(0);
  }

  /// 세션 KILLED 처리 - 다른 기기에서 로그인됨
  Future<void> _handleSessionKilled() async {
    _sessionCheckTimer?.cancel();

    // 모든 원격 세션 종료
    await oneDeskWinManager.closeAllSubWindows();
    // CM 창의 모든 연결 종료
    await gFFI.serverModel.closeAll();

    // 로그아웃 처리
    await gFFI.userModel.reset(resetOther: true);

    // 창 보이기
    await windowManager.show();
    await windowManager.focus();

    // 다이얼로그 표시
    if (mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: EdgeInsets.zero,
          content: Container(
            width: 320,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFEFEFE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  translate('Warning'),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF454447),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  translate('Login other device'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF454447),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: StyledPrimaryButton(
                    label: translate('OK'),
                    height: 52,
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  /// 버전 업데이트 필요 처리
  Future<void> _handleVersionUpdateRequired() async {
    debugPrint('[AuthWrapper] Version update required');

    // 로그인 상태라면 로그아웃
    final isLoggedIn = gFFI.userModel.userName.isNotEmpty ||
                       gFFI.userModel.userEmail.isNotEmpty;
    if (isLoggedIn) {
      await gFFI.userModel.reset(resetOther: true);
    }

    // 업데이트 필요 플래그 설정 (LoginPage가 비활성화됨)
    updateRequired.value = true;

    // 다이얼로그 표시
    if (mounted) {
      await windowManager.show();
      await windowManager.focus();
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: EdgeInsets.zero,
          content: Container(
            width: 320,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFEFEFE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  translate('Warning'),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF454447),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  translate('Can use on update'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF454447),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: StyledPrimaryButton(
                    label: translate('OK'),
                    height: 52,
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  /// 시작 시 버전 체크
  Future<void> _checkVersionOnStartup() async {
    try {
      if (!isSessionServiceInitialized()) return;
      final version = await bind.mainGetVersion();
      final res = await getSessionService().checkVersion(version);
      if (res.success) {
        final serverVersion = res.extract('version') ?? '';
        if (serverVersion.isNotEmpty && serverVersion != version) {
          debugPrint('[AuthWrapper] Startup version mismatch: server=$serverVersion, current=$version');
          await _handleVersionUpdateRequired();
        }
      }
    } catch (e) {
      debugPrint('[AuthWrapper] Startup version check error: $e');
    }
  }

  Future<void> _initCheck() async {
    // 약간의 딜레이를 주어 userModel이 초기화될 시간을 줌
    await Future.delayed(const Duration(milliseconds: 100));

    if (mounted) {
      setState(() => _isLoading = false);
    }

    // 시작 시 버전 체크
    await _checkVersionOnStartup();

    // 세션 상태 + 버전 주기적 체크 시작 (3분 간격)
    _sessionCheckTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      _checkSession();
      _checkVersion();
    });
  }

  /// 주기적 세션 상태 확인 (KILLED 체크)
  Future<void> _checkSession() async {
    final isLoggedIn = gFFI.userModel.userName.isNotEmpty ||
                       gFFI.userModel.userEmail.isNotEmpty;
    if (!isLoggedIn) return;
    if (!isSessionServiceInitialized()) return;
    if (gFFI.userModel.sessionKey.value.isEmpty) return;
    if (gFFI.userModel.deviceKey.value.isEmpty) return;

    try {
      final res = await getSessionService().getCurrentSessions(
        gFFI.userModel.deviceKey.value,
        gFFI.userModel.sessionKey.value,
      );

      if (res.success) {
        final status = res.extract('status') ?? '';
        if (status == 'KILLED') {
          debugPrint('[AuthWrapper] Session KILLED detected');
          await _handleSessionKilled();
        }
      }
    } catch (e) {
      debugPrint('[AuthWrapper] Session check error: $e');
    }
  }

  /// 주기적 버전 체크
  Future<void> _checkVersion() async {
    if (updateRequired.value) return;
    try {
      if (!isSessionServiceInitialized()) return;
      final version = await bind.mainGetVersion();
      final res = await getSessionService().checkVersion(version);
      if (res.success) {
        final serverVersion = res.extract('version') ?? '';
        if (serverVersion.isNotEmpty && serverVersion != version) {
          debugPrint('[AuthWrapper] Version mismatch: server=$serverVersion, current=$version');
          await _handleVersionUpdateRequired();
        }
      }
    } catch (e) {
      debugPrint('[AuthWrapper] Version check error: $e');
    }
  }

  void _onLoginSuccess() {
    setState(() {});
  }

  @override
  void onWindowClose() {
    // 로그인 여부와 관계없이 창 숨김 (트레이에서 다시 열기 가능)
    windowManager.hide();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Obx를 사용하여 userModel의 userName 변화를 감지
    return Obx(() {
      final isLoggedIn = gFFI.userModel.userName.isNotEmpty ||
                         gFFI.userModel.userEmail.isNotEmpty;

      if (isLoggedIn) {
        return const DesktopTabPage();
      } else {
        return LoginPage(onLoginSuccess: _onLoginSuccess);
      }
    });
  }
}
