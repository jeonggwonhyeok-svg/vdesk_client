/// 회원가입 다이얼로그
/// 이름, 이메일 중복확인, 비밀번호 설정 플로우를 제공합니다.
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../api/auth_service.dart';
import './dialog.dart';

/// 이메일 유효성 검사 정규식
final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// 비밀번호 유효성 검사 정규식 (영문 + 숫자 + 특수문자, 8자 이상)
final _passwordRegex =
    RegExp(r'^(?=.*[A-Za-z])(?=.*\d)(?=.*[!@#$%^&*()_+\-={}[\]:;"<>,.?/]).{8,}$');

/// 회원가입 다이얼로그 표시
Future<bool?> signupDialog() async {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  String? nameError;
  String? emailError;
  String? passwordError;
  String? confirmPasswordError;

  var isInProgress = false;
  var isEmailChecked = false; // 이메일 중복확인 완료 여부
  var isEmailAvailable = false; // 이메일 사용 가능 여부
  var isAgreed = false;

  final res = await gFFI.dialogManager.show<bool>((setState, close, context) {
    // 리스너 추가 - 입력 시 에러 클리어
    nameController.addListener(() {
      if (nameError != null) {
        setState(() => nameError = null);
      }
    });

    emailController.addListener(() {
      if (emailError != null) {
        setState(() => emailError = null);
      }
      // 이메일 변경 시 중복확인 상태 초기화
      if (isEmailChecked) {
        setState(() {
          isEmailChecked = false;
          isEmailAvailable = false;
        });
      }
    });

    // 이메일 중복 확인
    Future<void> checkEmailDuplicate() async {
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

        // 이메일 중복 확인
        final dupRes = await authService.checkEmailDuplicate(email);
        // "사용가능"이 없거나 "중복"이 있으면 이미 등록된 이메일
        if (!dupRes.rawBody.contains('사용가능') || dupRes.rawBody.contains('중복')) {
          setState(() {
            emailError = translate('Email already exists');
            isEmailChecked = true;
            isEmailAvailable = false;
            isInProgress = false;
          });
          return;
        }

        setState(() {
          isEmailChecked = true;
          isEmailAvailable = true;
          isInProgress = false;
        });
        showToast(translate('Email available'));
      } catch (e) {
        setState(() {
          emailError = translate('Bad Request');
          isInProgress = false;
        });
      }
    }

    // 회원가입 완료
    Future<void> onSignup() async {
      final name = nameController.text.trim();
      final email = emailController.text.trim();
      final password = passwordController.text;
      final confirmPassword = confirmPasswordController.text;

      // 유효성 검사
      if (name.isEmpty) {
        setState(() => nameError = translate('Enter your name'));
        return;
      }

      if (!isEmailChecked || !isEmailAvailable) {
        setState(() => emailError = translate('Please check email availability'));
        return;
      }

      if (!isAgreed) {
        showToast(translate('Please agree to the terms'));
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
        nameError = null;
        passwordError = null;
        confirmPasswordError = null;
      });

      try {
        final authService = getAuthService();
        final signupRes = await authService.signup(name, email, password, confirmPassword);

        // 성공 여부 확인
        if (!signupRes.rawBody.contains('성공')) {
          setState(() {
            passwordError = translate('Bad Request');
            isInProgress = false;
          });
          return;
        }

        showToast(translate('Signup successful'));
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
      close(false);
    }

    // 이름 입력 필드
    Widget nameField() {
      return DialogTextField(
        title: translate('Name'),
        controller: nameController,
        prefixIcon: const Icon(Icons.person_outline),
        errorText: nameError,
        hintText: translate('Enter your name'),
      );
    }

    // 이메일 입력 필드
    Widget emailField() {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: DialogTextField(
              title: translate('Email'),
              controller: emailController,
              prefixIcon: const Icon(Icons.email_outlined),
              errorText: emailError,
              keyboardType: TextInputType.emailAddress,
              hintText: translate('Enter your email'),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: SizedBox(
              width: 100,
              height: 48,
              child: ElevatedButton(
                onPressed: isEmailAvailable || isInProgress ? null : checkEmailDuplicate,
                style: isEmailAvailable
                    ? ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      )
                    : null,
                child: Text(
                  isEmailAvailable ? translate('Verified') : translate('Check'),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return CustomAlertDialog(
      title: Text(translate('Sign Up')),
      contentBoxConstraints: const BoxConstraints(minWidth: 400),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 이름 입력
          nameField(),
          const SizedBox(height: 8),

          // 이메일 입력 (중복확인 버튼 포함)
          emailField(),
          const SizedBox(height: 8),

          // 비밀번호 입력
          PasswordWidget(
            controller: passwordController,
            autoFocus: false,
            errorText: passwordError,
            hintText: translate('Enter password'),
          ),
          PasswordWidget(
            controller: confirmPasswordController,
            autoFocus: false,
            title: translate('Confirm Password'),
            errorText: confirmPasswordError,
            hintText: translate('Confirm password'),
          ),
          const SizedBox(height: 8),

          // 약관 동의
          Row(
            children: [
              Checkbox(
                value: isAgreed,
                onChanged: (value) {
                  setState(() => isAgreed = value ?? false);
                },
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => isAgreed = !isAgreed),
                  child: Text(
                    translate('I agree to the Terms of Service'),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ],
          ),

          // 진행 표시
          if (isInProgress) const LinearProgressIndicator(),
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(child: dialogButton(translate('Cancel'), onPressed: onCancel, isOutline: true)),
            const SizedBox(width: 12),
            Expanded(child: dialogButton(translate('Sign Up'), onPressed: isInProgress ? null : onSignup)),
          ],
        ),
      ],
      onCancel: onCancel,
      onSubmit: onSignup,
    );
  });

  return res;
}
