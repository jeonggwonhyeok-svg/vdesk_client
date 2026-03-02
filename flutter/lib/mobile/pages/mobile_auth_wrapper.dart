/// 모바일용 인증 래퍼 위젯
/// 로그인 상태에 따라 LoginPage 또는 HomePage를 표시합니다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../models/platform_model.dart';
import '../../models/state_model.dart';
import '../../common/api/session_service.dart';
import '../../common/widgets/styled_form_widgets.dart';
import '../../desktop/pages/login_page.dart';
import './home_page.dart';

/// 인증 상태에 따라 적절한 페이지를 표시하는 래퍼 위젯
class MobileAuthWrapper extends StatefulWidget {
  const MobileAuthWrapper({Key? key}) : super(key: key);

  @override
  State<MobileAuthWrapper> createState() => _MobileAuthWrapperState();
}

class _MobileAuthWrapperState extends State<MobileAuthWrapper> {
  bool _isLoading = true;
  Timer? _sessionCheckTimer;

  @override
  void initState() {
    super.initState();
    _initCheck();
  }

  @override
  void dispose() {
    _sessionCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _initCheck() async {
    // 약간의 딜레이를 주어 userModel이 초기화될 시간을 줌
    await Future.delayed(const Duration(milliseconds: 100));

    // 자동 로그인이 아니면 로그인 데이터 삭제
    if (bind.mainGetLocalOption(key: 'auto_login') != 'Y') {
      await bind.mainSetLocalOption(key: 'access_token', value: '');
      await bind.mainSetLocalOption(key: 'user_info', value: '');
      await gFFI.userModel.reset();
    }

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

  /// 시작 시 버전 체크
  Future<void> _checkVersionOnStartup() async {
    try {
      if (!isSessionServiceInitialized()) return;
      final version = await bind.mainGetVersion();
      final res = await getSessionService().checkVersion(version);
      if (res.success) {
        final serverVersion = res.extract('version') ?? '';
        if (serverVersion.isNotEmpty && serverVersion != version) {
          debugPrint('[MobileAuthWrapper] Startup version mismatch: server=$serverVersion, current=$version');
          await _handleVersionUpdateRequired();
        }
      }
    } catch (e) {
      debugPrint('[MobileAuthWrapper] Startup version check error: $e');
    }
  }

  /// 주기적 버전 체크
  Future<void> _checkVersion() async {
    if (updateRequired.value) return; // 이미 업데이트 필요 상태
    try {
      if (!isSessionServiceInitialized()) return;
      final version = await bind.mainGetVersion();
      final res = await getSessionService().checkVersion(version);
      if (res.success) {
        final serverVersion = res.extract('version') ?? '';
        if (serverVersion.isNotEmpty && serverVersion != version) {
          debugPrint('[MobileAuthWrapper] Version mismatch: server=$serverVersion, current=$version');
          await _handleVersionUpdateRequired();
        }
      }
    } catch (e) {
      debugPrint('[MobileAuthWrapper] Version check error: $e');
    }
  }

  /// 버전 업데이트 필요 처리
  Future<void> _handleVersionUpdateRequired() async {
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

  /// 세션 상태 확인 (KILLED 체크)
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
          debugPrint('[MobileSessionMonitor] Session KILLED');
          await _handleSessionKilled();
        }
      }
    } catch (e) {
      debugPrint('[MobileSessionMonitor] Check error: $e');
    }
  }

  /// 세션 KILLED 처리 - 다른 기기에서 로그인됨
  Future<void> _handleSessionKilled() async {
    _sessionCheckTimer?.cancel();

    // 원격 연결 페이지에서 홈으로 돌아가기
    if (!stateGlobal.isInMainPage) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: SystemUiOverlay.values);
      gFFI.chatModel.hideChatOverlay();
      if (globalKey.currentContext != null) {
        Navigator.popUntil(globalKey.currentContext!, ModalRoute.withName("/"));
      }
      stateGlobal.isInMainPage = true;
    }

    // 활성 세션 종료
    if (gFFI.id.isNotEmpty) {
      await gFFI.close();
    }
    // CM 창의 모든 연결 종료
    await gFFI.serverModel.closeAll();

    // 로그아웃 처리
    await gFFI.userModel.reset(resetOther: true);

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

  void _onLoginSuccess() {
    setState(() {});
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
        return HomePage();
      } else {
        return LoginPage(onLoginSuccess: _onLoginSuccess);
      }
    });
  }
}
