/// 비밀번호 재설정 다이얼로그
/// 이메일 인증 후 새 비밀번호를 설정합니다.
library;

import 'dart:async';
import 'package:flutter/material.dart';

import '../../common.dart';
import '../api/auth_service.dart';
import '../api/api_client.dart';
import './dialog.dart';

/// 이메일 유효성 검사 정규식
final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// 비밀번호 유효성 검사 정규식 (영문 + 숫자 + 특수문자, 8자 이상)
final _passwordRegex =
    RegExp(r'^(?=.*[A-Za-z])(?=.*\d)(?=.*[!@#$%^&*()_+\-={}[\]:;"<>,.?/]).{8,}$');

/// 비밀번호 재설정 다이얼로그 표시
Future<bool?> resetPasswordDialog() async {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final codeController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  String? nameError;
  String? emailError;
  String? codeError;
  String? passwordError;
  String? confirmPasswordError;

  var isInProgress = false;
  var isEmailSent = false;
  var isEmailVerified = false;

  // 인증코드 발송 쿨다운
  var sendCooldown = 0;
  Timer? cooldownTimer;

  final res = await gFFI.dialogManager.show<bool>((setState, close, context) {
    // 쿨다운 시작
    void startCooldown() {
      sendCooldown = 30;
      cooldownTimer?.cancel();
      cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (sendCooldown > 0) {
          setState(() => sendCooldown--);
        } else {
          timer.cancel();
        }
      });
    }

    // 이메일 인증코드 발송
    Future<void> sendVerificationCode() async {
      final name = nameController.text.trim();
      final email = emailController.text.trim();

      // 이름 유효성 검사
      if (name.isEmpty) {
        setState(() => nameError = translate('Enter your name'));
        return;
      }

      // 이메일 유효성 검사
      if (email.isEmpty) {
        setState(() => emailError = translate('Enter your email'));
        return;
      }
      if (!_emailRegex.hasMatch(email)) {
        setState(() => emailError = translate('Invalid email format'));
        return;
      }

      setState(() {
        isInProgress = true;
        emailError = null;
      });

      try {
        final authService = getAuthService();

        // 1. 이메일 중복 확인 (기존 회원인지 확인)
        final duplicateRes = await authService.checkEmailDuplicate(email);
        // "중복"이 없으면 등록되지 않은 이메일 (신규 이메일)
        if (!duplicateRes.rawBody.contains('중복')) {
          setState(() {
            emailError = translate('Email not found');
            isInProgress = false;
          });
          return;
        }

        // 2. 인증코드 발송
        final sendRes = await authService.sendVerificationEmail(email);
        if (!sendRes.rawBody.contains('성공')) {
          setState(() {
            emailError = translate('Bad Request');
            isInProgress = false;
          });
          return;
        }

        setState(() {
          isEmailSent = true;
          isInProgress = false;
        });
        startCooldown();
        showToast(translate('Verification code sent'));
      } catch (e) {
        setState(() {
          emailError = translate('Bad Request');
          isInProgress = false;
        });
      }
    }

    // 인증코드 검증
    Future<void> verifyCode() async {
      final email = emailController.text.trim();
      final code = codeController.text.trim();

      if (code.isEmpty) {
        setState(() => codeError = translate('Please enter verification code'));
        return;
      }

      setState(() {
        isInProgress = true;
        codeError = null;
      });

      try {
        final authService = getAuthService();
        final verifyRes = await authService.verifyEmailCode(email, code);

        // 응답에 "성공"이 없으면 인증 실패
        if (!verifyRes.rawBody.contains('성공')) {
          setState(() {
            codeError = translate('Invalid verification code');
            isInProgress = false;
          });
          return;
        }

        setState(() {
          isEmailVerified = true;
          isInProgress = false;
        });
        showToast(translate('Email verified'));
      } catch (e) {
        setState(() {
          codeError = translate('Bad Request');
          isInProgress = false;
        });
      }
    }

    // 비밀번호 재설정 완료
    Future<void> onResetPassword() async {
      final name = nameController.text.trim();
      final email = emailController.text.trim();
      final password = passwordController.text;
      final confirmPassword = confirmPasswordController.text;

      // 유효성 검사
      if (!isEmailVerified) {
        showToast(translate('Please verify your email first'));
        return;
      }

      if (name.isEmpty) {
        setState(() => nameError = translate('Enter your name'));
        return;
      }

      if (password.isEmpty) {
        setState(() => passwordError = translate('Please enter password'));
        return;
      }

      if (!_passwordRegex.hasMatch(password)) {
        setState(() => passwordError = translate(
            'Password requirements not met'));
        return;
      }

      if (password != confirmPassword) {
        setState(() => confirmPasswordError = translate('The confirmation is not identical.'));
        return;
      }

      setState(() {
        isInProgress = true;
        passwordError = null;
        confirmPasswordError = null;
      });

      try {
        final authService = getAuthService();
        final resetRes = await authService.resetPassword(email, name, password, confirmPassword);

        // 성공 여부 확인
        if (!resetRes.rawBody.contains('성공')) {
          setState(() {
            passwordError = translate('Bad Request');
            isInProgress = false;
          });
          return;
        }

        showToast(translate('Password reset successful'));
        close(true);
      } catch (e) {
        setState(() {
          passwordError = translate('Bad Request');
          isInProgress = false;
        });
      }
    }

    // 취소
    void onCancel() {
      cooldownTimer?.cancel();
      close(false);
    }

    // 이름 입력 필드
    Widget nameField() {
      return DialogTextField(
        title: translate('Name'),
        controller: nameController,
        prefixIcon: const Icon(Icons.person_outlined),
        errorText: nameError,
      );
    }

    // 이메일 입력 필드
    Widget emailField() {
      return Row(
        children: [
          Expanded(
            child: DialogTextField(
              title: translate('Email'),
              controller: emailController,
              prefixIcon: const Icon(Icons.email_outlined),
              errorText: emailError,
              keyboardType: TextInputType.emailAddress,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            height: 48,
            child: ElevatedButton(
              onPressed: sendCooldown > 0 || isInProgress ? null : sendVerificationCode,
              child: Text(
                sendCooldown > 0 ? '${sendCooldown}s' : translate('Send'),
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
        ],
      );
    }

    // 인증코드 입력 필드
    Widget codeField() {
      return Row(
        children: [
          Expanded(
            child: DialogTextField(
              title: translate('Verification Code'),
              controller: codeController,
              prefixIcon: const Icon(Icons.verified_outlined),
              errorText: codeError,
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            height: 48,
            child: ElevatedButton(
              onPressed: isEmailVerified || isInProgress ? null : verifyCode,
              style: isEmailVerified
                  ? ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    )
                  : null,
              child: Text(
                isEmailVerified ? translate('Verified') : translate('Verify'),
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
        ],
      );
    }

    return CustomAlertDialog(
      title: Text(translate('Reset Password')),
      contentBoxConstraints: const BoxConstraints(minWidth: 400),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 안내 텍스트
          Text(
            translate('Enter your email to reset password'),
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 16),

          // 이름 입력
          nameField(),
          const SizedBox(height: 8),

          // 이메일 입력
          emailField(),
          const SizedBox(height: 8),

          // 인증코드 입력 (이메일 발송 후 표시)
          if (isEmailSent) ...[
            codeField(),
            const SizedBox(height: 16),
          ],

          // 비밀번호 입력 (이메일 인증 후 표시)
          if (isEmailVerified) ...[
            Text(
              translate('Enter your new password'),
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 8),
            PasswordWidget(
              controller: passwordController,
              autoFocus: false,
              title: translate('New Password'),
              errorText: passwordError,
              hintText: translate('Enter new password'),
            ),
            PasswordWidget(
              controller: confirmPasswordController,
              autoFocus: false,
              title: translate('Confirm Password'),
              errorText: confirmPasswordError,
              hintText: translate('Confirm new password'),
            ),
          ],

          // 진행 표시
          if (isInProgress) const LinearProgressIndicator(),
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: dialogButton(
                translate('Cancel'),
                onPressed: onCancel,
                isOutline: true,
              ),
            ),
            if (isEmailVerified) ...[
              const SizedBox(width: 12),
              Expanded(
                child: dialogButton(
                  translate('Reset'),
                  onPressed: isInProgress ? null : onResetPassword,
                ),
              ),
            ],
          ],
        ),
      ],
      onCancel: onCancel,
      onSubmit: isEmailVerified ? onResetPassword : null,
    );
  });

  return res;
}
