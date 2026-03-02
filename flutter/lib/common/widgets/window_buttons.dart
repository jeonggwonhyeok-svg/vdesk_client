/// 공용 창 컨트롤 버튼 위젯
/// 메인 앱과 인증 페이지에서 공통으로 사용
library;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';

import '../../common.dart';
import '../../models/state_model.dart';
import '../../main.dart';

/// 창 버튼 테마
enum WindowButtonTheme {
  light, // 흰색 배경, 회색 아이콘
  dark, // 파란색 배경, 흰색 아이콘
}

/// 기본 창 버튼 높이
const double kWindowButtonHeight = 44.0;

/// 기본 창 버튼 너비
const double kWindowButtonWidth = 46.0;

/// 기본 아이콘 크기
const double kWindowButtonIconSize = 24.0;

/// 창 컨트롤 버튼 (최소화, 최대화, 닫기)
class WindowControlButtons extends StatefulWidget {
  final bool isMainWindow;
  final WindowButtonTheme theme;
  final double height;
  final double buttonWidth;
  final double iconSize;
  final bool showMinimize;
  final bool showMaximize;
  final bool showClose;
  final Future<bool> Function()? onClose;

  const WindowControlButtons({
    Key? key,
    this.isMainWindow = true,
    this.theme = WindowButtonTheme.light,
    this.height = kWindowButtonHeight,
    this.buttonWidth = kWindowButtonWidth,
    this.iconSize = kWindowButtonIconSize,
    this.showMinimize = true,
    this.showMaximize = true,
    this.showClose = true,
    this.onClose,
  }) : super(key: key);

  @override
  State<WindowControlButtons> createState() => _WindowControlButtonsState();
}

class _WindowControlButtonsState extends State<WindowControlButtons> {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    _checkMaximized();
  }

  Future<void> _checkMaximized() async {
    if (widget.isMainWindow) {
      _isMaximized = await windowManager.isMaximized();
    } else if (kWindowId != null) {
      final wc = WindowController.fromWindowId(kWindowId!);
      _isMaximized = await wc.isMaximized();
    }
    if (mounted) setState(() {});
  }

  void _onMinimize() {
    if (widget.isMainWindow) {
      windowManager.minimize();
    } else if (kWindowId != null) {
      WindowController.fromWindowId(kWindowId!).minimize();
    }
  }

  Future<void> _onMaximize() async {
    bool newMaximized;
    if (widget.isMainWindow) {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
        newMaximized = false;
      } else {
        await windowManager.maximize();
        newMaximized = true;
      }
    } else if (kWindowId != null) {
      final wc = WindowController.fromWindowId(kWindowId!);
      if (await wc.isMaximized()) {
        await wc.unmaximize();
        newMaximized = false;
      } else {
        await wc.maximize();
        newMaximized = true;
      }
    } else {
      return;
    }
    // 상태 즉시 업데이트
    if (mounted) {
      setState(() => _isMaximized = newMaximized);
    }
    stateGlobal.setMaximized(newMaximized);
  }

  void _onClose() async {
    // 원래 RustDesk 코드와 동일한 방식으로 처리
    // 1. onClose 콜백 호출 (확인 다이얼로그 등)
    // 2. 결과가 true면 Future.delayed로 비동기 close 실행
    final res = await widget.onClose?.call() ?? true;
    if (res) {
      // Future.delayed(Duration.zero)로 현재 이벤트 루프 이후에 실행
      // 이렇게 하면 UI 스레드를 블로킹하지 않음
      Future.delayed(Duration.zero, () async {
        if (widget.isMainWindow) {
          await windowManager.close();
        } else if (kWindowId != null) {
          await WindowController.fromWindowId(kWindowId!).close();
        }
      });
    }
  }

  Color get _iconColor {
    return widget.theme == WindowButtonTheme.light
        ? Colors.grey.shade600
        : Colors.white;
  }

  Color get _hoverColor {
    return widget.theme == WindowButtonTheme.light
        ? Colors.grey.withValues(alpha: 0.15)
        : Colors.white.withValues(alpha: 0.1);
  }

  @override
  Widget build(BuildContext context) {
    if (isMacOS) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showMinimize)
          _WindowButton(
            iconPath: 'assets/icons/top-mini.svg',
            iconSize: widget.iconSize,
            iconColor: _iconColor,
            buttonWidth: widget.buttonWidth,
            buttonHeight: widget.height,
            hoverColor: _hoverColor,
            onPressed: _onMinimize,
            tooltip: translate('Minimize'),
          ),
        if (widget.showMaximize)
          _WindowButton(
            iconPath: _isMaximized
                ? 'assets/icons/topbar-change-to-normal.svg'
                : 'assets/icons/topbar-change-to-big.svg',
            iconSize: widget.iconSize,
            iconColor: _iconColor,
            buttonWidth: widget.buttonWidth,
            buttonHeight: widget.height,
            hoverColor: _hoverColor,
            onPressed: _onMaximize,
            tooltip: _isMaximized ? translate('Restore') : translate('Maximize'),
          ),
        if (widget.showClose)
          _WindowButton(
            iconPath: 'assets/icons/topbar-close.svg',
            iconSize: widget.iconSize,
            iconColor: _iconColor,
            buttonWidth: widget.buttonWidth,
            buttonHeight: widget.height,
            hoverColor: Colors.red.withValues(alpha: 0.8),
            hoverIconColor: Colors.white,
            onPressed: _onClose,
            tooltip: translate('Close'),
            isClose: true,
          ),
      ],
    );
  }
}

/// 개별 창 버튼 위젯
class _WindowButton extends StatefulWidget {
  final String iconPath;
  final double iconSize;
  final Color iconColor;
  final double buttonWidth;
  final double buttonHeight;
  final Color hoverColor;
  final Color? hoverIconColor;
  final VoidCallback onPressed;
  final String? tooltip;
  final bool isClose;

  const _WindowButton({
    required this.iconPath,
    required this.iconSize,
    required this.iconColor,
    required this.buttonWidth,
    required this.buttonHeight,
    required this.hoverColor,
    this.hoverIconColor,
    required this.onPressed,
    this.tooltip,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final currentIconColor = _isHovered && widget.hoverIconColor != null
        ? widget.hoverIconColor!
        : widget.iconColor;

    Widget button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPressed,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Container(
          width: widget.buttonWidth,
          height: widget.buttonHeight,
          color: _isHovered ? widget.hoverColor : Colors.transparent,
          child: Center(
            child: SvgPicture.asset(
              widget.iconPath,
              width: widget.iconSize,
              height: widget.iconSize,
              colorFilter: ColorFilter.mode(currentIconColor, BlendMode.srcIn),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(seconds: 1),
        child: button,
      );
    }

    return button;
  }
}

/// 창 드래그 시작 헬퍼 함수
void startWindowDragging(bool isMainWindow) {
  if (isMainWindow) {
    windowManager.startDragging();
  } else if (kWindowId != null) {
    WindowController.fromWindowId(kWindowId!).startDragging();
  }
}

/// 창 이동 가능 여부 설정 헬퍼 함수
void setWindowMovable(bool isMainWindow, bool movable) {
  if (isMainWindow) {
    windowManager.setMovable(movable);
  } else if (kWindowId != null) {
    WindowController.fromWindowId(kWindowId!).setMovable(movable);
  }
}

/// 창 최대화 토글 헬퍼 함수
Future<bool> toggleWindowMaximize(bool isMainWindow) async {
  if (isMainWindow) {
    if (await windowManager.isMaximized()) {
      windowManager.unmaximize();
      return false;
    } else {
      windowManager.maximize();
      return true;
    }
  } else if (kWindowId != null) {
    final wc = WindowController.fromWindowId(kWindowId!);
    if (await wc.isMaximized()) {
      wc.unmaximize();
      return false;
    } else {
      wc.maximize();
      return true;
    }
  }
  return false;
}
