import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/pages/server_page.dart';
import 'package:flutter_hbb/mobile/pages/settings_page.dart';
import 'package:flutter_hbb/mobile/pages/my_page.dart';
import 'package:flutter_hbb/mobile/pages/plan_selection_page.dart';
import 'package:flutter_hbb/mobile/pages/mobile_security_settings_page.dart';
import 'package:flutter_hbb/web/settings_page.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import '../../common.dart';
import '../../common/widgets/dialog.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';
import '../../models/state_model.dart';
import 'connection_page.dart';

abstract class PageShape extends Widget {
  final String title = "";
  final Widget icon = Icon(null);
  final List<Widget> appBarActions = [];
}

/// 하단 네비게이션 탭 정보
class _NavItem {
  final String iconPath;
  final String label;
  final Widget Function() pageBuilder;

  const _NavItem({
    required this.iconPath,
    required this.label,
    required this.pageBuilder,
  });
}

class HomePage extends StatefulWidget {
  static final homeKey = GlobalKey<HomePageState>();

  HomePage() : super(key: homeKey);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  var _selectedIndex = 0;
  int get selectedIndex => _selectedIndex;

  // 커스텀 네비게이션 색상
  static const Color _selectedColor = Color(0xFF5F71FF);
  static const Color _unselectedColor = Color(0xFF8F8E95);

  // 네비게이션 아이템 (3개: 홈, 화면공유, 마이페이지)
  late final List<_NavItem> _navItems;

  // 기존 PageShape 호환용
  final List<PageShape> _pages = [];
  bool get isChatPageCurrentTab => false;

  void refreshPages() {
    setState(() {
      initPages();
    });
  }

  @override
  void initState() {
    super.initState();
    initPages();
    _initNavItems();
  }

  /// Get appBarActions for current page
  List<Widget> _getAppBarActions() {
    // ServerPage의 경우에만 appBarActions 반환
    if (_selectedIndex == 1 && !Platform.isIOS) {
      return ServerPage().appBarActions;
    }
    return [];
  }

  void _initNavItems() {
    _navItems = [
      _NavItem(
        iconPath: 'assets/icons/mobile-menu-home.svg',
        label: translate('Home'),
        pageBuilder: () => ConnectionPage(appBarActions: []),
      ),
      if (!Platform.isIOS)
        _NavItem(
          iconPath: 'assets/icons/mobile-menu-screen-connection.svg',
          label: translate('Share screen'),
          pageBuilder: () => ServerPage(),
        ),
      _NavItem(
        iconPath: 'assets/icons/mobile-menu-mypage.svg',
        label: translate('My Page'),
        pageBuilder: () => MobileMyPage(),
      ),
    ];
  }

  void initPages() {
    _pages.clear();
    if (!bind.isIncomingOnly()) {
      _pages.add(ConnectionPage(
        appBarActions: [],
      ));
    }
    // 채팅, 설정 탭 숨김 - 채팅은 나중에 별도 구현, 설정은 상단 헤더에 있음
    if (isAndroid && !bind.isOutgoingOnly()) {
      _pages.add(ServerPage());
    }
    _pages.add(MobileMyPage());
  }

  @override
  Widget build(BuildContext context) {
    // 매 빌드마다 페이지를 새로 생성하여 회전 시 레이아웃이 올바르게 재계산되도록 함
    final currentPage = _navItems[_selectedIndex].pageBuilder();
    final isConnectionPage = currentPage is ConnectionPage;
    final isServerPage = currentPage is ServerPage;
    final isMyPage = currentPage is MobileMyPage;

    return WillPopScope(
        onWillPop: () async {
          if (_selectedIndex != 0) {
            setState(() {
              _selectedIndex = 0;
            });
          } else {
            return true;
          }
          return false;
        },
        child: Scaffold(
          backgroundColor: isServerPage ? const Color(0xFFFEFEFE) : null,
          appBar: isConnectionPage
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(60),
                  child: _buildCustomHeader(context),
                )
              : isServerPage
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(56),
                      child: _buildServerPageHeader(context),
                    )
                  : isMyPage
                      ? null
                      : AppBar(
                          centerTitle: true,
                          title: Text(_navItems[_selectedIndex].label),
                          actions: _getAppBarActions(),
                        ),
          bottomNavigationBar: _buildCustomBottomNav(),
          body: isConnectionPage
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    _buildWelcomeMessage(),
                    const SizedBox(height: 20),
                    Expanded(child: currentPage),
                  ],
                )
              : isMyPage
                  ? SafeArea(child: currentPage)
                  : currentPage,
        ));
  }

  /// 커스텀 하단 네비게이션 바
  Widget _buildCustomBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: List.generate(_navItems.length, (index) {
              final isSelected = _selectedIndex == index;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 아이콘
                      SvgPicture.asset(
                        _navItems[index].iconPath,
                        width: 24,
                        height: 24,
                        colorFilter: ColorFilter.mode(
                          isSelected ? _selectedColor : _unselectedColor,
                          BlendMode.srcIn,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 라벨
                      Text(
                        _navItems[index].label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: isSelected ? _selectedColor : _unselectedColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 하단 인디케이터 바
                      Container(
                        height: 3,
                        width: 40,
                        decoration: BoxDecoration(
                          color: isSelected ? _selectedColor : Colors.transparent,
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  /// 환영 메시지 위젯
  Widget _buildWelcomeMessage() {
    return Obx(() {
      final userName = gFFI.userModel.userName.value;
      final isEmail = userName.contains('@');
      final displayName = (userName.isEmpty || isEmail) ? '홍길동' : userName;

      return Padding(
        padding: const EdgeInsets.only(left: 20),
        child: Text(
          '$displayName ${translate('Dear\nWelcome.')}',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            height: 1.4,
          ),
        ),
      );
    });
  }

  /// 화면 공유 페이지 헤더
  Widget _buildServerPageHeader(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 56,
        color: const Color(0xFFFEFEFE),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(width: 24), // 왼쪽 여백 (아이콘 크기만큼)
            // 가운데: 제목
            Text(
              translate("Screen Share"),
              style: const TextStyle(
                color: Color(0xFF454447),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            // 오른쪽: 보안 설정 아이콘
            GestureDetector(
              onTap: () {
                _showSecuritySettings(context);
              },
              child: SvgPicture.asset(
                'assets/icons/mobile-security-setting.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(
                  Color(0xFF8F8E95),
                  BlendMode.srcIn,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 보안 설정 페이지로 이동
  void _showSecuritySettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MobileSecuritySettingsPage(),
      ),
    );
  }

  /// 커스텀 헤더 (ConnectionPage용)
  Widget _buildCustomHeader(BuildContext context) {
    const primaryColor = Color(0xFF5F71FF);

    return SafeArea(
      bottom: false,
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 왼쪽: 로고
              SvgPicture.asset(
                'assets/icons/topbar-logo.svg',
                width: 34,
                height: 34,
                colorFilter:
                    const ColorFilter.mode(primaryColor, BlendMode.srcIn),
              ),
              // 오른쪽: 플랜 버튼 + 설정 버튼
              Row(
                children: [
                  // 플랜 버튼
                  Obx(() {
                    final planType =
                        gFFI.userModel.planType.value.toUpperCase();
                    final isFree = planType == 'FREE' || planType.isEmpty;

                    if (isFree) {
                      return GestureDetector(
                        onTap: () => _navigateToPlanSelection(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: const Color(0xFF7F8DFF), width: 1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            translate('Plan Upgrade'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF7F8DFF),
                            ),
                          ),
                        ),
                      );
                    } else {
                      return GestureDetector(
                        onTap: () => _navigateToPlanSelection(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF5F71FF), Color(0xFF4350B5)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _getPlanDisplayName(planType),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFFEFEFE),
                            ),
                          ),
                        ),
                      );
                    }
                  }),
                  const SizedBox(width: 12),
                  // 설정 버튼
                  GestureDetector(
                    onTap: () {
                      // 설정 페이지로 이동
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SettingsPage()),
                      );
                    },
                    child: SvgPicture.asset(
                      'assets/icons/left-bottom-setting.svg',
                      width: 20,
                      height: 20,
                      colorFilter: const ColorFilter.mode(
                        Color(0xFF8F8E95),
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 플랜 선택 페이지로 이동
  void _navigateToPlanSelection(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MobilePlanSelectionPage()),
    );
  }

  /// 플랜 표시 이름
  String _getPlanDisplayName(String planType) {
    switch (planType.toUpperCase()) {
      case 'FREE':
        return 'Free Plan';
      case 'SOLO':
        return 'Solo Plan';
      case 'PRO':
        return 'Pro Plan';
      case 'TEAM':
        return 'Team Plan';
      case 'BUSINESS':
        return 'Business Plan';
      default:
        return 'Free Plan';
    }
  }

  Widget appTitle() {
    final currentUser = gFFI.chatModel.currentUser;
    final currentKey = gFFI.chatModel.currentKey;
    if (isChatPageCurrentTab &&
        currentUser != null &&
        currentKey.peerId.isNotEmpty) {
      final connected =
          gFFI.serverModel.clients.any((e) => e.id == currentKey.connId);
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Tooltip(
            message: currentKey.isOut
                ? translate('Outgoing connection')
                : translate('Incoming connection'),
            child: Icon(
              currentKey.isOut
                  ? Icons.call_made_rounded
                  : Icons.call_received_rounded,
            ),
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "${currentUser.firstName}   ${currentUser.id}",
                  ),
                  if (connected)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.fromARGB(255, 133, 246, 199)),
                    ).marginSymmetric(horizontal: 2),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Text(bind.mainGetAppNameSync());
  }
}

class WebHomePage extends StatelessWidget {
  final connectionPage =
      ConnectionPage(appBarActions: <Widget>[const WebSettingsPage()]);

  @override
  Widget build(BuildContext context) {
    stateGlobal.isInMainPage = true;
    handleUnilink(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text("${bind.mainGetAppNameSync()} (Preview)"),
        actions: connectionPage.appBarActions,
      ),
      body: connectionPage,
    );
  }

  handleUnilink(BuildContext context) {
    if (webInitialLink.isEmpty) {
      return;
    }
    final link = webInitialLink;
    webInitialLink = '';
    final splitter = ["/#/", "/#", "#/", "#"];
    var fakelink = '';
    for (var s in splitter) {
      if (link.contains(s)) {
        var list = link.split(s);
        if (list.length < 2 || list[1].isEmpty) {
          return;
        }
        list.removeAt(0);
        fakelink = "onedesk://${list.join(s)}";
        break;
      }
    }
    if (fakelink.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(fakelink);
    if (uri == null) {
      return;
    }
    final args = urlLinkToCmdArgs(uri);
    if (args == null || args.isEmpty) {
      return;
    }
    bool isFileTransfer = false;
    bool isViewCamera = false;
    bool isTerminal = false;
    String? id;
    String? password;
    for (int i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--connect':
        case '--play':
          id = args[i + 1];
          i++;
          break;
        case '--file-transfer':
          isFileTransfer = true;
          id = args[i + 1];
          i++;
          break;
        case '--view-camera':
          isViewCamera = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal':
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal-admin':
          setEnvTerminalAdmin();
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--password':
          password = args[i + 1];
          i++;
          break;
        default:
          break;
      }
    }
    if (id != null) {
      connect(context, id,
          isFileTransfer: isFileTransfer,
          isViewCamera: isViewCamera,
          isTerminal: isTerminal,
          password: password);
    }
  }
}
