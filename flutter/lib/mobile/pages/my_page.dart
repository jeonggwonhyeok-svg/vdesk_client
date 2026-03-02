/// 모바일 마이페이지

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/login.dart';
import 'home_page.dart';
import 'mobile_set_password_page.dart';
import 'plan_selection_page.dart';

class MobileMyPage extends StatefulWidget implements PageShape {
  @override
  final title = translate("My Page");

  @override
  final icon = const Icon(Icons.person_outline);

  @override
  final appBarActions = <Widget>[];

  MobileMyPage({Key? key}) : super(key: key);

  @override
  State<MobileMyPage> createState() => _MobileMyPageState();
}

class _MobileMyPageState extends State<MobileMyPage> {
  // 플랜 섹션 펼침/접힘 상태
  bool _isPlanExpanded = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // 헤더
          const SizedBox(
            height: 56,
            child: Center(
              child: Text(
                '마이페이지',
                style: TextStyle(
                  color: Color(0xFF454447),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          // 프로필 아이콘 (데스크탑과 동일한 로고)
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF1FF),
              borderRadius: BorderRadius.circular(40),
            ),
            child: Center(
              child: SvgPicture.asset(
                'assets/icons/topbar-logo.svg',
                width: 40,
                height: 40,
                colorFilter: const ColorFilter.mode(
                  Color(0xFFCDD3FF),
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 사용자 이름
          Text(
            '${gFFI.userModel.userName.value} ${translate("nim")}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF646368),
            ),
          ),
          // 이메일 (null이 아닐 경우에만 표시)
          if (gFFI.userModel.userEmail.value.isNotEmpty &&
              gFFI.userModel.userEmail.value != 'null') ...[
            const SizedBox(height: 4),
            Text(
              gFFI.userModel.userEmail.value,
              style: const TextStyle(fontSize: 13, color: Color(0xFF8F8E95)),
            ),
          ],
          const SizedBox(height: 20),
          // 로그아웃 버튼
          OutlinedButton(
            onPressed: () => logOutConfirmDialog(),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF646368),
              side: const BorderSide(color: Color(0xFFDEDEE2)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            ),
            child: Text(translate('Logout')),
          ),
          const SizedBox(height: 32),
          // 현재 플랜
          _buildPlanCard(),
          const SizedBox(height: 16),
          // 비밀번호 변경 (소셜 로그인이 아닌 경우만 표시)
          if (gFFI.userModel.loginType.value == 0) ...[
            _buildChangePasswordCard(),
            const SizedBox(height: 16),
          ],
          // 정책
          _buildPolicyCard(),
          const SizedBox(height: 4),
          // 회원탈퇴
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => withdrawConfirmDialog(),
              child: Text(
                translate('Delete Account'),
                style: const TextStyle(fontSize: 14, color: Color(0xFF8F8E95)),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// 플랜 이름
  String get _currentPlan {
    final planType = gFFI.userModel.planType.value;
    return _getPlanName(planType);
  }

  /// 프리 플랜 여부
  bool get _isFreePlan => _currentPlan.toLowerCase().contains('free');

  /// 결제 수단
  String get _paymentMethod {
    final provider = gFFI.userModel.currentUserInfo?.billingProvider;
    if (provider == null || provider.isEmpty) return '-';
    switch (provider) {
      case 'WELCOME':
        return 'Welcome Payments';
      case 'PAYPAL':
        return 'PayPal';
      default:
        return provider;
    }
  }

  /// 구독 시작일
  String get _subscriptionStart {
    final date = gFFI.userModel.currentUserInfo?.lastPay;
    if (date == null || date.isEmpty) return '-';
    return '${date.replaceAll('-', '.')}~';
  }

  /// 다음 결제 예정일
  String get _nextPaymentDate {
    final date = gFFI.userModel.currentUserInfo?.nextChargeDate;
    if (date == null || date.isEmpty) return '-';
    return date.replaceAll('-', '.');
  }

  Widget _buildPlanCard() {
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
        children: [
          // 플랜 헤더
          InkWell(
            onTap: _isFreePlan ? null : () => setState(() => _isPlanExpanded = !_isPlanExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 라벨
                  Text(
                    translate('Current Plan'),
                    style: const TextStyle(fontSize: 14, color: Color(0xFF8F8E95)),
                  ),
                  const SizedBox(height: 12),
                  // 플랜 이름 + 아이콘/버튼
                  Row(
                    children: [
                      Text(
                        '$_currentPlan Plan',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF454447),
                        ),
                      ),
                      const Spacer(),
                      if (_isFreePlan)
                        // 프리 플랜: 업그레이드 버튼
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const MobilePlanSelectionPage()),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF5F71FF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              translate('Upgrade Plan'),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        )
                      else
                        // 유료 플랜: 펼침/접힘 아이콘
                        Icon(
                          _isPlanExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: const Color(0xFF8F8E95),
                          size: 24,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 플랜 상세 정보 (유료 플랜이고 펼쳐졌을 때만 표시)
          if (!_isFreePlan && _isPlanExpanded) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // 결제 수단 라벨
                  Text(
                    translate('Payment Method'),
                    style: const TextStyle(fontSize: 14, color: Color(0xFF8F8E95)),
                  ),
                  const SizedBox(height: 8),
                  // 결제 수단 카드
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _paymentMethod,
                      style: const TextStyle(fontSize: 14, color: Color(0xFF454447)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 변경하기 버튼
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton(
                      onPressed: () {
                        // TODO: 결제 수단 변경
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF646368),
                        side: const BorderSide(color: Color(0xFFDEDEE2)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
                      ),
                      child: Text(translate('Change')),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 구독 시작일 라벨
                  Text(
                    translate('Subscription Start'),
                    style: const TextStyle(fontSize: 14, color: Color(0xFF8F8E95)),
                  ),
                  const SizedBox(height: 8),
                  // 구독 시작일 값
                  Text(
                    _subscriptionStart,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF454447)),
                  ),
                  const SizedBox(height: 20),
                  // 결제 예정일 라벨
                  Text(
                    translate('Next Payment Date'),
                    style: const TextStyle(fontSize: 14, color: Color(0xFF8F8E95)),
                  ),
                  const SizedBox(height: 8),
                  // 결제 예정일 값
                  Text(
                    _nextPaymentDate,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF454447)),
                  ),
                  const SizedBox(height: 20),
                  // 플랜 변경하기 버튼
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const MobilePlanSelectionPage()),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5F71FF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(translate('Plan Change')),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 플랜 상세 정보 행
  Widget _buildPlanDetailRow({
    required String label,
    required String value,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Color(0xFF8F8E95)),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 14, color: Color(0xFF454447)),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ],
        ],
      ),
    );
  }

  Widget _buildChangePasswordCard() {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const MobileSetPasswordPage()),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
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
        child: Row(
          children: [
            Text(
              translate('Change Password'),
              style: const TextStyle(fontSize: 14, color: Color(0xFF454447)),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, color: Color(0xFF8F8E95)),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicyCard() {
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
        children: [
          _buildPolicyItem(translate('Terms of Service'), 'https://onedesk.co.kr/terms'),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _buildPolicyItem(translate('Privacy Policy'), 'https://onedesk.co.kr/privacy'),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _buildPolicyItem(translate('Payment and Refund Policy'), 'https://onedesk.co.kr/refund'),
        ],
      ),
    );
  }

  Widget _buildPolicyItem(String title, String url) {
    return InkWell(
      onTap: () => launchUrlString(url),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 14, color: Color(0xFF454447))),
            const Spacer(),
            const Icon(Icons.chevron_right, color: Color(0xFF8F8E95)),
          ],
        ),
      ),
    );
  }

  String _getPlanName(String planType) {
    switch (planType.toUpperCase()) {
      case 'FREE': return 'Free';
      case 'SOLO': return 'Solo';
      case 'PRO': return 'Pro';
      case 'TEAM': return 'Team';
      case 'BUSINESS': return 'Business';
      default: return 'Free';
    }
  }
}
