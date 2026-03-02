/// 플랜 선택 페이지 (새 창용)
/// 홈 화면의 플랜 카드 클릭 시 새 창으로 표시

import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/main.dart';
import 'package:window_manager/window_manager.dart';

import '../../common/widgets/window_buttons.dart';

/// 플랜 정보 모델
class PlanInfo {
  final String id;
  final String name;
  final String description;
  final String licenseInfo;
  final List<String> features;
  final int originalPrice;
  final int discountedPrice;
  final int discountPercent;

  const PlanInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.licenseInfo,
    required this.features,
    required this.originalPrice,
    required this.discountedPrice,
    required this.discountPercent,
  });
}

/// 플랜 데이터
const List<PlanInfo> _planList = [
  PlanInfo(
    id: 'solo',
    name: 'Solo',
    description: '1인 회사를 위한 기능 세트입니다.',
    licenseInfo: '1명의 라이선스 사용자, 1개 연결 포함',
    features: [
      '연결 가능한 등록된 기기 3대',
      '최대 100개의 관리 기기(무인 액세스)',
      '연결할 수 있는 기기 수 무제한(대화형 액세스)',
      '프리랜서 맞춤형 기능 세트',
      '모바일 장치 지원',
    ],
    originalPrice: 20000,
    discountedPrice: 16000,
    discountPercent: 20,
  ),
  PlanInfo(
    id: 'basic',
    name: '기본',
    description: '소규모 팀을 위한 기본 플랜입니다.',
    licenseInfo: '3명의 라이선스 사용자, 3개 연결 포함',
    features: [
      '연결 가능한 등록된 기기 10대',
      '최대 300개의 관리 기기(무인 액세스)',
      '연결할 수 있는 기기 수 무제한(대화형 액세스)',
      '팀 협업 기능',
      '모바일 장치 지원',
    ],
    originalPrice: 50000,
    discountedPrice: 40000,
    discountPercent: 20,
  ),
  PlanInfo(
    id: 'advanced',
    name: 'Advanced',
    description: '성장하는 비즈니스를 위한 플랜입니다.',
    licenseInfo: '10명의 라이선스 사용자, 10개 연결 포함',
    features: [
      '연결 가능한 등록된 기기 50대',
      '최대 1000개의 관리 기기(무인 액세스)',
      '연결할 수 있는 기기 수 무제한(대화형 액세스)',
      '고급 관리 기능',
      '우선 지원',
    ],
    originalPrice: 150000,
    discountedPrice: 120000,
    discountPercent: 20,
  ),
  PlanInfo(
    id: 'ultimate',
    name: 'Ultimate',
    description: '대규모 조직을 위한 엔터프라이즈 플랜입니다.',
    licenseInfo: '무제한 라이선스 사용자, 무제한 연결',
    features: [
      '연결 가능한 등록된 기기 무제한',
      '무제한 관리 기기(무인 액세스)',
      '연결할 수 있는 기기 수 무제한(대화형 액세스)',
      '전용 지원 담당자',
      'SLA 보장',
    ],
    originalPrice: 500000,
    discountedPrice: 400000,
    discountPercent: 20,
  ),
];

/// 테마 색상
const Color _primaryColor = Color(0xFF8B5CF6);
const Color _backgroundColor = Color(0xFFF8FAFC);
const Color _cardColor = Colors.white;
const Color _textPrimary = Color(0xFF1E293B);
const Color _textSecondary = Color(0xFF64748B);
const Color _dividerColor = Color(0xFFE2E8F0);

class PlanSelectionPage extends StatefulWidget {
  const PlanSelectionPage({Key? key}) : super(key: key);

  @override
  State<PlanSelectionPage> createState() => _PlanSelectionPageState();
}

class _PlanSelectionPageState extends State<PlanSelectionPage> {
  final RxInt _selectedPlanIndex = 0.obs;
  final String _currentPlan = 'Solo plan'; // 현재 사용 중인 플랜

  // 결제 완료 여부
  final RxBool _isPurchased = false.obs;

  @override
  Widget build(BuildContext context) {
    return Obx(() => _isPurchased.value
        ? _buildPurchaseCompletedView()
        : _buildPlanSelectionView());
  }

  Widget _buildPlanSelectionView() {
    return Column(
      children: [
        // 타이틀바
        _buildTitleBar(),
        // 컨텐츠
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더
                Row(
                  children: [
                    SvgPicture.asset(
                      'assets/icons/logo.svg',
                      width: 32,
                      height: 32,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          translate('Select Plan'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          translate('Choose the best plan for your team'),
                          style: const TextStyle(
                            fontSize: 13,
                            color: _textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // 플랜 탭
                Container(
                  decoration: BoxDecoration(
                    color: _backgroundColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Obx(() => Row(
                        children: List.generate(_planList.length, (index) {
                          final isSelected = _selectedPlanIndex.value == index;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => _selectedPlanIndex.value = index,
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? _primaryColor
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Center(
                                  child: Text(
                                    _planList[index].name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: isSelected
                                          ? Colors.white
                                          : _textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      )),
                ),
                const SizedBox(height: 24),
                // 플랜 상세 카드
                Obx(() =>
                    _buildPlanDetailCard(_planList[_selectedPlanIndex.value])),
                const SizedBox(height: 24),
                // 결제 및 환불 정책 링크
                InkWell(
                  onTap: () {
                    // TODO: 결제 및 환불 정책 페이지로 이동
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.asset(
                        'assets/icons/arrow-right.svg',
                        width: 14,
                        height: 14,
                        colorFilter: const ColorFilter.mode(
                          _textSecondary,
                          BlendMode.srcIn,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        translate('Payment and Refund Policy'),
                        style: const TextStyle(
                          fontSize: 13,
                          color: _textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 타이틀바
  Widget _buildTitleBar() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (details) {
        startWindowDragging(kWindowId == null);
      },
      onDoubleTap: () async {
        await toggleWindowMaximize(kWindowId == null);
      },
      child: Container(
        height: 44,
        color: Colors.white,
        child: Row(
          children: [
            const Expanded(child: SizedBox()),
            // 창 버튼
            WindowControlButtons(
              isMainWindow: kWindowId == null,
              theme: WindowButtonTheme.light,
              onClose: () async {
                if (kWindowId != null) {
                  await WindowController.fromWindowId(kWindowId!).close();
                } else {
                  exit(0);
                }
                return false;
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 플랜 상세 카드
  Widget _buildPlanDetailCard(PlanInfo plan) {
    final isCurrentPlan = _currentPlan.toLowerCase().contains(plan.id);

    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 좌측: 플랜 정보
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: _primaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    plan.description,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    plan.licenseInfo,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 기능 목록
                  ...plan.features.map((feature) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '•  ',
                              style: TextStyle(
                                fontSize: 13,
                                color: _textSecondary,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                feature,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),
          // 구분선
          Container(
            width: 1,
            height: 280,
            color: _dividerColor,
          ),
          // 우측: 가격 및 구매 버튼
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 원가
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${_formatPrice(plan.originalPrice)}원',
                        style: const TextStyle(
                          fontSize: 16,
                          color: _textSecondary,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const Text(
                        '/월',
                        style: TextStyle(
                          fontSize: 12,
                          color: _textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: _primaryColor),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${plan.discountPercent}% ${translate("Discount")}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: _primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 할인가
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${_formatPrice(plan.discountedPrice)}원',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 4),
                        child: Text(
                          '/월',
                          style: TextStyle(
                            fontSize: 14,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    translate('VAT may apply'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: _textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 구매 버튼
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isCurrentPlan
                          ? null
                          : () {
                              // TODO: 토스 페이먼츠 결제 처리
                              _isPurchased.value = true;
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isCurrentPlan
                            ? _primaryColor.withValues(alpha: 0.3)
                            : _primaryColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            _primaryColor.withValues(alpha: 0.3),
                        disabledForegroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        isCurrentPlan
                            ? translate('Current plan in use')
                            : translate('Purchase'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 결제 완료 화면
  Widget _buildPurchaseCompletedView() {
    return Column(
      children: [
        // 타이틀바
        _buildTitleBar(),
        // 컨텐츠
        Expanded(
          child: Center(
            child: Container(
              width: 400,
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 체크 아이콘
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: _primaryColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      size: 50,
                      color: _primaryColor,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 완료 메시지
                  Text(
                    translate('Plan payment completed'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: _primaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    translate('Start remote computing in an upgraded environment'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: _textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // 메인화면 돌아가기 버튼
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        // 창 닫기
                        if (kWindowId != null) {
                          await WindowController.fromWindowId(kWindowId!)
                              .close();
                        } else {
                          exit(0);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor.withValues(alpha: 0.3),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        translate('Return to main screen'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 가격 포맷팅 (천 단위 콤마)
  String _formatPrice(int price) {
    return price.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
  }
}
