/// 모바일 보안 설정 페이지
/// 데스크탑 설정의 보안 섹션과 동일한 기능 제공

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../common/widgets/styled_form_widgets.dart';
import '../../models/server_model.dart';
import 'mobile_set_password_page.dart';

class MobileSecuritySettingsPage extends StatefulWidget {
  const MobileSecuritySettingsPage({Key? key}) : super(key: key);

  @override
  State<MobileSecuritySettingsPage> createState() =>
      _MobileSecuritySettingsPageState();
}

class _MobileSecuritySettingsPageState
    extends State<MobileSecuritySettingsPage> {
  static const Color _titleColor = Color(0xFF454447);
  static const Color _labelColor = Color(0xFF646368);
  static const Color _accentColor = Color(0xFF5F71FF);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(
        builder: (context, serverModel, child) {
          final usePassword = serverModel.approveMode != 'click';
          final tmpEnabled =
              serverModel.verificationMethod != kUsePermanentPassword;
          final permEnabled =
              serverModel.verificationMethod != kUseTemporaryPassword;

          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios,
                    color: _titleColor, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                translate('Security Settings'),
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
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 세션 카드
                        _buildSessionCard(serverModel),
                        const SizedBox(height: 12),
                        // 비밀번호 카드 (비밀번호 모드일 때만)
                        if (usePassword)
                          _buildPasswordCard(serverModel, tmpEnabled, permEnabled),
                      ],
                    ),
                  ),
                ),
                // 하단 버튼
                _buildBottomButtons(context),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 세션 카드 (설정 페이지 카드 스타일)
  Widget _buildSessionCard(ServerModel serverModel) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26333C87),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 카드 타이틀
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              translate('Session'),
              style: const TextStyle(
                color: _titleColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(
              height: 1, color: Color(0xFFEEEEEE), indent: 16, endIndent: 16),
          // 드롭다운
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildDropdownInCard(
              value: _getApproveModeLabel(serverModel.approveMode),
              items: [
                translate('Accept sessions via password'),
                translate('Accept sessions via click'),
                translate('Accept sessions via both'),
              ],
              onChanged: (value) {
                if (value == translate('Accept sessions via password')) {
                  serverModel.setApproveMode('password');
                } else if (value == translate('Accept sessions via click')) {
                  serverModel.setApproveMode('click');
                } else {
                  serverModel.setApproveMode(defaultOptionApproveMode);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 비밀번호 카드 (설정 페이지 카드 스타일)
  Widget _buildPasswordCard(ServerModel serverModel, bool tmpEnabled, bool permEnabled) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26333C87),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 카드 타이틀
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              translate('Password'),
              style: const TextStyle(
                color: _titleColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(
              height: 1, color: Color(0xFFEEEEEE), indent: 16, endIndent: 16),
          // 비밀번호 방식 드롭다운
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildDropdownInCard(
              value:
                  _getVerificationMethodLabel(serverModel.verificationMethod),
              items: [
                translate('Use one-time password'),
                translate('Use permanent password'),
                translate('Use both passwords'),
              ],
              onChanged: (value) async {
                String key;
                if (value == translate('Use one-time password')) {
                  key = kUseTemporaryPassword;
                } else if (value == translate('Use permanent password')) {
                  key = kUsePermanentPassword;
                } else {
                  key = kUseBothPasswords;
                }
                await serverModel.setVerificationMethod(key);
                await serverModel.updatePasswordModel();
              },
            ),
          ),
          // 일회용 비밀번호 옵션 (일회용 비밀번호 사용 시에만) - F7F7F7 인라인 배경 카드
          if (tmpEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 일회용 비밀번호 길이 라벨
                    Text(
                      translate('One-time password length'),
                      style: const TextStyle(
                        color: _titleColor,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 숫자 비밀번호 체크박스
                    GestureDetector(
                      onTap: () =>
                          serverModel.switchAllowNumericOneTimePassword(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StyledCheckbox(
                            value: serverModel.allowNumericOneTimePassword,
                            onChanged: (v) =>
                                serverModel.switchAllowNumericOneTimePassword(),
                            accentColor: _accentColor,
                            size: 20,
                            iconSize: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            translate('Numeric one-time password'),
                            style: const TextStyle(
                              color: _titleColor,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 길이 선택 라디오 버튼
                    Row(
                      children: ['6', '8', '10'].map((length) {
                        final isSelected =
                            serverModel.temporaryPasswordLength == length;
                        return GestureDetector(
                          onTap: () async {
                            await serverModel.setTemporaryPasswordLength(length);
                            await serverModel.updatePasswordModel();
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StyledRadio<String>(
                                value: length,
                                groupValue: serverModel.temporaryPasswordLength,
                                onChanged: (value) async {
                                  if (value != null) {
                                    await serverModel
                                        .setTemporaryPasswordLength(value);
                                    await serverModel.updatePasswordModel();
                                  }
                                },
                                accentColor: _accentColor,
                                size: 20,
                                innerSize: 10,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                length,
                                style: TextStyle(
                                  color:
                                      isSelected ? _accentColor : _titleColor,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 16),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
          // 영구 비밀번호 설정 버튼 (카드 안)
          if (permEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MobileSetPasswordPage(),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _titleColor,
                    side: const BorderSide(color: Color(0xFFDEDEE2)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    translate('Set permanent password'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 카드 내부용 드롭다운 (설정 페이지 스타일 - 테두리)
  Widget _buildDropdownInCard({
    required String value,
    required List<String> items,
    required Function(String) onChanged,
  }) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFDEDEE2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<String>(
        value: value,
        items: items.map((item) {
          return DropdownMenuItem<String>(
            value: item,
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                item,
                style: const TextStyle(
                  color: _titleColor,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        }).toList(),
        onChanged: (newValue) {
          if (newValue != null) {
            onChanged(newValue);
          }
        },
        isExpanded: true,
        underline: const SizedBox.shrink(),
        icon: const Padding(
          padding: EdgeInsets.only(right: 16),
          child: Icon(Icons.expand_more, color: _labelColor, size: 20),
        ),
      ),
    );
  }

  /// 하단 버튼
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
            // 취소 버튼
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
            // 설정 완료 버튼
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
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
                  translate('Settings Complete'),
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

  /// 세션 수락 모드 레이블
  String _getApproveModeLabel(String mode) {
    switch (mode) {
      case 'password':
        return translate('Accept sessions via password');
      case 'click':
        return translate('Accept sessions via click');
      default:
        return translate('Accept sessions via both');
    }
  }

  /// 비밀번호 인증 방식 레이블
  String _getVerificationMethodLabel(String method) {
    switch (method) {
      case kUseTemporaryPassword:
        return translate('Use one-time password');
      case kUsePermanentPassword:
        return translate('Use permanent password');
      default:
        return translate('Use both passwords');
    }
  }
}
