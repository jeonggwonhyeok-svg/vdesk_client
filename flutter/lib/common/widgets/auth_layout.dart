/// 인증 페이지 공통 레이아웃 위젯
/// 로그인, 회원가입, 비밀번호 재설정 페이지에서 공통으로 사용
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../common.dart' show isDesktop;
import './window_buttons.dart';

// StyledTextField를 re-export (하위 호환성)
export './styled_text_field.dart';
// flutter_svg re-export
export 'package:flutter_svg/flutter_svg.dart' show SvgPicture;

/// 인증 페이지 타이틀바 높이
const double kAuthTitleBarHeight = kWindowButtonHeight;

/// 인증 페이지 공통 border radius
const double kAuthBorderRadius = 8.0;

/// 인증 페이지 타이틀바 (흰색 배경, 파란색 로고, 회색 창 버튼)
class AuthTitleBar extends StatelessWidget {
  const AuthTitleBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kAuthTitleBarHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade200,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 로고 아이콘 (파란색, 세로 중앙 정렬)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Center(
              child: SvgPicture.asset(
                'assets/icons/topbar-logo.svg',
                width: 20,
                height: 20,
                colorFilter:
                    const ColorFilter.mode(Color(0xFF5B7BF8), BlendMode.srcIn),
              ),
            ),
          ),
          // 드래그 영역
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => startWindowDragging(true),
              onDoubleTap: () => toggleWindowMaximize(true),
              child: const SizedBox.expand(),
            ),
          ),
          // 창 컨트롤 버튼 (공용 컴포넌트 사용)
          const WindowControlButtons(
            isMainWindow: true,
            theme: WindowButtonTheme.light,
          ),
        ],
      ),
    );
  }
}

/// 브랜드 로고 (그라데이션 위에 표시, 흰색) - 로고만
class AuthBrandLogo extends StatelessWidget {
  const AuthBrandLogo({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/main-unlogin-logo.svg',
      width: 140,
      height: 24,
      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
    );
  }
}

/// 인증 페이지 레이아웃 (브랜드 영역 + 폼 영역 + 타이틀바)
class AuthPageLayout extends StatelessWidget {
  final Widget formContent;
  final Widget? mobileHeader; // 모바일에서 상단 고정 헤더

  const AuthPageLayout({
    Key? key,
    required this.formContent,
    this.mobileHeader,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 모바일: 폼만 전체 화면으로 표시 (키보드 올라와도 스크롤 가능)
    if (!isDesktop) {
      return Scaffold(
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                // 상단 고정 헤더
                if (mobileHeader != null) mobileHeader!,
                // 스크롤 가능한 폼 영역
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: IntrinsicHeight(
                            child: formContent,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 데스크톱: 기존 레이아웃 (브랜드 + 폼)
    return Scaffold(
      body: Stack(
        children: [
          // 1. 기본 배경 (흰색/라이트)
          Positioned.fill(
            child: Container(color: Theme.of(context).scaffoldBackgroundColor),
          ),
          // 2. 브랜드 영역 (왼쪽 55%, 그라데이션, 둥근 모서리, 패딩)
          Positioned(
            left: 24,
            top: kAuthTitleBarHeight + 24,
            bottom: 24,
            width: MediaQuery.of(context).size.width * 0.59 - 48,
            child: Container(
              decoration: BoxDecoration(
                gradient: const RadialGradient(
                  center: Alignment(-1.0, -0.5), // 좌측 0, 25% 위치
                  radius: 1.5,
                  colors: [
                    Color(0xFF6070F5), // 중심: 진한 블루
                    Color.fromARGB(255, 142, 155, 253), // 중간
                    Color.fromARGB(255, 161, 182, 238), // 청록
                    Color.fromARGB(255, 201, 201, 250), // 가장자리: 라벤더
                  ],
                  stops: [0.0, 0.25, 0.5, 1.0],
                ),
                borderRadius: BorderRadius.circular(kAuthBorderRadius),
              ),
              child: const Center(child: AuthBrandLogo()),
            ),
          ),
          // 3. 폼 영역 (오른쪽 45%, 전체 높이 사용)
          Positioned(
            right: 0,
            top: kAuthTitleBarHeight,
            bottom: 0,
            width: MediaQuery.of(context).size.width * 0.41,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth > 355 ? 355.0 : constraints.maxWidth;
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: width,
                      height: constraints.maxHeight,
                      child: formContent,
                    ),
                  );
                },
              ),
            ),
          ),
          // 4. 타이틀바 (최상위 오버레이)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AuthTitleBar(),
          ),
        ],
      ),
    );
  }
}

/// 인증 페이지 메인 버튼 (로그인/회원가입 등) - 호버 효과 포함
class AuthMainButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isInProgress;
  final bool isOutlined; // true: 흰 배경 + 테두리, false: 파란 배경

  const AuthMainButton({
    Key? key,
    required this.label,
    this.onPressed,
    this.isInProgress = false,
    this.isOutlined = false,
  }) : super(key: key);

  @override
  State<AuthMainButton> createState() => _AuthMainButtonState();
}

class _AuthMainButtonState extends State<AuthMainButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF5B7BF8);
    const hoverBorderColor = Color(0xFF5F71FF);

    final isDisabled = widget.onPressed == null || widget.isInProgress;

    // Outlined 스타일 (인증번호 발송 버튼 등)
    if (widget.isOutlined) {
      final borderColor = isDisabled
          ? Colors.grey[300]!
          : (_isHovered ? primaryColor : Colors.grey[300]!);
      final textColor = isDisabled
          ? Colors.grey[400]!
          : (_isHovered ? primaryColor : Colors.grey[600]!);

      return MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: SizedBox(
          height: 56,
          width: double.infinity,
          child: OutlinedButton(
            onPressed: widget.isInProgress ? null : widget.onPressed,
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[100],
              side: BorderSide(color: borderColor, width: 1),
              overlayColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 16,
                color: textColor,
              ),
            ),
          ),
        ),
      );
    }

    // Primary 스타일 (로그인/회원가입 버튼 등)
    final borderColor = isDisabled
        ? Colors.grey[300]!
        : (_isHovered ? hoverBorderColor : primaryColor);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: borderColor,
              width: 1,
            ),
          ),
          child: ElevatedButton(
            onPressed: widget.isInProgress ? null : widget.onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              disabledBackgroundColor: Colors.grey[300],
              elevation: 0,
              overlayColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 16,
                color: isDisabled ? Colors.grey[500] : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 소셜 로그인 버튼 - 디자인에 맞춤
class AuthSocialButton extends StatefulWidget {
  final String iconPath;
  final String label;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? iconColor;
  final double? height;
  final bool isInProgress;
  final bool isOutlined;

  const AuthSocialButton({
    Key? key,
    required this.iconPath,
    required this.label,
    this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.iconColor,
    this.height,
    this.isInProgress = false,
    this.isOutlined = false,
  }) : super(key: key);

  @override
  State<AuthSocialButton> createState() => _AuthSocialButtonState();
}

class _AuthSocialButtonState extends State<AuthSocialButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    const hoverColor = Color(0xFF5B7BF8);

    if (widget.isOutlined) {
      // 구글 스타일: 테두리만 있는 버튼
      return MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: SizedBox(
          height: widget.height ?? 48,
          width: double.infinity,
          child: OutlinedButton(
            onPressed: widget.isInProgress ? null : widget.onPressed,
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              overlayColor: Colors.transparent, // 호버 시 어두워지는 효과 제거
              side: BorderSide(
                  color: _isHovered ? hoverColor : Colors.grey.shade300),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  widget.iconPath,
                  width: 20,
                  height: 20,
                  colorFilter: widget.iconColor != null
                      ? ColorFilter.mode(widget.iconColor!, BlendMode.srcIn)
                      : null,
                ),
                const SizedBox(width: 12),
                Text(widget.label,
                    style:
                        const TextStyle(fontSize: 15, color: Colors.black87)),
              ],
            ),
          ),
        ),
      );
    }

    // 네이버/카카오 스타일: 배경색이 있는 버튼
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: SizedBox(
        height: widget.height ?? 48,
        width: double.infinity,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered ? hoverColor : Colors.transparent,
              width: 1,
            ),
          ),
          child: ElevatedButton(
            onPressed: widget.isInProgress ? null : widget.onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.backgroundColor,
              foregroundColor: widget.foregroundColor,
              elevation: 0,
              overlayColor: Colors.transparent, // 호버 시 어두워지는 효과 제거
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  widget.iconPath,
                  width: 20,
                  height: 20,
                  colorFilter: widget.iconColor != null
                      ? ColorFilter.mode(widget.iconColor!, BlendMode.srcIn)
                      : null,
                ),
                const SizedBox(width: 12),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 15,
                    color: widget.foregroundColor ?? Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
