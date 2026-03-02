/// 로그인 다이얼로그
/// 이메일/비밀번호 기반 로그인 및 소셜 로그인(Google, Kakao, Naver)을 제공합니다.
library;

import 'dart:async';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../utils/multi_window_manager.dart';
import '../api/auth_service.dart';
import '../api/session_service.dart';
import '../api/api_client.dart';
import '../api/models.dart';
import '../api/google_auth_service.dart';
import '../../models/platform_model.dart';
import '../../models/user_model.dart';
import './dialog.dart';
import './signup.dart';
import './reset_password.dart';
import './styled_form_widgets.dart';

/// 이메일 유효성 검사 정규식
final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// 텍스트 링크 버튼 (호버 시 밑줄 표시)
class _TextLinkButton extends StatefulWidget {
  final String text;
  final VoidCallback? onTap;

  const _TextLinkButton({
    Key? key,
    required this.text,
    this.onTap,
  }) : super(key: key);

  @override
  State<_TextLinkButton> createState() => _TextLinkButtonState();
}

class _TextLinkButtonState extends State<_TextLinkButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    const linkColor = Color(0xFF666666);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Text(
          widget.text,
          style: TextStyle(
            fontSize: 13,
            color: linkColor,
            decoration: _isHovered ? TextDecoration.underline : TextDecoration.none,
            decorationColor: linkColor,
            backgroundColor: Colors.transparent,
          ),
        ),
      ),
    );
  }
}

/// 소셜 로그인 버튼 위젯 (호버 시 테두리 및 텍스트 색상 변경)
class SocialLoginButton extends StatefulWidget {
  final String iconPath;
  final String label;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool isInProgress;

  const SocialLoginButton({
    Key? key,
    required this.iconPath,
    required this.label,
    this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.isInProgress = false,
  }) : super(key: key);

  @override
  State<SocialLoginButton> createState() => _SocialLoginButtonState();
}

class _SocialLoginButtonState extends State<SocialLoginButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    const hoverColor = Color(0xFF5B7BF8);
    final isDisabled = widget.onPressed == null || widget.isInProgress;
    final borderColor = isDisabled
        ? Colors.grey.shade300
        : (_isHovered ? hoverColor : Colors.grey.shade300);
    final textColor = isDisabled
        ? Colors.grey[400]
        : (_isHovered ? hoverColor : (widget.foregroundColor ?? Colors.black87));

    return MouseRegion(
      cursor: isDisabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: SizedBox(
        height: 42,
        width: double.infinity,
        child: OutlinedButton(
          onPressed: widget.isInProgress ? null : widget.onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: widget.backgroundColor,
            foregroundColor: widget.foregroundColor,
            side: BorderSide(color: borderColor),
            overlayColor: Colors.transparent,
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
              ),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 14,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 로그인 위젯 (이메일/비밀번호)
class LoginWidgetUserPass extends StatelessWidget {
  final TextEditingController email;
  final TextEditingController pass;
  final String? emailMsg;
  final String? passMsg;
  final bool isInProgress;
  final Function() onLogin;
  final Function() onSignup;
  final Function() onResetPassword;
  final Function() onGoogleLogin;
  final Function() onKakaoLogin;
  final Function() onNaverLogin;
  final FocusNode? emailFocusNode;

  const LoginWidgetUserPass({
    Key? key,
    this.emailFocusNode,
    required this.email,
    required this.pass,
    required this.emailMsg,
    required this.passMsg,
    required this.isInProgress,
    required this.onLogin,
    required this.onSignup,
    required this.onResetPassword,
    required this.onGoogleLogin,
    required this.onKakaoLogin,
    required this.onNaverLogin,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 이메일 필드
          Text(
            translate('Email'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8.0),
          TextField(
            controller: email,
            focusNode: emailFocusNode,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: translate('Enter your email'),
              hintStyle: TextStyle(color: Colors.grey.shade400),
              errorText: emailMsg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Theme.of(context).primaryColor),
              ),
            ),
          ),
          const SizedBox(height: 16.0),
          // 비밀번호 필드
          Text(
            translate('Password'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8.0),
          TextField(
            controller: pass,
            obscureText: true,
            decoration: InputDecoration(
              hintText: translate('Enter your password'),
              hintStyle: TextStyle(color: Colors.grey.shade400),
              errorText: passMsg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Theme.of(context).primaryColor),
              ),
            ),
          ),
          const SizedBox(height: 8.0),
          // 비밀번호 찾기 / 회원가입 링크 (같은 줄)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _TextLinkButton(
                text: translate('Forgot password?'),
                onTap: onResetPassword,
              ),
              _TextLinkButton(
                text: translate('Sign Up'),
                onTap: onSignup,
              ),
            ],
          ),
          // 진행 표시
          if (isInProgress) ...[
            const SizedBox(height: 12.0),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 20.0),
          // 로그인 버튼
          SizedBox(
            height: 48,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isInProgress ? null : onLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5B6EF5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: Text(
                translate('Login'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          const SizedBox(height: 24.0),
          // 구분선
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  translate('or'),
                  style: TextStyle(
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 20.0),
          // 소셜 로그인 버튼들
          SocialLoginButton(
            iconPath: 'assets/icons/google.svg',
            label: translate('Continue with Google'),
            onPressed: onGoogleLogin,
            isInProgress: isInProgress,
          ),
          const SizedBox(height: 12.0),
          SocialLoginButton(
            iconPath: 'assets/icons/naver.svg',
            label: translate('Continue with Naver'),
            onPressed: onNaverLogin,
            backgroundColor: const Color(0xFF03C75A),
            foregroundColor: Colors.white,
            isInProgress: isInProgress,
          ),
          const SizedBox(height: 12.0),
          SocialLoginButton(
            iconPath: 'assets/icons/kakao.svg',
            label: translate('Continue with Kakao'),
            onPressed: onKakaoLogin,
            backgroundColor: const Color(0xFFFEE500),
            foregroundColor: const Color(0xFF000000),
            isInProgress: isInProgress,
          ),
        ],
      ),
    );
  }
}

/// 메인 로그인 다이얼로그
Future<bool?> loginDialog() async {
  var email = TextEditingController();
  var password = TextEditingController();
  final emailFocusNode = FocusNode()..requestFocus();
  Timer(const Duration(milliseconds: 100), () => emailFocusNode.requestFocus());

  String? emailMsg;
  String? passwordMsg;
  var isInProgress = false;
  bool isCloseHovered = false;

  final res = await gFFI.dialogManager.show<bool>((setState, close, context) {
    email.addListener(() {
      if (emailMsg != null) {
        setState(() => emailMsg = null);
      }
    });

    password.addListener(() {
      if (passwordMsg != null) {
        setState(() => passwordMsg = null);
      }
    });

    void onDialogCancel() {
      isInProgress = false;
      close(false);
    }

    // 로그인 처리
    Future<void> onLogin() async {
      // 유효성 검사
      if (email.text.isEmpty) {
        setState(() => emailMsg = translate('Enter your email'));
        return;
      }
      if (!_emailRegex.hasMatch(email.text)) {
        setState(() => emailMsg = translate('Invalid email format'));
        return;
      }
      if (password.text.isEmpty) {
        setState(() => passwordMsg = translate('Enter your password'));
        return;
      }

      setState(() => isInProgress = true);

      try {
        final authService = getAuthService();
        final sessionService = getSessionService();

        // 로그인 API 호출
        final loginRes = await authService.login(email.text, password.text);
        
        if (!loginRes.success) {
          setState(() {
            passwordMsg = translate('Login failed. Please check your credentials.');
            isInProgress = false;
          });
          return;
        }

        // 사용자 정보 조회
        final meRes = await authService.me();
        if (!meRes.success || meRes.data == null) {
          setState(() {
            passwordMsg = translate('Bad Request');
            isInProgress = false;
          });
          return;
        }

        // UserInfo 생성
        final userInfo = UserInfo.fromJson(meRes.data!);

        // 버전 가져오기
        final version = await bind.mainGetVersion();

        // 세션 등록
        final registerRes = await sessionService.registerSession(
          version,
          deviceId: platformFFI.deviceId,
          deviceName: platformFFI.deviceName,
        );
        if (!registerRes.success) {
          setState(() {
            passwordMsg = translate('Bad Request');
            isInProgress = false;
          });
          return;
        }

        final deviceKey = registerRes.extract('deviceKey') ?? '';
        userInfo.deviceKey = deviceKey;

        // 세션 활성화 (약간의 딜레이 추가 - 서버 동기화 대기)
        await Future.delayed(const Duration(milliseconds: 500));
        final activateRes = await sessionService.activateSession(deviceKey);
        if (!activateRes.success) {
          setState(() {
            passwordMsg = translate('Bad Request');
            isInProgress = false;
          });
          return;
        }

        userInfo.sessionKey = activateRes.extract('sessionKey');

        // UserModel 업데이트
        gFFI.userModel.loginWithUserInfo(userInfo);

        close(true);
      } catch (e) {
        setState(() {
          passwordMsg = translate('Bad Request');
          isInProgress = false;
        });
      }
    }

    // 회원가입 다이얼로그 열기
    void onSignup() async {
      close(null);
      final result = await signupDialog();
      if (result == true) {
        // 회원가입 성공 후 로그인 다이얼로그 다시 열기
        loginDialog();
      }
    }

    // 비밀번호 재설정 다이얼로그 열기
    void onResetPassword() async {
      close(null);
      final result = await resetPasswordDialog();
      if (result == true) {
        // 비밀번호 재설정 성공 후 로그인 다이얼로그 다시 열기
        loginDialog();
      }
    }

    // Google 로그인 처리
    Future<void> onGoogleLogin() async {
      if (!isGoogleAuthServiceInitialized()) {
        setState(() => passwordMsg = translate('Google login not available'));
        return;
      }

      setState(() => isInProgress = true);

      try {
        final googleAuth = getGoogleAuthService();
        final result = await googleAuth.login();

        if (!result.success) {
          setState(() {
            passwordMsg = translate('Bad Request');
            isInProgress = false;
          });
          return;
        }

        if (result.userInfo != null) {
          gFFI.userModel.loginWithUserInfo(result.userInfo!);
          close(true);
        } else {
          setState(() {
            passwordMsg = translate('Bad Request');
            isInProgress = false;
          });
        }
      } catch (e) {
        setState(() {
          passwordMsg = translate('Bad Request');
          isInProgress = false;
        });
      }
    }

    // Kakao 로그인 처리 (UI만, API 미구현)
    Future<void> onKakaoLogin() async {
      // TODO: Kakao 로그인 API 구현 후 연동
      showToast(translate('Kakao login is not available yet'));
    }

    // Naver 로그인 처리 (UI만, API 미구현)
    Future<void> onNaverLogin() async {
      // TODO: Naver 로그인 API 구현 후 연동
      showToast(translate('Naver login is not available yet'));
    }

    final title = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(translate('Login')).marginOnly(top: MyTheme.dialogPadding),
        MouseRegion(
          onEnter: (_) => setState(() => isCloseHovered = true),
          onExit: (_) => setState(() => isCloseHovered = false),
          child: InkWell(
            onTap: onDialogCancel,
            hoverColor: Colors.red,
            borderRadius: BorderRadius.circular(5),
            child: Icon(
              Icons.close,
              size: 25,
              color: isCloseHovered
                  ? Colors.white
                  : Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.color
                      ?.withOpacity(0.55),
            ),
          ),
        ).marginOnly(top: 10, right: 15),
      ],
    );
    final titlePadding = EdgeInsets.fromLTRB(MyTheme.dialogPadding, 0, 0, 0);

    return CustomAlertDialog(
      title: title,
      titlePadding: titlePadding,
      contentBoxConstraints: const BoxConstraints(minWidth: 400),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 8.0),
          LoginWidgetUserPass(
            email: email,
            pass: password,
            emailMsg: emailMsg,
            passMsg: passwordMsg,
            isInProgress: isInProgress,
            onLogin: onLogin,
            onSignup: onSignup,
            onResetPassword: onResetPassword,
            onGoogleLogin: onGoogleLogin,
            onKakaoLogin: onKakaoLogin,
            onNaverLogin: onNaverLogin,
            emailFocusNode: emailFocusNode,
          ),
        ],
      ),
      onCancel: onDialogCancel,
      onSubmit: onLogin,
    );
  });

  return res;
}

/// 로그아웃 확인 다이얼로그
void logOutConfirmDialog() {
  gFFI.dialogManager.show((setState, close, context) {
    void submit() async {
      // 모든 원격 세션 종료
      if (isDesktop) {
        await oneDeskWinManager.closeAllSubWindows();
      } else {
        // 모바일에서 활성 세션이 있으면 종료
        if (gFFI.id.isNotEmpty) {
          await gFFI.close();
        }
      }
      // CM 창의 모든 연결 종료 (CM 창은 연결이 끊기면 자동으로 닫힘)
      await gFFI.serverModel.closeAll();
      close();
      await gFFI.userModel.logOut();
    }

    return CustomAlertDialog(
      title: Text(
        translate('Logout'),
        style: MyTheme.dialogTitleStyle,
      ),
      content: Text(translate("logout_tip")),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Row(
            children: [
              Expanded(
                child: StyledOutlinedButton(
                  label: translate("Cancel"),
                  onPressed: close,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StyledPrimaryButton(
                  label: translate("Logout"),
                  onPressed: submit,
                  backgroundColor: const Color(0xFFFE3E3E),
                  hoverBorderColor: const Color(0xFFFE3E3E),
                ),
              ),
            ],
          ),
        ),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  }, forceGlobal: true);
}

/// 회원탈퇴 확인 다이얼로그 (1단계)
void withdrawConfirmDialog() {
  bool isLoading = false;
  bool isChecked = false;

  gFFI.dialogManager.show((setState, close, context) {

    void submit() async {
      // loginType == 0 (일반 로그인)이면 비밀번호 입력 다이얼로그로 이동
      if (gFFI.userModel.loginType.value == 0) {
        close();
        _withdrawPasswordDialog();
        return;
      }

      // 소셜 로그인은 바로 탈퇴 진행
      setState(() {
        isLoading = true;
      });

      // 모든 원격 세션 종료
      if (isDesktop) {
        await oneDeskWinManager.closeAllSubWindows();
      } else {
        if (gFFI.id.isNotEmpty) {
          await gFFI.close();
        }
      }
      await gFFI.serverModel.closeAll();

      try {
        final authService = getAuthService();
        final response = await authService.signOut('');

        if (response.success) {
          close();
          _withdrawSuccessDialog();
        } else {
          setState(() {
            isLoading = false;
          });
          BotToast.showText(
            text: translate('Bad Request'),
            contentColor: Colors.red,
          );
        }
      } catch (e) {
        setState(() {
          isLoading = false;
        });
        BotToast.showText(
          text: translate('Bad Request'),
          contentColor: Colors.red,
        );
      }
    }

    return CustomAlertDialog(
      title: Text(
        translate('Withdraw'),
        style: MyTheme.dialogTitleStyle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 경고 문구 (빨간색, bold)
          Text(
            translate("withdraw_waring"),
            style: const TextStyle(
              color: Color(0xFFFE3E3E),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          // 안내 문구
          Text(
            translate("withdraw_tip"),
            style: const TextStyle(
              color: Color(0xFF666666),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          // 체크박스 (세팅 페이지 스타일)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  isChecked = !isChecked;
                });
              },
              child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isChecked ? MyTheme.accent : const Color(0xFFCCCCCC),
                      width: 1.5,
                    ),
                    color: isChecked ? MyTheme.accent : Colors.transparent,
                  ),
                  child: isChecked
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    translate("withdraw_confirm"),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          ),
          if (isLoading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Row(
            children: [
              Expanded(
                child: StyledOutlinedButton(
                  label: translate("Cancel"),
                  onPressed: isLoading ? null : close,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StyledPrimaryButton(
                  label: translate("withdraw_sucess"),
                  onPressed: (isLoading || !isChecked) ? null : submit,
                  backgroundColor: const Color(0xFFFE3E3E),
                  hoverBorderColor: const Color(0xFFFE3E3E),
                ),
              ),
            ],
          ),
        ),
      ],
      onSubmit: (isLoading || !isChecked) ? null : submit,
      onCancel: isLoading ? null : close,
    );
  }, forceGlobal: true);
}

/// 회원탈퇴 - 비밀번호 입력 다이얼로그 (일반 로그인 전용)
void _withdrawPasswordDialog() {
  bool isLoading = false;
  final passwordController = TextEditingController();
  bool obscurePassword = true;
  String? passwordError;

  gFFI.dialogManager.show((setState, close, context) {
    void submit() async {
      final password = passwordController.text.trim();
      if (password.isEmpty) {
        setState(() {
          passwordError = translate('Enter password');
        });
        return;
      }

      setState(() {
        isLoading = true;
        passwordError = null;
      });

      // 모든 원격 세션 종료
      if (isDesktop) {
        await oneDeskWinManager.closeAllSubWindows();
      } else {
        if (gFFI.id.isNotEmpty) {
          await gFFI.close();
        }
      }
      await gFFI.serverModel.closeAll();

      try {
        final authService = getAuthService();
        final response = await authService.signOut(password);

        if (response.success) {
          passwordController.dispose();
          close();
          _withdrawSuccessDialog();
        } else {
          setState(() {
            isLoading = false;
            passwordError = translate('Wrong Password');
          });
        }
      } catch (e) {
        setState(() {
          isLoading = false;
          passwordError = translate('Bad Request');
        });
      }
    }

    return CustomAlertDialog(
      title: Text(
        translate('Delete Account'),
        style: MyTheme.dialogTitleStyle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            translate('Password'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF454447),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: passwordController,
            obscureText: obscurePassword,
            autofocus: true,
            decoration: InputDecoration(
              hintText: translate('Enter password'),
              hintStyle: const TextStyle(color: Color(0xFFB0B0B0)),
              errorText: passwordError,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFDEDEE2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFDEDEE2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: MyTheme.accent),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: const Color(0xFF999999),
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    obscurePassword = !obscurePassword;
                  });
                },
              ),
            ),
            onSubmitted: isLoading ? null : (_) => submit(),
          ),
          if (isLoading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Row(
            children: [
              Expanded(
                child: StyledOutlinedButton(
                  label: translate("Cancel"),
                  onPressed: isLoading ? null : () {
                    passwordController.dispose();
                    close();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StyledPrimaryButton(
                  label: translate("OK"),
                  onPressed: isLoading ? null : submit,
                  backgroundColor: const Color(0xFFFE3E3E),
                  hoverBorderColor: const Color(0xFFFE3E3E),
                ),
              ),
            ],
          ),
        ),
      ],
      onSubmit: isLoading ? null : submit,
      onCancel: isLoading ? null : () {
        passwordController.dispose();
        close();
      },
    );
  }, forceGlobal: true);
}

/// 회원탈퇴 성공 다이얼로그 (2단계)
void _withdrawSuccessDialog() {
  gFFI.dialogManager.show((setState, close, context) {
    void submit() async {
      close();
      // 로그아웃 처리 후 로그인 화면으로
      await gFFI.userModel.logOut();
    }

    return CustomAlertDialog(
      title: Text(
        translate('withdraw_sucess_title'),
        style: MyTheme.dialogTitleStyle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 완료 문구 (파란색, bold)
          Text(
            translate("withdraw_sucess_waring"),
            style: const TextStyle(
              color: Color(0xFF5F71FF),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          // 안내 문구 (위 텍스트와 동일한 크기)
          Text(
            translate("withdraw_sucess_tip"),
            style: const TextStyle(
              color: Color(0xFF666666),
            ),
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: StyledPrimaryButton(
            label: translate("OK"),
            onPressed: submit,
            backgroundColor: const Color(0xFF5F71FF),
          ),
        ),
      ],
      onSubmit: submit,
    );
  }, forceGlobal: true);
}
