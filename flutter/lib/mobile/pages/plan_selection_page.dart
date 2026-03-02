/// 모바일 플랜 선택 페이지
/// 세로 스크롤 리스트 형태로 플랜 카드 표시

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/api/auth_service.dart';
import 'package:flutter_hbb/common/api/payment_service.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'mobile_payment_webview_page.dart';

/// 플랜 정보 모델
class MobilePlanInfo {
  final String id;
  final String name;
  final String targetKey; // 대상 (예: 개인 사용자)
  final String targetDescKey; // 대상 설명
  final String targetDetailDescKey; // 대상 상세 설명
  final String featuresKey; // 기능 목록
  final int price; // KRW 가격
  final double usdPrice; // USD 가격
  final bool isPopular; // 인기 플랜 여부

  const MobilePlanInfo({
    required this.id,
    required this.name,
    required this.targetKey,
    required this.targetDescKey,
    required this.targetDetailDescKey,
    required this.featuresKey,
    required this.price,
    required this.usdPrice,
    this.isPopular = false,
  });
}

/// 플랜 데이터
const List<MobilePlanInfo> _planList = [
  MobilePlanInfo(
    id: 'SOLO_PLAN',
    name: 'Solo',
    targetKey: 'plan_solo_target',
    targetDescKey: 'plan_solo_target_desc',
    targetDetailDescKey: 'plan_solo_target_detail_desc',
    featuresKey: 'plan_solo_features',
    price: 19000,
    usdPrice: 14,
  ),
  MobilePlanInfo(
    id: 'PRO_PLAN',
    name: 'Pro',
    targetKey: 'plan_pro_target',
    targetDescKey: 'plan_pro_target_desc',
    targetDetailDescKey: 'plan_pro_target_detail_desc',
    featuresKey: 'plan_pro_features',
    price: 35000,
    usdPrice: 25,
  ),
  MobilePlanInfo(
    id: 'TEAM_PLAN',
    name: 'Team',
    targetKey: 'plan_team_target',
    targetDescKey: 'plan_team_target_desc',
    targetDetailDescKey: 'plan_team_target_detail_desc',
    featuresKey: 'plan_team_features',
    price: 99000,
    usdPrice: 70,
    isPopular: true,
  ),
  MobilePlanInfo(
    id: 'BUSINESS_PLAN',
    name: 'Business',
    targetKey: 'plan_business_target',
    targetDescKey: 'plan_business_target_desc',
    targetDetailDescKey: 'plan_business_target_detail_desc',
    featuresKey: 'plan_business_features',
    price: 199000,
    usdPrice: 140,
  ),
];

/// 결제 제공자 타입
enum MobilePaymentProvider {
  welcome, // 한국 (토스페이먼츠/Welcome)
  paypal, // 해외 (PayPal)
  paddle, // 해외 (Paddle)
}

/// 결제 데이터 (URL 또는 HTML)
class MobilePaymentData {
  final String? url;
  final String? htmlContent;
  final String? orderId; // 결제 시도 카운터용 (PayPal: subscriptionId, Paddle: orderId 등)

  MobilePaymentData({this.url, this.htmlContent, this.orderId});

  bool get isHtml => htmlContent != null && htmlContent!.isNotEmpty;
  bool get isUrl => url != null && url!.isNotEmpty;
  bool get isValid => isHtml || isUrl;
}

class MobilePlanSelectionPage extends StatefulWidget {
  const MobilePlanSelectionPage({Key? key}) : super(key: key);

  @override
  State<MobilePlanSelectionPage> createState() =>
      _MobilePlanSelectionPageState();
}

class _MobilePlanSelectionPageState extends State<MobilePlanSelectionPage> {
  // 지역 확인 상태
  final RxBool _isKorea = false.obs;
  final RxBool _isCheckingRegion = true.obs;
  final RxBool _isProcessing = false.obs;

  // 각 카드 펼침 상태
  final RxList<bool> _expandedStates = <bool>[].obs;

  // API에서 로드된 가격 (productCode -> 가격)
  final RxMap<String, int> _apiKrwPrices = <String, int>{}.obs;
  final RxMap<String, double> _apiUsdPrices = <String, double>{}.obs;

  // 테마 색상
  static const Color _primaryColor = Color(0xFF5F71FF);
  static const Color _planNameColor = Color(0xFF5F71FF);
  static const Color _targetColor = Color(0xFF454447);
  static const Color _featureTextColor = Color(0xFF646368);
  static const Color _priceColor = Color(0xFF1A191C);
  static const Color _perMonthColor = Color(0xFF646368);
  static const Color _recommendBgColor = Color(0xFFEFF1FF); // 추천 대상 배경색
  static const Color _featuresBgColor = Color(0xFFF7F7F7); // 혜택 목록 배경색
  static const Color _cardBgColor = Color(0xFFFEFEFE);
  static const Color _viewDetailColor = Color(0xFF454447);
  static const Color _buttonTextColor = Color(0xFFFEFEFE);
  static const Color _checkIconColor = Color(0xFF5F71FF);
  static const Color _cardBorder = Color(0xFFDEDEE2); // 카드 보더 색상
  static const Color _cardShadow = Color(0x1A000000); // 그림자 색상 10%

  @override
  void initState() {
    super.initState();
    // 각 플랜의 펼침 상태 초기화 (모두 접힘)
    _expandedStates.value = List.generate(_planList.length, (_) => false);
    _checkRegion();
    _loadPlanPrices();
  }

  /// API에서 플랜 가격 로드
  Future<void> _loadPlanPrices() async {
    if (!isPaymentServiceInitialized()) return;
    try {
      final paymentService = getPaymentService();
      final response = await paymentService.getPlanList();
      if (response.success && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final List<dynamic> products = data['result'] ?? [];
        for (final product in products) {
          final productCode = product['productCode'] as String?;
          final amount = product['amount'] as int?;
          final usdAmount = (product['usdAmount'] as num?)?.toDouble();
          if (productCode != null && amount != null && usdAmount != null) {
            _apiKrwPrices[productCode] = amount;
            _apiUsdPrices[productCode] = usdAmount;
          }
        }
        debugPrint('[MobilePlanSelection] Plan prices loaded from API: $_apiKrwPrices');
      }
    } catch (e) {
      debugPrint('[MobilePlanSelection] loadPlanPrices error: $e');
    }
  }

  /// 플랜 KRW 가격 가져오기 (API 우선, 없으면 기본값)
  int _getKrwPrice(MobilePlanInfo plan) {
    return _apiKrwPrices[plan.id] ?? plan.price;
  }

  /// 플랜 USD 가격 가져오기 (API 우선, 없으면 기본값)
  double _getUsdPrice(MobilePlanInfo plan) {
    return _apiUsdPrices[plan.id] ?? plan.usdPrice;
  }

  /// 지역 확인 (한국 여부)
  Future<void> _checkRegion() async {
    if (!isAuthServiceInitialized()) {
      _isCheckingRegion.value = false;
      return;
    }
    try {
      final authService = getAuthService();
      _isKorea.value = await authService.checkIsKorea();
      debugPrint('[MobilePlanSelection] isKorea: ${_isKorea.value}');
    } catch (e) {
      debugPrint('[MobilePlanSelection] checkRegion error: $e');
      _isKorea.value = false;
    } finally {
      _isCheckingRegion.value = false;
    }
  }

  /// 현재 플랜 인덱스 (API planType 기준)
  /// FREE=0, SOLO=1, PRO=2, TEAM=3, BUSINESS=4
  int get _currentPlanIndex {
    final planType = gFFI.userModel.planType.value;
    switch (planType.toUpperCase()) {
      case 'SOLO':
        return 1;
      case 'PRO':
        return 2;
      case 'TEAM':
        return 3;
      case 'BUSINESS':
        return 4;
      default:
        return 0; // FREE
    }
  }

  /// 현재 플랜인지 plan.id로 비교
  bool _isCurrentPlanById(String planId) {
    final planType = gFFI.userModel.planType.value.toUpperCase();
    switch (planId) {
      case 'SOLO_PLAN':
        return planType == 'SOLO';
      case 'PRO_PLAN':
        return planType == 'PRO';
      case 'TEAM_PLAN':
        return planType == 'TEAM';
      case 'BUSINESS_PLAN':
        return planType == 'BUSINESS';
      default:
        return false;
    }
  }

  /// 플랜이 현재 플랜보다 낮은 등급인지 확인
  bool _isLowerPlan(String planId) {
    final currentIdx = _currentPlanIndex;
    int planIdx;
    switch (planId) {
      case 'SOLO_PLAN':
        planIdx = 1;
        break;
      case 'PRO_PLAN':
        planIdx = 2;
        break;
      case 'TEAM_PLAN':
        planIdx = 3;
        break;
      case 'BUSINESS_PLAN':
        planIdx = 4;
        break;
      default:
        planIdx = 0;
    }
    return planIdx < currentIdx;
  }

  /// 가격 포맷 (천 단위 콤마)
  String _formatPrice(int price) {
    final str = price.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(str[i]);
    }
    return buffer.toString();
  }

  /// 플랜 가격 표시 (지역별 - 한국: KRW, 해외: USD)
  String _getPlanPriceDisplay(MobilePlanInfo plan) {
    if (_isKorea.value) {
      return '${_formatPrice(_getKrwPrice(plan))}${translate("Won")}';
    } else {
      return '\$${_getUsdPrice(plan).toStringAsFixed(0)}';
    }
  }

  /// 플랜 가격만 (통화 기호 없이)
  String _getPlanPrice(MobilePlanInfo plan) {
    if (_isKorea.value) {
      return _formatPrice(_getKrwPrice(plan));
    } else {
      return _getUsdPrice(plan).toStringAsFixed(0);
    }
  }

  /// 통화 단위
  String _getCurrencyUnit() {
    return _isKorea.value ? translate("Won") : '';
  }

  /// 통화 기호 (앞에 붙는)
  String _getCurrencySymbol() {
    return _isKorea.value ? '' : '\$';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: _targetColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          translate('Plan Selection'),
          style: const TextStyle(
            color: _targetColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: Obx(() {
        if (_isCheckingRegion.value) {
          return const Center(child: CircularProgressIndicator());
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 결제 및 환불 정책 버튼
              _buildRefundPolicyButton(),
              const SizedBox(height: 20),

              // 헤더 텍스트
              Text(
                translate('Choose the best plan for your team'),
                style: const TextStyle(
                  fontSize: 16,
                  color: _featureTextColor,
                ),
              ),
              const SizedBox(height: 24),

              // 플랜 카드 리스트 (세로)
              ...List.generate(_planList.length, (index) {
                final plan = _planList[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildPlanCard(plan, index),
                );
              }),
            ],
          ),
        );
      }),
    );
  }

  /// 결제 및 환불 정책 버튼
  Widget _buildRefundPolicyButton() {
    return GestureDetector(
      onTap: () => launchUrlString('https://onedesk.co.kr/refund'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: _cardBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_outward, size: 16, color: _featureTextColor),
            const SizedBox(width: 6),
            Text(
              translate('Payment and Refund Policy'),
              style: const TextStyle(
                fontSize: 14,
                color: _featureTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 플랜 카드 위젯
  Widget _buildPlanCard(MobilePlanInfo plan, int index) {
    final isCurrentPlan = _isCurrentPlanById(plan.id);
    final isLowerPlan = _isLowerPlan(plan.id);
    final isDisabled = isCurrentPlan || isLowerPlan;

    return Obx(() {
      final isExpanded = _expandedStates[index];

      return Container(
        decoration: BoxDecoration(
          color: _cardBgColor,
          borderRadius: BorderRadius.circular(16), // 코너 둥글기 16px
          border: Border.all(
            // 팀플랜(인기 플랜): #5F71FF, 현재 플랜: #5F71FF, 기본: #DEDEE2
            color: plan.isPopular || isCurrentPlan ? _primaryColor : _cardBorder,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: _cardShadow, // 그림자 #0000001A 10%
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 인기 플랜 배너 (Team 플랜)
            if (plan.isPopular) _buildPopularBanner(),

            // 플랜 헤더
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 플랜명
                  Text(
                    plan.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _planNameColor,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 대상 (개인 사용자 등)
                  Text(
                    translate(plan.targetKey),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _targetColor,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // 대상 설명
                  Text(
                    translate(plan.targetDescKey),
                    style: const TextStyle(
                      fontSize: 14,
                      color: _featureTextColor, // #646368
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 가격
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _getPlanPriceDisplay(plan),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _priceColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '/${translate("Month")}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: _perMonthColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 추천 대상 섹션 (배경색 #EFF1FF)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _recommendBgColor, // #EFF1FF
                borderRadius: BorderRadius.circular(8), // 코너 둥글기 8px
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 추천 대상 제목
                  Text(
                    translate('Recommand Target'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _targetColor,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 추천 대상 목록 (plan_solo_target_detail_desc)
                  ...translate(plan.targetDetailDescKey)
                      .split('\n')
                      .map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SvgPicture.asset(
                            'assets/icons/plan-desc-check.svg',
                            width: 16,
                            height: 16,
                            colorFilter: const ColorFilter.mode(
                              _checkIconColor,
                              BlendMode.srcIn,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.trim(),
                              style: const TextStyle(
                                fontSize: 14,
                                color: _featureTextColor,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),

            // 혜택 자세히 보기 버튼 (두 섹션 사이에 위치)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: GestureDetector(
                onTap: () {
                  _expandedStates[index] = !isExpanded;
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      translate('View Details Benefits'),
                      style: const TextStyle(
                        fontSize: 14,
                        color: _viewDetailColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    SvgPicture.asset(
                      isExpanded
                          ? 'assets/icons/plan-show-arrow-up.svg'
                          : 'assets/icons/plan-show-arrow-down.svg',
                      width: 16,
                      height: 16,
                      colorFilter: const ColorFilter.mode(
                        _viewDetailColor,
                        BlendMode.srcIn,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 펼쳐진 경우 혜택 목록 섹션
            if (isExpanded) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 기능 서브타이틀
                    Text(
                      translate('Function'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _targetColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 기능 목록 (plan_solo_features)
                    ...translate(plan.featuresKey).split('\n').map((feature) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SvgPicture.asset(
                              'assets/icons/plan-desc-check.svg',
                              width: 16,
                              height: 16,
                              colorFilter: const ColorFilter.mode(
                                _checkIconColor,
                                BlendMode.srcIn,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                feature.trim(),
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: _featureTextColor,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // 시작하기 버튼
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: _buildStartButton(plan, isDisabled),
            ),
          ],
        ),
      );
    });
  }

  /// 인기 플랜 배너
  Widget _buildPopularBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        color: _primaryColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(15), // 카드 코너 16px - 보더 1px
          topRight: Radius.circular(15),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            translate('Most Popular Plans'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _buttonTextColor,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            '\u2728', // sparkle emoji
            style: TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  /// 시작하기 버튼
  Widget _buildStartButton(MobilePlanInfo plan, bool isDisabled) {
    if (isDisabled) {
      final isCurrentPlan = _isCurrentPlanById(plan.id);
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          isCurrentPlan
              ? translate('Current plan in use')
              : translate('Lower plan'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _featureTextColor,
          ),
        ),
      );
    }

    return Obx(() {
      if (_isProcessing.value) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: _primaryColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
          ),
        );
      }

      return GestureDetector(
        onTap: () => _showPaymentOptions(plan),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: _primaryColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            translate('Start Plan'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _buttonTextColor,
            ),
          ),
        ),
      );
    });
  }

  /// 결제 옵션 선택 다이얼로그
  void _showPaymentOptions(MobilePlanInfo plan) {
    if (_isKorea.value) {
      // 한국: 기존 결제 옵션 (토스페이먼츠 + 해외)
      _showKoreaPaymentOptions(plan);
    } else {
      // 해외: PayPal/Paddle 선택 다이얼로그
      _showGlobalPaymentDialog(plan);
    }
  }

  /// 한국 결제 확인 다이얼로그 (Welcome용)
  void _showKoreaPaymentOptions(MobilePlanInfo plan) {
    final isChecked = false.obs;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더
              Text(
                translate('payment_confirm'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _targetColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                translate('payment_info_check'),
                style: const TextStyle(
                  fontSize: 14,
                  color: _featureTextColor,
                ),
              ),
              const SizedBox(height: 20),

              // 상품 정보 카드
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 플랜명
                    Text(
                      plan.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _targetColor,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 총 결제 금액 (오른쪽 정렬)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            translate('total_payment'),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: _primaryColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _getCurrencySymbol(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: _primaryColor,
                            ),
                          ),
                          Text(
                            _getPlanPrice(plan),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: _primaryColor,
                            ),
                          ),
                          Text(
                            _getCurrencyUnit(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: _primaryColor,
                            ),
                          ),
                          Text(
                            '/${translate("Month")}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: _featureTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),

                    // VAT 안내
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        translate('vat_excluded'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: _featureTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 약관 동의
              Obx(() => GestureDetector(
                    onTap: () => isChecked.value = !isChecked.value,
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: isChecked.value
                                ? _primaryColor
                                : Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isChecked.value
                                  ? _primaryColor
                                  : _cardBorder,
                              width: 2,
                            ),
                          ),
                          child: isChecked.value
                              ? const Icon(Icons.check,
                                  size: 16, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: _buildPaymentAgreeText()),
                      ],
                    ),
                  )),
              const SizedBox(height: 24),

              // 버튼들
              Row(
                children: [
                  // 취소 버튼
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _cardBorder),
                        ),
                        child: Center(
                          child: Text(
                            translate('Cancel'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _targetColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 확인 버튼
                  Expanded(
                    child: Obx(() => GestureDetector(
                          onTap: isChecked.value
                              ? () {
                                  Navigator.pop(context);
                                  _processPayment(
                                      plan.id, MobilePaymentProvider.welcome);
                                }
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: isChecked.value
                                  ? _primaryColor
                                  : const Color(0xFFE5E5E5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                translate('OK'),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isChecked.value
                                      ? Colors.white
                                      : const Color(0xFF999999),
                                ),
                              ),
                            ),
                          ),
                        )),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// 해외 결제 다이얼로그 (PayPal/Paddle 선택)
  void _showGlobalPaymentDialog(MobilePlanInfo plan) {
    final isChecked = false.obs;
    final selectedProvider = Rxn<MobilePaymentProvider>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더
              Text(
                translate('plan_payment'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _targetColor,
                ),
              ),
              const SizedBox(height: 20),

              // 결제 수단 섹션
              Text(
                translate('payment_method'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _targetColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                translate('payment_method_select'),
                style: const TextStyle(
                  fontSize: 14,
                  color: _featureTextColor,
                ),
              ),
              const SizedBox(height: 16),

              // PayPal / Paddle 버튼
              Obx(() => Row(
                    children: [
                      // PayPal 버튼
                      Expanded(
                        child: GestureDetector(
                          onTap: () => selectedProvider.value =
                              MobilePaymentProvider.paypal,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: selectedProvider.value ==
                                      MobilePaymentProvider.paypal
                                  ? const Color(0xFFEFF1FF)
                                  : const Color(0xFFF7F7F7),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selectedProvider.value ==
                                        MobilePaymentProvider.paypal
                                    ? _primaryColor
                                    : const Color(0xFFF7F7F7),
                                width: selectedProvider.value ==
                                        MobilePaymentProvider.paypal
                                    ? 2
                                    : 1,
                              ),
                            ),
                            child: Center(
                              child: Image.asset(
                                'assets/icons/paypal.png',
                                height: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Paddle 버튼
                      Expanded(
                        child: GestureDetector(
                          onTap: () => selectedProvider.value =
                              MobilePaymentProvider.paddle,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: selectedProvider.value ==
                                      MobilePaymentProvider.paddle
                                  ? const Color(0xFFEFF1FF)
                                  : const Color(0xFFF7F7F7),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selectedProvider.value ==
                                        MobilePaymentProvider.paddle
                                    ? _primaryColor
                                    : const Color(0xFFF7F7F7),
                                width: selectedProvider.value ==
                                        MobilePaymentProvider.paddle
                                    ? 2
                                    : 1,
                              ),
                            ),
                            child: Center(
                              child: Image.asset(
                                'assets/icons/paddle.png',
                                height: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )),
              const SizedBox(height: 24),

              // 주문 상품 섹션
              Text(
                translate('order_summary_title'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _targetColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                translate('payment_info_check'),
                style: const TextStyle(
                  fontSize: 14,
                  color: _featureTextColor,
                ),
              ),
              const SizedBox(height: 16),

              // 상품 정보 카드
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 플랜명
                    Text(
                      plan.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _targetColor,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 총 결제 금액 (오른쪽 정렬)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            translate('total_payment'),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: _primaryColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _getCurrencySymbol(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: _primaryColor,
                            ),
                          ),
                          Text(
                            _getPlanPrice(plan),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: _primaryColor,
                            ),
                          ),
                          Text(
                            _getCurrencyUnit(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: _primaryColor,
                            ),
                          ),
                          Text(
                            '/${translate("Month")}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: _featureTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),

                    // VAT 안내
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        translate('vat_excluded'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: _featureTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 약관 동의
              Obx(() => GestureDetector(
                    onTap: () => isChecked.value = !isChecked.value,
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: isChecked.value
                                ? _primaryColor
                                : Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isChecked.value
                                  ? _primaryColor
                                  : _cardBorder,
                              width: 2,
                            ),
                          ),
                          child: isChecked.value
                              ? const Icon(Icons.check,
                                  size: 16, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: _buildPaymentAgreeText()),
                      ],
                    ),
                  )),
              const SizedBox(height: 24),

              // 버튼들
              Row(
                children: [
                  // 취소 버튼
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _cardBorder),
                        ),
                        child: Center(
                          child: Text(
                            translate('Cancel'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _targetColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 확인 버튼
                  Expanded(
                    child: Obx(() => GestureDetector(
                          onTap: (isChecked.value &&
                                  selectedProvider.value != null)
                              ? () {
                                  Navigator.pop(context);
                                  _processPayment(
                                      plan.id, selectedProvider.value!);
                                }
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: (isChecked.value &&
                                      selectedProvider.value != null)
                                  ? _primaryColor
                                  : const Color(0xFFE5E5E5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                translate('OK'),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: (isChecked.value &&
                                          selectedProvider.value != null)
                                      ? Colors.white
                                      : const Color(0xFF999999),
                                ),
                              ),
                            ),
                          ),
                        )),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// 결제 약관 동의 텍스트 빌드 (링크 포함)
  Widget _buildPaymentAgreeText() {
    const textColor = Color(0xFF454447);
    const linkColor = Color(0xFF5F71FF);

    final fullText = translate('payment_agree_text');
    final startIndex = fullText.indexOf('<');
    final endIndex = fullText.indexOf('>');

    if (startIndex == -1 || endIndex == -1 || startIndex >= endIndex) {
      return Text(
        fullText,
        style: const TextStyle(fontSize: 14, color: textColor),
      );
    }

    final beforeLink = fullText.substring(0, startIndex);
    final linkText = fullText.substring(startIndex + 1, endIndex);
    final afterLink = fullText.substring(endIndex + 1);

    return Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 14, color: textColor),
        children: [
          if (beforeLink.isNotEmpty) TextSpan(text: beforeLink),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () => launchUrlString('https://onedesk.co.kr/refund'),
              child: Text(
                linkText,
                style: const TextStyle(
                  fontSize: 14,
                  color: linkColor,
                ),
              ),
            ),
          ),
          if (afterLink.isNotEmpty) TextSpan(text: afterLink),
        ],
      ),
    );
  }

  /// 결제 처리
  Future<void> _processPayment(
      String planId, MobilePaymentProvider provider) async {
    _isProcessing.value = true;

    try {
      final email = gFFI.userModel.userName.value;
      if (email.isEmpty) {
        _showErrorDialog(translate('Please login first'));
        return;
      }

      MobilePaymentData? paymentData;
      String providerName = '';
      String providerCode = ''; // 결제 시도 카운터용

      switch (provider) {
        case MobilePaymentProvider.welcome:
          paymentData = await _startWelcomePayment(planId, email);
          providerName = translate('Toss Payments (Korea)');
          providerCode = 'WELCOME_BILLING';
          break;
        case MobilePaymentProvider.paypal:
          paymentData = await _startPaypalPayment(planId, email);
          providerName = 'PayPal';
          providerCode = 'PAYPAL_BILLING';
          break;
        case MobilePaymentProvider.paddle:
          paymentData = await _startPaddlePayment(planId, email);
          providerName = 'Paddle';
          providerCode = 'PADDLE_BILLING';
          break;
      }

      // 결제 시도 카운터 (API 호출 후, WebView 열기 전)
      if (isAuthServiceInitialized() && paymentData != null) {
        try {
          final authService = getAuthService();
          // orderId: PayPal=subscriptionId, Welcome=P_OID, Paddle=orderId
          final orderId = paymentData.orderId ?? planId;
          await authService.setCountPayClick(providerCode, planId, orderId);
          debugPrint('[MobilePlanSelection] Payment attempt counted: $providerCode, $planId, $orderId');
        } catch (e) {
          debugPrint('[MobilePlanSelection] setCountPayClick error: $e');
        }
      }

      if (paymentData != null && paymentData.isValid) {
        // WebView 페이지로 이동
        final planName = _planList.firstWhere((p) => p.id == planId).name;

        final result = await Navigator.push<MobilePaymentResult>(
          context,
          MaterialPageRoute(
            builder: (context) => paymentData!.isHtml
                ? MobilePaymentWebViewPage.withHtml(
                    htmlContent: paymentData.htmlContent!,
                    planName: planName,
                    providerName: providerName,
                    orderId: paymentData.orderId,
                  )
                : MobilePaymentWebViewPage.withUrl(
                    url: paymentData.url!,
                    planName: planName,
                    providerName: providerName,
                    orderId: paymentData.orderId,
                  ),
          ),
        );

        // 결제 결과 처리
        _handlePaymentResult(result, planName);
      }
    } catch (e) {
      debugPrint('[MobilePlanSelection] Payment error: $e');
      _showErrorDialog(translate('Bad Request'));
    } finally {
      _isProcessing.value = false;
    }
  }

  /// 결제 결과 처리
  void _handlePaymentResult(MobilePaymentResult? result, String planName) {
    if (result == null) {
      // 사용자가 그냥 닫은 경우
      debugPrint('[MobilePlanSelection] Payment result: null (dismissed)');
      return;
    }

    switch (result) {
      case MobilePaymentResult.success:
        debugPrint('[MobilePlanSelection] Payment SUCCESS');
        _showSuccessDialog(planName);
        // 사용자 정보 새로고침
        gFFI.userModel.refreshCurrentUser();
        break;
      case MobilePaymentResult.cancel:
        debugPrint('[MobilePlanSelection] Payment CANCELLED');
        // 다이얼로그 없이 조용히 플랜 선택 페이지로 돌아감
        break;
      case MobilePaymentResult.fail:
        debugPrint('[MobilePlanSelection] Payment FAILED');
        _showErrorDialog(translate('Bad Request'));
        break;
    }
  }

  /// 성공 다이얼로그
  void _showSuccessDialog(String planName) {
    gFFI.dialogManager.show((setState, close, context) {
      return CustomAlertDialog(
        title: Text(
          translate('Payment Successful'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          '${translate('Your')} $planName ${translate('plan has been activated.')}',
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: dialogButton('OK', onPressed: () {
              close();
              Navigator.pop(context); // 플랜 선택 페이지 닫기
            }),
          ),
        ],
        onCancel: close,
      );
    });
  }

  /// Welcome 결제 시작 (HTML form 생성)
  Future<MobilePaymentData?> _startWelcomePayment(String planId, String email) async {
    // 테스트용: TEST_PLAN으로 변경
    const testPlanId = 'TEST_PLAN';
    debugPrint('[MobilePlanSelection] Welcome 결제 시작: $testPlanId (원래: $planId)');

    if (!isPaymentServiceInitialized()) {
      debugPrint('[MobilePlanSelection] PaymentService not initialized');
      return null;
    }

    try {
      final paymentService = getPaymentService();

      // 서버에서 Welcome 빌링 파라미터 발급
      final response = await paymentService.createWelcomeBilling(testPlanId);

      if (!response.success || response.data == null) {
        debugPrint('[MobilePlanSelection] Welcome billing failed: ${response.message}');
        return null;
      }

      final data = response.data!;
      final actionUrl = data['actionUrl'];

      if (actionUrl == null || actionUrl.toString().isEmpty) {
        debugPrint('[MobilePlanSelection] Welcome actionUrl not found');
        return null;
      }

      // fields 추출 (API 응답 구조: result.fields)
      final fields = data['fields'] as Map<String, dynamic>? ?? data;

      // orderId 추출 (Welcome: P_OID)
      final orderId = data['orderId'] ?? fields['P_OID'];

      // HTML form 생성 (로컬 서버 방식과 동일)
      final htmlContent = _buildWelcomeBillingHtml(actionUrl.toString(), fields);

      debugPrint('[MobilePlanSelection] Welcome payment HTML generated');
      debugPrint('[MobilePlanSelection] ActionUrl: $actionUrl, orderId: $orderId');

      return MobilePaymentData(htmlContent: htmlContent, orderId: orderId?.toString());
    } catch (e) {
      debugPrint('[MobilePlanSelection] Welcome payment error: $e');
      return null;
    }
  }

  /// Welcome 빌링 HTML form 생성
  String _buildWelcomeBillingHtml(String actionUrl, Map<String, dynamic> data) {
    // 필수 필드들
    final pMid = data['P_MID'] ?? '';
    final pOid = data['P_OID'] ?? '';
    final pAmt = data['P_AMT'] ?? '';
    final pUname = data['P_UNAME'] ?? '';
    final pTimestamp = data['P_TIMESTAMP'] ?? '';
    final pSignature = data['P_SIGNATURE'] ?? '';
    final pReserved = data['P_RESERVED'] ?? '';
    final pNextUrl = data['P_NEXT_URL'] ?? '';
    final pNotiUrl = data['P_NOTI_URL'] ?? '';
    final pGoodsNm = data['P_GOODS_NM'] ?? '';
    final pMname = data['P_MNAME'] ?? '';
    final pMobile = data['P_MOBILE'] ?? '';
    final pEmail = data['P_EMAIL'] ?? '';
    final pCharSet = data['P_CHARSET'] ?? 'utf8';

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>결제 처리 중...</title>
  <style>
    body {
      display: flex;
      justify-content: center;
      align-items: center;
      height: 100vh;
      margin: 0;
      background-color: #f5f5f5;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    }
    .loading {
      text-align: center;
    }
    .spinner {
      width: 50px;
      height: 50px;
      border: 3px solid #e0e0e0;
      border-top: 3px solid #5F71FF;
      border-radius: 50%;
      animation: spin 1s linear infinite;
      margin: 0 auto 20px;
    }
    @keyframes spin {
      0% { transform: rotate(0deg); }
      100% { transform: rotate(360deg); }
    }
    .text {
      color: #666;
      font-size: 16px;
    }
  </style>
</head>
<body>
  <div class="loading">
    <div class="spinner"></div>
    <p class="text">결제 페이지로 이동 중...</p>
  </div>

  <form id="billingForm" method="POST" action="$actionUrl">
    <input type="hidden" name="P_MID" value="$pMid" />
    <input type="hidden" name="P_OID" value="$pOid" />
    <input type="hidden" name="P_AMT" value="$pAmt" />
    <input type="hidden" name="P_UNAME" value="$pUname" />
    <input type="hidden" name="P_TIMESTAMP" value="$pTimestamp" />
    <input type="hidden" name="P_SIGNATURE" value="$pSignature" />
    <input type="hidden" name="P_RESERVED" value="$pReserved" />
    <input type="hidden" name="P_NEXT_URL" value="$pNextUrl" />
    <input type="hidden" name="P_NOTI_URL" value="$pNotiUrl" />
    <input type="hidden" name="P_GOODS_NM" value="$pGoodsNm" />
    <input type="hidden" name="P_MNAME" value="$pMname" />
    <input type="hidden" name="P_MOBILE" value="$pMobile" />
    <input type="hidden" name="P_EMAIL" value="$pEmail" />
    <input type="hidden" name="P_CHARSET" value="$pCharSet" />
  </form>

  <script>
    // Welcome 결제 결과 메시지 리스너
    // Welcome이 postMessage로 결과를 보내면, 해당 결과에 맞는 localhost URL로 리다이렉트
    window.addEventListener('message', function(e) {
      console.log('[Welcome] Message received:', e.data);
      if (e.data && e.data.result === 'success') {
        window.location.href = 'http://localhost:57423/success';
      } else if (e.data && e.data.result === 'cancel') {
        window.location.href = 'http://localhost:57423/cancel';
      } else if (e.data && e.data.result === 'fail') {
        window.location.href = 'http://localhost:57423/fail';
      }
    });

    window.onload = function() {
      setTimeout(function() {
        document.getElementById('billingForm').submit();
      }, 500);
    };
  </script>
</body>
</html>
''';
  }

  /// PayPal 결제 시작 (구독 방식 - approvalUrl 우선, SDK 폴백)
  Future<MobilePaymentData?> _startPaypalPayment(String planId, String email) async {
    if (!isPaymentServiceInitialized()) {
      debugPrint('[MobilePlanSelection] PaymentService not initialized');
      return null;
    }

    try {
      final paymentService = getPaymentService();

      // PayPal 구독 생성 (서버에서 subscriptionId 발급)
      debugPrint('[MobilePlanSelection] Creating PayPal subscription: $planId');
      final response = await paymentService.createPayPalSubscription(planId);

      if (!response.success || response.data == null) {
        debugPrint('[MobilePlanSelection] PayPal subscription failed: ${response.message}');
        return null;
      }

      debugPrint('[MobilePlanSelection] PayPal response data: ${response.data}');

      // subscriptionId 추출
      final subscriptionId = response.data!['subscriptionId'] as String?;

      // approvalUrl 확인 (직접 리다이렉트 방식)
      final approvalUrl = response.data!['href'] ??
          response.data!['approvalUrl'] ??
          response.data!['approveUrl'];

      if (approvalUrl != null && approvalUrl.toString().isNotEmpty) {
        debugPrint('[MobilePlanSelection] PayPal approvalUrl found: $approvalUrl');
        // URL 방식으로 결제 페이지 열기
        return MobilePaymentData(url: approvalUrl.toString(), orderId: subscriptionId);
      }

      if (subscriptionId == null || subscriptionId.isEmpty) {
        debugPrint('[MobilePlanSelection] PayPal subscriptionId not found');
        return null;
      }

      debugPrint('[MobilePlanSelection] PayPal subscriptionId: $subscriptionId (SDK 방식 - WebView에서 제한적)');

      // SDK HTML 생성 (폴백, 일반적으로 WebView에서 작동 안 함)
      final htmlContent = _buildPayPalSubscriptionHtml(subscriptionId);
      return MobilePaymentData(htmlContent: htmlContent, orderId: subscriptionId);
    } catch (e) {
      debugPrint('[MobilePlanSelection] PayPal payment error: $e');
      return null;
    }
  }

  /// PayPal 구독 HTML 생성 (SDK 버튼 방식)
  String _buildPayPalSubscriptionHtml(String subscriptionId) {
    final escapedSubscriptionId = subscriptionId
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('"', '\\"');

    // sandbox: www.sandbox.paypal.com, live: www.paypal.com
    const paypalDomain = 'www.sandbox.paypal.com';

    return '''
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>PayPal 구독 결제</title>
    <style>
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 0;
            padding: 40px 20px;
            background: #f5f7fa;
            display: flex;
            justify-content: center;
            align-items: flex-start;
            min-height: 100vh;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 12px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.1);
            max-width: 450px;
            width: 100%;
            text-align: center;
        }
        h2 { margin: 0 0 8px 0; color: #333; font-size: 24px; }
        .subtitle { color: #666; margin-bottom: 24px; font-size: 14px; }
        .paypal-btn {
            display: block;
            width: 100%;
            padding: 16px 24px;
            background: #0070ba;
            color: white;
            border: none;
            border-radius: 8px;
            font-size: 18px;
            font-weight: 600;
            cursor: pointer;
            text-decoration: none;
            margin-bottom: 12px;
        }
        .paypal-btn:hover { background: #005ea6; }
        .paypal-btn:active { background: #004d8c; }
        .cancel-btn {
            display: block;
            width: 100%;
            padding: 12px 24px;
            background: #f0f0f0;
            color: #666;
            border: none;
            border-radius: 8px;
            font-size: 14px;
            cursor: pointer;
            text-decoration: none;
        }
        .info { color: #888; font-size: 12px; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h2>PayPal 결제</h2>
        <div class="subtitle">구독 결제를 진행합니다</div>

        <a href="https://$paypalDomain/webapps/billing/subscriptions?subscription_id=$escapedSubscriptionId" class="paypal-btn">
            PayPal로 결제하기
        </a>

        <a href="http://localhost:47423/cancel" class="cancel-btn">
            취소
        </a>

        <div class="info">
            Subscription ID: $escapedSubscriptionId
        </div>
    </div>
</body>
</html>
''';
  }

  /// Paddle 결제 시작 (구독)
  Future<MobilePaymentData?> _startPaddlePayment(String planId, String email) async {
    if (!isPaymentServiceInitialized()) {
      debugPrint('[MobilePlanSelection] PaymentService not initialized');
      return null;
    }

    try {
      final paymentService = getPaymentService();

      // Paddle 구독 체크아웃 생성
      final response = await paymentService.createPaddleSubCheckout(planId);

      if (!response.success || response.data == null) {
        debugPrint('[MobilePlanSelection] Paddle checkout failed: ${response.message}');
        return null;
      }

      // Paddle 체크아웃 URL 및 orderId 추출
      final data = response.data!;
      final checkoutUrl = data['checkoutUrl'] ?? data['checkout_url'] ?? data['url'];
      final orderId = data['ourOrderId'] ?? data['orderId'] ?? data['transactionId'];

      if (checkoutUrl == null || checkoutUrl.toString().isEmpty) {
        debugPrint('[MobilePlanSelection] Paddle checkoutUrl not found');
        return null;
      }

      debugPrint('[MobilePlanSelection] Paddle checkout URL: $checkoutUrl, orderId: $orderId');
      return MobilePaymentData(url: checkoutUrl.toString(), orderId: orderId?.toString());
    } catch (e) {
      debugPrint('[MobilePlanSelection] Paddle payment error: $e');
      return null;
    }
  }

  /// 에러 다이얼로그
  void _showErrorDialog(String message) {
    gFFI.dialogManager.show((setState, close, context) {
      return CustomAlertDialog(
        title: Text(
          translate('Error'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(message),
        actions: [
          SizedBox(
            width: double.infinity,
            child: dialogButton('OK', onPressed: close),
          ),
        ],
        onCancel: close,
      );
    });
  }
}

// ===== 기기 추가 결제 다이얼로그 (모바일 - 외부 호출용) =====

/// 가격 포맷팅 (천 단위 콤마) - top-level
String _mobileFormatPrice(int price) {
  final str = price.toString();
  final buffer = StringBuffer();
  for (int i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
    buffer.write(str[i]);
  }
  return buffer.toString();
}

/// 결제 약관 동의 텍스트 빌드 (모바일 top-level)
Widget _mobileAddonPaymentAgreeText() {
  const textColor = Color(0xFF454447);
  const linkColor = Color(0xFF5F71FF);

  final fullText = translate('payment_agree_text');
  final startIndex = fullText.indexOf('<');
  final endIndex = fullText.indexOf('>');

  if (startIndex == -1 || endIndex == -1 || startIndex >= endIndex) {
    return Text(fullText, style: const TextStyle(fontSize: 14, color: textColor));
  }

  final beforeLink = fullText.substring(0, startIndex);
  final linkText = fullText.substring(startIndex + 1, endIndex);
  final afterLink = fullText.substring(endIndex + 1);

  return Text.rich(
    TextSpan(
      style: const TextStyle(fontSize: 14, color: textColor),
      children: [
        if (beforeLink.isNotEmpty) TextSpan(text: beforeLink),
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () => launchUrlString('https://onedesk.co.kr/refund'),
            child: Text(linkText, style: const TextStyle(fontSize: 14, color: linkColor)),
          ),
        ),
        if (afterLink.isNotEmpty) TextSpan(text: afterLink),
      ],
    ),
  );
}

/// 수량 스테퍼 위젯
Widget _buildAddonStepper(RxInt count) {
  const textColor = Color(0xFF454447);
  const borderColor = Color(0xFFDEDEE2);

  return Obx(() => Row(
    children: [
      GestureDetector(
        onTap: () { if (count.value > 1) count.value--; },
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: const Center(child: Text('−', style: TextStyle(fontSize: 20, color: textColor))),
        ),
      ),
      Expanded(
        child: Container(
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Center(
            child: Text('${count.value}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
          ),
        ),
      ),
      GestureDetector(
        onTap: () => count.value++,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: const Center(child: Text('+', style: TextStyle(fontSize: 20, color: textColor))),
        ),
      ),
    ],
  ));
}

/// 모바일 기기 추가 결제 다이얼로그 표시 (외부에서 호출)
Future<void> showMobileAddonSessionDialog(BuildContext context) async {
  // 지역 확인
  bool isKorea = false;
  if (isAuthServiceInitialized()) {
    try {
      isKorea = await getAuthService().checkIsKorea();
    } catch (_) {}
  }

  // 가격 조회
  int krwUnitPrice = 1000;
  double usdUnitPrice = 1.0;
  if (isPaymentServiceInitialized()) {
    try {
      final response = await getPaymentService().getPlanList();
      if (response.success) {
        final products = response.extract('') as List<dynamic>?;
        if (products != null) {
          for (final product in products) {
            if (product['productCode'] == 'ADDON_SESSION') {
              krwUnitPrice = product['amount'] as int? ?? 1000;
              usdUnitPrice = (product['usdAmount'] as num?)?.toDouble() ?? 1.0;
              break;
            }
          }
        }
      }
    } catch (_) {}
  }

  if (!context.mounted) return;

  if (isKorea) {
    _showMobileAddonWelcomeDialog(context, krwUnitPrice);
  } else {
    _showMobileAddonGlobalDialog(context, usdUnitPrice);
  }
}

/// 모바일 기기 추가 - 한국 결제 다이얼로그
void _showMobileAddonWelcomeDialog(BuildContext context, int krwUnitPrice) {
  final isChecked = false.obs;
  final addonCount = 1.obs;

  const primaryColor = Color(0xFF5F71FF);
  const textColor = Color(0xFF454447);
  const featureTextColor = Color(0xFF646368);
  const cardBorder = Color(0xFFDEDEE2);

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              translate('Add number of session cconnections'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor),
            ),
            const SizedBox(height: 4),
            Text(
              translate('Add number of session cconnections Pre'),
              style: const TextStyle(fontSize: 14, color: featureTextColor),
            ),
            const SizedBox(height: 20),
            // 카드 영역
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    translate('Add number of session cconnections'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
                  ),
                  const SizedBox(height: 16),
                  _buildAddonStepper(addonCount),
                  const SizedBox(height: 16),
                  // 총 가격
                  Align(
                    alignment: Alignment.centerRight,
                    child: Obx(() => Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(translate('total_payment'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: primaryColor)),
                        const SizedBox(width: 4),
                        Text('${_mobileFormatPrice(krwUnitPrice * addonCount.value)}${translate("Won")}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: primaryColor)),
                        Text('/${translate("Month")}', style: const TextStyle(fontSize: 14, color: featureTextColor)),
                      ],
                    )),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(translate('vat_excluded'), style: const TextStyle(fontSize: 12, color: featureTextColor)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // 약관 동의
            Obx(() => GestureDetector(
              onTap: () => isChecked.value = !isChecked.value,
              child: Row(
                children: [
                  Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: isChecked.value ? primaryColor : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: isChecked.value ? primaryColor : cardBorder, width: 2),
                    ),
                    child: isChecked.value ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _mobileAddonPaymentAgreeText()),
                ],
              ),
            )),
            const SizedBox(height: 24),
            // 버튼
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Center(
                        child: Text(translate('Cancel'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Obx(() => GestureDetector(
                    onTap: isChecked.value ? () { Navigator.pop(context); /* TODO: Welcome 결제 시작 */ } : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: isChecked.value ? primaryColor : const Color(0xFFE5E5E5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(translate('OK'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isChecked.value ? Colors.white : const Color(0xFF999999))),
                      ),
                    ),
                  )),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

/// 모바일 기기 추가 - 해외 결제 다이얼로그
void _showMobileAddonGlobalDialog(BuildContext context, double usdUnitPrice) {
  final isChecked = false.obs;
  final addonCount = 1.obs;
  final selectedProvider = Rxn<MobilePaymentProvider>();

  const primaryColor = Color(0xFF5F71FF);
  const textColor = Color(0xFF454447);
  const featureTextColor = Color(0xFF646368);
  const cardBorder = Color(0xFFDEDEE2);
  const sectionTitleColor = Color(0xFF1A191C);

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.all(24),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                translate('Add number of session cconnections'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor),
              ),
              const SizedBox(height: 16),
              // 결제 수단 섹션
              Text(translate('payment_method'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: sectionTitleColor)),
              const SizedBox(height: 8),
              Text(translate('payment_method_select'), style: const TextStyle(fontSize: 14, color: featureTextColor)),
              const SizedBox(height: 16),
              // PayPal / Paddle
              Obx(() => Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => selectedProvider.value = MobilePaymentProvider.paypal,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: selectedProvider.value == MobilePaymentProvider.paypal ? const Color(0xFFEFF1FF) : const Color(0xFFF7F7F7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selectedProvider.value == MobilePaymentProvider.paypal ? primaryColor : const Color(0xFFF7F7F7),
                            width: selectedProvider.value == MobilePaymentProvider.paypal ? 2 : 1,
                          ),
                        ),
                        child: Center(child: Image.asset('assets/icons/paypal.png', height: 24)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => selectedProvider.value = MobilePaymentProvider.paddle,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: selectedProvider.value == MobilePaymentProvider.paddle ? const Color(0xFFEFF1FF) : const Color(0xFFF7F7F7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selectedProvider.value == MobilePaymentProvider.paddle ? primaryColor : const Color(0xFFF7F7F7),
                            width: selectedProvider.value == MobilePaymentProvider.paddle ? 2 : 1,
                          ),
                        ),
                        child: Center(child: Image.asset('assets/icons/paddle.png', height: 24)),
                      ),
                    ),
                  ),
                ],
              )),
              const SizedBox(height: 24),
              // 주문 상품 섹션
              Text(translate('order_summary_title'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: sectionTitleColor)),
              const SizedBox(height: 8),
              Text(translate('Add number of session cconnections Pre'), style: const TextStyle(fontSize: 14, color: featureTextColor)),
              const SizedBox(height: 16),
              // 카드 영역
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(translate('Add number of session cconnections'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
                    const SizedBox(height: 16),
                    _buildAddonStepper(addonCount),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Obx(() => Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(translate('total_payment'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: primaryColor)),
                          const SizedBox(width: 4),
                          Text('\$${(usdUnitPrice * addonCount.value).toStringAsFixed(0)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: primaryColor)),
                          Text('/${translate("Month")}', style: const TextStyle(fontSize: 14, color: featureTextColor)),
                        ],
                      )),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(translate('vat_excluded'), style: const TextStyle(fontSize: 12, color: featureTextColor)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // 약관 동의
              Obx(() => GestureDetector(
                onTap: () => isChecked.value = !isChecked.value,
                child: Row(
                  children: [
                    Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: isChecked.value ? primaryColor : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isChecked.value ? primaryColor : cardBorder, width: 2),
                      ),
                      child: isChecked.value ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _mobileAddonPaymentAgreeText()),
                  ],
                ),
              )),
              const SizedBox(height: 24),
              // 버튼
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cardBorder),
                        ),
                        child: Center(
                          child: Text(translate('Cancel'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Obx(() => GestureDetector(
                      onTap: isChecked.value && selectedProvider.value != null
                          ? () { Navigator.pop(context); /* TODO: 해외 결제 시작 */ }
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: isChecked.value && selectedProvider.value != null ? primaryColor : const Color(0xFFE5E5E5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(translate('OK'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isChecked.value && selectedProvider.value != null ? Colors.white : const Color(0xFF999999))),
                        ),
                      ),
                    )),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
