/// 회원가입 페이지 (3단계 방식)
/// 1단계: 이름 + 이메일 + 인증번호 전송 + 인증번호 입력 → 다음
/// 2단계: 비밀번호 + 비밀번호 확인 + 개인정보 동의 → 회원가입
/// 3단계: 회원가입 완료 → 로그인하러 가기
library;

import 'dart:async';
import 'package:flutter/material.dart';

import '../../common.dart';
import '../../common/api/auth_service.dart';
import '../../common/widgets/auth_layout.dart';
import '../../common/widgets/styled_form_widgets.dart';

/// 이메일 유효성 검사 정규식
final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// 비밀번호 유효성 검사 정규식 (영문 + 숫자 + 특수문자, 8자 이상)
final _passwordRegex = RegExp(
    r'^(?=.*[A-Za-z])(?=.*\d)(?=.*[!@#$%^&*()_+\-={}\[\]:;"<>,.?/]).{8,}$');

/// 회원가입 페이지
class SignupPage extends StatefulWidget {
  final VoidCallback onSignupSuccess;
  final VoidCallback onBackToLogin;

  const SignupPage({
    Key? key,
    required this.onSignupSuccess,
    required this.onBackToLogin,
  }) : super(key: key);

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _nameError;
  String? _emailError;
  String? _codeError;
  String? _passwordError;
  String? _confirmPasswordError;

  bool _isInProgress = false;
  bool _isCodeSent = false;
  bool _isAgreed = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // 비밀번호 규칙 상태
  bool _hasNumber = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasMinLength = false;

  // 현재 단계 (1 또는 2)
  int _currentStep = 1;

  int _sendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _sendCooldown = 30;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sendCooldown > 0) {
        setState(() => _sendCooldown--);
      } else {
        timer.cancel();
      }
    });
  }

  /// 인증번호 전송
  Future<void> _sendVerificationCode() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty) {
      setState(() => _nameError = translate('Enter your name'));
      return;
    }
    if (email.isEmpty) {
      setState(() => _emailError = translate('Enter your email'));
      return;
    }
    if (!_emailRegex.hasMatch(email)) {
      setState(() => _emailError = translate('Invalid email format'));
      return;
    }

    setState(() {
      _isInProgress = true;
      _emailError = null;
    });

    try {
      final authService = getAuthService();

      // 1. 이메일 중복 확인 (이미 가입된 이메일인지 확인)
      final duplicateRes = await authService.checkEmailDuplicate(email);
      if (!duplicateRes.rawBody.contains('사용가능') ||
          duplicateRes.rawBody.contains('중복')) {
        setState(() {
          _emailError = translate('Email not available');
          _isInProgress = false;
        });
        return;
      }

      // 2. 인증코드 발송
      final sendRes = await authService.sendVerificationEmail(email);
      if (!sendRes.rawBody.contains('성공')) {
        setState(() {
          _emailError = translate('Bad Request');
          _isInProgress = false;
        });
        return;
      }

      setState(() {
        _isCodeSent = true;
        _isInProgress = false;
      });
      _startCooldown();
      showToast(translate('Verification code sent'));
    } catch (e) {
      setState(() {
        _emailError = translate('Bad Request');
        _isInProgress = false;
      });
    }
  }

  /// 1단계 → 2단계 이동 (인증번호 확인)
  Future<void> _goToStep2() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();

    if (code.isEmpty) {
      setState(() => _codeError = translate('Please enter verification code'));
      return;
    }

    setState(() {
      _isInProgress = true;
      _nameError = null;
      _codeError = null;
    });

    try {
      final authService = getAuthService();
      final verifyRes = await authService.verifyEmailCode(email, code);

      if (!verifyRes.rawBody.contains('성공')) {
        setState(() {
          _codeError = translate('Invalid verification code');
          _isInProgress = false;
        });
        return;
      }

      setState(() {
        _currentStep = 2;
        _isInProgress = false;
      });
    } catch (e) {
      setState(() {
        _codeError = translate('Bad Request');
        _isInProgress = false;
      });
    }
  }

  /// 2단계에서 뒤로가기
  void _goBackToStep1() {
    setState(() {
      _currentStep = 1;
      _passwordController.clear();
      _confirmPasswordController.clear();
      _passwordError = null;
      _confirmPasswordError = null;
      _isAgreed = false;
    });
  }

  /// 회원가입 실행
  Future<void> _onSignup() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    // 유효성 검사
    if (password.isEmpty) {
      setState(() => _passwordError = translate('Please enter password'));
      return;
    }

    if (!_passwordRegex.hasMatch(password)) {
      setState(() => _passwordError = translate(
          'Password requirements not met'));
      return;
    }

    if (password != confirmPassword) {
      setState(
          () => _confirmPasswordError = translate('The confirmation is not identical.'));
      return;
    }

    if (!_isAgreed) {
      showToast(translate('Please agree to the terms'));
      return;
    }

    setState(() {
      _isInProgress = true;
      _passwordError = null;
      _confirmPasswordError = null;
    });

    try {
      final authService = getAuthService();
      final signupRes =
          await authService.signup(name, email, password, confirmPassword);

      if (!signupRes.rawBody.contains('성공')) {
        setState(() {
          _passwordError = translate('Bad Request');
          _isInProgress = false;
        });
        return;
      }

      setState(() {
        _currentStep = 3;
        _isInProgress = false;
      });
    } catch (e) {
      setState(() {
        _passwordError = translate('Bad Request');
        _isInProgress = false;
      });
    }
  }

  /// 인증번호 전송 버튼 활성화 여부
  bool get _canSendCode {
    return _nameController.text.trim().isNotEmpty &&
        _emailController.text.trim().isNotEmpty &&
        _sendCooldown == 0 &&
        !_isInProgress;
  }

  /// 1단계 다음 버튼 활성화 여부
  bool get _isStep1Valid {
    return _nameController.text.trim().isNotEmpty &&
        _isCodeSent &&
        _codeController.text.trim().isNotEmpty;
  }

  /// 2단계 다음 버튼 활성화 여부
  bool get _isStep2Valid {
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    return password.isNotEmpty &&
        confirmPassword.isNotEmpty &&
        password == confirmPassword &&
        _isAgreed;
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
    // 모바일: 헤더를 스크롤 영역 밖에 고정
    Widget? mobileHeader;
    if (!isDesktop && _currentStep < 3) {
      mobileHeader = Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: _buildHeader(
          translate('Sign Up'),
          _currentStep == 1 ? widget.onBackToLogin : _goBackToStep1,
        ),
      );
    }

    return AuthPageLayout(
      mobileHeader: mobileHeader,
      formContent: _currentStep == 1
          ? _buildStep1()
          : _currentStep == 2
              ? _buildStep2()
              : _buildStep3(),
    );
  }

  /// 1단계: 이름 + 이메일 + 인증번호 전송 + 인증번호 입력
  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더 (데스크탑만 - 모바일은 AuthPageLayout.mobileHeader로 고정)
        if (isDesktop) ...[
          const SizedBox(height: 8),
          _buildHeader(translate('Sign Up'), widget.onBackToLogin),
        ],

        // 폼 영역 (가운데)
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 이름 필드
                Text(
                  translate('Name'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                AuthTextField(
                  controller: _nameController,
                  enabled: !_isCodeSent,
                  hintText: translate('Enter your name'),
                  errorText: _nameError,
                  onChanged: (_) {
                    if (_nameError != null) setState(() => _nameError = null);
                    setState(() {}); // 버튼 상태 업데이트
                  },
                ),
                const SizedBox(height: 20),

                // 이메일 필드
                Text(
                  translate('Email (ID)'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                AuthTextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_isCodeSent,
                  hintText: translate('Enter your email'),
                  errorText: _emailError,
                  onChanged: (_) {
                    if (_emailError != null) setState(() => _emailError = null);
                    setState(() {}); // 버튼 상태 업데이트
                  },
                ),
                const SizedBox(height: 20),

                // 인증번호 전송/재전송 버튼
                AuthMainButton(
                  label: _sendCooldown > 0
                      ? '${translate("Resend verification code")} (${_sendCooldown}s)'
                      : _isCodeSent
                          ? translate('Resend verification code')
                          : translate('Send verification code'),
                  onPressed: _canSendCode ? _sendVerificationCode : null,
                  isInProgress: _isInProgress && !_isCodeSent,
                  isOutlined: true,
                ),

                // 인증번호 입력 필드 (인증번호 전송 후 표시)
                if (_isCodeSent) ...[
                  const SizedBox(height: 20),
                  Text(
                    translate('Verification Code'),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  AuthTextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    hintText: translate('Please enter verification code'),
                    errorText: _codeError,
                    onChanged: (_) {
                      if (_codeError != null) setState(() => _codeError = null);
                      setState(() {}); // 버튼 상태 업데이트
                    },
                  ),
                ],
              ],
            ),
          ),
        ),

        // 진행 표시
        if (_isInProgress && _isCodeSent)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(),
          ),

        // 다음 버튼 (맨 아래)
        AuthMainButton(
          label: translate('Next'),
          onPressed: _isStep1Valid && !_isInProgress ? _goToStep2 : null,
          isInProgress: _isInProgress && _isCodeSent,
        ),
      ],
    );
  }

  /// 2단계: 비밀번호 + 비밀번호 확인 + 개인정보 동의
  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더 (데스크탑만 - 모바일은 AuthPageLayout.mobileHeader로 고정)
        if (isDesktop) ...[
          const SizedBox(height: 8),
          _buildHeader(translate('Sign Up'), _goBackToStep1),
        ],

        // 폼 영역 (가운데)
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 이메일 필드 (읽기 전용)
                Text(
                  translate('Email (ID)'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                AuthTextField(
                  controller: _emailController,
                  enabled: false,
                  hintText: 'you@example.com',
                ),
                const SizedBox(height: 20),

                // 비밀번호 필드
                Text(
                  translate('Password'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                AuthTextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  hintText: translate('Enter password'),
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
                  onChanged: (value) {
                    if (_passwordError != null) {
                      setState(() => _passwordError = null);
                    }
                    _updatePasswordRules(value);
                  },
                ),
                const SizedBox(height: 12),
                // 비밀번호 규칙 칩
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildRuleChip(translate('Use numbers'), _hasNumber),
                    _buildRuleChip(translate('Use uppercase'), _hasUppercase),
                    _buildRuleChip(translate('Use lowercase'), _hasLowercase),
                    _buildRuleChip(
                        translate('8 or more characters'), _hasMinLength),
                  ],
                ),
                const SizedBox(height: 20),

                // 비밀번호 확인 필드
                Text(
                  translate('Confirm Password'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                AuthTextField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  hintText: translate('Re-enter password'),
                  errorText: _confirmPasswordError,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: Colors.grey[500],
                    ),
                    onPressed: () => setState(() =>
                        _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                  onChanged: (_) {
                    if (_confirmPasswordError != null)
                      setState(() => _confirmPasswordError = null);
                    setState(() {}); // 버튼 상태 업데이트
                  },
                ),
                const SizedBox(height: 24),

                // 개인정보 동의
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StyledCheckbox(
                      value: _isAgreed,
                      onChanged: (value) =>
                          setState(() => _isAgreed = value ?? false),
                      accentColor: kFormPrimaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isAgreed = !_isAgreed),
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[700]),
                            children: [
                              TextSpan(
                                text: translate('Privacy Policy'),
                                style: const TextStyle(
                                  color: Color(0xFF5B7BF8),
                                ),
                              ),
                              TextSpan(text: translate(' and ')),
                              TextSpan(
                                text: translate('Terms of Service'),
                                style: const TextStyle(
                                  color: Color(0xFF5B7BF8),
                                ),
                              ),
                              TextSpan(text: translate(' agree.')),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // 진행 표시
        if (_isInProgress)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(),
          ),

        // 다음(회원가입) 버튼 (맨 아래)
        AuthMainButton(
          label: translate('Next'),
          onPressed: _isStep2Valid && !_isInProgress ? _onSignup : null,
          isInProgress: _isInProgress,
        ),
      ],
    );
  }

  /// 3단계: 회원가입 완료
  Widget _buildStep3() {
    return Column(
      children: [
        // 폼 영역 (가운데)
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                  translate('Signup completed'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5B7BF8),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  translate('Login and try various OneDesk services!'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),

        // 로그인하러 가기 버튼 (맨 아래)
        AuthMainButton(
          label: translate('Go to login'),
          onPressed: widget.onSignupSuccess,
        ),
      ],
    );
  }

  /// 비밀번호 규칙 업데이트
  void _updatePasswordRules(String password) {
    setState(() {
      _hasNumber = password.contains(RegExp(r'[0-9]'));
      _hasUppercase = password.contains(RegExp(r'[A-Z]'));
      _hasLowercase = password.contains(RegExp(r'[a-z]'));
      _hasMinLength = password.length >= 8;
    });
  }

  /// 비밀번호 규칙 칩
  Widget _buildRuleChip(String label, bool isValid) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isValid ? const Color(0xFFEEF2FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isValid ? kFormPrimaryColor : kFormDisabledColor,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check,
            size: 14,
            color: isValid ? kFormPrimaryColor : kFormDisabledColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isValid ? kFormPrimaryColor : kFormDisabledColor,
                ),
          ),
        ],
      ),
    );
  }
}
