import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/my_page.dart';
import 'package:flutter_hbb/desktop/pages/access_list_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';
// import 'package:flutter/services.dart';

import '../../common/shared_state.dart';

class DesktopTabPage extends StatefulWidget {
  const DesktopTabPage({Key? key}) : super(key: key);

  @override
  State<DesktopTabPage> createState() => _DesktopTabPageState();

  /// 설정 탭 추가
  /// SVG 아이콘 사용 (toptab-setting.svg)
  static void onAddSetting(
      {SettingsTabKey initialPage = SettingsTabKey.general}) {
    try {
      DesktopTabController tabController = Get.find<DesktopTabController>();
      tabController.add(TabInfo(
          key: kTabLabelSettingPage,
          label: kTabLabelSettingPage,
          // SVG 아이콘으로 교체
          svgIconPath: 'assets/icons/toptab-setting.svg',
          page: DesktopSettingPage(
            key: const ValueKey(kTabLabelSettingPage),
            initialTabkey: initialPage,
          )));
    } catch (e) {
      debugPrintStack(label: '$e');
    }
  }

  /// 마이페이지 탭 추가
  /// 사용자 프로필 및 설정 페이지
  static void onAddMyPage() {
    try {
      DesktopTabController tabController = Get.find<DesktopTabController>();
      tabController.add(TabInfo(
          key: kTabLabelMyPage,
          label: kTabLabelMyPage,
          // 사용자 아이콘 사용
          svgIconPath: 'assets/icons/left-bottom-userinfo.svg',
          page: const MyPage(
            key: ValueKey(kTabLabelMyPage),
          )));
    } catch (e) {
      debugPrintStack(label: '$e');
    }
  }

  /// 플랜 선택 탭 추가
  /// 홈 화면의 플랜 카드 클릭 시 호출
  static void onAddPlanSelection() {
    try {
      DesktopTabController tabController = Get.find<DesktopTabController>();
      // 플랜 선택 전용 탭 키
      const String planTabKey = 'Plan Selection';
      tabController.add(TabInfo(
          key: planTabKey,
          label: planTabKey,
          // 플랜 아이콘 사용
          svgIconPath: 'assets/icons/left-plancard-logo.svg',
          page: const MyPage(
            key: ValueKey(planTabKey),
            initialView: MyPageView.selectPlan,
          )));
    } catch (e) {
      debugPrintStack(label: '$e');
    }
  }

  /// 액세스 리스트 탭 추가
  /// 카메라 공유, 음성 채팅 등 연결 목록 표시
  static void onAddAccessList() {
    try {
      DesktopTabController tabController = Get.find<DesktopTabController>();
      tabController.add(TabInfo(
          key: kTabLabelAccessList,
          label: kTabLabelAccessList,
          // 카메라 아이콘 사용
          svgIconPath: 'assets/icons/camera.svg',
          page: const AccessListPage(
            key: ValueKey(kTabLabelAccessList),
          )));
    } catch (e) {
      debugPrintStack(label: '$e');
    }
  }
}

class _DesktopTabPageState extends State<DesktopTabPage> {
  final tabController = DesktopTabController(tabType: DesktopTabType.main);

  _DesktopTabPageState() {
    RemoteCountState.init();
    Get.put<DesktopTabController>(tabController);
    // 홈 탭 추가 - SVG 아이콘 사용 (toptab-home.svg)
    tabController.add(TabInfo(
        key: kTabLabelHomePage,
        label: kTabLabelHomePage,
        // SVG 아이콘으로 교체
        svgIconPath: 'assets/icons/toptab-home.svg',
        closable: false,
        page: DesktopHomePage(
          key: const ValueKey(kTabLabelHomePage),
        )));
    if (bind.isIncomingOnly()) {
      tabController.onSelected = (key) {
        if (key == kTabLabelHomePage) {
          windowManager.setSize(getIncomingOnlyHomeSize());
          setResizable(false);
        } else {
          windowManager.setSize(getIncomingOnlySettingsSize());
          setResizable(true);
        }
      };
    }
  }

  @override
  void initState() {
    super.initState();
    // HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  /*
  bool _handleKeyEvent(KeyEvent event) {
    if (!mouseIn && event is KeyDownEvent) {
      print('key down: ${event.logicalKey}');
      shouldBeBlocked(_block, canBeBlocked);
    }
    return false; // allow it to propagate
  }
  */

  @override
  void dispose() {
    // HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    Get.delete<DesktopTabController>();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabWidget = Container(
        child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: DesktopTab(
              controller: tabController,
              tail: const Offstage(
                offstage: true,
                child: SizedBox.shrink(),
              ),
            )));
    return isMacOS || kUseCompatibleUiMode
        ? tabWidget
        : Obx(
            () => DragToResizeArea(
              resizeEdgeSize: stateGlobal.resizeEdgeSize.value,
              enableResizeEdges: windowManagerEnableResizeEdges,
              child: tabWidget,
            ),
          );
  }
}
