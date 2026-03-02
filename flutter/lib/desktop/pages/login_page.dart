/// 로그인 페이지 (전체 화면)
/// 공통 레이아웃 사용 - AuthPageLayout
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/api/auth_service.dart';
import '../../common/api/session_service.dart';
import '../../common/api/google_auth_service.dart';
import '../../common/api/kakao_auth_service.dart';
import '../../common/api/naver_auth_service.dart';
import '../../common/api/mobile_google_auth_service.dart';
import '../../common/api/mobile_kakao_auth_service.dart';
import '../../common/api/mobile_naver_auth_service.dart';
import '../../common/api/models.dart';
import '../../common/widgets/dialog.dart';
import '../../common/widgets/auth_layout.dart';
import '../../common/widgets/styled_form_widgets.dart';
import '../../models/platform_model.dart';
import './signup_page.dart';
import './reset_password_page.dart';

/// 이메일 유효성 검사 정규식
final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// 비밀번호 변경 완료 메시지 표시 플래그 (전역)
final showPasswordChangedCompletion = false.obs;

/// 업데이트 필요 플래그 (전역) - 버전이 다르면 로그인 비활성화
final updateRequired = false.obs;

/// 로그인 페이지
class LoginPage extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginPage({Key? key, required this.onLoginSuccess}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();

  String? _emailError;
  String? _passwordError;
  bool _isInProgress = false;
  bool _obscurePassword = true;
  bool _autoLogin = false;
  BuildContext? _loginDialogContext;

  void _showLoginLoadingDialog() {
    if (_loginDialogContext != null) return;

    const primaryColor = Color(0xFF5F71FF);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _loginDialogContext = dialogContext;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Container(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 24),
                SizedBox(
                  width: 80,
                  height: 80,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              primaryColor.withOpacity(0.7)),
                          backgroundColor: primaryColor.withOpacity(0.15),
                        ),
                      ),
                      SvgPicture.asset(
                        'assets/icons/topbar-logo.svg',
                        width: 32,
                        height: 32,
                        colorFilter: const ColorFilter.mode(
                            primaryColor, BlendMode.srcIn),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  translate('Logging in...'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      _hideLoginLoadingDialog();
                      setState(() => _isInProgress = false);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      translate('Cancel'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _hideLoginLoadingDialog() {
    if (_loginDialogContext != null) {
      Navigator.of(_loginDialogContext!).pop();
      _loginDialogContext = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _autoLogin = bind.mainGetLocalOption(key: 'auto_login') == 'Y';
    Timer(const Duration(milliseconds: 100), () {
      if (mounted) _emailFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    // 유효성 검사
    if (_emailController.text.isEmpty) {
      setState(() => _emailError = translate('Enter your email'));
      return;
    }
    if (!_emailRegex.hasMatch(_emailController.text)) {
      setState(() => _emailError = translate('Invalid email format'));
      return;
    }
    if (_passwordController.text.isEmpty) {
      setState(() => _passwordError = translate('Enter your password'));
      return;
    }

    setState(() {
      _isInProgress = true;
      _emailError = null;
      _passwordError = null;
    });
    _showLoginLoadingDialog();

    try {
      final authService = getAuthService();
      final sessionService = getSessionService();

      // 로그인 API 호출
      final loginRes = await authService.login(
        _emailController.text,
        _passwordController.text,
      );
      if (!loginRes.success) {
        _hideLoginLoadingDialog();
        setState(() {
          _passwordError = translate('Bad Request');
          _isInProgress = false;
        });
        return;
      }

      // 사용자 정보 조회
      final meRes = await authService.me();
      if (!meRes.success || meRes.data == null) {
        _hideLoginLoadingDialog();
        setState(() {
          _passwordError = translate('Bad Request');
          _isInProgress = false;
        });
        return;
      }

      // UserInfo 생성
      final userInfo = UserInfo.fromJson(meRes.data!);

      // 버전 가져오기
      final version = await bind.mainGetVersion();

      // 세션 등록
      final registerRes =
          await sessionService.registerSession(
            version,
            deviceId: platformFFI.deviceId,
            deviceName: platformFFI.deviceName,
          );
      if (!registerRes.success) {
        _hideLoginLoadingDialog();
        setState(() {
          _passwordError = translate('Bad Request');
          _isInProgress = false;
        });
        return;
      }

      final deviceKey = registerRes.extract('deviceKey') ?? '';
      userInfo.deviceKey = deviceKey;

      // 세션 활성화
      await Future.delayed(const Duration(milliseconds: 500));
      final activateRes = await sessionService.activateSession(deviceKey);
      if (!activateRes.success) {
        _hideLoginLoadingDialog();
        setState(() {
          _passwordError = translate('Bad Request');
          _isInProgress = false;
        });
        return;
      }

      userInfo.sessionKey = activateRes.extract('sessionKey');
      _hideLoginLoadingDialog();

      // UserModel 업데이트
      gFFI.userModel.loginWithUserInfo(userInfo);

      widget.onLoginSuccess();
    } catch (e) {
      _hideLoginLoadingDialog();
      setState(() {
        _passwordError = translate('Bad Request');
        _isInProgress = false;
      });
    }
  }

  Future<void> _onGoogleLogin() async {
    setState(() => _isInProgress = true);
    _showLoginLoadingDialog();

    try {
      // 모바일/데스크톱 구분
      if (isDesktop) {
        // 데스크톱: localhost 서버 방식
        if (!isGoogleAuthServiceInitialized()) {
          _hideLoginLoadingDialog();
          setState(() {
            _passwordError = translate('Bad Request');
            _isInProgress = false;
          });
          return;
        }

        final googleAuth = getGoogleAuthService();
        final result = await googleAuth.login();

        if (!result.success) {
          _hideLoginLoadingDialog();
          setState(() {
            _passwordError = translate('Bad Request');
            _isInProgress = false;
          });
          return;
        }

        if (result.userInfo != null) {
          _hideLoginLoadingDialog();
          gFFI.userModel.loginWithUserInfo(result.userInfo!);
          widget.onLoginSuccess();
        } else {
          _hideLoginLoadingDialog();
          setState(() {
            _passwordError = translate('Bad Request');
            _isInProgress = false;
          });
        }
      } else {
        // 모바일: WebView 방식
        if (!isMobileGoogleAuthServiceInitialized()) {
          _hideLoginLoadingDialog();
          setState(() {
            _passwordError = translate('Bad Request');
            _isInProgress = false;
          });
          return;
        }

        final mobileGoogleAuth = getMobileGoogleAuthService();
        final result = await mobileGoogleAuth.login(context);

        if (!result.success) {
          _hideLoginLoadingDialog();
          setState(() {
            _passwordError = translate('Bad Request');
            _isInProgress = false;
          });
          return;
        }

        if (result.userInfo != null) {
          _hideLoginLoadingDialog();
          gFFI.userModel.loginWithUserInfo(result.userInfo!);
          widget.onLoginSuccess();
        } else {
          _hideLoginLoadingDialog();
          setState(() {
            _passwordError = translate('Bad Request');
            _isInProgress = false;
          });
        }
      }
    } catch (e) {
      _hideLoginLoadingDialog();
      setState(() {
        _passwordError = translate('Bad Request');
        _isInProgress = false;
      });
    }
  }

  Future<void> _onKakaoLogin() async {
    setState(() => _isInProgress = true);
    _showLoginLoadingDialog();

    try {
      if (isDesktop) {
        // 데스크톱: localhost HTTP 서버 방식
        if (!isKakaoAuthServiceInitialized()) {
          _hideLoginLoadingDialog();
          setState(() {
            _passwordError = translate('Bad Request');
            _isInProgress = false;
          });
          return;
        }

        final kakaoAuth = getKakaoAuthService();
        final result = await kakaoAuth.login();

        if (!result.success) {
          _hideLoginLoadingDialog();
          setState(() {
            _passwordError = translate('Bad Request');
            _isInProgress = false;
          });
          return;
        }

        if (result.userInfo != null) {
          _hideLoginLoadingDialog();
          gFFI.userModel.loginWithUserInfo(result.userInfo!);
          widget.onLoginSuccess();
        } else {
          _hideLoginLoadingDialog();
          setState(() {
            _passwordError = translate('Bad Request');
            _isInProgress = false;
          });
        }
      } else {
        // 모바일: WebView 방식
        if (!isMobileKakaoAuthServiceInitialized()) {
          _hideLoginLoadingDialog();
          setState(() {
            _passwordError = translate('Bad Request');
            _isInProgress = false;
          });
          return;
        }

        final mobileKakaoAuth = getMobileKakaoAuthService();
        final result = await mobileKakaoAuth.login(context);

        if (!result.success) {
          _hideLoginLoadingDialog();
          setState(() {
            _passwordError = translate('Bad Request');
            _isInProgress = false;
          });
          return;
        }

        if (result.userInfo != null) {
          _hideLoginLoadingDialog();
          gFFI.userModel.loginWithUserInfo(result.userInfo!);
          widget.onLoginSuccess();
        } else {
          _hideLoginLoadingDialog();
          setState(() {
            _passwordError = translate('Bad Request');
            _isInProgress = false;
          });
        }
      }
    } catch (e) {
      _hideLoginLoadingDialog();
      setState(() {
        _passwordError = translate('Bad Request');
        _isInProgress = false;
      });
    }
  }

  Future<void> _onNaverLogin() async {
    setState(() => _isInProgress = true);
    _showLoginLoadingDialog();

    try {
      if (isDesktop) {
        // 데스크톱: localhost HTTP 서버 방식
        if (!isNaverAuthServiceInitialized()) {
          _hideLoginLoadingDialog();
          setState(() {
            _passwordError = translate('Bad Request');
            _isInProgress = false;
          });
          return;
        }

        final naverAuth = getNaverAuthService();
        final result = await naverAuth.login();

        if (!result.success) {
          _hideLoginLoadingDialog();
          setState(() {
            _passwordError = translate('Bad Request');
            _isInProgress = false;
          });
          return;
        }

        if (result.userInfo != null) {
          _hideLoginLoadingDialog();
          gFFI.userModel.loginWithUserInfo(result.userInfo!);
          widget.onLoginSuccess();
        } else {
          _hideLoginLoadingDialog();
          setState(() {
            _passwordError = translate('Bad Request');
            _isInProgress = false;
          });
        }
      } else {
        // 모바일: WebView 방식
        if (!isMobileNaverAuthServiceInitialized()) {
          _hideLoginLoadingDialog();
          setState(() {
            _passwordError = translate('Bad Request');
            _isInProgress = false;
          });
          return;
        }

        final mobileNaverAuth = getMobileNaverAuthService();
        final result = await mobileNaverAuth.login(context);

        if (!result.success) {
          _hideLoginLoadingDialog();
          setState(() {
            _passwordError = translate('Bad Request');
            _isInProgress = false;
          });
          return;
        }

        if (result.userInfo != null) {
          _hideLoginLoadingDialog();
          gFFI.userModel.loginWithUserInfo(result.userInfo!);
          widget.onLoginSuccess();
        } else {
          _hideLoginLoadingDialog();
          setState(() {
            _passwordError = translate('Bad Request');
            _isInProgress = false;
          });
        }
      }
    } catch (e) {
      _hideLoginLoadingDialog();
      setState(() {
        _passwordError = translate('Bad Request');
        _isInProgress = false;
      });
    }
  }

  void _navigateToSignup() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SignupPage(
          onSignupSuccess: () {
            Navigator.of(context).pop();
            showToast(translate('Signup successful. Please login.'));
          },
          onBackToLogin: () {
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  void _navigateToResetPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ResetPasswordPage(
          onResetSuccess: () {
            Navigator.of(context).pop();
            showToast(translate('Password reset successful. Please login.'));
          },
          onBackToLogin: () {
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // 업데이트 필요 시 로그인 비활성화
      if (updateRequired.value) {
        if (!isDesktop) {
          return _buildMobileUpdateRequiredUI();
        }
        return AuthPageLayout(
          formContent: _buildUpdateRequiredContent(),
        );
      }

      // 비밀번호 변경 완료 메시지 표시
      if (showPasswordChangedCompletion.value) {
        return AuthPageLayout(
          formContent: _buildPasswordChangedContent(),
        );
      }

      // 모바일: 간편 로그인 UI
      if (!isDesktop) {
        return _buildMobileLoginUI();
      }

      // 데스크톱: 기존 로그인 폼
      return AuthPageLayout(
        formContent: _buildDesktopLoginForm(),
      );
    });
  }

  /// 모바일 로그인 UI (간편 로그인)
  Widget _buildMobileLoginUI() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 상단 텍스트
              Text(
                translate(
                    'The easiest and fastest\n way When you need your PC'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 24),
              // 로고 이미지
              Image.asset(
                'assets/icons/mobile-login-logo.png',
                height: 34,
              ),
              const SizedBox(height: 32),
              // 소셜 로그인 버튼들
              AuthSocialButton(
                iconPath: 'assets/icons/google.svg',
                label: translate('Google Sign in'),
                onPressed: _onGoogleLogin,
                height: 56,
                isInProgress: _isInProgress,
                isOutlined: true,
              ),
              const SizedBox(height: 12),
              AuthSocialButton(
                iconPath: 'assets/icons/naver.svg',
                label: translate('Naver Sign in'),
                onPressed: _onNaverLogin,
                backgroundColor: const Color(0xFF03C75A),
                foregroundColor: Colors.white,
                height: 56,
                isInProgress: _isInProgress,
              ),
              const SizedBox(height: 12),
              AuthSocialButton(
                iconPath: 'assets/icons/kakao.svg',
                label: translate('Kakao Sign in'),
                onPressed: _onKakaoLogin,
                backgroundColor: const Color(0xFFFEE500),
                foregroundColor: const Color(0xFF000000),
                height: 56,
                isInProgress: _isInProgress,
              ),
              const SizedBox(height: 12),
              // 아이디 로그인/회원가입 버튼
              AuthSocialButton(
                iconPath: 'assets/icons/logo.svg',
                label: translate('ID Login/Sign up'),
                onPressed: _navigateToIdLogin,
                backgroundColor: const Color(0xFF5F71FF),
                foregroundColor: const Color(0xFFFEFEFE),
                iconColor: const Color(0xFFFEFEFE),
                height: 56,
                isInProgress: _isInProgress,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 아이디 로그인 페이지로 이동
  void _navigateToIdLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _MobileIdLoginPage(
          onLoginSuccess: widget.onLoginSuccess,
        ),
      ),
    );
  }

  /// 데스크톱 로그인 폼
  Widget _buildDesktopLoginForm() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text(
            translate('Login'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 35),
        Text(translate('Email (ID)'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        AuthTextField(
          controller: _emailController,
          focusNode: _emailFocusNode,
          keyboardType: TextInputType.emailAddress,
          hintText: translate('Enter your email'),
          errorText: _emailError,
          onChanged: (_) {
            if (_emailError != null) setState(() => _emailError = null);
          },
          onSubmitted: (_) => _onLogin(),
        ),
        const SizedBox(height: 16),
        Text(translate('Password'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        AuthTextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          hintText: translate('Enter your password'),
          errorText: _passwordError,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 20,
              color: Colors.grey[500],
            ),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
          onChanged: (_) {
            if (_passwordError != null) setState(() => _passwordError = null);
          },
          onSubmitted: (_) => _onLogin(),
        ),
        const SizedBox(height: 16),
        // 자동 로그인 체크박스
        GestureDetector(
          onTap: () {
            setState(() => _autoLogin = !_autoLogin);
            bind.mainSetLocalOption(key: 'auto_login', value: _autoLogin ? 'Y' : '');
          },
          child: Row(
            children: [
              StyledCheckbox(
                value: _autoLogin,
                onChanged: (v) {
                  setState(() => _autoLogin = v ?? false);
                  bind.mainSetLocalOption(key: 'auto_login', value: _autoLogin ? 'Y' : '');
                },
                size: 20,
                iconSize: 14,
              ),
              const SizedBox(width: 8),
              Text(
                translate('Auto Login'),
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _TextLink(
              text: translate('Find Password'),
              onTap: _navigateToResetPassword,
            ),
            _TextLink(
              text: translate('Sign Up'),
              onTap: _navigateToSignup,
            ),
          ],
        ),
        const SizedBox(height: 25),
        AuthMainButton(
          label: translate('Login'),
          onPressed: _onLogin,
          isInProgress: _isInProgress,
        ),
        const SizedBox(height: 30),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                translate('or'),
                style: TextStyle(
                    fontSize: 15,
                    color: Theme.of(context).textTheme.bodySmall?.color),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 30),
        AuthSocialButton(
          iconPath: 'assets/icons/google.svg',
          label: translate('Google Sign in'),
          onPressed: _onGoogleLogin,
          isInProgress: _isInProgress,
          isOutlined: true,
        ),
        const SizedBox(height: 12),
        AuthSocialButton(
          iconPath: 'assets/icons/naver.svg',
          label: translate('Naver Sign in'),
          onPressed: _onNaverLogin,
          backgroundColor: const Color(0xFF03C75A),
          foregroundColor: Colors.white,
          isInProgress: _isInProgress,
        ),
        const SizedBox(height: 12),
        AuthSocialButton(
          iconPath: 'assets/icons/kakao.svg',
          label: translate('Kakao Sign in'),
          onPressed: _onKakaoLogin,
          backgroundColor: const Color(0xFFFEE500),
          foregroundColor: const Color(0xFF000000),
          isInProgress: _isInProgress,
        ),
      ],
    );
  }

  /// 업데이트 필요 UI (데스크톱)
  Widget _buildUpdateRequiredContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.system_update,
          size: 80,
          color: Color(0xFF5F71FF),
        ),
        const SizedBox(height: 32),
        Text(
          translate('Can use on update'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  /// 업데이트 필요 UI (모바일)
  Widget _buildMobileUpdateRequiredUI() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.system_update,
                size: 80,
                color: Color(0xFF5F71FF),
              ),
              const SizedBox(height: 32),
              Text(
                translate('Can use on update'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 비밀번호 변경 완료 UI
  Widget _buildPasswordChangedContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 체크 아이콘
        Image.asset(
          'assets/icons/sucess.png',
          width: 160,
          height: 160,
        ),
        const SizedBox(height: 32),
        // 완료 메시지
        Text(
          translate('Password change completed'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF5B7BF8),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          translate('Please log in again with your new password for security'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 32),
        // 로그인하러 가기 버튼
        AuthMainButton(
          label: translate('Go to login'),
          onPressed: () {
            showPasswordChangedCompletion.value = false;
          },
        ),
      ],
    );
  }
}

/// 텍스트 링크 (호버 시 밑줄)
class _TextLink extends StatefulWidget {
  final String text;
  final VoidCallback? onTap;

  const _TextLink({Key? key, required this.text, this.onTap}) : super(key: key);

  @override
  State<_TextLink> createState() => _TextLinkState();
}

class _TextLinkState extends State<_TextLink> {
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
            decoration:
                _isHovered ? TextDecoration.underline : TextDecoration.none,
            decorationColor: linkColor,
          ),
        ),
      ),
    );
  }
}

/// 모바일 아이디 로그인 페이지
class _MobileIdLoginPage extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const _MobileIdLoginPage({Key? key, required this.onLoginSuccess})
      : super(key: key);

  @override
  State<_MobileIdLoginPage> createState() => _MobileIdLoginPageState();
}

class _MobileIdLoginPageState extends State<_MobileIdLoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _emailError;
  String? _passwordError;
  bool _isInProgress = false;
  bool _obscurePassword = true;
  bool _autoLogin = false;
  BuildContext? _loginDialogContext;

  void _showLoginLoadingDialog() {
    if (_loginDialogContext != null) return;

    const primaryColor = Color(0xFF5F71FF);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _loginDialogContext = dialogContext;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Container(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 24),
                SizedBox(
                  width: 80,
                  height: 80,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              primaryColor.withOpacity(0.7)),
                          backgroundColor: primaryColor.withOpacity(0.15),
                        ),
                      ),
                      SvgPicture.asset(
                        'assets/icons/topbar-logo.svg',
                        width: 32,
                        height: 32,
                        colorFilter: const ColorFilter.mode(
                            primaryColor, BlendMode.srcIn),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  translate('Logging in...'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      _hideLoginLoadingDialog();
                      setState(() => _isInProgress = false);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      translate('Cancel'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _hideLoginLoadingDialog() {
    if (_loginDialogContext != null) {
      Navigator.of(_loginDialogContext!).pop();
      _loginDialogContext = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _autoLogin = bind.mainGetLocalOption(key: 'auto_login') == 'Y';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    // 유효성 검사
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (_emailController.text.isEmpty) {
      setState(() => _emailError = translate('Enter your email'));
      return;
    }
    if (!emailRegex.hasMatch(_emailController.text)) {
      setState(() => _emailError = translate('Invalid email format'));
      return;
    }
    if (_passwordController.text.isEmpty) {
      setState(() => _passwordError = translate('Enter your password'));
      return;
    }

    setState(() {
      _isInProgress = true;
      _emailError = null;
      _passwordError = null;
    });
    _showLoginLoadingDialog();

    try {
      final authService = getAuthService();
      final sessionService = getSessionService();

      // 로그인 API 호출
      final loginRes = await authService.login(
        _emailController.text,
        _passwordController.text,
      );
      if (!loginRes.success) {
        _hideLoginLoadingDialog();
        setState(() {
          _passwordError = translate('Login failed. Please check your credentials.');
          _isInProgress = false;
        });
        return;
      }

      // 사용자 정보 조회
      final meRes = await authService.me();
      if (!meRes.success || meRes.data == null) {
        _hideLoginLoadingDialog();
        setState(() {
          _passwordError = translate('Bad Request');
          _isInProgress = false;
        });
        return;
      }

      // UserInfo 생성
      final userInfo = UserInfo.fromJson(meRes.data!);

      // 버전 가져오기
      final version = await bind.mainGetVersion();

      // 세션 등록
      final registerRes =
          await sessionService.registerSession(
            version,
            deviceId: platformFFI.deviceId,
            deviceName: platformFFI.deviceName,
          );
      if (!registerRes.success) {
        _hideLoginLoadingDialog();
        setState(() {
          _passwordError = translate('Bad Request');
          _isInProgress = false;
        });
        return;
      }

      final deviceKey = registerRes.extract('deviceKey') ?? '';
      userInfo.deviceKey = deviceKey;

      // 세션 활성화
      await Future.delayed(const Duration(milliseconds: 500));
      final activateRes = await sessionService.activateSession(deviceKey);
      if (!activateRes.success) {
        _hideLoginLoadingDialog();
        setState(() {
          _passwordError = translate('Bad Request');
          _isInProgress = false;
        });
        return;
      }

      userInfo.sessionKey = activateRes.extract('sessionKey');
      _hideLoginLoadingDialog();

      // UserModel 업데이트
      gFFI.userModel.loginWithUserInfo(userInfo);

      // 로그인 성공 시 이전 화면으로 돌아가고 콜백 호출
      if (mounted) {
        Navigator.of(context).pop();
        widget.onLoginSuccess();
      }
    } catch (e) {
      _hideLoginLoadingDialog();
      setState(() {
        _passwordError = translate('Bad Request');
        _isInProgress = false;
      });
    }
  }

  void _navigateToSignup() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SignupPage(
          onSignupSuccess: () {
            Navigator.of(context).pop();
            showToast(translate('Signup successful. Please login.'));
          },
          onBackToLogin: () {
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  void _navigateToResetPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ResetPasswordPage(
          onResetSuccess: () {
            Navigator.of(context).pop();
            showToast(translate('Password reset successful. Please login.'));
          },
          onBackToLogin: () {
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  /// 헤더 위젯 (뒤로가기 + 타이틀)
  /// 데스크탑: 중앙 정렬 + chevron_left, 모바일: 좌측 정렬 + arrow_back_ios
  Widget _buildHeader(String title, VoidCallback onBack) {
    if (isDesktop) {
      return Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.chevron_left, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ],
      );
    }
    // 모바일: 좌측 정렬
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF454447), size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 4),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF454447),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단 여백
              const SizedBox(height: 8),
              // 헤더 (뒤로가기 + 타이틀)
              _buildHeader(translate('Login'), () => Navigator.of(context).pop()),
              // 폼 영역 (수직 가운데 정렬)
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 로고
                        SvgPicture.asset(
                          'assets/icons/logo.svg',
                          width: 48,
                          height: 48,
                          colorFilter: const ColorFilter.mode(
                            Color(0xFF5F71FF),
                            BlendMode.srcIn,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(translate('Email (ID)'),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        AuthTextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          hintText: translate('Enter your email'),
                          errorText: _emailError,
                          onChanged: (_) {
                            if (_emailError != null) {
                              setState(() => _emailError = null);
                            }
                          },
                          onSubmitted: (_) => _onLogin(),
                        ),
                        const SizedBox(height: 16),
                        Text(translate('Password'),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        AuthTextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          hintText: translate('Enter your password'),
                          errorText: _passwordError,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                              color: Colors.grey[500],
                            ),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                          onChanged: (_) {
                            if (_passwordError != null) {
                              setState(() => _passwordError = null);
                            }
                          },
                          onSubmitted: (_) => _onLogin(),
                        ),
                        const SizedBox(height: 16),
                        // 자동 로그인 체크박스 (StyledCheckbox 사용)
                        GestureDetector(
                          onTap: () {
                            setState(() => _autoLogin = !_autoLogin);
                            bind.mainSetLocalOption(key: 'auto_login', value: _autoLogin ? 'Y' : '');
                          },
                          child: Row(
                            children: [
                              StyledCheckbox(
                                value: _autoLogin,
                                onChanged: (v) {
                                  setState(() => _autoLogin = v ?? false);
                                  bind.mainSetLocalOption(key: 'auto_login', value: _autoLogin ? 'Y' : '');
                                },
                                size: 20,
                                iconSize: 14,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                translate('Auto Login'),
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GestureDetector(
                              onTap: _navigateToResetPassword,
                              child: Text(
                                translate('Find Password'),
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.grey),
                              ),
                            ),
                            GestureDetector(
                              onTap: _navigateToSignup,
                              child: Text(
                                translate('Sign Up'),
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.grey),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 25),
                        AuthMainButton(
                          label: translate('Login'),
                          onPressed: _onLogin,
                          isInProgress: _isInProgress,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
