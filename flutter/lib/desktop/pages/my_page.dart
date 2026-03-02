/// 마이페이지 (프로필 설정)
/// 사용자 정보, 플랜, 비밀번호 변경, 약관 등을 관리

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'dart:io' show Platform;
import 'package:url_launcher/url_launcher_string.dart';
import 'package:webview_windows/webview_windows.dart' as wv;
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iaw;
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/api/auth_service.dart';
import 'package:flutter_hbb/common/api/cookie_manager.dart';
import 'package:flutter_hbb/common/api/models.dart';
import 'package:flutter_hbb/common/api/paddle_local_server.dart';
import 'package:flutter_hbb/common/api/payment_service.dart';
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/common/widgets/styled_form_widgets.dart';
import 'package:flutter_hbb/common/widgets/styled_text_field.dart';
import 'package:flutter_hbb/desktop/pages/login_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';

/// 마이페이지 뷰 상태
enum MyPageView {
  main, // 메인 설정 목록
  changePassword, // 비밀번호 변경 폼
  passwordChanged, // 비밀번호 변경 완료
  selectPlan, // 플랜 선택
  planPurchased, // 플랜 결제 완료
  paymentWebView, // 결제 웹뷰
}

/// 결제 제공자 타입
enum PaymentProvider {
  welcome, // 한국 (토스페이먼츠/Welcome)
  paypal, // 해외 (PayPal)
  paddle, // 해외 (Paddle)
}

/// 플랜 정보 모델
class PlanInfo {
  final String id;
  final String name;
  final String descriptionKey; // 번역 키
  final String licenseInfoKey; // 번역 키
  final String featuresKey; // 번역 키 (\n으로 구분된 기능 목록)
  final String targetKey; // 대상 (예: 개인 사용자)
  final String targetDescKey; // 대상 설명
  final String targetDetailDescKey; // 대상 상세 설명
  final int originalPrice;
  final int discountedPrice;
  final int discountPercent;
  final bool isPopular; // 인기 플랜 여부

  const PlanInfo({
    required this.id,
    required this.name,
    required this.descriptionKey,
    required this.licenseInfoKey,
    required this.featuresKey,
    required this.targetKey,
    required this.targetDescKey,
    required this.targetDetailDescKey,
    required this.originalPrice,
    required this.discountedPrice,
    required this.discountPercent,
    this.isPopular = false,
  });
}

/// 플랜 데이터
/// id는 API product code와 일치해야 함 (SOLO_PLAN, PRO_PLAN, TEAM_PLAN, BUSINESS_PLAN)
const List<PlanInfo> _planList = [
  PlanInfo(
    id: 'SOLO_PLAN',
    name: 'Solo',
    descriptionKey: 'plan_solo_desc',
    licenseInfoKey: 'plan_solo_license',
    featuresKey: 'plan_solo_features',
    targetKey: 'plan_solo_target',
    targetDescKey: 'plan_solo_target_desc',
    targetDetailDescKey: 'plan_solo_target_detail_desc',
    originalPrice: 19000,
    discountedPrice: 19000,
    discountPercent: 0,
  ),
  PlanInfo(
    id: 'PRO_PLAN',
    name: 'Pro',
    descriptionKey: 'plan_pro_desc',
    licenseInfoKey: 'plan_pro_license',
    featuresKey: 'plan_pro_features',
    targetKey: 'plan_pro_target',
    targetDescKey: 'plan_pro_target_desc',
    targetDetailDescKey: 'plan_pro_target_detail_desc',
    originalPrice: 35000,
    discountedPrice: 35000,
    discountPercent: 0,
  ),
  PlanInfo(
    id: 'TEAM_PLAN',
    name: 'Team',
    descriptionKey: 'plan_team_desc',
    licenseInfoKey: 'plan_team_license',
    featuresKey: 'plan_team_features',
    targetKey: 'plan_team_target',
    targetDescKey: 'plan_team_target_desc',
    targetDetailDescKey: 'plan_team_target_detail_desc',
    originalPrice: 99000,
    discountedPrice: 99000,
    discountPercent: 0,
    isPopular: true,
  ),
  PlanInfo(
    id: 'BUSINESS_PLAN',
    name: 'Business',
    descriptionKey: 'plan_business_desc',
    licenseInfoKey: 'plan_business_license',
    featuresKey: 'plan_business_features',
    targetKey: 'plan_business_target',
    targetDescKey: 'plan_business_target_desc',
    targetDetailDescKey: 'plan_business_target_detail_desc',
    originalPrice: 199000,
    discountedPrice: 199000,
    discountPercent: 0,
  ),
];

/// 마이페이지 테마 색상
const Color _primaryColor = Color(0xFF8B5CF6); // 보라색
const Color _cardColor = Colors.white;
const Color _textPrimary = Color(0xFF646368); // 메인 라벨 색상
const Color _textSecondary = Color(0xFF8F8E95); // 상세 라벨 색상
const Color _textValue = Color(0xFF454447); // 상세 값 색상
const Color _dividerColor = Color(0xFFE2E8F0);
const Color _successColor = Color(0xFF22C55E); // 성공 색상

/// 서브 타이틀 스타일 (카드 메뉴 항목용) - 테마에서 가져옴
/// 모바일에서는 텍스트 크기 축소 및 기본 weight 적용
TextStyle? _subLargeTitle(BuildContext context) {
  if (isMobile) {
    return const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.normal,
      color: _textValue,
    );
  }
  return Theme.of(context).textTheme.titleSmall;
}

class MyPage extends StatefulWidget {
  final MyPageView initialView;

  const MyPage({Key? key, this.initialView = MyPageView.main})
      : super(key: key);

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  // 현재 뷰 상태
  late final Rx<MyPageView> _currentView;

  // 플랜 섹션 펼침/접힘 상태
  final RxBool _isPlanExpanded = false.obs;

  @override
  void initState() {
    super.initState();
    _currentView = widget.initialView.obs;
    // 현재 플랜 다음 인덱스로 초기화 (비활성화된 탭 건너뛰기)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSelectedPlanIndex();
      _checkRegion();
      _loadPlanPrices();
    });
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
          if (productCode != null && amount != null) {
            _apiKrwPrices[productCode] = amount;
          }
          if (productCode != null && usdAmount != null) {
            _apiUsdPrices[productCode] = usdAmount;
          }
        }
        debugPrint('[MyPage] Plan prices loaded from API: KRW=$_apiKrwPrices, USD=$_apiUsdPrices');
      }
    } catch (e) {
      debugPrint('[MyPage] loadPlanPrices error: $e');
    }
  }

  /// 플랜 KRW 가격 가져오기 (API 우선, 없으면 기본값)
  int _getKrwPrice(PlanInfo plan) {
    return _apiKrwPrices[plan.id] ?? plan.discountedPrice;
  }

  /// 플랜 USD 가격 가져오기 (API 우선, 없으면 기본값)
  double _getUsdPrice(PlanInfo plan) {
    return _apiUsdPrices[plan.id] ?? (plan.discountedPrice / 1400); // 기본 환율로 fallback
  }

  /// 플랜 가격 표시 문자열 (지역에 따라 KRW/USD)
  String _getPlanPriceDisplay(PlanInfo plan) {
    if (_isKorea.value) {
      return '${_formatPrice(_getKrwPrice(plan))}${translate("Won")}';
    } else {
      return '\$${_getUsdPrice(plan).toStringAsFixed(0)}';
    }
  }

  /// 지역 확인 (한국 여부)
  Future<void> _checkRegion() async {
    if (!isAuthServiceInitialized()) return;
    _isCheckingRegion.value = true;
    try {
      final authService = getAuthService();
      _isKorea.value = await authService.checkIsKorea();
    } catch (e) {
      debugPrint('[MyPage] checkRegion error: $e');
      _isKorea.value = false;
    } finally {
      _isCheckingRegion.value = false;
    }
  }

  /// 선택된 플랜 인덱스를 현재 플랜 다음으로 초기화
  void _initSelectedPlanIndex() {
    // _currentPlanIndex는 FREE=0, SOLO=1, PRO=2, TEAM=3, BUSINESS=4
    // _planList 인덱스는 0=Solo, 1=Pro, 2=Team, 3=Business (FREE 없음)
    // 따라서 _planList 인덱스 = _currentPlanIndex - 1
    final currentPlanIdx = _currentPlanIndex - 1; // FREE면 -1이 됨
    final nextIndex = currentPlanIdx + 1;
    if (nextIndex < _planList.length && nextIndex >= 0) {
      _selectedPlanIndex.value = nextIndex;
    } else if (currentPlanIdx < 0) {
      // FREE 플랜이면 첫 번째 탭 선택 (Solo)
      _selectedPlanIndex.value = 0;
    }
  }

  // 선택된 플랜 인덱스
  final RxInt _selectedPlanIndex = 0.obs;

  // 각 플랜 카드 펼침 상태
  final RxList<bool> _planExpandedStates =
      List.generate(_planList.length, (_) => false).obs;

  // 각 플랜 카드 호버 상태
  final RxList<bool> _planHoverStates =
      List.generate(_planList.length, (_) => false).obs;

  // 비밀번호 입력 컨트롤러
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  // 비밀번호 표시 여부
  final RxBool _obscurePassword = true.obs;
  final RxBool _obscureConfirmPassword = true.obs;

  // 비밀번호 유효성 검사 상태
  final RxBool _hasNumber = false.obs;
  final RxBool _hasUppercase = false.obs;
  final RxBool _hasLowercase = false.obs;
  final RxBool _hasMinLength = false.obs;

  // 에러 메시지 및 로딩 상태
  final RxnString _passwordError = RxnString(null);
  final RxnString _confirmPasswordError = RxnString(null);
  final RxBool _isChangingPassword = false.obs;

  // 결제 관련 상태
  final RxnString _paymentUrl = RxnString(null);
  final RxnString _paymentHtml = RxnString(null); // PayPal HTML 직접 로드용
  final Rxn<PaymentProvider> _paymentProvider = Rxn<PaymentProvider>();
  final RxnString _paymentOrderId = RxnString(null);
  final RxBool _isKorea = false.obs;
  final RxBool _isCheckingRegion = false.obs;
  final RxBool _isPaymentLoading = false.obs;

  // API에서 로드된 가격 (productCode -> 가격)
  final RxMap<String, int> _apiKrwPrices = <String, int>{}.obs;
  final RxMap<String, double> _apiUsdPrices = <String, double>{}.obs;
  final RxInt _webViewProgress = 0.obs;
  final RxBool _webViewReady = false.obs;
  wv.WebviewController? _webViewController;
  final PaddleLocalServer _paddleLocalServer = PaddleLocalServer();

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _webViewController?.dispose();
    _paddleLocalServer.stop();
    super.dispose();
  }

  /// 비밀번호 유효성 검사
  void _validatePassword(String password) {
    _hasNumber.value = password.contains(RegExp(r'[0-9]'));
    _hasUppercase.value = password.contains(RegExp(r'[A-Z]'));
    _hasLowercase.value = password.contains(RegExp(r'[a-z]'));
    _hasMinLength.value = password.length >= 8;
  }

  /// 비밀번호 변경 처리
  Future<void> _handleChangePassword() async {
    // 에러 초기화
    _passwordError.value = null;
    _confirmPasswordError.value = null;

    // 새 비밀번호 유효성 검사
    if (!_hasNumber.value ||
        !_hasUppercase.value ||
        !_hasLowercase.value ||
        !_hasMinLength.value) {
      _passwordError.value = translate('Password requirements not met');
      return;
    }

    // 비밀번호 확인 일치 검사
    if (_passwordController.text != _confirmPasswordController.text) {
      _confirmPasswordError.value = translate(
        'The confirmation is not identical.',
      );
      return;
    }

    _isChangingPassword.value = true;

    try {
      final authService = getAuthService();
      final response = await authService.resetPassword(
        _userEmail,
        '',
        _passwordController.text,
        _confirmPasswordController.text,
      );

      if (response.success) {
        // 비밀번호 변경 완료 플래그 설정 후 로그아웃
        showPasswordChangedCompletion.value = true;
        await gFFI.userModel.logOut();
      } else {
        _passwordError.value = translate('Bad Request');
      }
    } catch (e) {
      _passwordError.value = translate('Bad Request');
    } finally {
      _isChangingPassword.value = false;
    }
  }

  /// 비밀번호 변경 폼 초기화
  void _resetPasswordForm() {
    _passwordController.clear();
    _confirmPasswordController.clear();
    _hasNumber.value = false;
    _hasUppercase.value = false;
    _hasLowercase.value = false;
    _hasMinLength.value = false;
    _obscurePassword.value = true;
    _obscureConfirmPassword.value = true;
    _passwordError.value = null;
    _confirmPasswordError.value = null;
    _isChangingPassword.value = false;
  }

  // 사용자 정보 (userModel에서 가져옴)
  String get _userName => gFFI.userModel.userName.value;
  String get _userEmail => gFFI.userModel.userEmail.value;

  /// 현재 플랜 인덱스 (API planType 기준) - 반응형
  /// FREE=0, SOLO=1, PRO=2, TEAM=3, BUSINESS=4
  int get _currentPlanIndex {
    final planType = gFFI.userModel.planType.value; // 반응형 변수 사용
    switch (planType.toUpperCase()) {
      case 'FREE':
        return 0;
      case 'SOLO':
        return 1;
      case 'PRO':
        return 2;
      case 'TEAM':
        return 3;
      case 'BUSINESS':
        return 4;
      default:
        return 0;
    }
  }

  /// 현재 플랜 (userModel에서 가져옴) - 반응형
  /// API planType: FREE, SOLO, PRO, TEAM, BUSINESS
  String get _currentPlan {
    final planType = gFFI.userModel.planType.value; // 반응형 변수 사용
    switch (planType.toUpperCase()) {
      case 'FREE':
        return 'Free';
      case 'SOLO':
        return 'Solo';
      case 'PRO':
        return 'Pro';
      case 'TEAM':
        return 'Team';
      case 'BUSINESS':
        return 'Business';
      default:
        return 'Free';
    }
  }

  /// 현재 플랜인지 plan.id로 비교 (반응형)
  /// plan.id: SOLO_PLAN, PRO_PLAN, TEAM_PLAN, BUSINESS_PLAN
  /// planType: FREE, SOLO, PRO, TEAM, BUSINESS
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

  /// 결제 수단 (billingProvider)
  String get _paymentMethod {
    final provider = gFFI.userModel.currentUserInfo?.billingProvider;
    if (provider == null || provider.isEmpty) return '-';
    switch (provider) {
      case 'WELCOME':
        return 'Welcome Payments';
      case 'PAYPAL':
        return 'PayPal';
      case 'PADDLE':
        return 'Paddle';
      default:
        return provider;
    }
  }

  /// 구독 시작일 (paidAt)
  String get _subscriptionStart {
    final date = gFFI.userModel.currentUserInfo?.lastPay;
    if (date == null || date.isEmpty) return '-';
    return '${date.replaceAll('-', '.')}~';
  }

  /// 다음 결제 예정일 (nextChargeDate)
  String get _nextPaymentDate {
    final date = gFFI.userModel.currentUserInfo?.nextChargeDate;
    if (date == null || date.isEmpty) return '-';
    return date.replaceAll('-', '.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = MyTheme.settingTab(context);

    // 데스크톱: Scaffold 사용
    // 마이페이지는 색상 반전: 사이드바=콘텐츠색, 콘텐츠=사이드바색
    return Scaffold(
      backgroundColor: theme.sidebarBackgroundColor,
      body: Obx(() {
        // 플랜 선택/결제 완료/결제 웹뷰 화면은 전체 화면으로 표시 (사이드바 없음)
        if (_currentView.value == MyPageView.selectPlan ||
            _currentView.value == MyPageView.planPurchased ||
            _currentView.value == MyPageView.paymentWebView) {
          switch (_currentView.value) {
            case MyPageView.selectPlan:
              return _buildSelectPlanContent();
            case MyPageView.planPurchased:
              return _buildPlanPurchasedContent();
            case MyPageView.paymentWebView:
              return _buildPaymentWebViewContent();
            default:
              return _buildSelectPlanContent();
          }
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start, // 상단 정렬
          children: [
            // 좌측 사이드바 - 사용자 프로필
            _buildSidebar(theme),
            // 구분선
            Container(width: 1, color: _dividerColor),
            // 우측 컨텐츠 - 뷰 상태에 따라 다른 내용 표시
            Expanded(
              child: Builder(
                builder: (context) {
                  switch (_currentView.value) {
                    case MyPageView.changePassword:
                      return _buildChangePasswordContent();
                    case MyPageView.passwordChanged:
                      return _buildPasswordChangedContent();
                    case MyPageView.main:
                    default:
                      return _buildContent();
                  }
                },
              ),
            ),
          ],
        );
      }),
    );
  }

  /// 좌측 사이드바 - 사용자 프로필 정보
  Widget _buildSidebar(SettingTabTheme theme) {
    return Container(
      width: theme.sidebarWidth,
      color: theme.contentBackgroundColor,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start, // 상단 정렬
        children: [
          const SizedBox(height: 8),
          // 타이틀
          Text(
            translate('My Page'),
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),
          // 프로필 아이콘
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
                width: 23,
                height: 24,
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
            '$_userName ${translate("nim")}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
          // 이메일 (null이 아닐 경우에만 표시)
          if (_userEmail.isNotEmpty && _userEmail != 'null') ...[
            const SizedBox(height: 4),
            Text(
              _userEmail,
              style: const TextStyle(fontSize: 13, color: _textSecondary),
            ),
          ],
          const SizedBox(height: 24),
          // 로그아웃 버튼
          StyledOutlinedButton(
            label: translate('Logout'),
            onPressed: () => logOutConfirmDialog(),
            fillWidth: false,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
          ),
        ],
      ),
    );
  }

  /// 우측 컨텐츠 - 설정 목록
  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 현재 이용 중인 플랜 (토글 가능)
          _buildPlanSection(),
          const SizedBox(height: 20),
          // 비밀번호 변경 (소셜 로그인이 아닌 경우만 표시)
          if (gFFI.userModel.loginType.value == 0) ...[
            _buildMenuItem(
              icon: 'assets/icons/profile-change-password.svg',
              title: translate('Change Password'),
              onTap: () {
                _resetPasswordForm();
                _currentView.value = MyPageView.changePassword;
              },
            ),
            const SizedBox(height: 20),
          ],
          // 이용약관, 개인정보취급정책, 결제 및 환불정책 (하나의 카드)
          _buildPolicyCard(),
          const SizedBox(height: 32),
          // 회원탈퇴
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => withdrawConfirmDialog(),
              child: Text(
                translate('Delete Account'),
                style: const TextStyle(fontSize: 13, color: _textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 프리 플랜 여부 확인
  bool get _isFreePlan =>
      _currentPlan.toLowerCase().contains('free') ||
      _currentPlan.toLowerCase().contains('무료');

  /// 플랜 섹션 (토글 가능)
  Widget _buildPlanSection() {
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
      child: Column(
        children: [
          // 플랜 헤더
          InkWell(
            onTap: _isFreePlan ? null : () => _isPlanExpanded.toggle(),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(translate('Current Plan'),
                      style: _subLargeTitle(context)),
                  const Spacer(),
                  Text(
                    _currentPlan,
                    style: isMobile
                        ? const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _textValue,
                          )
                        : Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                  ),
                  const SizedBox(width: 8),
                  // 프리 플랜: 유료플랜 전환 버튼, 유료 플랜: 토글 아이콘
                  if (_isFreePlan)
                    isMobile
                        ? ElevatedButton(
                            onPressed: () {
                              DesktopTabPage.onAddPlanSelection();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF5F71FF),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              translate('Upgrade Plan'),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )
                        : StyledOutlinedButton(
                            label: translate('Upgrade Plan'),
                            onPressed: () {
                              DesktopTabPage.onAddPlanSelection();
                            },
                            fillWidth: false,
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 12,
                            ),
                          )
                  else
                    Obx(
                      () => SvgPicture.asset(
                        _isPlanExpanded.value
                            ? 'assets/icons/arrow-up.svg'
                            : 'assets/icons/arrow-down.svg',
                        width: 40,
                        height: 40,
                        colorFilter: const ColorFilter.mode(
                          _textPrimary,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // 플랜 상세 정보 (유료 플랜이고 펼쳐졌을 때만 표시)
          if (!_isFreePlan)
            Obx(
              () => _isPlanExpanded.value
                  ? Column(
                      children: [
                        const Divider(
                          height: 1,
                          indent: 20,
                          endIndent: 20,
                          color: _dividerColor,
                        ),
                        // 결제 수단
                        _buildPlanDetailRow(
                          label: translate('Payment Method'),
                          value: _paymentMethod,
                          trailing: StyledOutlinedButton(
                            label: translate('Change'),
                            onPressed: () {
                              // TODO: 결제 수단 변경
                            },
                            fillWidth: false,
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 12,
                            ),
                          ),
                        ),
                        // 구독 시작일
                        _buildPlanDetailRow(
                          label: translate('Subscription Start'),
                          value: _subscriptionStart,
                        ),
                        // 결제 예정일
                        _buildPlanDetailRow(
                          label: translate('Next Payment Date'),
                          value: _nextPaymentDate,
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 16, color: _textSecondary),
          ),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 16, color: _textValue)),
          if (trailing != null) ...[const SizedBox(width: 12), trailing],
        ],
      ),
    );
  }

  /// 메뉴 아이템
  Widget _buildMenuItem({
    String? icon,
    required String title,
    required VoidCallback onTap,
  }) {
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (icon != null) ...[
                SvgPicture.asset(
                  icon,
                  width: 20,
                  height: 20,
                  colorFilter: const ColorFilter.mode(
                    _textPrimary,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Text(title, style: _subLargeTitle(context)),
              const Spacer(),
              SvgPicture.asset(
                'assets/icons/arrow-right.svg',
                width: 40,
                height: 40,
                colorFilter: const ColorFilter.mode(
                  _textPrimary,
                  BlendMode.srcIn,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 정책 카드 (이용약관, 개인정보취급정책, 결제 및 환불정책)
  /// 하나의 카드 안에 구분선으로 구분
  Widget _buildPolicyCard() {
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
      child: Column(
        children: [
          // 이용약관
          _buildPolicyItem(
            title: translate('Terms of Service'),
            onTap: () => launchUrlString('https://onedesk.co.kr/terms'),
            isFirst: true,
          ),
          const Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: _dividerColor,
          ),
          // 개인정보취급정책
          _buildPolicyItem(
            title: translate('Privacy Policy'),
            onTap: () => launchUrlString('https://onedesk.co.kr/privacy'),
          ),
          const Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: _dividerColor,
          ),
          // 결제 및 환불정책
          _buildPolicyItem(
            title: translate('Payment and Refund Policy'),
            onTap: () => launchUrlString('https://onedesk.co.kr/refund'),
            isLast: true,
          ),
        ],
      ),
    );
  }

  /// 정책 카드 내 개별 아이템
  Widget _buildPolicyItem({
    required String title,
    required VoidCallback onTap,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.vertical(
        top: isFirst ? const Radius.circular(12) : Radius.zero,
        bottom: isLast ? const Radius.circular(12) : Radius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text(title, style: _subLargeTitle(context)),
            const Spacer(),
            SvgPicture.asset(
              'assets/icons/arrow-right.svg',
              width: 40,
              height: 40,
              colorFilter: const ColorFilter.mode(
                _textPrimary,
                BlendMode.srcIn,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 비밀번호 변경 폼 컨텐츠
  Widget _buildChangePasswordContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 비밀번호 입력 카드 (헤더 포함)
          Container(
            width: double.infinity,
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
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 뒤로가기 헤더
                InkWell(
                  onTap: () => _currentView.value = MyPageView.main,
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.asset(
                        'assets/icons/arrow-left.svg',
                        width: 40,
                        height: 40,
                        colorFilter: const ColorFilter.mode(
                          _textPrimary,
                          BlendMode.srcIn,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(translate('Change Password'),
                          style: _subLargeTitle(context)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // 비밀번호 라벨
                Text(
                  translate('Password'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                ),
                const SizedBox(height: 8),
                // 비밀번호 입력 필드
                Obx(
                  () => AuthTextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword.value,
                    hintText: translate('Enter password'),
                    errorText: _passwordError.value,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword.value
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                        color: Colors.grey[500],
                      ),
                      onPressed: () =>
                          _obscurePassword.value = !_obscurePassword.value,
                    ),
                    onChanged: _validatePassword,
                  ),
                ),
                const SizedBox(height: 12),
                // 비밀번호 규칙 칩
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Obx(
                      () => _buildRuleChip(
                        translate('Use numbers'),
                        _hasNumber.value,
                      ),
                    ),
                    Obx(
                      () => _buildRuleChip(
                        translate('Use uppercase'),
                        _hasUppercase.value,
                      ),
                    ),
                    Obx(
                      () => _buildRuleChip(
                        translate('Use lowercase'),
                        _hasLowercase.value,
                      ),
                    ),
                    Obx(
                      () => _buildRuleChip(
                        translate('8 or more characters'),
                        _hasMinLength.value,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // 비밀번호 확인 라벨
                Text(
                  translate('Confirm Password'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                ),
                const SizedBox(height: 8),
                // 비밀번호 확인 입력 필드
                Obx(
                  () => AuthTextField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword.value,
                    hintText: translate('Re-enter password'),
                    errorText: _confirmPasswordError.value,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword.value
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                        color: Colors.grey[500],
                      ),
                      onPressed: () => _obscureConfirmPassword.value =
                          !_obscureConfirmPassword.value,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // 로딩 표시
                Obx(
                  () => _isChangingPassword.value
                      ? const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: LinearProgressIndicator(),
                        )
                      : const SizedBox.shrink(),
                ),
                // 비밀번호 변경 버튼
                Obx(
                  () => SizedBox(
                    width: double.infinity,
                    child: StyledCompactButton(
                      label: translate('Change Password'),
                      onPressed: _isChangingPassword.value
                          ? null
                          : _handleChangePassword,
                      fillWidth: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

  /// 비밀번호 변경 완료 컨텐츠
  Widget _buildPasswordChangedContent() {
    return Center(
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFEFEFE),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 체크 아이콘
            Image.asset('assets/icons/sucess.png', width: 160, height: 160),
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
              translate('Login and try various OneDesk services!'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 32),
            // 로그인하러 가기 버튼
            StyledCompactButton(
              label: translate('Go to login'),
              onPressed: () async {
                // 로그아웃 후 로그인 페이지로 이동
                await gFFI.userModel.logOut();
              },
              padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 14),
            ),
          ],
        ),
      ),
    );
  }

  /// 플랜 선택 컨텐츠 (가로 카드 방식)
  Widget _buildSelectPlanContent() {
    // 플랜 카드 색상 상수
    const planNameColor = Color(0xFF5F71FF);
    const targetColor = Color(0xFF454447);
    const targetDescColor = Color(0xFF646368);
    const featureTextColor = Color(0xFF646368);
    const priceColor = Color(0xFF1A191C);
    const perMonthColor = Color(0xFF646368);
    const recommendBgColor = Color(0xFFEFF1FF); // 추천 대상 배경색
    const featuresBgColor = Color(0xFFF7F7F7); // 혜택 목록 배경색
    const cardBgColor = Color(0xFFFEFEFE);
    const viewDetailColor = Color(0xFF454447);
    const buttonTextColor = Color(0xFFFEFEFE);
    const checkIconColor = Color(0xFF5F71FF);
    const cardBorderColor = Color(0xFFDEDEE2); // 카드 보더 색상
    const cardShadow = Color(0x1A000000); // 그림자 색상 10%

    return LayoutBuilder(
      builder: (context, constraints) => Container(
        color: const Color(0xFFFEFEFE),
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 헤더
              SizedBox(
                height: 75,
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    SvgPicture.asset(
                      'assets/icons/topbar-logo.svg',
                      width: 40,
                      height: 40,
                      colorFilter: const ColorFilter.mode(
                        Color(0xFF5F71FF),
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 30),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          translate('Select Plan'),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF454447),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          translate('Choose the best plan for your team'),
                          style: const TextStyle(
                            fontSize: 18,
                            color: Color(0xFF8F8E95),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // 결제 및 환불 정책 링크
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () =>
                            launchUrlString('https://onedesk.co.kr/refund'),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.arrow_outward,
                                size: 16, color: _textSecondary),
                            const SizedBox(width: 6),
                            Text(
                              translate('Payment and Refund Policy'),
                              style: const TextStyle(
                                fontSize: 14,
                                color: _textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                ),
              ),
              // 인기 배너 높이(36) + 기본 간격(20)
              const SizedBox(height: 56),

              // 가로 플랜 카드 리스트
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(_planList.length, (index) {
                  final plan = _planList[index];
                  final isCurrentPlan = _isCurrentPlanById(plan.id);
                  final isLowerPlan = _isLowerPlanByIndex(index);
                  final isDisabled = isCurrentPlan || isLowerPlan;

                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: index == 0 ? 0 : 8,
                        right: index == _planList.length - 1 ? 0 : 8,
                      ),
                      child: Obx(() {
                        final isExpanded = _planExpandedStates[index];
                        final isHovered = _planHoverStates[index];

                        // 인기 배너 높이 (vertical padding 10*2 + 텍스트 높이 약 16)
                        const popularBannerHeight = 36.0;

                        return MouseRegion(
                          onEnter: (_) => _planHoverStates[index] = true,
                          onExit: (_) => _planHoverStates[index] = false,
                          child: Transform.translate(
                            // 인기 플랜은 배너 높이만큼 위로 이동
                            offset: Offset(
                                0, plan.isPopular ? -popularBannerHeight : 0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: cardBgColor,
                                borderRadius:
                                    BorderRadius.circular(16), // 코너 둥글기 16px
                                border: Border.all(
                                  // 호버 또는 팀플랜(인기 플랜) 또는 현재 플랜: #5F71FF, 기본: #DEDEE2
                                  color: isHovered ||
                                          plan.isPopular ||
                                          isCurrentPlan
                                      ? planNameColor
                                      : cardBorderColor,
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: cardShadow, // 그림자 #0000001A 10%
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 인기 플랜 배너
                                  if (plan.isPopular)
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                      decoration: const BoxDecoration(
                                        color: planNameColor,
                                        borderRadius: BorderRadius.only(
                                          topLeft: Radius.circular(
                                              15), // 카드 16px - 보더 1px
                                          topRight: Radius.circular(15),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            translate('Most Popular Plans'),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: buttonTextColor,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Text('\u2728',
                                              style: TextStyle(fontSize: 14)),
                                        ],
                                      ),
                                    ),

                                  // 플랜 헤더
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // 플랜명
                                        Text(
                                          plan.name,
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: planNameColor,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        // 대상
                                        Text(
                                          translate(plan.targetKey),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: targetColor,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        // 대상 설명 (마지막 콤마만 줄바꿈)
                                        Text(
                                          _replaceLastComma(
                                              translate(plan.targetDescKey)),
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: targetDescColor,
                                            height: 1.4,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        // 가격
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.baseline,
                                          textBaseline: TextBaseline.alphabetic,
                                          children: [
                                            Obx(() => Text(
                                              _getPlanPriceDisplay(plan),
                                              style: const TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.bold,
                                                color: priceColor,
                                              ),
                                            )),
                                            const SizedBox(width: 2),
                                            Text(
                                              '/${translate("Month")}',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: perMonthColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // 추천 대상 섹션 (배경색 #EFF1FF)
                                  Container(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: recommendBgColor, // #EFF1FF
                                      borderRadius: BorderRadius.circular(
                                          8), // 코너 둥글기 8px
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          translate('Recommand Target'),
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: targetColor,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        ...translate(plan.targetDetailDescKey)
                                            .split('\n')
                                            .map((item) {
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 6),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                SvgPicture.asset(
                                                  'assets/icons/plan-desc-check.svg',
                                                  width: 14,
                                                  height: 14,
                                                  colorFilter:
                                                      const ColorFilter.mode(
                                                    checkIconColor,
                                                    BlendMode.srcIn,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    item.trim(),
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: featureTextColor,
                                                      height: 1.3,
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
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: GestureDetector(
                                        onTap: () {
                                          _planExpandedStates[index] =
                                              !isExpanded;
                                        },
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              translate(
                                                  'View Details Benefits'),
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: viewDetailColor,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            SvgPicture.asset(
                                              isExpanded
                                                  ? 'assets/icons/plan-show-arrow-up.svg'
                                                  : 'assets/icons/plan-show-arrow-down.svg',
                                              width: 14,
                                              height: 14,
                                              colorFilter:
                                                  const ColorFilter.mode(
                                                viewDetailColor,
                                                BlendMode.srcIn,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),

                                  // 펼쳐진 경우 혜택 목록 섹션
                                  if (isExpanded) ...[
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            translate('Function'),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: targetColor,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          ...translate(plan.featuresKey)
                                              .split('\n')
                                              .map((feature) {
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 6),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  SvgPicture.asset(
                                                    'assets/icons/plan-desc-check.svg',
                                                    width: 14,
                                                    height: 14,
                                                    colorFilter:
                                                        const ColorFilter.mode(
                                                      checkIconColor,
                                                      BlendMode.srcIn,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      feature.trim(),
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: featureTextColor,
                                                        height: 1.3,
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
                                    padding: const EdgeInsets.fromLTRB(
                                        12, 0, 12, 12),
                                    child: _buildDesktopPlanButton(
                                        plan, isCurrentPlan, isDisabled),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 현재 플랜보다 낮은 등급인지 확인 (인덱스 기준)
  bool _isLowerPlanByIndex(int planIndex) {
    final currentIdx = _currentPlanIndex;
    // _planList 인덱스는 0=Solo, 1=Pro, 2=Team, 3=Business
    // _currentPlanIndex는 FREE=0, SOLO=1, PRO=2, TEAM=3, BUSINESS=4
    // 따라서 planIndex + 1을 currentIdx와 비교
    return (planIndex + 1) < currentIdx;
  }

  /// 데스크탑 플랜 버튼
  Widget _buildDesktopPlanButton(
      PlanInfo plan, bool isCurrentPlan, bool isDisabled) {
    const buttonTextColor = Color(0xFFFEFEFE);
    const planNameColor = Color(0xFF5F71FF);
    const featureTextColor = Color(0xFF646368);

    if (isCurrentPlan) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          translate('Current plan in use'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: featureTextColor,
          ),
        ),
      );
    }

    if (isDisabled) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          translate('Lower plan'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: featureTextColor,
          ),
        ),
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _isKorea.value
            ? _showWelcomePaymentConfirmDialog(plan.id)
            : _showGlobalPaymentDialog(plan.id),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: planNameColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            translate('Start Plan'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: buttonTextColor,
            ),
          ),
        ),
      ),
    );
  }

  /// 가격 포맷팅 (천 단위 콤마)
  String _formatPrice(int price) {
    return price.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
  }

  /// 마지막 콤마 뒤에 줄바꿈 추가 (, \n)
  String _replaceLastComma(String text) {
    final lastCommaIndex = text.lastIndexOf(',');
    if (lastCommaIndex == -1) return text;
    return '${text.substring(0, lastCommaIndex)},\n${text.substring(lastCommaIndex + 2)}';
  }

  /// 플랜 결제 완료 컨텐츠
  Widget _buildPlanPurchasedContent() {
    return Center(
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFEFEFE),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 체크 아이콘
            Image.asset('assets/icons/sucess.png', width: 160, height: 160),
            const SizedBox(height: 32),
            // 완료 메시지
            Text(
              translate('Plan payment completed'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5B7BF8),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              translate('Start remote computing in an upgraded environment'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 32),
            // 메인화면 돌아가기 버튼
            StyledCompactButton(
              label: translate('Return to main screen'),
              onPressed: () {
                // 메인 탭(홈)으로 이동
                try {
                  final tabController = Get.find<DesktopTabController>();
                  tabController.jumpTo(0); // 첫 번째 탭(홈)으로 이동
                } catch (e) {
                  debugPrint('[MyPage] Failed to jump to home: $e');
                  _currentView.value = MyPageView.main;
                }
              },
              padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 14),
            ),
          ],
        ),
      ),
    );
  }

  /// 결제 웹뷰 컨텐츠
  Widget _buildPaymentWebViewContent() {
    return Container(
      color: const Color(0xFFFEFEFE),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // 헤더 - 뒤로가기 버튼
          Row(
            children: [
              InkWell(
                onTap: _cancelPayment,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.asset(
                        'assets/icons/arrow-left.svg',
                        width: 40,
                        height: 40,
                        colorFilter: const ColorFilter.mode(
                          _textPrimary,
                          BlendMode.srcIn,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(translate('Cancel Payment'),
                          style: _subLargeTitle(context)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // 결제 제공자 표시
              // Obx(() => Text(
              //       _getPaymentProviderName(),
              //       style: const TextStyle(
              //         fontSize: 16,
              //         fontWeight: FontWeight.bold,
              //         color: _textPrimary,
              //       ),
              //     )),
            ],
          ),
          // // 디버그: 현재 URL 표시
          // Obx(() => Container(
          //       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          //       child: Text(
          //         'URL: ${_paymentUrl.value ?? "(none)"}',
          //         style: const TextStyle(fontSize: 10, color: Colors.grey),
          //         maxLines: 1,
          //         overflow: TextOverflow.ellipsis,
          //       ),
          //     )),
          const SizedBox(height: 8),
          // 웹뷰 영역
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x1A1B2151)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Obx(() {
                final url = _paymentUrl.value;
                final htmlContent = _paymentHtml.value;

                // URL과 HTML 모두 없으면 로딩 표시
                final hasUrl = url != null && url.isNotEmpty;
                final hasHtml = htmlContent != null && htmlContent.isNotEmpty;

                if (!hasUrl && !hasHtml) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (hasHtml) {
                  debugPrint('[PaymentWebView] Loading HTML content');
                } else {
                  debugPrint('[PaymentWebView] Loading URL: $url');
                }

                // Paddle 결제 시 쿠키 전달
                Map<String, String>? cookies;
                String? cookieDomain;
                if (_paymentProvider.value == PaymentProvider.paddle &&
                    hasUrl) {
                  try {
                    final authService = getAuthService();
                    final apiDomain = Uri.parse(authService.baseUrl).host;
                    final domainCookies =
                        cookieManager.getCookiesForDomain(apiDomain);
                    if (domainCookies != null && domainCookies.isNotEmpty) {
                      cookies =
                          domainCookies.map((k, v) => MapEntry(k, v.value));
                      cookieDomain = Uri.parse(url).host;
                      debugPrint(
                          '[PaymentWebView] Passing ${cookies.length} cookies for Paddle');
                    }
                  } catch (e) {
                    debugPrint('[PaymentWebView] Failed to get cookies: $e');
                  }
                }

                if (Platform.isWindows) {
                  // Windows: webview_windows (WebView2) 사용
                  return _WindowsWebView(
                    url: hasUrl ? url : null,
                    htmlContent: hasHtml ? htmlContent : null,
                    onUrlChanged: (newUrl) {
                      debugPrint('[PaymentWebView] URL changed: $newUrl');
                      _checkPaymentResultUrl(newUrl);
                    },
                    onLoadingStateChanged: (isLoading) {
                      _webViewProgress.value = isLoading ? 50 : 100;
                    },
                    cookies: cookies,
                    cookieDomain: cookieDomain,
                  );
                } else {
                  // macOS/Linux: flutter_inappwebview 사용
                  return _InAppWebViewWidget(
                    url: hasUrl ? url : null,
                    htmlContent: hasHtml ? htmlContent : null,
                    onUrlChanged: (newUrl) {
                      debugPrint('[PaymentWebView] URL changed: $newUrl');
                      _checkPaymentResultUrl(newUrl);
                    },
                    onLoadingStateChanged: (isLoading) {
                      _webViewProgress.value = isLoading ? 50 : 100;
                    },
                    cookies: cookies,
                    cookieDomain: cookieDomain,
                  );
                }
              }),
            ),
          ),
        ],
      ),
    );
  }

  /// URL 문자열로 결제 결과 체크
  bool _checkPaymentResultUrl(String? urlStr) {
    if (urlStr == null || urlStr.isEmpty) return false;
    final urlStrLower = urlStr.toLowerCase();

    debugPrint('========================================');
    debugPrint('[PaymentWebView] 체크 URL: $urlStr');
    debugPrint('========================================');

    // Welcome 에러/취소 파라미터 체크 (우선)
    if (urlStrLower.contains('p_status=') &&
        !urlStrLower.contains('p_status=00')) {
      debugPrint('[PaymentWebView] Payment FAIL (P_STATUS)');
      _onPaymentCancel();
      return true;
    }
    if (urlStrLower.contains('errcode=') || urlStrLower.contains('errmsg=')) {
      debugPrint('[PaymentWebView] Payment FAIL (errcode/errmsg)');
      _onPaymentCancel();
      return true;
    }
    if (urlStrLower.contains('isblockback=err')) {
      debugPrint('[PaymentWebView] Payment FAIL (isBlockBack)');
      _onPaymentCancel();
      return true;
    }

    // localhost:8080 (서버 콜백)은 스킵 - 서버가 리다이렉트할 때까지 대기
    // 서버에서 Welcome 응답을 처리하고 status 파라미터를 붙여서 리다이렉트해야 함
    if (urlStrLower.contains('localhost:8080')) {
      debugPrint(
          '[PaymentWebView] Server callback URL, waiting for server response...');
      return false;
    }

    // status 파라미터 체크 (서버 리다이렉트 결과)
    if (urlStrLower.contains('status=fail') ||
        urlStrLower.contains('status=error')) {
      debugPrint('[PaymentWebView] Payment FAIL (status param)');
      _onPaymentCancel();
      return true;
    }
    if (urlStrLower.contains('status=cancel')) {
      debugPrint('[PaymentWebView] Payment CANCEL (status param)');
      _onPaymentCancel();
      return true;
    }
    if (urlStrLower.contains('status=success')) {
      debugPrint('[PaymentWebView] Payment SUCCESS (status param)');
      _onPaymentSuccess();
      return true;
    }

    // 클라이언트용 localhost URL 체크 (C# 로컬 서버 방식)
    if (urlStrLower.contains('localhost')) {
      if (urlStrLower.contains('/fail')) {
        debugPrint('[PaymentWebView] Payment FAIL (localhost)');
        _onPaymentCancel();
        return true;
      }
      if (urlStrLower.contains('/cancel')) {
        debugPrint('[PaymentWebView] Payment CANCEL (localhost)');
        _onPaymentCancel();
        return true;
      }
      if (urlStrLower.contains('/success')) {
        debugPrint('[PaymentWebView] Payment SUCCESS (localhost)');
        _onPaymentSuccess();
        return true;
      }
    }

    return false;
  }

  /// 결제 제공자 이름 반환
  String _getPaymentProviderName() {
    switch (_paymentProvider.value) {
      case PaymentProvider.welcome:
        return 'Welcome Payments';
      case PaymentProvider.paypal:
        return 'PayPal';
      case PaymentProvider.paddle:
        return 'Paddle';
      default:
        return '';
    }
  }

  /// 결제 성공 처리
  Future<void> _onPaymentSuccess() async {
    _resetPaymentState();
    _currentView.value = MyPageView.planPurchased;

    // API에서 최신 사용자 정보 가져와서 플랜 갱신
    try {
      if (isAuthServiceInitialized()) {
        final authService = getAuthService();
        final meRes = await authService.me();
        if (meRes.success && meRes.data != null) {
          final userInfo = UserInfo.fromJson(meRes.data!);
          gFFI.userModel.loginWithUserInfo(userInfo);
          debugPrint(
              '[Payment] User info refreshed: planType=${userInfo.planType}');
        }
      }
    } catch (e) {
      debugPrint('[Payment] Failed to refresh user info: $e');
    }

    // 기존 RustDesk 사용자 정보도 새로고침
    gFFI.userModel.refreshCurrentUser();
  }

  /// 결제 취소 처리
  void _onPaymentCancel() {
    _resetPaymentState();
    _currentView.value = MyPageView.selectPlan;
  }

  /// 결제 취소 버튼 핸들러
  void _cancelPayment() {
    _resetPaymentState();
    _currentView.value = MyPageView.selectPlan;
  }

  /// 결제 상태 초기화
  void _resetPaymentState() {
    _paymentUrl.value = null;
    _paymentHtml.value = null;
    _paymentProvider.value = null;
    _paymentOrderId.value = null;
    _isPaymentLoading.value = false;
    _webViewController = null;
    _paddleLocalServer.stop();
  }

  /// 결제 확인 다이얼로그 (Welcome용 - 체크박스 포함)
  void _showWelcomePaymentConfirmDialog(String productCode) {
    final isChecked = false.obs;

    // 플랜 정보 찾기
    final plan = _planList.firstWhere(
      (p) => p.id == productCode,
      orElse: () => _planList.first,
    );

    // 테마 색상
    const primaryColor = Color(0xFF5F71FF);
    const textColor = Color(0xFF454447);
    const cardBgColor = Color(0xFFF7F7F7);

    gFFI.dialogManager.show((setState, close, context) {
      return CustomAlertDialog(
        title: Text(
          translate('payment_confirm'),
          style: MyTheme.dialogTitleStyle,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 서브타이틀
            Text(
              translate('payment_info_check'),
              style: const TextStyle(
                fontSize: 14,
                color: textColor,
              ),
            ),
            const SizedBox(height: 20),

            // 플랜 정보 카드
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardBgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 플랜 이름
                  Text(
                    plan.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: textColor,
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
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: primaryColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Obx(() => Text(
                          _getPlanPriceDisplay(plan),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: primaryColor,
                          ),
                        )),
                        Text(
                          '/${translate("Month")}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // VAT 별도 (오른쪽 정렬)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      translate('vat_excluded'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFB9B8BF),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 체크박스와 약관 동의
            Obx(() => GestureDetector(
                  onTap: () => isChecked.value = !isChecked.value,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StyledCheckbox(
                        value: isChecked.value,
                        onChanged: (v) => isChecked.value = v ?? false,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildPaymentAgreeText(),
                      ),
                    ],
                  ),
                )),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: StyledOutlinedButton(
                  label: translate('Cancel'),
                  onPressed: close,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Obx(() => StyledPrimaryButton(
                      label: translate('OK'),
                      onPressed: isChecked.value
                          ? () {
                              close();
                              _startWelcomePayment(productCode);
                            }
                          : null,
                    )),
              ),
            ],
          ),
        ],
        onCancel: close,
      );
    });
  }

  /// 기기 추가(ADDON_SESSION) 결제 다이얼로그 - 한국 (Welcome)
  void _showAddonWelcomeDialog() {
    final isChecked = false.obs;
    final addonCount = 1.obs;

    // ADDON_SESSION 가격 (API에서 로드된 값 사용)
    final krwUnitPrice = _apiKrwPrices['ADDON_SESSION'] ?? 1000;

    const primaryColor = Color(0xFF5F71FF);
    const textColor = Color(0xFF454447);
    const cardBgColor = Color(0xFFF7F7F7);

    gFFI.dialogManager.show((setState, close, context) {
      return CustomAlertDialog(
        title: Text(
          translate('Add number of session cconnections'),
          style: MyTheme.dialogTitleStyle,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              translate('Add number of session cconnections Pre'),
              style: const TextStyle(fontSize: 14, color: textColor),
            ),
            const SizedBox(height: 20),
            // 카드 영역
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardBgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    translate('Add number of session cconnections'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // [-] 수량 [+] 스테퍼
                  Obx(() => Row(
                    children: [
                      // - 버튼
                      GestureDetector(
                        onTap: () {
                          if (addonCount.value > 1) addonCount.value--;
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFDEDEE2)),
                          ),
                          child: const Center(
                            child: Text('−', style: TextStyle(fontSize: 20, color: textColor)),
                          ),
                        ),
                      ),
                      // 수량 표시
                      Expanded(
                        child: Container(
                          height: 40,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFDEDEE2)),
                          ),
                          child: Center(
                            child: Text(
                              '${addonCount.value}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
                            ),
                          ),
                        ),
                      ),
                      // + 버튼
                      GestureDetector(
                        onTap: () => addonCount.value++,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFDEDEE2)),
                          ),
                          child: const Center(
                            child: Text('+', style: TextStyle(fontSize: 20, color: textColor)),
                          ),
                        ),
                      ),
                    ],
                  )),
                  const SizedBox(height: 16),
                  // 총 가격
                  Align(
                    alignment: Alignment.centerRight,
                    child: Obx(() => Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          translate('total_payment'),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: primaryColor),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_formatPrice(krwUnitPrice * addonCount.value)}${translate("Won")}',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: primaryColor),
                        ),
                        Text(
                          '/${translate("Month")}',
                          style: const TextStyle(fontSize: 14, color: textColor),
                        ),
                      ],
                    )),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      translate('vat_excluded'),
                      style: const TextStyle(fontSize: 12, color: Color(0xFFB9B8BF)),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StyledCheckbox(
                    value: isChecked.value,
                    onChanged: (v) => isChecked.value = v ?? false,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _buildPaymentAgreeText()),
                ],
              ),
            )),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: StyledOutlinedButton(
                  label: translate('Cancel'),
                  onPressed: close,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Obx(() => StyledPrimaryButton(
                  label: translate('OK'),
                  onPressed: isChecked.value
                      ? () {
                          close();
                          // TODO: Welcome 결제 시작
                        }
                      : null,
                )),
              ),
            ],
          ),
        ],
        onCancel: close,
      );
    });
  }

  /// 기기 추가(ADDON_SESSION) 결제 다이얼로그 - 해외 (PayPal/Paddle)
  void _showAddonGlobalDialog() {
    final isChecked = false.obs;
    final addonCount = 1.obs;
    final selectedProvider = Rxn<PaymentProvider>();

    // ADDON_SESSION 가격 (API에서 로드된 값 사용)
    final usdUnitPrice = _apiUsdPrices['ADDON_SESSION'] ?? 1.0;

    const primaryColor = Color(0xFF5F71FF);
    const textColor = Color(0xFF454447);
    const cardBgColor = Color(0xFFF7F7F7);
    const sectionTitleColor = Color(0xFF1A191C);

    gFFI.dialogManager.show((setState, close, context) {
      return CustomAlertDialog(
        title: Text(
          translate('Add number of session cconnections'),
          style: MyTheme.dialogTitleStyle,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 결제 수단 섹션
            Text(
              translate('payment_method'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: sectionTitleColor),
            ),
            const SizedBox(height: 8),
            Text(
              translate('payment_method_select'),
              style: const TextStyle(fontSize: 14, color: textColor),
            ),
            const SizedBox(height: 16),
            // PayPal / Paddle 선택
            Obx(() => Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => selectedProvider.value = PaymentProvider.paypal,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: selectedProvider.value == PaymentProvider.paypal
                            ? const Color(0xFFEFF1FF) : cardBgColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedProvider.value == PaymentProvider.paypal
                              ? primaryColor : cardBgColor,
                          width: selectedProvider.value == PaymentProvider.paypal ? 2 : 1,
                        ),
                      ),
                      child: Center(child: Image.asset('assets/icons/paypal.png', height: 24)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => selectedProvider.value = PaymentProvider.paddle,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: selectedProvider.value == PaymentProvider.paddle
                            ? const Color(0xFFEFF1FF) : cardBgColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedProvider.value == PaymentProvider.paddle
                              ? primaryColor : cardBgColor,
                          width: selectedProvider.value == PaymentProvider.paddle ? 2 : 1,
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
            Text(
              translate('order_summary_title'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: sectionTitleColor),
            ),
            const SizedBox(height: 8),
            Text(
              translate('Add number of session cconnections Pre'),
              style: const TextStyle(fontSize: 14, color: textColor),
            ),
            const SizedBox(height: 16),
            // 카드 영역
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardBgColor,
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
                  // [-] 수량 [+] 스테퍼
                  Obx(() => Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (addonCount.value > 1) addonCount.value--;
                        },
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFDEDEE2)),
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
                            border: Border.all(color: const Color(0xFFDEDEE2)),
                          ),
                          child: Center(
                            child: Text('${addonCount.value}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => addonCount.value++,
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFDEDEE2)),
                          ),
                          child: const Center(child: Text('+', style: TextStyle(fontSize: 20, color: textColor))),
                        ),
                      ),
                    ],
                  )),
                  const SizedBox(height: 16),
                  // 총 가격 (USD)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Obx(() => Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          translate('total_payment'),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: primaryColor),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '\$${(usdUnitPrice * addonCount.value).toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: primaryColor),
                        ),
                        Text(
                          '/${translate("Month")}',
                          style: const TextStyle(fontSize: 14, color: textColor),
                        ),
                      ],
                    )),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      translate('vat_excluded'),
                      style: const TextStyle(fontSize: 12, color: Color(0xFFB9B8BF)),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StyledCheckbox(
                    value: isChecked.value,
                    onChanged: (v) => isChecked.value = v ?? false,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _buildPaymentAgreeText()),
                ],
              ),
            )),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: StyledOutlinedButton(
                  label: translate('Cancel'),
                  onPressed: close,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Obx(() => StyledPrimaryButton(
                  label: translate('OK'),
                  onPressed: isChecked.value && selectedProvider.value != null
                      ? () {
                          close();
                          // TODO: 해외 결제 시작
                        }
                      : null,
                )),
              ),
            ],
          ),
        ],
        onCancel: close,
      );
    });
  }

  /// 기기 추가 결제 다이얼로그 표시 (IP 기반 분기)
  void showAddonSessionDialog() {
    if (_isKorea.value) {
      _showAddonWelcomeDialog();
    } else {
      _showAddonGlobalDialog();
    }
  }

  /// 기기 추가 결제 다이얼로그 (외부 호출용 static)
  static void showAddonDialog() {
    showDesktopAddonSessionDialog();
  }

  /// 결제 약관 동의 텍스트 빌드 (링크 포함)
  Widget _buildPaymentAgreeText() {
    const textColor = Color(0xFF454447);
    const linkColor = Color(0xFF5F71FF);

    // payment_agree_text: "<결제 및 환불약관>에 동의합니다."
    // <> 안의 텍스트를 링크로 만듦
    final fullText = translate('payment_agree_text');

    // < > 사이의 텍스트 추출
    final startIndex = fullText.indexOf('<');
    final endIndex = fullText.indexOf('>');

    if (startIndex == -1 || endIndex == -1 || startIndex >= endIndex) {
      // < > 없으면 그냥 텍스트로 표시
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
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
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
          ),
          if (afterLink.isNotEmpty) TextSpan(text: afterLink),
        ],
      ),
    );
  }

  /// 해외 결제 다이얼로그 (PayPal/Paddle 선택)
  void _showGlobalPaymentDialog(String productCode) {
    final isChecked = false.obs;
    final selectedProvider = Rxn<PaymentProvider>();

    // 플랜 정보 찾기
    final plan = _planList.firstWhere(
      (p) => p.id == productCode,
      orElse: () => _planList.first,
    );

    // 테마 색상
    const primaryColor = Color(0xFF5F71FF);
    const textColor = Color(0xFF454447);
    const cardBgColor = Color(0xFFF7F7F7);
    const sectionTitleColor = Color(0xFF1A191C);

    gFFI.dialogManager.show((setState, close, context) {
      return CustomAlertDialog(
        title: Text(
          translate('payment_title'),
          style: MyTheme.dialogTitleStyle,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 결제 수단 섹션
            Text(
              translate('payment_method'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: sectionTitleColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              translate('payment_method_select'),
              style: const TextStyle(
                fontSize: 14,
                color: textColor,
              ),
            ),
            const SizedBox(height: 16),

            // PayPal / Paddle 버튼
            Obx(() => Row(
                  children: [
                    // PayPal 버튼
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            selectedProvider.value = PaymentProvider.paypal,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color:
                                selectedProvider.value == PaymentProvider.paypal
                                    ? const Color(0xFFEFF1FF)
                                    : const Color(0xFFF7F7F7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selectedProvider.value ==
                                      PaymentProvider.paypal
                                  ? primaryColor
                                  : const Color(0xFFF7F7F7),
                              width: selectedProvider.value ==
                                      PaymentProvider.paypal
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
                        onTap: () =>
                            selectedProvider.value = PaymentProvider.paddle,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color:
                                selectedProvider.value == PaymentProvider.paddle
                                    ? const Color(0xFFEFF1FF)
                                    : const Color(0xFFF7F7F7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selectedProvider.value ==
                                      PaymentProvider.paddle
                                  ? primaryColor
                                  : const Color(0xFFF7F7F7),
                              width: selectedProvider.value ==
                                      PaymentProvider.paddle
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
                color: sectionTitleColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              translate('payment_info_check'),
              style: const TextStyle(
                fontSize: 14,
                color: textColor,
              ),
            ),
            const SizedBox(height: 16),

            // 플랜 정보 카드
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardBgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 플랜 이름
                  Text(
                    plan.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: textColor,
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
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: primaryColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Obx(() => Text(
                          _getPlanPriceDisplay(plan),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: primaryColor,
                          ),
                        )),
                        Text(
                          '/${translate("Month")}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // VAT 별도 (오른쪽 정렬)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      translate('vat_excluded'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFB9B8BF),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 체크박스와 약관 동의
            Obx(() => GestureDetector(
                  onTap: () => isChecked.value = !isChecked.value,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StyledCheckbox(
                        value: isChecked.value,
                        onChanged: (v) => isChecked.value = v ?? false,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildPaymentAgreeText(),
                      ),
                    ],
                  ),
                )),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: StyledOutlinedButton(
                  label: translate('Cancel'),
                  onPressed: close,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Obx(() => StyledPrimaryButton(
                      label: translate('OK'),
                      onPressed:
                          isChecked.value && selectedProvider.value != null
                              ? () {
                                  close();
                                  _startGlobalPayment(
                                      productCode, selectedProvider.value!);
                                }
                              : null,
                    )),
              ),
            ],
          ),
        ],
        onCancel: close,
      );
    });
  }

  /// 해외 결제 시작 (PayPal/Paddle)
  Future<void> _startGlobalPayment(
      String productCode, PaymentProvider provider) async {
    debugPrint('[Payment] Global 결제 시작: $productCode, provider: $provider');

    if (!isPaymentServiceInitialized()) {
      _showPaymentError(translate('Bad Request'),
          details: 'PaymentService not initialized.');
      return;
    }

    _isPaymentLoading.value = true;
    _paymentProvider.value = provider;

    try {
      final paymentService = getPaymentService();
      String? paymentUrl;
      String providerCode = '';
      String? orderId; // 결제 시도 카운터용 orderId

      if (provider == PaymentProvider.paypal) {
        providerCode = 'PAYPAL_BILLING';
        final response =
            await paymentService.createPayPalSubscription(productCode);
        if (response.success && response.data != null) {
          paymentUrl = response.data!['href'] ??
              response.data!['approveUrl'] ??
              response.data!['url'];
          orderId = response.data!['subscriptionId']; // PayPal subscriptionId
        } else {
          _showPaymentError(translate('Bad Request'));
          return;
        }
      } else if (provider == PaymentProvider.paddle) {
        providerCode = 'PADDLE_BILLING';
        final response = await paymentService.createPaddleSubCheckout(productCode);
        if (response.success && response.data != null) {
          paymentUrl = response.data!['checkoutUrl'] ?? response.data!['url'];
          orderId = response.data!['ourOrderId'] ?? response.data!['orderId'] ?? response.data!['transactionId'];

          // PaddleLocalServer 시작 (폴링으로 결제 상태 확인)
          if (orderId != null && orderId.isNotEmpty) {
            await _paddleLocalServer.startServer(
              orderId: orderId,
              onResult: (result, details) {
                debugPrint('[Payment] Paddle polling result: $result, details: $details');
                if (result == PaddlePaymentResult.success) {
                  _onPaymentSuccess();
                } else {
                  _onPaymentCancel();
                }
              },
            );
            debugPrint('[Payment] PaddleLocalServer started for orderId: $orderId');
          }
        } else {
          _showPaymentError(translate('Bad Request'));
          return;
        }
      }

      // 결제 시도 카운터
      if (isAuthServiceInitialized() && providerCode.isNotEmpty) {
        try {
          final authService = getAuthService();
          await authService.setCountPayClick(providerCode, productCode, orderId ?? productCode);
          debugPrint('[Payment] Payment attempt counted: $providerCode, $productCode, $orderId');
        } catch (e) {
          debugPrint('[Payment] setCountPayClick error: $e');
        }
      }

      if (paymentUrl != null && paymentUrl.isNotEmpty) {
        _paymentUrl.value = paymentUrl;
        _currentView.value = MyPageView.paymentWebView;
      } else {
        _showPaymentError(translate('Bad Request'),
            details: 'Payment URL not found.');
      }
    } catch (e) {
      debugPrint('[Payment] Global payment error: $e');
      _showPaymentError(translate('Bad Request'), details: e.toString());
    } finally {
      _isPaymentLoading.value = false;
    }
  }

  /// Welcome 빌링 결제 시작
  /// HTML form을 생성하여 WebView에서 POST 전송
  Future<void> _startWelcomePayment(String productCode) async {
    debugPrint('[Payment] Welcome 결제 시작: $productCode');

    // 서비스 초기화 확인
    if (!isPaymentServiceInitialized()) {
      _showPaymentError(translate('Bad Request'),
          details: 'PaymentService가 초기화되지 않았습니다.');
      return;
    }

    _isPaymentLoading.value = true;
    _paymentProvider.value = PaymentProvider.welcome;

    try {
      final paymentService = getPaymentService();

      // 서버에서 빌링 파라미터 발급 요청
      final response = await paymentService.createWelcomeBilling(productCode);

      if (!response.success || response.data == null) {
        _showPaymentError(translate('Bad Request'),
            details: 'API 응답 실패: ${response.rawBody}');
        return;
      }

      final data = response.data!;
      final actionUrl = data['actionUrl'];

      if (actionUrl == null || actionUrl.toString().isEmpty) {
        _showPaymentError(translate('Bad Request'),
            details: 'actionUrl이 없습니다.');
        return;
      }

      debugPrint('[Payment] Welcome actionUrl: $actionUrl');

      // fields 추출 (API 응답 구조: result.fields)
      final fields = data['fields'] as Map<String, dynamic>? ?? data;

      // 주문 ID 저장 (있으면)
      _paymentOrderId.value = data['orderId'] ?? fields['P_OID'];

      // 결제 시도 카운터
      if (isAuthServiceInitialized()) {
        try {
          final authService = getAuthService();
          final orderId = _paymentOrderId.value ?? productCode;
          await authService.setCountPayClick('WELCOME_BILLING', productCode, orderId);
          debugPrint('[Payment] Payment attempt counted: WELCOME_BILLING, $productCode, $orderId');
        } catch (e) {
          debugPrint('[Payment] setCountPayClick error: $e');
        }
      }

      // HTML form 생성
      final htmlContent =
          _buildWelcomeBillingHtml(actionUrl.toString(), fields);

      // WebView로 결제창 열기 (HTML 사용)
      _paymentUrl.value = null; // URL 초기화
      _paymentHtml.value = htmlContent;
      _currentView.value = MyPageView.paymentWebView;
    } catch (e) {
      _showPaymentError('결제 오류: $e');
    } finally {
      _isPaymentLoading.value = false;
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

  /// 결제 에러 표시 (다이얼로그로 상세 내용 표시)
  void _showPaymentError(String message, {String? details}) {
    _resetPaymentState();

    // 항상 상세 다이얼로그 표시 (디버깅용)
    gFFI.dialogManager.show(
      (setState, close, context) => CustomAlertDialog(
        title: Text(translate('Payment error')),
        content: SizedBox(
          width: 500,
          height: 300,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text('Details:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    details ?? '(no details)',
                    style:
                        const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          dialogButton(translate('OK'), onPressed: close),
        ],
        onSubmit: close,
      ),
    );
  }
}

/// Windows WebView2 위젯 (webview_windows 패키지 사용)
class _WindowsWebView extends StatefulWidget {
  final String? url;
  final String? htmlContent; // HTML 콘텐츠 (Welcome 결제용)
  final Function(String)? onUrlChanged;
  final Function(bool)? onLoadingStateChanged;
  final Map<String, String>? cookies;
  final String? cookieDomain;

  const _WindowsWebView({
    this.url,
    this.htmlContent,
    this.onUrlChanged,
    this.onLoadingStateChanged,
    this.cookies,
    this.cookieDomain,
  });

  @override
  State<_WindowsWebView> createState() => _WindowsWebViewState();
}

class _WindowsWebViewState extends State<_WindowsWebView> {
  final wv.WebviewController _controller = wv.WebviewController();
  bool _isInitialized = false;
  bool _isLoading = true;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    try {
      debugPrint('[WindowsWebView] Initializing WebView2...');

      await _controller.initialize();
      debugPrint('[WindowsWebView] WebView2 initialized');

      // 팝업 허용 (select 드롭다운 등 네이티브 UI를 위해)
      await _controller.setPopupWindowPolicy(wv.WebviewPopupWindowPolicy.allow);

      // window.open 가로채기 및 select 드롭다운 커스텀 스크립트
      await _controller.addScriptToExecuteOnDocumentCreated('''
        (function() {
          var originalOpen = window.open;
          window.open = function(url, name, specs) {
            console.log('[Intercepted] window.open:', url);
            window.chrome.webview.postMessage(JSON.stringify({
              type: 'newWindow',
              url: url,
              name: name || ''
            }));
            return null;
          };

          // target="_blank" 링크도 처리
          document.addEventListener('click', function(e) {
            var target = e.target.closest('a');
            if (target && target.target === '_blank') {
              e.preventDefault();
              console.log('[Intercepted] _blank link:', target.href);
              window.chrome.webview.postMessage(JSON.stringify({
                type: 'newWindow',
                url: target.href
              }));
            }
          }, true);

          // Select 드롭다운 - 모달 방식
          var modalOverlay = null;
          var modalContent = null;
          var currentSelect = null;

          function createModal() {
            if (modalOverlay) return;

            modalOverlay = document.createElement('div');
            modalOverlay.id = 'select-modal-overlay';
            modalOverlay.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,0.5);z-index:999999;display:none;justify-content:center;align-items:center;';

            modalContent = document.createElement('div');
            modalContent.id = 'select-modal-content';
            modalContent.style.cssText = 'background:#fff;border-radius:8px;min-width:200px;max-width:300px;max-height:400px;overflow-y:auto;box-shadow:0 4px 20px rgba(0,0,0,0.3);';

            modalOverlay.appendChild(modalContent);
            document.body.appendChild(modalOverlay);

            modalOverlay.addEventListener('click', function(e) {
              if (e.target === modalOverlay) {
                modalOverlay.style.display = 'none';
              }
            });
          }

          function showSelectModal(select) {
            createModal();
            currentSelect = select;
            modalContent.innerHTML = '';

            // 제목
            var title = document.createElement('div');
            title.style.cssText = 'padding:15px;border-bottom:1px solid #eee;font-weight:bold;text-align:center;';
            title.textContent = '선택하세요';
            modalContent.appendChild(title);

            // 옵션들
            Array.from(select.options).forEach(function(opt, idx) {
              var optDiv = document.createElement('div');
              optDiv.textContent = opt.text || opt.value || '(빈 값)';
              optDiv.style.cssText = 'padding:12px 20px;cursor:pointer;border-bottom:1px solid #f0f0f0;';
              if (idx === select.selectedIndex) {
                optDiv.style.background = '#e3f2fd';
                optDiv.style.fontWeight = 'bold';
              }
              optDiv.onmouseover = function() { this.style.background = '#f5f5f5'; };
              optDiv.onmouseout = function() { this.style.background = idx === select.selectedIndex ? '#e3f2fd' : '#fff'; };
              optDiv.onclick = function() {
                select.selectedIndex = idx;
                select.dispatchEvent(new Event('change', {bubbles: true}));
                modalOverlay.style.display = 'none';
                updateSelectDisplay(select);
              };
              modalContent.appendChild(optDiv);
            });

            modalOverlay.style.display = 'flex';
          }

          function updateSelectDisplay(select) {
            var wrapper = select.nextElementSibling;
            if (wrapper && wrapper.classList.contains('custom-select-btn')) {
              var span = wrapper.querySelector('span');
              if (span) {
                span.textContent = select.options[select.selectedIndex]?.text || '선택';
              }
            }
          }

          function initCustomSelects() {
            var selects = document.querySelectorAll('select:not(.custom-select-initialized)');
            selects.forEach(function(select) {
              select.classList.add('custom-select-initialized');
              select.style.opacity = '0';
              select.style.position = 'absolute';
              select.style.pointerEvents = 'none';

              var btn = document.createElement('div');
              btn.className = 'custom-select-btn';
              btn.style.cssText = 'display:inline-flex;align-items:center;justify-content:space-between;padding:8px 12px;border:1px solid #ccc;border-radius:4px;background:#fff;cursor:pointer;min-width:80px;gap:8px;';
              btn.innerHTML = '<span>' + (select.options[select.selectedIndex]?.text || '선택') + '</span><span style="font-size:10px;">▼</span>';

              btn.onclick = function(e) {
                e.preventDefault();
                e.stopPropagation();
                showSelectModal(select);
              };

              select.parentNode.insertBefore(btn, select.nextSibling);
            });
          }

          // DOM 로드 후 및 동적 변경 감지
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', initCustomSelects);
          } else {
            setTimeout(initCustomSelects, 500);
          }

          // MutationObserver로 동적으로 추가되는 select 감지
          var observer = new MutationObserver(function(mutations) {
            setTimeout(initCustomSelects, 100);
          });
          observer.observe(document.body || document.documentElement, {childList: true, subtree: true});
        })();
      ''');
      debugPrint('[WindowsWebView] Custom select script injected');

      // User-Agent 설정
      await _controller.setUserAgent(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');

      // 배경색 설정
      await _controller.setBackgroundColor(Colors.white);

      // JavaScript 메시지 수신 (newWindow 요청 포함)
      _controller.webMessage.listen((message) {
        debugPrint('[WindowsWebView] JS Message: $message');

        // newWindow 요청 처리
        try {
          final data = jsonDecode(message);
          if (data is Map && data['type'] == 'newWindow') {
            final url = data['url'] as String?;
            if (url != null && url.isNotEmpty) {
              debugPrint(
                  '[WindowsWebView] Opening popup URL in same view: $url');
              _controller.loadUrl(url);
            }
          }
        } catch (e) {
          // JSON 파싱 실패 시 일반 콘솔 메시지로 처리
        }
      });

      // URL 변경 리스너
      _controller.url.listen((url) {
        debugPrint('[WindowsWebView] URL changed: $url');
        widget.onUrlChanged?.call(url);
      });

      // 로딩 상태 리스너
      _controller.loadingState.listen((state) {
        final isLoading = state == wv.LoadingState.loading;
        if (mounted) {
          setState(() => _isLoading = isLoading);
        }
        widget.onLoadingStateChanged?.call(isLoading);
      });

      // 초기 콘텐츠 로드 (HTML 또는 URL)
      if (widget.htmlContent != null && widget.htmlContent!.isNotEmpty) {
        debugPrint('[WindowsWebView] Loading HTML content');
        // HTML 콘텐츠를 data URI로 변환
        final encodedHtml = Uri.encodeComponent(widget.htmlContent!);
        final dataUri = 'data:text/html;charset=utf-8,$encodedHtml';
        await _controller.loadUrl(dataUri);
      } else if (widget.url != null && widget.url!.isNotEmpty) {
        // 쿠키가 있으면 대상 도메인에 먼저 쿠키 설정 후 URL 로드
        if (widget.cookies != null && widget.cookies!.isNotEmpty) {
          debugPrint('[WindowsWebView] Setting ${widget.cookies!.length} cookies before loading URL');
          final uri = Uri.parse(widget.url!);
          final originUrl = '${uri.scheme}://${uri.host}/';

          // 대상 도메인으로 먼저 이동 (쿠키 도메인 설정을 위해)
          await _controller.loadUrl(originUrl);
          await Future.delayed(const Duration(milliseconds: 1000));

          // JavaScript로 쿠키 설정
          for (final entry in widget.cookies!.entries) {
            final cookieStr = '${entry.key}=${entry.value}; path=/';
            await _controller.executeScript('document.cookie = "$cookieStr";');
            debugPrint('[WindowsWebView] Cookie set: ${entry.key}');
          }

          // 쿠키 설정 후 실제 URL 로드
          debugPrint('[WindowsWebView] Cookies set, loading URL: ${widget.url}');
          await _controller.loadUrl(widget.url!);
        } else {
          debugPrint('[WindowsWebView] Loading URL: ${widget.url}');
          await _controller.loadUrl(widget.url!);
        }
      }

      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e, stackTrace) {
      debugPrint('[WindowsWebView] Init error: $e');
      debugPrint('[WindowsWebView] Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _initError = e.toString();
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant _WindowsWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isInitialized) {
      // HTML 콘텐츠 변경 감지
      if (oldWidget.htmlContent != widget.htmlContent &&
          widget.htmlContent != null &&
          widget.htmlContent!.isNotEmpty) {
        debugPrint('[WindowsWebView] HTML content updated');
        final encodedHtml = Uri.encodeComponent(widget.htmlContent!);
        final dataUri = 'data:text/html;charset=utf-8,$encodedHtml';
        _controller.loadUrl(dataUri);
      }
      // URL 변경 감지
      else if (oldWidget.url != widget.url &&
          widget.url != null &&
          widget.url!.isNotEmpty) {
        debugPrint('[WindowsWebView] URL updated, loading: ${widget.url}');
        _controller.loadUrl(widget.url!);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'WebView2 초기화 실패',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _initError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'WebView2 Runtime이 설치되어 있는지 확인하세요.\nhttps://developer.microsoft.com/en-us/microsoft-edge/webview2/',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _initError = null;
                });
                _initWebView();
              },
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('WebView2 초기화 중...'),
          ],
        ),
      );
    }

    return Stack(
      children: [
        wv.Webview(_controller),
        if (_isLoading)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              backgroundColor: Colors.grey[200],
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
            ),
          ),
      ],
    );
  }
}

/// macOS/Linux WebView 위젯 (flutter_inappwebview 패키지 사용)
class _InAppWebViewWidget extends StatefulWidget {
  final String? url;
  final String? htmlContent;
  final Function(String)? onUrlChanged;
  final Function(bool)? onLoadingStateChanged;
  final Map<String, String>? cookies;
  final String? cookieDomain;

  const _InAppWebViewWidget({
    this.url,
    this.htmlContent,
    this.onUrlChanged,
    this.onLoadingStateChanged,
    this.cookies,
    this.cookieDomain,
  });

  @override
  State<_InAppWebViewWidget> createState() => _InAppWebViewWidgetState();
}

class _InAppWebViewWidgetState extends State<_InAppWebViewWidget> {
  iaw.InAppWebViewController? _controller;
  bool _isLoading = true;

  @override
  void didUpdateWidget(covariant _InAppWebViewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller != null) {
      if (oldWidget.htmlContent != widget.htmlContent &&
          widget.htmlContent != null &&
          widget.htmlContent!.isNotEmpty) {
        _controller!.loadData(
          data: widget.htmlContent!,
          mimeType: 'text/html',
          encoding: 'utf-8',
        );
      } else if (oldWidget.url != widget.url &&
          widget.url != null &&
          widget.url!.isNotEmpty) {
        _controller!.loadUrl(
            urlRequest: iaw.URLRequest(url: iaw.WebUri(widget.url!)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        iaw.InAppWebView(
          initialUrlRequest:
              widget.htmlContent == null && widget.url != null
                  ? iaw.URLRequest(url: iaw.WebUri(widget.url!))
                  : null,
          initialData: widget.htmlContent != null
              ? iaw.InAppWebViewInitialData(
                  data: widget.htmlContent!,
                  mimeType: 'text/html',
                  encoding: 'utf-8',
                )
              : null,
          initialSettings: iaw.InAppWebViewSettings(
            useShouldOverrideUrlLoading: true,
            javaScriptEnabled: true,
            domStorageEnabled: true,
            supportMultipleWindows: true,
            javaScriptCanOpenWindowsAutomatically: true,
          ),
          onWebViewCreated: (controller) async {
            _controller = controller;
            // 쿠키 설정
            if (widget.cookies != null &&
                widget.cookies!.isNotEmpty &&
                widget.url != null) {
              final cookieMgr = iaw.CookieManager.instance();
              for (final entry in widget.cookies!.entries) {
                await cookieMgr.setCookie(
                  url: iaw.WebUri(widget.url!),
                  name: entry.key,
                  value: entry.value,
                );
              }
              controller.loadUrl(
                  urlRequest: iaw.URLRequest(url: iaw.WebUri(widget.url!)));
            }
          },
          onLoadStart: (controller, url) {
            if (mounted) setState(() => _isLoading = true);
            widget.onLoadingStateChanged?.call(true);
          },
          onLoadStop: (controller, url) {
            if (mounted) setState(() => _isLoading = false);
            widget.onLoadingStateChanged?.call(false);
          },
          onUpdateVisitedHistory: (controller, url, androidIsReload) {
            if (url != null) {
              widget.onUrlChanged?.call(url.toString());
            }
          },
          shouldOverrideUrlLoading:
              (controller, navigationAction) async {
            return iaw.NavigationActionPolicy.ALLOW;
          },
          onCreateWindow:
              (controller, createWindowAction) async {
            final url =
                createWindowAction.request.url?.toString();
            if (url != null && url.isNotEmpty) {
              _controller?.loadUrl(
                  urlRequest: iaw.URLRequest(url: iaw.WebUri(url)));
            }
            return false;
          },
        ),
        if (_isLoading)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF8B5CF6)),
            ),
          ),
      ],
    );
  }
}

/// 가격 포맷팅 (천 단위 콤마) - top-level
String _formatAddonPrice(int price) {
  return price.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (Match m) => '${m[1]},',
  );
}

/// 결제 약관 동의 텍스트 빌드 (top-level)
Widget _buildAddonPaymentAgreeText() {
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
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => launchUrlString('https://onedesk.co.kr/refund'),
              child: Text(linkText, style: const TextStyle(fontSize: 14, color: linkColor)),
            ),
          ),
        ),
        if (afterLink.isNotEmpty) TextSpan(text: afterLink),
      ],
    ),
  );
}

/// 기기 추가 결제 다이얼로그 (desktop_home_page 등에서 호출)
Future<void> showDesktopAddonSessionDialog() async {
  // 지역 확인
  bool isKorea = false;
  // TODO: 테스트용 하드코딩 - 나중에 복원 필요
  // if (isAuthServiceInitialized()) {
  //   try {
  //     isKorea = await getAuthService().checkIsKorea();
  //   } catch (_) {}
  // }

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

  if (isKorea) {
    _showAddonWelcomeDialogStandalone(krwUnitPrice);
  } else {
    _showAddonGlobalDialogStandalone(usdUnitPrice);
  }
}

/// 기기 추가 - 한국 결제 다이얼로그 (standalone)
void _showAddonWelcomeDialogStandalone(int krwUnitPrice) {
  final isChecked = false.obs;
  final addonCount = 1.obs;

  const primaryColor = Color(0xFF5F71FF);
  const textColor = Color(0xFF454447);
  const cardBgColor = Color(0xFFF7F7F7);

  gFFI.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(
        translate('Add number of session cconnections'),
        style: MyTheme.dialogTitleStyle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            translate('Add number of session cconnections Pre'),
            style: const TextStyle(fontSize: 14, color: textColor),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBgColor,
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
                Obx(() => Row(
                  children: [
                    GestureDetector(
                      onTap: () { if (addonCount.value > 1) addonCount.value--; },
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFDEDEE2)),
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
                          border: Border.all(color: const Color(0xFFDEDEE2)),
                        ),
                        child: Center(
                          child: Text('${addonCount.value}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => addonCount.value++,
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFDEDEE2)),
                        ),
                        child: const Center(child: Text('+', style: TextStyle(fontSize: 20, color: textColor))),
                      ),
                    ),
                  ],
                )),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Obx(() => Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(translate('total_payment'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: primaryColor)),
                      const SizedBox(width: 8),
                      Text('${_formatAddonPrice(krwUnitPrice * addonCount.value)}${translate("Won")}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: primaryColor)),
                      Text('/${translate("Month")}', style: const TextStyle(fontSize: 14, color: textColor)),
                    ],
                  )),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(translate('vat_excluded'), style: const TextStyle(fontSize: 12, color: Color(0xFFB9B8BF))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Obx(() => GestureDetector(
            onTap: () => isChecked.value = !isChecked.value,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StyledCheckbox(value: isChecked.value, onChanged: (v) => isChecked.value = v ?? false),
                const SizedBox(width: 8),
                Expanded(child: _buildAddonPaymentAgreeText()),
              ],
            ),
          )),
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(child: StyledOutlinedButton(label: translate('Cancel'), onPressed: close)),
            const SizedBox(width: 12),
            Expanded(
              child: Obx(() => StyledPrimaryButton(
                label: translate('OK'),
                onPressed: isChecked.value ? () {
                  close();
                  _startAddonWelcomePayment(krwUnitPrice, addonCount.value);
                } : null,
              )),
            ),
          ],
        ),
      ],
      onCancel: close,
    );
  });
}

/// 기기 추가 Welcome 일반결제 시작
Future<void> _startAddonWelcomePayment(int unitPrice, int count) async {
  debugPrint('[AddonPayment] Welcome 결제 시작: unitPrice=$unitPrice, count=$count');

  if (!isPaymentServiceInitialized()) {
    debugPrint('[AddonPayment] PaymentService not initialized');
    return;
  }

  try {
    final paymentService = getPaymentService();
    final response = await paymentService.createWelcomeOrder(unitPrice, count);

    if (!response.success || response.data == null) {
      debugPrint('[AddonPayment] 주문 생성 실패: ${response.message}');
      gFFI.dialogManager.show((setState, close, context) {
        return CustomAlertDialog(
          title: Text(translate('Payment error')),
          content: Text(translate('Bad Request')),
          actions: [dialogButton(translate('OK'), onPressed: close)],
          onSubmit: close,
        );
      });
      return;
    }

    final data = response.data!;
    debugPrint('[AddonPayment] 주문 생성 성공: $data');

    // Web Standard HTML 생성
    final htmlContent = _buildAddonWelcomeStdPayHtml(data);

    // MyPage의 WebView로 결제창 열기
    // DesktopTabPage에서 MyPage 탭을 열고 WebView 모드로 전환
    try {
      DesktopTabController tabController = Get.find<DesktopTabController>();

      // 기존 마이페이지 탭이 있으면 제거
      final existingIndex = tabController.state.value.tabs.indexWhere(
        (t) => t.key == 'my-page' || t.key == 'addon-payment',
      );
      if (existingIndex != -1) {
        tabController.closeBy(tabController.state.value.tabs[existingIndex].key);
      }

      // 새 탭으로 WebView 열기
      tabController.add(TabInfo(
        key: 'addon-payment',
        label: translate('Add number of session cconnections'),
        selectedIcon: Icons.payment,
        unselectedIcon: Icons.payment,
        page: _AddonPaymentWebView(htmlContent: htmlContent),
      ));
    } catch (e) {
      debugPrint('[AddonPayment] Tab 열기 실패: $e');
    }
  } catch (e) {
    debugPrint('[AddonPayment] 결제 오류: $e');
  }
}

/// 애드온 Web Standard 결제 HTML 생성
String _buildAddonWelcomeStdPayHtml(Map<String, dynamic> data) {
  final version = data['version'] ?? '1.0';
  final mid = data['mid'] ?? '';
  final oid = data['oid'] ?? '';
  final goodname = data['goodname'] ?? '';
  final price = data['price'] ?? '';
  final currency = data['currency'] ?? 'WON';
  final buyername = data['buyername'] ?? '';
  final buyertel = data['buyertel'] ?? '';
  final buyeremail = data['buyeremail'] ?? '';
  final timestamp = data['timestamp'] ?? '';
  final signature = data['signature'] ?? '';
  final returnUrl = data['returnUrl'] ?? '';
  final closeUrl = data['closeUrl'] ?? '';
  final mKey = data['mKey'] ?? '';
  final gopaymethod = data['gopaymethod'] ?? 'Card';
  final charset = data['charset'] ?? 'UTF-8';
  final payViewType = data['payViewType'] ?? 'overlay';

  return '''
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>결제 처리 중...</title>
  <script language="javascript" type="text/javascript"
    src="https://stdpay.paywelcome.co.kr/stdjs/INIStdPay.js"
    charset="UTF-8"></script>
  <style>
    body {
      display: flex; justify-content: center; align-items: center;
      height: 100vh; margin: 0; background-color: #f5f5f5;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    }
    .loading { text-align: center; }
    .spinner {
      width: 50px; height: 50px;
      border: 3px solid #e0e0e0; border-top: 3px solid #5F71FF;
      border-radius: 50%; animation: spin 1s linear infinite;
      margin: 0 auto 20px;
    }
    @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
    .text { color: #666; font-size: 16px; }
  </style>
</head>
<body>
  <div class="loading">
    <div class="spinner"></div>
    <p class="text">결제 페이지로 이동 중...</p>
  </div>

  <form id="SendPayForm_id" name="SendPayForm_name" method="POST">
    <input type="hidden" name="version" value="$version" />
    <input type="hidden" name="mid" value="$mid" />
    <input type="hidden" name="oid" value="$oid" />
    <input type="hidden" name="goodname" value="$goodname" />
    <input type="hidden" name="price" value="$price" />
    <input type="hidden" name="currency" value="$currency" />
    <input type="hidden" name="buyername" value="$buyername" />
    <input type="hidden" name="buyertel" value="$buyertel" />
    <input type="hidden" name="buyeremail" value="$buyeremail" />
    <input type="hidden" name="timestamp" value="$timestamp" />
    <input type="hidden" name="signature" value="$signature" />
    <input type="hidden" name="returnUrl" value="$returnUrl" />
    <input type="hidden" name="closeUrl" value="$closeUrl" />
    <input type="hidden" name="mKey" value="$mKey" />
    <input type="hidden" name="gopaymethod" value="$gopaymethod" />
    <input type="hidden" name="charset" value="$charset" />
    <input type="hidden" name="payViewType" value="$payViewType" />
  </form>

  <script>
    window.onload = function() {
      setTimeout(function() {
        try {
          INIStdPay.pay('SendPayForm_id');
        } catch(e) {
          document.querySelector('.text').textContent = '결제 모듈 로딩 실패: ' + e.message;
        }
      }, 1000);
    };
  </script>
</body>
</html>
''';
}

/// 애드온 결제 WebView 위젯
class _AddonPaymentWebView extends StatefulWidget {
  final String htmlContent;
  const _AddonPaymentWebView({required this.htmlContent});

  @override
  State<_AddonPaymentWebView> createState() => _AddonPaymentWebViewState();
}

class _AddonPaymentWebViewState extends State<_AddonPaymentWebView> {
  late final iaw.InAppWebViewController? _controller;

  @override
  Widget build(BuildContext context) {
    return iaw.InAppWebView(
      initialData: iaw.InAppWebViewInitialData(
        data: widget.htmlContent,
        mimeType: 'text/html',
        encoding: 'utf-8',
      ),
      initialSettings: iaw.InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        allowsInlineMediaPlayback: true,
        mixedContentMode: iaw.MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
      },
      onLoadStop: (controller, url) {
        debugPrint('[AddonPaymentWebView] onLoadStop: $url');
        // 결제 완료/취소/실패 URL 감지
        final urlStr = url?.toString() ?? '';
        if (urlStr.contains('/success') || urlStr.contains('/close') || urlStr.contains('/cancel') || urlStr.contains('/fail')) {
          debugPrint('[AddonPaymentWebView] 결제 결과 감지: $urlStr');
          // 탭 닫기
          try {
            final tabController = Get.find<DesktopTabController>();
            tabController.closeBy('addon-payment');
          } catch (_) {}
        }
      },
    );
  }
}

/// 기기 추가 - 해외 결제 다이얼로그 (standalone)
void _showAddonGlobalDialogStandalone(double usdUnitPrice) {
  final isChecked = false.obs;
  final addonCount = 1.obs;
  final selectedProvider = Rxn<PaymentProvider>();

  const primaryColor = Color(0xFF5F71FF);
  const textColor = Color(0xFF454447);
  const cardBgColor = Color(0xFFF7F7F7);
  const sectionTitleColor = Color(0xFF1A191C);

  gFFI.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(
        translate('Add number of session cconnections'),
        style: MyTheme.dialogTitleStyle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(translate('payment_method'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: sectionTitleColor)),
          const SizedBox(height: 8),
          Text(translate('payment_method_select'), style: const TextStyle(fontSize: 14, color: textColor)),
          const SizedBox(height: 16),
          Obx(() => Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => selectedProvider.value = PaymentProvider.paypal,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: selectedProvider.value == PaymentProvider.paypal ? const Color(0xFFEFF1FF) : cardBgColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selectedProvider.value == PaymentProvider.paypal ? primaryColor : cardBgColor,
                        width: selectedProvider.value == PaymentProvider.paypal ? 2 : 1,
                      ),
                    ),
                    child: Center(child: Image.asset('assets/icons/paypal.png', height: 24)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => selectedProvider.value = PaymentProvider.paddle,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: selectedProvider.value == PaymentProvider.paddle ? const Color(0xFFEFF1FF) : cardBgColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selectedProvider.value == PaymentProvider.paddle ? primaryColor : cardBgColor,
                        width: selectedProvider.value == PaymentProvider.paddle ? 2 : 1,
                      ),
                    ),
                    child: Center(child: Image.asset('assets/icons/paddle.png', height: 24)),
                  ),
                ),
              ),
            ],
          )),
          const SizedBox(height: 24),
          Text(translate('order_summary_title'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: sectionTitleColor)),
          const SizedBox(height: 8),
          Text(translate('Add number of session cconnections Pre'), style: const TextStyle(fontSize: 14, color: textColor)),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(translate('Add number of session cconnections'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
                const SizedBox(height: 16),
                Obx(() => Row(
                  children: [
                    GestureDetector(
                      onTap: () { if (addonCount.value > 1) addonCount.value--; },
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFDEDEE2))),
                        child: const Center(child: Text('−', style: TextStyle(fontSize: 20, color: textColor))),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 40,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFDEDEE2))),
                        child: Center(child: Text('${addonCount.value}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor))),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => addonCount.value++,
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFDEDEE2))),
                        child: const Center(child: Text('+', style: TextStyle(fontSize: 20, color: textColor))),
                      ),
                    ),
                  ],
                )),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Obx(() => Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(translate('total_payment'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: primaryColor)),
                      const SizedBox(width: 8),
                      Text('\$${(usdUnitPrice * addonCount.value).toStringAsFixed(0)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: primaryColor)),
                      Text('/${translate("Month")}', style: const TextStyle(fontSize: 14, color: textColor)),
                    ],
                  )),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(translate('vat_excluded'), style: const TextStyle(fontSize: 12, color: Color(0xFFB9B8BF))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Obx(() => GestureDetector(
            onTap: () => isChecked.value = !isChecked.value,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StyledCheckbox(value: isChecked.value, onChanged: (v) => isChecked.value = v ?? false),
                const SizedBox(width: 8),
                Expanded(child: _buildAddonPaymentAgreeText()),
              ],
            ),
          )),
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(child: StyledOutlinedButton(label: translate('Cancel'), onPressed: close)),
            const SizedBox(width: 12),
            Expanded(
              child: Obx(() => StyledPrimaryButton(
                label: translate('OK'),
                onPressed: isChecked.value && selectedProvider.value != null
                    ? () { close(); /* TODO: 해외 결제 시작 */ }
                    : null,
              )),
            ),
          ],
        ),
      ],
      onCancel: close,
    );
  });
}
