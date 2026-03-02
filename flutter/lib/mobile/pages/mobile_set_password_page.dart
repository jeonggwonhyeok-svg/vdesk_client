/// 모바일 영구 비밀번호 설정 페이지
/// 데스크탑 setPasswordDialog와 동일한 디자인

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/widgets/custom_password.dart';
import '../../models/platform_model.dart';

class MobileSetPasswordPage extends StatefulWidget {
  final VoidCallback? onSuccess;

  const MobileSetPasswordPage({Key? key, this.onSuccess}) : super(key: key);

  @override
  State<MobileSetPasswordPage> createState() => _MobileSetPasswordPageState();
}

class _MobileSetPasswordPageState extends State<MobileSetPasswordPage> {
  // 모바일 마이페이지 스타일과 동일한 색상
  static const Color _titleColor = Color(0xFF454447); // _textValue와 동일
  static const Color _labelColor = Color(0xFF323335);
  static const Color _textSecondary = Color(0xFF8F8E95);
  static const Color _accentColor = Color(0xFF5F71FF);
  static const Color _disabledColor = Color(0xFFB9B8BF);

  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final RxString _rxPass = ''.obs;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String _errMsg0 = '';
  String _errMsg1 = '';
  bool _showComplete = false;

  final _rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    MinCharactersValidationRule(8),
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentPassword();
  }

  Future<void> _loadCurrentPassword() async {
    final currentPassword = await bind.mainGetPermanentPassword();
    if (currentPassword.isNotEmpty) {
      _passwordController.text = currentPassword;
      _confirmController.text = currentPassword;
      _rxPass.value = currentPassword;
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _errMsg0 = '';
      _errMsg1 = '';
    });

    final pass = _passwordController.text.trim();
    if (pass.isNotEmpty) {
      final violations = _rules.where((r) => !r.validate(pass));
      if (violations.isNotEmpty) {
        setState(() {
          _errMsg0 = translate('Password requirements not met');
        });
        return;
      }
    }

    if (_confirmController.text.trim() != pass) {
      setState(() {
        _errMsg1 = translate('The confirmation is not identical.');
      });
      return;
    }

    await bind.mainSetPermanentPassword(password: pass);

    if (mounted) {
      if (pass.isNotEmpty) {
        setState(() => _showComplete = true);
      } else {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showComplete) return _buildCompleteScreen();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: _titleColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          translate('Set permanent password'),
          style: const TextStyle(
            color: _titleColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 비밀번호 라벨 - 모바일 마이페이지 스타일 (normal weight)
                  Text(
                    translate('Password'),
                    style: const TextStyle(
                      color: _labelColor,
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 비밀번호 입력 필드
                  _buildPasswordField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    hintText: translate('Enter password'),
                    errorText: _errMsg0,
                    onToggleVisibility: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                    onChanged: (value) {
                      _rxPass.value = value.trim();
                      setState(() => _errMsg0 = '');
                    },
                  ),
                  const SizedBox(height: 16),
                  // 비밀번호 규칙 칩 (한 줄에 2개씩, 늘리지 않음)
                  Obx(() => Column(
                        children: [
                          for (int i = 0; i < _rules.length; i += 2)
                            Padding(
                              padding: EdgeInsets.only(bottom: i < _rules.length - 2 ? 8 : 0),
                              child: Row(
                                children: [
                                  _buildValidationChip(
                                    _rules[i].name,
                                    _rules[i].validate(_rxPass.value.trim()),
                                  ),
                                  const SizedBox(width: 8),
                                  if (i + 1 < _rules.length)
                                    _buildValidationChip(
                                      _rules[i + 1].name,
                                      _rules[i + 1].validate(_rxPass.value.trim()),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      )),
                  const SizedBox(height: 24),
                  // 비밀번호 확인 라벨 - 모바일 마이페이지 스타일 (normal weight)
                  Text(
                    translate('Confirm Password'),
                    style: const TextStyle(
                      color: _labelColor,
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 비밀번호 확인 입력 필드
                  _buildPasswordField(
                    controller: _confirmController,
                    obscureText: _obscureConfirm,
                    hintText: translate('Re-enter password'),
                    errorText: _errMsg1,
                    onToggleVisibility: () {
                      setState(() => _obscureConfirm = !_obscureConfirm);
                    },
                    onChanged: (value) {
                      setState(() => _errMsg1 = '');
                    },
                  ),
                ],
              ),
            ),
          ),
          // 하단 버튼
          _buildBottomButtons(context),
        ],
      ),
    );
  }

  /// 비밀번호 설정 완료 화면
  Widget _buildCompleteScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: _titleColor, size: 20),
          onPressed: () {
            widget.onSuccess?.call();
            Navigator.pop(context);
          },
        ),
        title: Text(
          translate('Set permanent password'),
          style: const TextStyle(
            color: _titleColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/icons/sucess.png', width: 120, height: 120),
                  const SizedBox(height: 24),
                  Text(
                    translate('Password setting complete'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5B7BF8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    translate('Password setting has been completed.'),
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 하단 확인 버튼
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    widget.onSuccess?.call();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5B7BF8),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    translate('OK'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 비밀번호 입력 필드
  Widget _buildPasswordField({
    required TextEditingController controller,
    required bool obscureText,
    required String hintText,
    required String errorText,
    required VoidCallback onToggleVisibility,
    required Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: errorText.isNotEmpty ? Colors.red : const Color(0xFFDEDEE2),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 14, color: _titleColor),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(color: Color(0xFFB9B8BF), fontSize: 14),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              suffixIcon: IconButton(
                icon: Icon(
                  obscureText
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: _labelColor,
                ),
                onPressed: onToggleVisibility,
              ),
            ),
          ),
        ),
        if (errorText.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            errorText,
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ],
      ],
    );
  }

  /// 유효성 검사 칩
  Widget _buildValidationChip(String label, bool isValid) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isValid ? const Color(0xFFEEF2FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isValid ? _accentColor : _disabledColor,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check,
            size: 14,
            color: isValid ? _accentColor : _disabledColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: isValid ? _accentColor : _disabledColor,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// 하단 버튼 (홈페이지 연결 버튼 스타일)
  Widget _buildBottomButtons(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // 취소 버튼 (마이페이지 로그아웃 버튼 스타일)
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF646368),
                  side: const BorderSide(color: Color(0xFFDEDEE2)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(translate('Cancel')),
              ),
            ),
            const SizedBox(width: 12),
            // 완료 버튼 (홈페이지 연결 버튼 스타일)
            Expanded(
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5B7BF8),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  translate('Done'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
