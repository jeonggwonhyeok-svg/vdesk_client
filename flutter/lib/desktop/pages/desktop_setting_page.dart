import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/audio_input.dart';
import 'package:flutter_hbb/common/widgets/setting_widgets.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/mobile/widgets/dialog.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/printer_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/plugin/manager.dart';
import 'package:flutter_hbb/plugin/widgets/desktop_settings.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../common/widgets/dialog.dart';
import '../../common/widgets/login.dart';
import '../../common/widgets/content_card.dart';
import '../../common/widgets/styled_form_widgets.dart';
import '../../common/widgets/styled_text_field.dart';

// 설정 페이지 레이아웃 상수
const double _kCardFixedWidth = 540; // 카드 고정 너비
const double _kCardLeftMargin = 15; // 카드 좌측 마진
const double _kContentHMargin = 15; // 콘텐츠 수평 마진
const double _kContentHSubMargin = _kContentHMargin + 33;
const double _kListViewBottomMargin = 15;
const double _kContentFontSize = 16; // 콘텐츠 폰트 크기 (테마와 동일)

// 설정 페이지 테마 색상 (테마와 일치하는 색상 사용)
const Color _accentColor = Color(0xFF5F71FF); // 메인 색상 (테마 색상)
const Color _primaryColor = Color(0xFF5B7BF8); // 버튼 기본 색상
const Color _accentColorLighter = Color(0xFFEFF1FF); // 연한 보라색 (특수 섹션 배경)
const Color _cardBackgroundColor = Colors.white; // 카드 배경색
const String _kSettingPageControllerTag = 'settingPageController';
const String _kSettingPageTabKeyTag = 'settingPageTabKey';

/// 옵션 정보를 저장하는 클래스
class _OptionNotifierInfo {
  final ValueNotifier<bool> notifier;
  final String optionKey;
  final bool isServer;
  final bool reversed;

  _OptionNotifierInfo({
    required this.notifier,
    required this.optionKey,
    required this.isServer,
    required this.reversed,
  });

  /// 스토리지(파일)에서 현재 값 읽기 (캐시 우회)
  bool readFromStorage() {
    // 다른 프로세스(CM 창 등)에서 변경된 값을 읽기 위해 파일에서 직접 읽음
    return isServer
        ? mainGetBoolOptionSync(optionKey)
        : mainGetLocalBoolOptionFromFile(optionKey);
  }
}

/// 전역 옵션 ValueNotifier 저장소 (설정 동기화용)
final Map<String, _OptionNotifierInfo> _globalOptionNotifierMap = {};

/// 옵션의 ValueNotifier 가져오기 또는 생성
ValueNotifier<bool> _getOrCreateOptionNotifier(
    String notifierKey, String optionKey, bool isServer, bool reversed) {
  if (!_globalOptionNotifierMap.containsKey(notifierKey)) {
    final storageValue = isServer
        ? mainGetBoolOptionSync(optionKey)
        : mainGetLocalBoolOptionSync(optionKey);
    _globalOptionNotifierMap[notifierKey] = _OptionNotifierInfo(
      notifier: ValueNotifier<bool>(reversed ? !storageValue : storageValue),
      optionKey: optionKey,
      isServer: isServer,
      reversed: reversed,
    );
  }
  return _globalOptionNotifierMap[notifierKey]!.notifier;
}

/// 모든 옵션의 ValueNotifier를 스토리지에서 새로고침 (다른 창에서 변경된 경우)
/// 설정 페이지가 열릴 때 호출하여 CM 창 등 다른 창에서 변경된 옵션을 반영
void _refreshAllOptionNotifiersFromStorage() {
  for (final entry in _globalOptionNotifierMap.entries) {
    try {
      final info = entry.value;
      final storageValue = info.readFromStorage();
      final syncValue = info.reversed ? !storageValue : storageValue;
      if (info.notifier.value != syncValue) {
        info.notifier.value = syncValue;
      }
    } catch (e) {
      // 파일 읽기 실패 시 무시 (캐시 값 유지)
      continue;
    }
  }
}

/// 설정 탭 정보 클래스
/// SVG 아이콘 경로를 사용하여 탭을 표시
class _TabInfo {
  late final SettingsTabKey key; // 탭 키
  late final String label; // 탭 라벨
  late final String iconPath; // SVG 아이콘 경로
  _TabInfo(this.key, this.label, this.iconPath);
}

enum SettingsTabKey {
  general,
  safety,
  network,
  display,
  plugin,
  account,
  printer,
  about,
}

class DesktopSettingPage extends StatefulWidget {
  final SettingsTabKey initialTabkey;
  // 설정 탭 목록 (네트워크, 계정 탭 제거됨)
  static final List<SettingsTabKey> tabKeys = [
    SettingsTabKey.general,
    if (!isWeb &&
        !bind.isOutgoingOnly() &&
        !bind.isDisableSettings() &&
        bind.mainGetBuildinOption(key: kOptionHideSecuritySetting) != 'Y')
      SettingsTabKey.safety,
    // 네트워크 탭 제거됨
    // if (!bind.isDisableSettings() &&
    //     bind.mainGetBuildinOption(key: kOptionHideNetworkSetting) != 'Y')
    //   SettingsTabKey.network,
    if (!bind.isIncomingOnly()) SettingsTabKey.display,
    if (!isWeb && !bind.isIncomingOnly() && bind.pluginFeatureIsEnabled())
      SettingsTabKey.plugin,
    // 계정 탭 제거됨
    // if (!bind.isDisableAccount()) SettingsTabKey.account,
    if (isWindows &&
        bind.mainGetBuildinOption(key: kOptionHideRemotePrinterSetting) != 'Y')
      SettingsTabKey.printer,
    SettingsTabKey.about,
  ];

  DesktopSettingPage({Key? key, required this.initialTabkey}) : super(key: key);

  @override
  State<DesktopSettingPage> createState() =>
      _DesktopSettingPageState(initialTabkey);

  static void switch2page(SettingsTabKey page) {
    try {
      int index = tabKeys.indexOf(page);
      if (index == -1) {
        return;
      }
      if (Get.isRegistered<PageController>(tag: _kSettingPageControllerTag)) {
        DesktopTabPage.onAddSetting(initialPage: page);
        PageController controller =
            Get.find<PageController>(tag: _kSettingPageControllerTag);
        Rx<SettingsTabKey> selected =
            Get.find<Rx<SettingsTabKey>>(tag: _kSettingPageTabKeyTag);
        selected.value = page;
        controller.jumpToPage(index);
      } else {
        DesktopTabPage.onAddSetting(initialPage: page);
      }
    } catch (e) {
      debugPrintStack(label: '$e');
    }
  }
}

class _DesktopSettingPageState extends State<DesktopSettingPage>
    with
        TickerProviderStateMixin,
        AutomaticKeepAliveClientMixin,
        WidgetsBindingObserver {
  late PageController controller;
  late Rx<SettingsTabKey> selectedTab;

  @override
  bool get wantKeepAlive => true;

  final RxBool _block = false.obs;
  final RxBool _canBeBlocked = false.obs;
  Timer? _videoConnTimer;

  _DesktopSettingPageState(SettingsTabKey initialTabkey) {
    var initialIndex = DesktopSettingPage.tabKeys.indexOf(initialTabkey);
    if (initialIndex == -1) {
      initialIndex = 0;
    }
    selectedTab = DesktopSettingPage.tabKeys[initialIndex].obs;
    Get.put<Rx<SettingsTabKey>>(selectedTab, tag: _kSettingPageTabKeyTag);
    controller = PageController(initialPage: initialIndex);
    Get.put<PageController>(controller, tag: _kSettingPageControllerTag);
    controller.addListener(() {
      if (controller.page != null) {
        int page = controller.page!.toInt();
        if (page < DesktopSettingPage.tabKeys.length) {
          selectedTab.value = DesktopSettingPage.tabKeys[page];
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
      // 앱이 포커스 받을 때 다른 창에서 변경된 옵션 값 새로고침
      _refreshAllOptionNotifiersFromStorage();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 설정 페이지 열릴 때 다른 창(CM 등)에서 변경된 옵션 값을 파일에서 읽어옴
    _refreshAllOptionNotifiersFromStorage();
    _videoConnTimer =
        periodic_immediate(Duration(milliseconds: 1000), () async {
      if (!mounted) {
        return;
      }
      _canBeBlocked.value = await canBeBlocked();
    });
  }

  @override
  void dispose() {
    super.dispose();
    Get.delete<PageController>(tag: _kSettingPageControllerTag);
    Get.delete<RxInt>(tag: _kSettingPageTabKeyTag);
    WidgetsBinding.instance.removeObserver(this);
    _videoConnTimer?.cancel();
  }

  /// 설정 탭 목록 생성
  /// 각 탭에 해당하는 SVG 아이콘 경로 지정
  List<_TabInfo> _settingTabs() {
    final List<_TabInfo> settingTabs = <_TabInfo>[];
    for (final tab in DesktopSettingPage.tabKeys) {
      switch (tab) {
        case SettingsTabKey.general:
          // 일반 설정 - setting-left-normal.svg 아이콘 사용
          settingTabs.add(
              _TabInfo(tab, 'General', 'assets/icons/setting-left-normal.svg'));
          break;
        case SettingsTabKey.safety:
          // 보안 설정 - setting-left-security.svg 아이콘 사용
          settingTabs.add(_TabInfo(
              tab, 'Security', 'assets/icons/setting-left-security.svg'));
          break;
        case SettingsTabKey.network:
          // 네트워크 설정 - 일반 아이콘 재사용
          settingTabs.add(
              _TabInfo(tab, 'Network', 'assets/icons/setting-left-normal.svg'));
          break;
        case SettingsTabKey.display:
          // 디스플레이 설정 - setting-left-display.svg 아이콘 사용
          settingTabs.add(_TabInfo(
              tab, 'Display', 'assets/icons/setting-left-display.svg'));
          break;
        case SettingsTabKey.plugin:
          // 플러그인 설정 - 일반 아이콘 재사용
          settingTabs.add(
              _TabInfo(tab, 'Plugin', 'assets/icons/setting-left-normal.svg'));
          break;
        case SettingsTabKey.account:
          // 계정 설정 - 일반 아이콘 재사용
          settingTabs.add(
              _TabInfo(tab, 'Account', 'assets/icons/setting-left-normal.svg'));
          break;
        case SettingsTabKey.printer:
          // 프린터 설정 - setting-left-printer.svg 아이콘 사용
          settingTabs.add(_TabInfo(
              tab, 'Printer', 'assets/icons/setting-left-printer.svg'));
          break;
        case SettingsTabKey.about:
          // 정보 설정 - setting-left-Info.svg 아이콘 사용
          settingTabs.add(
              _TabInfo(tab, 'About', 'assets/icons/setting-left-Info.svg'));
          break;
      }
    }
    return settingTabs;
  }

  List<Widget> _children() {
    final children = List<Widget>.empty(growable: true);
    for (final tab in DesktopSettingPage.tabKeys) {
      switch (tab) {
        case SettingsTabKey.general:
          children.add(const _General());
          break;
        case SettingsTabKey.safety:
          children.add(const _Safety());
          break;
        case SettingsTabKey.network:
          children.add(const _Network());
          break;
        case SettingsTabKey.display:
          children.add(const _Display());
          break;
        case SettingsTabKey.plugin:
          children.add(const _Plugin());
          break;
        case SettingsTabKey.account:
          children.add(const _Account());
          break;
        case SettingsTabKey.printer:
          children.add(const _Printer());
          break;
        case SettingsTabKey.about:
          children.add(const _About());
          break;
      }
    }
    return children;
  }

  Widget _buildBlock({required List<Widget> children}) {
    // check both mouseMoveTime and videoConnCount
    return Obx(() {
      final videoConnBlock =
          _canBeBlocked.value && stateGlobal.videoConnCount > 0;
      return Stack(children: [
        buildRemoteBlock(
          block: _block,
          mask: false,
          use: canBeBlocked,
          child: preventMouseKeyBuilder(
            child: Row(children: children),
            block: videoConnBlock,
          ),
        ),
        if (videoConnBlock)
          Container(
            color: Colors.black.withOpacity(0.5),
          )
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = MyTheme.settingTab(context);
    return Scaffold(
      backgroundColor: theme.contentBackgroundColor,
      body: _buildBlock(
        children: <Widget>[
          // 좌측 사이드바 (탭 메뉴) - 헤더 제거됨
          Container(
            width: theme.sidebarWidth,
            color: theme.sidebarBackgroundColor,
            padding: const EdgeInsets.only(top: 16), // 상단 여백
            child: Column(
              children: [
                Flexible(child: _listView(tabs: _settingTabs())),
              ],
            ),
          ),
          // 사이드바와 콘텐츠 구분선
          Container(
            width: 1,
            color: const Color(0xFFE2E8F0), // 연한 구분선
          ),
          // 우측 콘텐츠 영역
          Expanded(
            child: Container(
              color: theme.contentBackgroundColor,
              child: PageView(
                controller: controller,
                physics: NeverScrollableScrollPhysics(),
                children: _children(),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _listView({required List<_TabInfo> tabs}) {
    final scrollController = ScrollController();
    return ListView(
      controller: scrollController,
      children: tabs.map((tab) => _listItem(tab: tab)).toList(),
    );
  }

  /// 개별 탭 아이템 위젯
  /// 선택된 탭은 테마 색상으로 표시
  Widget _listItem({required _TabInfo tab}) {
    return Obx(() {
      bool selected = tab.key == selectedTab.value;
      final theme = MyTheme.settingTab(context);
      return Container(
        width: theme.sidebarWidth,
        height: theme.height,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(theme.borderRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(theme.borderRadius),
            onTap: () {
              if (selectedTab.value != tab.key) {
                int index = DesktopSettingPage.tabKeys.indexOf(tab.key);
                if (index == -1) {
                  return;
                }
                controller.jumpToPage(index);
              }
              selectedTab.value = tab.key;
            },
            child: Container(
              decoration: BoxDecoration(
                // 선택된 탭은 테마 배경색
                color: selected
                    ? theme.selectedBackgroundColor
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(theme.borderRadius),
              ),
              padding:
                  EdgeInsets.symmetric(horizontal: theme.horizontalPadding),
              child: Row(children: [
                // SVG 아이콘 표시 (20x20 고정)
                SvgPicture.asset(
                  tab.iconPath,
                  width: 20,
                  height: 20,
                  colorFilter: ColorFilter.mode(
                    // 테마에서 아이콘 색상 가져오기
                    selected
                        ? theme.selectedIconColor
                        : theme.unselectedIconColor,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: 12),
                // 탭 라벨
                Expanded(
                  child: Text(
                    translate(tab.label),
                    style: TextStyle(
                      // 테마에서 텍스트 색상 가져오기
                      color: selected
                          ? theme.selectedTextColor
                          : theme.unselectedTextColor,
                      fontWeight: FontWeight.w500, // 보통 두께
                      fontSize: theme.fontSize,
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    });
  }
}

//#region pages

class _General extends StatefulWidget {
  const _General({Key? key}) : super(key: key);

  @override
  State<_General> createState() => _GeneralState();
}

class _GeneralState extends State<_General> with WidgetsBindingObserver {
  final RxBool serviceStop =
      isWeb ? RxBool(false) : Get.find<RxBool>(tag: 'stop-service');
  RxBool serviceBtnEnabled = true.obs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 앱이 다시 활성화되면 새로고침
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(
      controller: scrollController,
      children: [
        _Card(title: 'Language', children: [language()]),
        if (!isWeb) hwcodec(),
        if (!isWeb) audio(context),
        if (!isWeb) record(context),
        if (!isWeb) screenshot(context),
        if (!isWeb) WaylandCard(),
        other()
      ],
    ).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget other() {
    final showAutoUpdate =
        isWindows && bind.mainIsInstalled() && !bind.isCustomClient();
    final children = <Widget>[
      if (!isWeb && !bind.isIncomingOnly())
        _OptionCheckBox(context, 'Confirm before closing multiple tabs',
            kOptionEnableConfirmClosingTabs,
            isServer: false),
      _OptionCheckBox(context, 'Adaptive bitrate', kOptionEnableAbr),
      if (!isWeb) wallpaper(),
      if (!isWeb && !bind.isIncomingOnly()) ...[
        _OptionCheckBox(
          context,
          'Open connection in new tab',
          kOptionOpenNewConnInTabs,
          isServer: false,
        ),
        // though this is related to GUI, but opengl problem affects all users, so put in config rather than local
        if (isLinux)
          Tooltip(
            message: translate('software_render_tip'),
            child: _OptionCheckBox(
              context,
              "Always use software rendering",
              kOptionAllowAlwaysSoftwareRender,
            ),
          ),
        if (!isWeb)
          Tooltip(
            message: translate('texture_render_tip'),
            child: _OptionCheckBox(
              context,
              "Use texture rendering",
              kOptionTextureRender,
              optGetter: bind.mainGetUseTextureRender,
              optSetter: (k, v) async =>
                  await bind.mainSetLocalOption(key: k, value: v ? 'Y' : 'N'),
            ),
          ),
        if (isWindows)
          Tooltip(
            message: translate('d3d_render_tip'),
            child: _OptionCheckBox(
              context,
              "Use D3D rendering",
              kOptionD3DRender,
              isServer: false,
            ),
          ),
        if (!isWeb && !bind.isCustomClient())
          _OptionCheckBox(
            context,
            'Check for software update on startup',
            kOptionEnableCheckUpdate,
            isServer: false,
          ),
        if (showAutoUpdate)
          _OptionCheckBox(
            context,
            'Auto update',
            kOptionAllowAutoUpdate,
            isServer: true,
          ),
        if (isWindows && !bind.isOutgoingOnly())
          _OptionCheckBox(
            context,
            'Capture screen using DirectX',
            kOptionDirectxCapture,
          ),
        if (!bind.isIncomingOnly()) ...[
          _OptionCheckBox(
            context,
            'Enable UDP hole punching',
            kOptionEnableUdpPunch,
            isServer: false,
          ),
          _OptionCheckBox(
            context,
            'Enable IPv6 P2P connection',
            kOptionEnableIpv6Punch,
            isServer: false,
          ),
        ],
      ],
    ];
    if (!isWeb && bind.mainShowOption(key: kOptionAllowLinuxHeadless)) {
      children.add(_OptionCheckBox(
          context, 'Allow linux headless', kOptionAllowLinuxHeadless));
    }
    return _Card(title: 'Other', children: children);
  }

  Widget wallpaper() {
    if (bind.isOutgoingOnly()) {
      return const SizedBox.shrink();
    }

    return futureBuilder(future: () async {
      final support = await bind.mainSupportRemoveWallpaper();
      return support;
    }(), hasData: (data) {
      if (data is bool && data == true) {
        bool value = mainGetBoolOptionSync(kOptionAllowRemoveWallpaper);
        return Row(
          children: [
            Expanded(
              child: _OptionCheckBox(
                context,
                'Remove wallpaper during incoming sessions',
                kOptionAllowRemoveWallpaper,
                update: (bool v) {
                  setState(() {});
                },
              ),
            ),
            if (value)
              _CountDownButton(
                text: 'Test',
                second: 5,
                onPressed: () {
                  bind.mainTestWallpaper(second: 5);
                },
              ),
          ],
        );
      }

      return const SizedBox.shrink();
    });
  }

  Widget hwcodec() {
    final hwcodec = bind.mainHasHwcodec();
    final vram = bind.mainHasVram();
    return Offstage(
      offstage: !(hwcodec || vram),
      child: _Card(title: 'Hardware Codec', children: [
        _OptionCheckBox(
          context,
          'Enable hardware codec',
          kOptionEnableHwcodec,
          update: (bool v) {
            if (v) {
              bind.mainCheckHwcodec();
            }
          },
        )
      ]),
    );
  }

  Widget audio(BuildContext context) {
    if (bind.isOutgoingOnly()) {
      return const Offstage();
    }

    builder(devices, currentDevice, setDevice) {
      final child = ComboBox(
        keys: devices,
        values: devices,
        initialKey: currentDevice,
        onChanged: (key) async {
          setDevice(key);
          setState(() {});
        },
      );
      return _Card(title: 'Audio Input Device', children: [child]);
    }

    return AudioInput(builder: builder, isCm: false, isVoiceCall: false);
  }

  /// 녹화 설정 위젯
  /// 체크박스 + 수신/발신 경로를 하나의 보라색 컨테이너에
  Widget record(BuildContext context) {
    return futureBuilder(future: () async {
      String incoming_dir = bind.mainVideoSaveDirectory(root: true);
      String outgoing_dir = bind.mainVideoSaveDirectory(root: false);
      bool incoming_dir_exists = await Directory(incoming_dir).exists();
      bool outgoing_dir_exists = await Directory(outgoing_dir).exists();
      return {
        'incoming_dir': incoming_dir,
        'outgoing_dir': outgoing_dir,
        'incoming_dir_exists': incoming_dir_exists,
        'outgoing_dir_exists': outgoing_dir_exists,
      };
    }(), hasData: (data) {
      Map<String, dynamic> map = data as Map<String, dynamic>;
      String incoming_dir = map['incoming_dir']!;
      String outgoing_dir = map['outgoing_dir']!;
      bool incoming_dir_exists = map['incoming_dir_exists']!;
      bool outgoing_dir_exists = map['outgoing_dir_exists']!;
      return _Card(title: 'Recording', children: [
        // 체크박스 영역 (흰 배경)
        if (!bind.isOutgoingOnly())
          _OptionCheckBox(context, 'Automatically record incoming sessions',
              kOptionAllowAutoRecordIncoming),
        if (!bind.isIncomingOnly())
          _OptionCheckBox(context, 'Automatically record outgoing sessions',
              kOptionAllowAutoRecordOutgoing,
              isServer: false),
        // 녹화 경로 컨테이너 (보라색 배경)
        Builder(builder: (context) {
          final cardTheme = Theme.of(context).extension<ContentCardTheme>() ??
              ContentCardTheme.light;
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            decoration: BoxDecoration(
              color: _accentColorLighter,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 녹화 경로 타이틀
                Text(
                  translate('Recording Path'),
                  style: TextStyle(
                    color: _primaryColor,
                    fontSize: cardTheme.titleFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                // 수신 경로
                if (!bind.isOutgoingOnly())
                  Row(
                    children: [
                      Text(
                        '${translate("Incoming")}:',
                        style: const TextStyle(
                          color: Color(0xFF475569),
                          fontSize: _kContentFontSize,
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                            onTap: incoming_dir_exists
                                ? () => launchUrl(Uri.file(incoming_dir))
                                : null,
                            child: Text(
                              incoming_dir,
                              softWrap: true,
                              style: TextStyle(
                                color: incoming_dir_exists
                                    ? _accentColor
                                    : const Color(0xFF64748B),
                                decoration: incoming_dir_exists
                                    ? TextDecoration.underline
                                    : null,
                                fontSize: _kContentFontSize,
                              ),
                            )).marginOnly(left: 10),
                      ),
                      StyledCompactButton(
                        label: translate('Change'),
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 20),
                        onPressed: isOptionFixed(
                                kOptionVideoSaveDirectoryIncoming)
                            ? null
                            : () async {
                                String? initialDirectory;
                                if (await Directory.fromUri(
                                        Uri.directory(incoming_dir))
                                    .exists()) {
                                  initialDirectory = incoming_dir;
                                }
                                String? selectedDirectory =
                                    await FilePicker.platform.getDirectoryPath(
                                        initialDirectory: initialDirectory);
                                if (selectedDirectory != null) {
                                  await bind.mainSetLocalOption(
                                      key: kOptionVideoSaveDirectoryIncoming,
                                      value: selectedDirectory);
                                  setState(() {});
                                }
                              },
                        fontSize: _kContentFontSize,
                      ).marginOnly(left: 10),
                    ],
                  ),
                // 수신/발신 사이 간격
                if (!bind.isOutgoingOnly() && !bind.isIncomingOnly())
                  const SizedBox(height: 12),
                // 발신 경로
                if (!bind.isIncomingOnly())
                  Row(
                    children: [
                      Text(
                        '${translate("Outgoing")}:',
                        style: const TextStyle(
                          color: Color(0xFF475569),
                          fontSize: _kContentFontSize,
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                            onTap: outgoing_dir_exists
                                ? () => launchUrl(Uri.file(outgoing_dir))
                                : null,
                            child: Text(
                              outgoing_dir,
                              softWrap: true,
                              style: TextStyle(
                                color: outgoing_dir_exists
                                    ? _accentColor
                                    : const Color(0xFF64748B),
                                decoration: outgoing_dir_exists
                                    ? TextDecoration.underline
                                    : null,
                                fontSize: _kContentFontSize,
                              ),
                            )).marginOnly(left: 10),
                      ),
                      StyledCompactButton(
                        label: translate('Change'),
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 20),
                        onPressed: isOptionFixed(
                                kOptionVideoSaveDirectoryOutgoing)
                            ? null
                            : () async {
                                String? initialDirectory;
                                if (await Directory.fromUri(
                                        Uri.directory(outgoing_dir))
                                    .exists()) {
                                  initialDirectory = outgoing_dir;
                                }
                                String? selectedDirectory =
                                    await FilePicker.platform.getDirectoryPath(
                                        initialDirectory: initialDirectory);
                                if (selectedDirectory != null) {
                                  await bind.mainSetLocalOption(
                                      key: kOptionVideoSaveDirectoryOutgoing,
                                      value: selectedDirectory);
                                  setState(() {});
                                }
                              },
                        fontSize: _kContentFontSize,
                      ).marginOnly(left: 10),
                    ],
                  ),
              ],
            ),
          );
        }),
      ]);
    });
  }

  /// 스크린샷 설정 위젯
  Widget screenshot(BuildContext context) {
    return futureBuilder(future: () async {
      String screenshot_dir = bind.mainScreenshotSaveDirectory();
      bool screenshot_dir_exists = await Directory(screenshot_dir).exists();
      return {
        'screenshot_dir': screenshot_dir,
        'screenshot_dir_exists': screenshot_dir_exists,
      };
    }(), hasData: (data) {
      Map<String, dynamic> map = data as Map<String, dynamic>;
      String screenshot_dir = map['screenshot_dir']!;
      bool screenshot_dir_exists = map['screenshot_dir_exists']!;
      return _Card(title: 'Screenshot', children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _accentColorLighter,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Text(
                '${translate("Directory")}:',
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: _kContentFontSize,
                ),
              ),
              Expanded(
                child: GestureDetector(
                    onTap: screenshot_dir_exists
                        ? () => launchUrl(Uri.file(screenshot_dir))
                        : null,
                    child: Text(
                      screenshot_dir,
                      softWrap: true,
                      style: TextStyle(
                        color: screenshot_dir_exists
                            ? _accentColor
                            : const Color(0xFF64748B),
                        decoration: screenshot_dir_exists
                            ? TextDecoration.underline
                            : null,
                        fontSize: _kContentFontSize,
                      ),
                    )).marginOnly(left: 10),
              ),
              StyledCompactButton(
                label: translate('Change'),
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                onPressed: isOptionFixed(kOptionScreenshotSaveDirectory)
                    ? null
                    : () async {
                        String? initialDirectory;
                        if (await Directory.fromUri(
                                Uri.directory(screenshot_dir))
                            .exists()) {
                          initialDirectory = screenshot_dir;
                        }
                        String? selectedDirectory = await FilePicker.platform
                            .getDirectoryPath(
                                initialDirectory: initialDirectory);
                        if (selectedDirectory != null) {
                          await bind.mainSetLocalOption(
                              key: kOptionScreenshotSaveDirectory,
                              value: selectedDirectory);
                          setState(() {});
                        }
                      },
                fontSize: _kContentFontSize,
              ).marginOnly(left: 10),
            ],
          ),
        ),
      ]);
    });
  }

  Widget language() {
    return futureBuilder(future: () async {
      String langs = await bind.mainGetLangs();
      return {'langs': langs};
    }(), hasData: (res) {
      Map<String, String> data = res as Map<String, String>;
      List<dynamic> langsList = jsonDecode(data['langs']!);
      Map<String, String> langsMap = {for (var v in langsList) v[0]: v[1]};
      List<String> keys = langsMap.keys.toList();
      List<String> values = langsMap.values.toList();
      String currentKey = bind.mainGetLocalOption(key: kCommConfKeyLang);
      if (currentKey.isEmpty || currentKey == 'default' || !keys.contains(currentKey)) {
        currentKey = 'ko';
      }
      final isOptFixed = isOptionFixed(kCommConfKeyLang);
      return ComboBox(
        keys: keys,
        values: values,
        initialKey: currentKey,
        onChanged: (key) async {
          await bind.mainSetLocalOption(key: kCommConfKeyLang, value: key);
          if (isWeb) reloadCurrentWindow();
          if (!isWeb) reloadAllWindows();
          if (!isWeb) bind.mainChangeLanguage(lang: key);
        },
        enabled: !isOptFixed,
      );
    });
  }
}

enum _AccessMode {
  custom,
  full,
  view,
}

class _Safety extends StatefulWidget {
  const _Safety({Key? key}) : super(key: key);

  @override
  State<_Safety> createState() => _SafetyState();
}

class _SafetyState extends State<_Safety> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  bool locked = bind.mainIsInstalled();
  final scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
        controller: scrollController,
        child: Column(
          children: [
            _lock(locked, 'Unlock Security Settings', () {
              locked = false;
              setState(() => {});
            }),
            preventMouseKeyBuilder(
              block: locked,
              child: Column(children: [
                permissions(context),
                approveMode(context),
                password(context),
                more(context),
              ]),
            ),
          ],
        )).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget tfa() {
    bool enabled = !locked;
    // Simple temp wrapper for PR check
    tmpWrapper() {
      RxBool has2fa = bind.mainHasValid2FaSync().obs;
      RxBool hasBot = bind.mainHasValidBotSync().obs;
      update() async {
        has2fa.value = bind.mainHasValid2FaSync();
        setState(() {});
      }

      onChanged(bool? checked) async {
        if (checked == false) {
          CommonConfirmDialog(
              gFFI.dialogManager, translate('cancel-2fa-confirm-tip'), () {
            change2fa(callback: update);
          });
        } else {
          change2fa(callback: update);
        }
      }

      final tfa = GestureDetector(
        child: InkWell(
          child: Obx(() => Row(
                children: [
                  StyledCheckbox(
                    value: has2fa.value,
                    onChanged: enabled ? onChanged : null,
                    enabled: enabled,
                    accentColor: _accentColor,
                  ).marginOnly(right: 5),
                  Expanded(
                      child: Text(
                    translate('enable-2fa-title'),
                    style:
                        TextStyle(color: disabledTextColor(context, enabled)),
                  ))
                ],
              )),
        ),
        onTap: () {
          onChanged(!has2fa.value);
        },
      );
      if (!has2fa.value) {
        return tfa;
      }
      updateBot() async {
        hasBot.value = bind.mainHasValidBotSync();
        setState(() {});
      }

      onChangedBot(bool? checked) async {
        if (checked == false) {
          CommonConfirmDialog(
              gFFI.dialogManager, translate('cancel-bot-confirm-tip'), () {
            changeBot(callback: updateBot);
          });
        } else {
          changeBot(callback: updateBot);
        }
      }

      final bot = GestureDetector(
        child: Tooltip(
          waitDuration: Duration(milliseconds: 300),
          message: translate("enable-bot-tip"),
          child: InkWell(
              child: Obx(() => Row(
                    children: [
                      StyledCheckbox(
                        value: hasBot.value,
                        onChanged: enabled ? onChangedBot : null,
                        enabled: enabled,
                        accentColor: _accentColor,
                      ).marginOnly(right: 5),
                      Expanded(
                          child: Text(
                        translate('Telegram bot'),
                        style: TextStyle(
                            color: disabledTextColor(context, enabled)),
                      ))
                    ],
                  ))),
        ),
        onTap: () {
          onChangedBot(!hasBot.value);
        },
      ).marginOnly(left: 30);

      final trust = Row(
        children: [
          Flexible(
            child: Tooltip(
              waitDuration: Duration(milliseconds: 300),
              message: translate("enable-trusted-devices-tip"),
              child: _OptionCheckBox(context, "Enable trusted devices",
                  kOptionEnableTrustedDevices,
                  enabled: !locked, update: (v) {
                setState(() {});
              }),
            ),
          ),
          if (mainGetBoolOptionSync(kOptionEnableTrustedDevices))
            StyledCompactButton(
              label: translate('Manage trusted devices'),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
              onPressed: locked ? null : () => manageTrustedDeviceDialog(),
              height: 38,
              fontSize: _kContentFontSize,
            )
        ],
      ).marginOnly(left: 30);

      return Column(
        children: [
          tfa.marginOnly(bottom: 8),
          bot.marginOnly(bottom: 8),
          trust,
        ],
      );
    }

    return tmpWrapper();
  }

  Widget changeId() {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(builder: ((context, model, child) {
          return _Button('Change ID', changeIdDialog,
              enabled: !locked && model.connectStatus > 0);
        })));
  }

  Widget permissions(context) {
    bool enabled = !locked;
    // Simple temp wrapper for PR check
    tmpWrapper() {
      String accessMode = bind.mainGetOptionSync(key: kOptionAccessMode);
      _AccessMode mode;
      if (accessMode == 'full') {
        mode = _AccessMode.full;
      } else if (accessMode == 'view') {
        mode = _AccessMode.view;
      } else {
        mode = _AccessMode.custom;
      }
      String initialKey;
      bool? fakeValue;
      switch (mode) {
        case _AccessMode.custom:
          initialKey = '';
          fakeValue = null;
          break;
        case _AccessMode.full:
          initialKey = 'full';
          fakeValue = true;
          break;
        case _AccessMode.view:
          initialKey = 'view';
          fakeValue = false;
          break;
      }

      return _Card(title: 'Permissions', children: [
        ComboBox(
            keys: [
              defaultOptionAccessMode,
              'full',
              'view',
            ],
            values: [
              translate('Custom'),
              translate('Full Access'),
              translate('Screen Share'),
            ],
            enabled: enabled && !isOptionFixed(kOptionAccessMode),
            initialKey: initialKey,
            onChanged: (mode) async {
              await bind.mainSetOption(key: kOptionAccessMode, value: mode);
              setState(() {});
            }),
        _OptionCheckBox(context, 'Enable keyboard/mouse', kOptionEnableKeyboard,
            enabled: enabled, fakeValue: fakeValue),
        if (isWindows)
          _OptionCheckBox(
              context, 'Enable remote printer', kOptionEnableRemotePrinter,
              enabled: enabled, fakeValue: fakeValue),
        _OptionCheckBox(context, 'Enable clipboard', kOptionEnableClipboard,
            enabled: enabled, fakeValue: fakeValue),
        _OptionCheckBox(
            context, 'Enable file transfer', kOptionEnableFileTransfer,
            enabled: enabled, fakeValue: fakeValue),
        _OptionCheckBox(context, 'Enable audio', kOptionEnableAudio,
            enabled: enabled, fakeValue: fakeValue),
        _OptionCheckBox(context, 'Enable camera', kOptionEnableCamera,
            enabled: enabled, fakeValue: fakeValue),
        _OptionCheckBox(
            context, 'Enable remote restart', kOptionEnableRemoteRestart,
            enabled: enabled, fakeValue: fakeValue),
        _OptionCheckBox(
            context, 'Enable recording session', kOptionEnableRecordSession,
            enabled: enabled, fakeValue: fakeValue),
        _OptionCheckBox(context, 'Enable remote configuration modification',
            kOptionAllowRemoteConfigModification,
            enabled: enabled, fakeValue: fakeValue),
      ]);
    }

    return tmpWrapper();
  }

  /// 액세스 수락 카드 (세션 수락 방법 선택)
  Widget approveMode(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(builder: ((context, model, child) {
          final modeKeys = <String>[
            'password',
            'click',
            defaultOptionApproveMode
          ];
          final modeValues = [
            translate('Accept sessions via password'),
            translate('Accept sessions via click'),
            translate('Accept sessions via both'),
          ];
          var modeInitialKey = model.approveMode;
          if (!modeKeys.contains(modeInitialKey)) {
            modeInitialKey = defaultOptionApproveMode;
          }
          final isApproveModeFixed = isOptionFixed(kOptionApproveMode);
          return _Card(title: 'Access Accept', children: [
            ComboBox(
              enabled: !locked && !isApproveModeFixed,
              keys: modeKeys,
              values: modeValues,
              initialKey: modeInitialKey,
              onChanged: (key) => model.setApproveMode(key),
            ),
          ]);
        })));
  }

  Widget password(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(builder: ((context, model, child) {
          // 비밀번호 모드가 click이면 비밀번호 카드 숨김
          final usePassword = model.approveMode != 'click';
          if (!usePassword) {
            return const SizedBox.shrink();
          }

          List<String> passwordKeys = [
            kUseTemporaryPassword,
            kUsePermanentPassword,
            kUseBothPasswords,
          ];
          List<String> passwordValues = [
            translate('Use one-time password'),
            translate('Use permanent password'),
            translate('Use both passwords'),
          ];
          bool tmpEnabled = model.verificationMethod != kUsePermanentPassword;
          bool permEnabled = model.verificationMethod != kUseTemporaryPassword;
          String currentValue =
              passwordValues[passwordKeys.indexOf(model.verificationMethod)];
          List<Widget> radios = passwordValues
              .map((value) => _Radio<String>(
                    context,
                    value: value,
                    groupValue: currentValue,
                    label: value,
                    onChanged: locked
                        ? null
                        : ((value) async {
                            callback() async {
                              await model.setVerificationMethod(
                                  passwordKeys[passwordValues.indexOf(value)]);
                              await model.updatePasswordModel();
                            }

                            if (value ==
                                    passwordValues[passwordKeys
                                        .indexOf(kUsePermanentPassword)] &&
                                (await bind.mainGetPermanentPassword())
                                    .isEmpty) {
                              setPasswordDialog(notEmptyCallback: callback);
                            } else {
                              await callback();
                            }
                          }),
                  ))
              .toList();

          var onChanged = tmpEnabled && !locked
              ? (value) {
                  if (value != null) {
                    () async {
                      await model.setTemporaryPasswordLength(value.toString());
                      await model.updatePasswordModel();
                    }();
                  }
                }
              : null;
          List<Widget> lengthRadios = ['6', '8', '10']
              .map((value) => GestureDetector(
                    child: Row(
                      children: [
                        StyledRadio<String>(
                          value: value,
                          groupValue: model.temporaryPasswordLength,
                          onChanged: onChanged,
                          enabled: onChanged != null,
                          accentColor: _accentColor,
                        ),
                        Text(
                          value,
                          style: TextStyle(
                              color: disabledTextColor(
                                  context, onChanged != null)),
                        ).marginOnly(left: 8),
                      ],
                    ).paddingOnly(right: 10),
                    onTap: () => onChanged?.call(value),
                  ))
              .toList();

          final isOptFixedNumOTP =
              isOptionFixed(kOptionAllowNumericOneTimePassword);
          final isNumOPTChangable = !isOptFixedNumOTP && tmpEnabled && !locked;

          // 일회용 비밀번호 옵션 카드 (배경색 #F7F7F7)
          final oneTimePasswordOptions = Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상단: 라벨 + 체크박스
                Row(
                  children: [
                    Text(
                      translate('One-time password length'),
                      style: TextStyle(
                          color: disabledTextColor(
                              context, tmpEnabled && !locked)),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: isNumOPTChangable
                          ? () => model.switchAllowNumericOneTimePassword()
                          : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StyledCheckbox(
                            value: model.allowNumericOneTimePassword,
                            onChanged: isNumOPTChangable
                                ? (bool? v) {
                                    model.switchAllowNumericOneTimePassword();
                                  }
                                : null,
                            enabled: isNumOPTChangable,
                            accentColor: _accentColor,
                          ).marginOnly(right: 5),
                          Text(
                            translate('Numeric one-time password'),
                            style: TextStyle(
                                color: disabledTextColor(
                                    context, isNumOPTChangable)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // 하단: 라디오 버튼
                const SizedBox(height: 8),
                Row(children: lengthRadios),
              ],
            ),
          );

          return _Card(title: 'Password', children: [
            radios[0],
            oneTimePasswordOptions,
            radios[1],
            _SubButton('Set permanent password', setPasswordDialog,
                permEnabled && !locked),
            radios[2],
          ]);
        })));
  }

  Widget more(BuildContext context) {
    bool enabled = !locked;
    return _Card(title: 'Security', children: [
      shareRdp(context, enabled),
      _OptionCheckBox(context, 'Deny LAN discovery', 'enable-lan-discovery',
          reverse: true, enabled: enabled),
      ...directIp(context),
      whitelist(),
      ...autoDisconnect(context),
      if (bind.mainIsInstalled())
        _OptionCheckBox(context, 'allow-only-conn-window-open-tip',
            'allow-only-conn-window-open',
            reverse: false, enabled: enabled),
      // if (bind.mainIsInstalled()) unlockPin()
    ]);
  }

  shareRdp(BuildContext context, bool enabled) {
    onChanged(bool b) async {
      await bind.mainSetShareRdp(enable: b);
      setState(() {});
    }

    bool value = bind.mainIsShareRdp();
    return Offstage(
      offstage: !(isWindows && bind.mainIsInstalled()),
      child: GestureDetector(
          child: Row(
            children: [
              StyledCheckbox(
                value: value,
                onChanged: enabled ? (_) => onChanged(!value) : null,
                enabled: enabled,
                accentColor: _accentColor,
              ).marginOnly(right: 5),
              Expanded(
                child: Text(translate('Enable RDP session sharing'),
                    style:
                        TextStyle(color: disabledTextColor(context, enabled))),
              )
            ],
          ),
          onTap: enabled ? () => onChanged(!value) : null),
    );
  }

  List<Widget> directIp(BuildContext context) {
    TextEditingController controller = TextEditingController();
    update(bool v) => setState(() {});
    RxBool applyEnabled = false.obs;
    return [
      _OptionCheckBox(context, 'Enable direct IP access', kOptionDirectServer,
          update: update, enabled: !locked),
      () {
        bool enabled = option2bool(kOptionDirectServer,
            bind.mainGetOptionSync(key: kOptionDirectServer));
        if (!enabled) return const SizedBox.shrink();
        applyEnabled.value = false;
        controller.text =
            bind.mainGetOptionSync(key: kOptionDirectAccessPort);
        final isOptFixed = isOptionFixed(kOptionDirectAccessPort);
        final isEnabled = enabled && !locked && !isOptFixed;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                translate('Port'),
                style: TextStyle(
                  color: disabledTextColor(context, isEnabled),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 234,
                    height: 40,
                    child: StyledTextField(
                      controller: controller,
                      enabled: isEnabled,
                      onChanged: (_) => applyEnabled.value = true,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(
                            r'^([0-9]|[1-9]\d|[1-9]\d{2}|[1-9]\d{3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$')),
                      ],
                      hintText: '21118',
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 0, horizontal: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Obx(() => StyledCompactButton(
                        label: translate('Apply'),
                        fillWidth: false,
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        onPressed: applyEnabled.value && isEnabled
                            ? () async {
                                applyEnabled.value = false;
                                await bind.mainSetOption(
                                    key: kOptionDirectAccessPort,
                                    value: controller.text);
                              }
                            : null,
                      )),
                ],
              ),
            ],
          ),
        );
      }(),
    ];
  }

  Widget whitelist() {
    bool enabled = !locked;
    // Simple temp wrapper for PR check
    tmpWrapper() {
      RxBool hasWhitelist = whitelistNotEmpty().obs;
      update() async {
        hasWhitelist.value = whitelistNotEmpty();
      }

      onChanged(bool? checked) async {
        changeWhiteList(callback: update);
      }

      final isOptFixed = isOptionFixed(kOptionWhitelist);
      final isEnabled = enabled && !isOptFixed;
      return MouseRegion(
        cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          child: Tooltip(
            message: translate('whitelist_tip'),
            child: Obx(() => Row(
                  children: [
                    StyledCheckbox(
                      value: hasWhitelist.value,
                      onChanged: isEnabled ? onChanged : null,
                      enabled: isEnabled,
                      accentColor: _accentColor,
                    ).marginOnly(right: 5),
                    Expanded(
                        child: Text(
                      translate('Use IP Whitelisting'),
                      style:
                          TextStyle(color: disabledTextColor(context, enabled)),
                    ))
                  ],
                )),
          ),
          onTap: isEnabled
              ? () {
                  onChanged(!hasWhitelist.value);
                }
              : null,
        ),
      );
    }

    return tmpWrapper();
  }

  Widget hide_cm(bool enabled) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(builder: (context, model, child) {
          final enableHideCm = model.approveMode == 'password' &&
              model.verificationMethod == kUsePermanentPassword;
          onHideCmChanged(bool? b) {
            if (b != null) {
              bind.mainSetOption(
                  key: 'allow-hide-cm', value: bool2option('allow-hide-cm', b));
            }
          }

          final isEnabled = enabled && enableHideCm;
          return Tooltip(
              message: enableHideCm ? "" : translate('hide_cm_tip'),
              child: MouseRegion(
                cursor: isEnabled
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: GestureDetector(
                  onTap:
                      isEnabled ? () => onHideCmChanged(!model.hideCm) : null,
                  child: Row(
                    children: [
                      StyledCheckbox(
                        value: model.hideCm,
                        onChanged: isEnabled ? onHideCmChanged : null,
                        enabled: isEnabled,
                        accentColor: _accentColor,
                      ).marginOnly(right: 5),
                      Expanded(
                        child: Text(
                          translate('Hide connection management window'),
                          style: TextStyle(
                              color: disabledTextColor(context, isEnabled)),
                        ),
                      ),
                    ],
                  ),
                ),
              ));
        }));
  }

  List<Widget> autoDisconnect(BuildContext context) {
    TextEditingController controller = TextEditingController();
    update(bool v) => setState(() {});
    RxBool applyEnabled = false.obs;
    return [
      _OptionCheckBox(
          context, 'auto_disconnect_option_tip', kOptionAllowAutoDisconnect,
          update: update, enabled: !locked),
      () {
        bool enabled = option2bool(kOptionAllowAutoDisconnect,
            bind.mainGetOptionSync(key: kOptionAllowAutoDisconnect));
        if (!enabled) return const SizedBox.shrink();
        applyEnabled.value = false;
        controller.text =
            bind.mainGetOptionSync(key: kOptionAutoDisconnectTimeout);
        final isOptFixed = isOptionFixed(kOptionAutoDisconnectTimeout);
        final isEnabled = enabled && !locked && !isOptFixed;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                translate('Timeout in minutes'),
                style: TextStyle(
                  color: disabledTextColor(context, isEnabled),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 234,
                    height: 40,
                    child: StyledTextField(
                      controller: controller,
                      enabled: isEnabled,
                      onChanged: (_) => applyEnabled.value = true,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(
                            r'^([0-9]|[1-9]\d|[1-9]\d{2}|[1-9]\d{3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$')),
                      ],
                      hintText: '10',
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 0, horizontal: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Obx(() => StyledCompactButton(
                        label: translate('Apply'),
                        fillWidth: false,
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        onPressed: applyEnabled.value && isEnabled
                            ? () async {
                                applyEnabled.value = false;
                                await bind.mainSetOption(
                                    key: kOptionAutoDisconnectTimeout,
                                    value: controller.text);
                              }
                            : null,
                      )),
                ],
              ),
            ],
          ),
        );
      }(),
    ];
  }

  Widget unlockPin() {
    bool enabled = !locked;
    RxString unlockPin = bind.mainGetUnlockPin().obs;
    update() async {
      unlockPin.value = bind.mainGetUnlockPin();
    }

    onChanged(bool? checked) async {
      changeUnlockPinDialog(unlockPin.value, update);
    }

    final isOptFixed = isOptionFixed(kOptionWhitelist);
    final isEnabled = enabled && !isOptFixed;
    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        child: Obx(() => Row(
              children: [
                StyledCheckbox(
                  value: unlockPin.isNotEmpty,
                  onChanged: isEnabled ? onChanged : null,
                  enabled: isEnabled,
                  accentColor: _accentColor,
                ).marginOnly(right: 5),
                Expanded(
                    child: Text(
                  translate('Unlock with PIN'),
                  style: TextStyle(color: disabledTextColor(context, enabled)),
                ))
              ],
            )),
        onTap: isEnabled
            ? () {
                onChanged(!unlockPin.isNotEmpty);
              }
            : null,
      ),
    );
  }
}

class _Network extends StatefulWidget {
  const _Network({Key? key}) : super(key: key);

  @override
  State<_Network> createState() => _NetworkState();
}

class _NetworkState extends State<_Network> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  bool locked = !isWeb && bind.mainIsInstalled();

  final scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(controller: scrollController, children: [
      _lock(locked, 'Unlock Network Settings', () {
        locked = false;
        setState(() => {});
      }),
      preventMouseKeyBuilder(
        block: locked,
        child: Column(children: [
          network(context),
        ]),
      ),
    ]).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget network(BuildContext context) {
    final hideServer =
        bind.mainGetBuildinOption(key: kOptionHideServerSetting) == 'Y';
    final hideProxy =
        isWeb || bind.mainGetBuildinOption(key: kOptionHideProxySetting) == 'Y';
    final hideWebSocket = isWeb ||
        bind.mainGetBuildinOption(key: kOptionHideWebSocketSetting) == 'Y';

    if (hideServer && hideProxy && hideWebSocket) {
      return Offstage();
    }

    // Helper function to create network setting ListTiles
    Widget listTile({
      required IconData icon,
      required String title,
      VoidCallback? onTap,
      Widget? trailing,
      bool showTooltip = false,
      String tooltipMessage = '',
    }) {
      final titleWidget = showTooltip
          ? Row(
              children: [
                Tooltip(
                  waitDuration: Duration(milliseconds: 1000),
                  message: translate(tooltipMessage),
                  child: Row(
                    children: [
                      Text(
                        translate(title),
                        style: TextStyle(fontSize: _kContentFontSize),
                      ),
                      SizedBox(width: 5),
                      Icon(
                        Icons.help_outline,
                        size: 14,
                        color: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.color
                            ?.withOpacity(0.7),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Text(
              translate(title),
              style: TextStyle(fontSize: _kContentFontSize),
            );

      return ListTile(
        leading: Icon(icon, color: _accentColor),
        title: titleWidget,
        enabled: !locked,
        onTap: onTap,
        trailing: trailing,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
        minLeadingWidth: 0,
        horizontalTitleGap: 10,
      );
    }

    Widget switchWidget(IconData icon, String title, String tooltipMessage,
            String optionKey) =>
        listTile(
          icon: icon,
          title: title,
          showTooltip: true,
          tooltipMessage: tooltipMessage,
          trailing: Switch(
            value: mainGetBoolOptionSync(optionKey),
            onChanged: locked || isOptionFixed(optionKey)
                ? null
                : (value) {
                    mainSetBoolOption(optionKey, value);
                    setState(() {});
                  },
          ),
        );

    final outgoingOnly = bind.isOutgoingOnly();

    final divider = const Divider(height: 1, indent: 16, endIndent: 16);
    return _Card(
      title: 'Network',
      children: [
        Container(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!hideServer)
                listTile(
                  icon: Icons.dns_outlined,
                  title: 'ID/Relay Server',
                  onTap: () => showServerSettings(gFFI.dialogManager, setState),
                ),
              if (!hideProxy && !hideServer) divider,
              if (!hideProxy)
                listTile(
                  icon: Icons.network_ping_outlined,
                  title: 'Socks5/Http(s) Proxy',
                  onTap: changeSocks5Proxy,
                ),
              if (!hideWebSocket && (!hideServer || !hideProxy)) divider,
              if (!hideWebSocket)
                switchWidget(
                    Icons.web_asset_outlined,
                    'Use WebSocket',
                    '${translate('websocket_tip')}\n\n${translate('server-oss-not-support-tip')}',
                    kOptionAllowWebSocket),
              if (!isWeb)
                futureBuilder(
                  future: bind.mainIsUsingPublicServer(),
                  hasData: (isUsingPublicServer) {
                    if (isUsingPublicServer) {
                      return Offstage();
                    } else {
                      return Column(
                        children: [
                          if (!hideServer || !hideProxy || !hideWebSocket)
                            divider,
                          switchWidget(
                              Icons.no_encryption_outlined,
                              'Allow insecure TLS fallback',
                              'allow-insecure-tls-fallback-tip',
                              kOptionAllowInsecureTLSFallback),
                          if (!outgoingOnly) divider,
                          if (!outgoingOnly)
                            listTile(
                              icon: Icons.lan_outlined,
                              title: 'Disable UDP',
                              showTooltip: true,
                              tooltipMessage:
                                  '${translate('disable-udp-tip')}\n\n${translate('server-oss-not-support-tip')}',
                              trailing: Switch(
                                value: bind.mainGetOptionSync(
                                        key: kOptionDisableUdp) ==
                                    'Y',
                                onChanged:
                                    locked || isOptionFixed(kOptionDisableUdp)
                                        ? null
                                        : (value) async {
                                            await bind.mainSetOption(
                                                key: kOptionDisableUdp,
                                                value: value ? 'Y' : 'N');
                                            setState(() {});
                                          },
                              ),
                            ),
                        ],
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Display extends StatefulWidget {
  const _Display({Key? key}) : super(key: key);

  @override
  State<_Display> createState() => _DisplayState();
}

class _DisplayState extends State<_Display> {
  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(controller: scrollController, children: [
      viewStyle(context),
      scrollStyle(context),
      imageQuality(context),
      codec(context),
      if (isDesktop) trackpadSpeed(context),
      if (!isWeb) privacyModeImpl(context),
      other(context),
    ]).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget viewStyle(BuildContext context) {
    final isOptFixed = isOptionFixed(kOptionViewStyle);
    onChanged(String value) async {
      await bind.mainSetUserDefaultOption(key: kOptionViewStyle, value: value);
      setState(() {});
    }

    final groupValue = bind.mainGetUserDefaultOption(key: kOptionViewStyle);
    return _Card(title: 'Default View Style', children: [
      _Radio(context,
          value: kRemoteViewStyleOriginal,
          groupValue: groupValue,
          label: 'Scale original',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: kRemoteViewStyleAdaptive,
          groupValue: groupValue,
          label: 'Scale adaptive',
          onChanged: isOptFixed ? null : onChanged),
    ]);
  }

  Widget scrollStyle(BuildContext context) {
    final isOptFixed = isOptionFixed(kOptionScrollStyle);
    onChanged(String value) async {
      await bind.mainSetUserDefaultOption(
          key: kOptionScrollStyle, value: value);
      setState(() {});
    }

    final groupValue = bind.mainGetUserDefaultOption(key: kOptionScrollStyle);

    return _Card(title: 'Default Scroll Style', children: [
      _Radio(context,
          value: kRemoteScrollStyleAuto,
          groupValue: groupValue,
          label: 'ScrollAuto',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: kRemoteScrollStyleBar,
          groupValue: groupValue,
          label: 'Scrollbar',
          onChanged: isOptFixed ? null : onChanged),
    ]);
  }

  Widget imageQuality(BuildContext context) {
    onChanged(String value) async {
      await bind.mainSetUserDefaultOption(
          key: kOptionImageQuality, value: value);
      setState(() {});
    }

    final isOptFixed = isOptionFixed(kOptionImageQuality);
    final groupValue = bind.mainGetUserDefaultOption(key: kOptionImageQuality);
    return _Card(title: 'Default Image Quality', children: [
      _Radio(context,
          value: kRemoteImageQualityBest,
          groupValue: groupValue,
          label: 'Good image quality',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: kRemoteImageQualityBalanced,
          groupValue: groupValue,
          label: 'Balanced',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: kRemoteImageQualityLow,
          groupValue: groupValue,
          label: 'Optimize reaction time',
          onChanged: isOptFixed ? null : onChanged),
    ]);
  }

  Widget trackpadSpeed(BuildContext context) {
    final initSpeed =
        (int.tryParse(bind.mainGetUserDefaultOption(key: kKeyTrackpadSpeed)) ??
            kDefaultTrackpadSpeed);
    final curSpeed = SimpleWrapper(initSpeed);
    void onDebouncer(int v) {
      bind.mainSetUserDefaultOption(
          key: kKeyTrackpadSpeed, value: v.toString());
      // It's better to notify all sessions that the default speed is changed.
      // But it may also be ok to take effect in the next connection.
    }

    return _Card(title: 'Default trackpad speed', children: [
      TrackpadSpeedWidget(
        value: curSpeed,
        onDebouncer: onDebouncer,
      ),
    ]);
  }

  Widget codec(BuildContext context) {
    onChanged(String value) async {
      await bind.mainSetUserDefaultOption(
          key: kOptionCodecPreference, value: value);
      setState(() {});
    }

    final groupValue =
        bind.mainGetUserDefaultOption(key: kOptionCodecPreference);
    var hwRadios = [];
    final isOptFixed = isOptionFixed(kOptionCodecPreference);
    try {
      final Map codecsJson = jsonDecode(bind.mainSupportedHwdecodings());
      final h264 = codecsJson['h264'] ?? false;
      final h265 = codecsJson['h265'] ?? false;
      if (h264) {
        hwRadios.add(_Radio(context,
            value: 'h264',
            groupValue: groupValue,
            label: 'H264',
            onChanged: isOptFixed ? null : onChanged));
      }
      if (h265) {
        hwRadios.add(_Radio(context,
            value: 'h265',
            groupValue: groupValue,
            label: 'H265',
            onChanged: isOptFixed ? null : onChanged));
      }
    } catch (e) {
      debugPrint("failed to parse supported hwdecodings, err=$e");
    }
    return _Card(title: 'Default Codec', children: [
      _Radio(context,
          value: 'auto',
          groupValue: groupValue,
          label: 'Auto',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: 'vp8',
          groupValue: groupValue,
          label: 'VP8',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: 'vp9',
          groupValue: groupValue,
          label: 'VP9',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: 'av1',
          groupValue: groupValue,
          label: 'AV1',
          onChanged: isOptFixed ? null : onChanged),
      ...hwRadios,
    ]);
  }

  Widget privacyModeImpl(BuildContext context) {
    final supportedPrivacyModeImpls = bind.mainSupportedPrivacyModeImpls();
    late final List<dynamic> privacyModeImpls;
    try {
      privacyModeImpls = jsonDecode(supportedPrivacyModeImpls);
    } catch (e) {
      debugPrint('failed to parse supported privacy mode impls, err=$e');
      return Offstage();
    }
    if (privacyModeImpls.length < 2) {
      return Offstage();
    }

    final key = 'privacy-mode-impl-key';
    onChanged(String value) async {
      await bind.mainSetOption(key: key, value: value);
      setState(() {});
    }

    String groupValue = bind.mainGetOptionSync(key: key);
    if (groupValue.isEmpty) {
      groupValue = bind.mainDefaultPrivacyModeImpl();
    }
    return _Card(
      title: 'Privacy mode',
      children: privacyModeImpls.map((impl) {
        final d = impl as List<dynamic>;
        return _Radio(context,
            value: d[0] as String,
            groupValue: groupValue,
            label: d[1] as String,
            onChanged: onChanged);
      }).toList(),
    );
  }

  Widget otherRow(String label, String key) {
    final value = bind.mainGetUserDefaultOption(key: key) == 'Y';
    final isOptFixed = isOptionFixed(key);
    onChanged(bool b) async {
      await bind.mainSetUserDefaultOption(
          key: key,
          value: b
              ? 'Y'
              : (key == kOptionEnableFileCopyPaste ? 'N' : defaultOptionNo));
      setState(() {});
    }

    return MouseRegion(
      cursor: isOptFixed ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
          child: Row(
            children: [
              StyledCheckbox(
                value: value,
                onChanged: isOptFixed ? null : (_) => onChanged(!value),
                enabled: !isOptFixed,
                accentColor: _accentColor,
              ).marginOnly(right: 5),
              Expanded(
                child: Text(translate(label)),
              )
            ],
          ),
          onTap: isOptFixed ? null : () => onChanged(!value)),
    );
  }

  Widget other(BuildContext context) {
    final children =
        otherDefaultSettings().map((e) => otherRow(e.$1, e.$2)).toList();
    return _Card(title: 'Other Default Options', children: children);
  }
}

class _Account extends StatefulWidget {
  const _Account({Key? key}) : super(key: key);

  @override
  State<_Account> createState() => _AccountState();
}

class _AccountState extends State<_Account> {
  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(
      controller: scrollController,
      children: [
        _Card(title: 'Account', children: [accountAction(), useInfo()]),
      ],
    ).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget accountAction() {
    return Obx(() {
      final isLoggedIn = gFFI.userModel.userName.value.isNotEmpty ||
          gFFI.userModel.userEmail.value.isNotEmpty;
      return _Button(
        isLoggedIn ? 'Logout' : 'Login',
        () => isLoggedIn ? logOutConfirmDialog() : loginDialog(),
      );
    });
  }

  Widget useInfo() {
    text(String key, String value) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SelectionArea(child: Text('${translate(key)}: $value'))
            .marginSymmetric(vertical: 4),
      );
    }

    String getPlanTypeName(int type) {
      switch (type) {
        case 1:
          return 'Free';
        case 2:
          return 'Personal';
        case 3:
          return 'Enterprise';
        default:
          return 'Unknown';
      }
    }

    return Obx(() => Offstage(
          offstage: gFFI.userModel.userName.value.isEmpty &&
              gFFI.userModel.userEmail.value.isEmpty,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (gFFI.userModel.userName.value.isNotEmpty)
                text('Username', gFFI.userModel.userName.value),
              if (gFFI.userModel.userEmail.value.isNotEmpty)
                text('Email', gFFI.userModel.userEmail.value),
              text('Plan', getPlanTypeName(gFFI.userModel.userType.value)),
            ],
          ),
        )).marginOnly(left: 18, top: 16);
  }
}

class _Checkbox extends StatefulWidget {
  final String label;
  final bool Function() getValue;
  final Future<void> Function(bool) setValue;

  const _Checkbox(
      {Key? key,
      required this.label,
      required this.getValue,
      required this.setValue})
      : super(key: key);

  @override
  State<_Checkbox> createState() => _CheckboxState();
}

class _CheckboxState extends State<_Checkbox> {
  var value = false;

  @override
  initState() {
    super.initState();
    value = widget.getValue();
  }

  @override
  Widget build(BuildContext context) {
    onChanged(bool b) async {
      await widget.setValue(b);
      setState(() {
        value = widget.getValue();
      });
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        child: Row(
          children: [
            StyledCheckbox(
              value: value,
              onChanged: (_) => onChanged(!value),
              accentColor: _accentColor,
            ).marginOnly(right: 5),
            Expanded(
              child: Text(translate(widget.label)),
            )
          ],
        ),
        onTap: () => onChanged(!value),
      ),
    );
  }
}

class _Plugin extends StatefulWidget {
  const _Plugin({Key? key}) : super(key: key);

  @override
  State<_Plugin> createState() => _PluginState();
}

class _PluginState extends State<_Plugin> {
  @override
  Widget build(BuildContext context) {
    bind.pluginListReload();
    final scrollController = ScrollController();
    return ChangeNotifierProvider.value(
      value: pluginManager,
      child: Consumer<PluginManager>(builder: (context, model, child) {
        return ListView(
          controller: scrollController,
          children: model.plugins.map((entry) => pluginCard(entry)).toList(),
        ).marginOnly(bottom: _kListViewBottomMargin);
      }),
    );
  }

  Widget pluginCard(PluginInfo plugin) {
    return ChangeNotifierProvider.value(
      value: plugin,
      child: Consumer<PluginInfo>(
        builder: (context, model, child) => DesktopSettingsCard(plugin: model),
      ),
    );
  }

  Widget accountAction() {
    return Obx(() => _Button(
        gFFI.userModel.userName.value.isEmpty ? 'Login' : 'Logout',
        () => {
              gFFI.userModel.userName.value.isEmpty
                  ? loginDialog()
                  : logOutConfirmDialog()
            }));
  }
}

class _Printer extends StatefulWidget {
  const _Printer({super.key});

  @override
  State<_Printer> createState() => __PrinterState();
}

class __PrinterState extends State<_Printer> {
  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(controller: scrollController, children: [
      outgoing(context),
      incoming(context),
    ]).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget outgoing(BuildContext context) {
    final isSupportPrinterDriver =
        bind.mainGetCommonSync(key: 'is-support-printer-driver') == 'true';

    Widget tipOsNotSupported() {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(translate('printer-os-requirement-tip')),
      ).marginOnly(left: _kCardLeftMargin);
    }

    Widget tipClientNotInstalled() {
      return Align(
        alignment: Alignment.topLeft,
        child:
            Text(translate('printer-requires-installed-{$appName}-client-tip')),
      ).marginOnly(left: _kCardLeftMargin);
    }

    Widget tipPrinterNotInstalled() {
      final failedMsg = ''.obs;
      platformFFI.registerEventHandler(
          'install-printer-res', 'install-printer-res', (evt) async {
        if (evt['success'] as bool) {
          setState(() {});
        } else {
          failedMsg.value = evt['msg'] as String;
        }
      }, replace: true);
      return Column(children: [
        Obx(
          () => failedMsg.value.isNotEmpty
              ? Offstage()
              : Align(
                  alignment: Alignment.topLeft,
                  child: Text(translate('printer-{$appName}-not-installed-tip'))
                      .marginOnly(bottom: 10.0),
                ),
        ),
        Obx(
          () => failedMsg.value.isEmpty
              ? Offstage()
              : Align(
                  alignment: Alignment.topLeft,
                  child: Text(failedMsg.value,
                          style: DefaultTextStyle.of(context)
                              .style
                              .copyWith(color: Colors.red))
                      .marginOnly(bottom: 10.0)),
        ),
        _Button('Install {$appName} Printer', () {
          failedMsg.value = '';
          bind.mainSetCommon(key: 'install-printer', value: '');
        })
      ]).marginOnly(left: _kCardLeftMargin, bottom: 2.0);
    }

    Widget tipReady() {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(translate('printer-{$appName}-ready-tip')),
      ).marginOnly(left: _kCardLeftMargin);
    }

    final installed = bind.mainIsInstalled();
    // `is-printer-installed` may fail, but it's rare case.
    // Add additional error message here if it's really needed.
    final isPrinterInstalled =
        bind.mainGetCommonSync(key: 'is-printer-installed') == 'true';

    final List<Widget> children = [];
    if (!isSupportPrinterDriver) {
      children.add(tipOsNotSupported());
    } else {
      children.addAll([
        if (!installed) tipClientNotInstalled(),
        if (installed && !isPrinterInstalled) tipPrinterNotInstalled(),
        if (installed && isPrinterInstalled) tipReady()
      ]);
    }
    return _Card(title: 'Outgoing Print Jobs', children: children);
  }

  Widget incoming(BuildContext context) {
    onRadioChanged(String value) async {
      await bind.mainSetLocalOption(
          key: kKeyPrinterIncomingJobAction, value: value);
      setState(() {});
    }

    PrinterOptions printerOptions = PrinterOptions.load();
    return _Card(title: 'Incoming Print Jobs', children: [
      _Radio(context,
          value: kValuePrinterIncomingJobDismiss,
          groupValue: printerOptions.action,
          label: 'Dismiss',
          onChanged: onRadioChanged),
      _Radio(context,
          value: kValuePrinterIncomingJobDefault,
          groupValue: printerOptions.action,
          label: 'use-the-default-printer-tip',
          onChanged: onRadioChanged),
      _Radio(context,
          value: kValuePrinterIncomingJobSelected,
          groupValue: printerOptions.action,
          label: 'use-the-selected-printer-tip',
          onChanged: onRadioChanged),
      if (printerOptions.printerNames.isNotEmpty)
        ComboBox(
          initialKey: printerOptions.printerName,
          keys: printerOptions.printerNames,
          values: printerOptions.printerNames,
          enabled: printerOptions.action == kValuePrinterIncomingJobSelected,
          onChanged: (value) async {
            await bind.mainSetLocalOption(
                key: kKeyPrinterSelected, value: value);
            setState(() {});
          },
        ).marginOnly(left: 10),
      _OptionCheckBox(
        context,
        'auto-print-tip',
        kKeyPrinterAllowAutoPrint,
        isServer: false,
        enabled: printerOptions.action != kValuePrinterIncomingJobDismiss,
      )
    ]);
  }
}

class _About extends StatefulWidget {
  const _About({Key? key}) : super(key: key);

  @override
  State<_About> createState() => _AboutState();
}

class _AboutState extends State<_About> {
  @override
  Widget build(BuildContext context) {
    return futureBuilder(future: () async {
      final version = await bind.mainGetVersion();
      final buildDate = await bind.mainGetBuildDate();
      return {
        'version': version,
        'buildDate': buildDate,
      };
    }(), hasData: (data) {
      final version = data['version'].toString();
      final buildDate = data['buildDate'].toString();
      final scrollController = ScrollController();
      return SingleChildScrollView(
        controller: scrollController,
        child: _Card(title: translate('About OneDesk'), children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8.0),
              // 버전 정보
              SelectionArea(
                child: Text(
                  '${translate('Version')}: $version',
                  style: const TextStyle(
                      fontSize: _kContentFontSize, color: Colors.black87),
                ),
              ).marginOnly(bottom: 12),
              // 빌드 날짜
              SelectionArea(
                child: Text(
                  '${translate('Build Date')}: $buildDate',
                  style: const TextStyle(
                      fontSize: _kContentFontSize, color: Colors.black87),
                ),
              ).marginOnly(bottom: 20),
              // 링크 버튼들
              Row(
                children: [
                  // Onedesk 홈페이지 버튼
                  _AboutLinkButton(
                    label: translate('Website'),
                    onPressed: () => launchUrlString('https://onedesk.co.kr'),
                  ),
                  const SizedBox(width: 12),
                  // 이용약관 버튼
                  _AboutLinkButton(
                    label: translate('Privacy Statement'),
                    onPressed: () =>
                        launchUrlString('https://onedesk.co.kr/terms'),
                  ),
                ],
              ).marginOnly(bottom: 20),
              // Copyright 박스 (녹화경로와 동일한 스타일)
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _accentColorLighter,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(20),
                child: SelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Copyright © ${DateTime.now().year} MarketingMonster Ltd.',
                        style: const TextStyle(
                          fontSize: _kContentFontSize,
                          color: _primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        translate('Slogan_tip'),
                        style: const TextStyle(
                          fontSize: _kContentFontSize,
                          color: _primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          )
        ]),
      );
    });
  }
}

/// About 페이지 링크 버튼
class _AboutLinkButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;

  const _AboutLinkButton({
    required this.label,
    required this.onPressed,
  });

  @override
  State<_AboutLinkButton> createState() => _AboutLinkButtonState();
}

class _AboutLinkButtonState extends State<_AboutLinkButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = _isHovered ? _primaryColor : Colors.grey[300]!;
    final contentColor = _isHovered ? _primaryColor : Colors.grey[700]!;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_outward, size: 16, color: contentColor),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 14,
                  color: contentColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//#endregion

//#region components

/// 설정 카드 위젯
/// ContentCard를 래핑하여 설정 페이지 스타일 적용
// ignore: non_constant_identifier_names
Widget _Card(
    {required String title,
    required List<Widget> children,
    List<Widget>? title_suffix,
    Color? backgroundColor}) {
  return ContentCard(
    title: translate(title),
    titleSuffix: title_suffix,
    backgroundColor: backgroundColor ?? _cardBackgroundColor,
    margin: const EdgeInsets.only(
        left: _kCardLeftMargin, right: _kCardLeftMargin, top: 16),
    contentPadding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...children.map((e) => _CardChildWrapper(child: e)),
        const SizedBox(height: 20),
      ],
    ),
  );
}

/// _Card 자식 위젯 래퍼 - 빈 위젯에는 Padding을 적용하지 않음
class _CardChildWrapper extends StatelessWidget {
  final Widget child;
  const _CardChildWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    // SizedBox.shrink()인 경우 패딩 없이 그대로 반환 (공간 차지 안함)
    if (child is SizedBox) {
      final sizedBox = child as SizedBox;
      if (sizedBox.width == 0 && sizedBox.height == 0) {
        return child;
      }
    }
    // Offstage인 경우 패딩 없이 그대로 반환
    if (child is Offstage) {
      return child;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: child,
    );
  }
}

/// 설정 옵션 체크박스 위젯
/// 보라색 테마 적용
// ignore: non_constant_identifier_names
Widget _OptionCheckBox(
  BuildContext context,
  String label,
  String key, {
  Function(bool)? update,
  bool reverse = false,
  bool enabled = true,
  Icon? checkedIcon,
  bool? fakeValue,
  bool isServer = true,
  bool Function()? optGetter,
  Future<void> Function(String, bool)? optSetter,
}) {
  getOpt() => optGetter != null
      ? optGetter()
      : (isServer
          ? mainGetBoolOptionSync(key)
          : mainGetLocalBoolOptionSync(key));

  final isOptFixed = isOptionFixed(key);

  // 전역 ValueNotifier 사용 (외부에서 변경 시 동기화됨)
  // optGetter가 제공된 경우 커스텀 로직이므로 동기화 대상에서 제외
  final notifierKey = reverse ? '${key}_reversed' : key;
  final notifier = optGetter != null
      ? ValueNotifier<bool>(reverse ? !getOpt() : getOpt())
      : _getOrCreateOptionNotifier(notifierKey, key, isServer, reverse);

  onChanged(option) async {
    if (option != null) {
      if (reverse) option = !option;
      final setter =
          optSetter ?? (isServer ? mainSetBoolOption : mainSetLocalBoolOption);
      await setter(key, option);
      final readOption = getOpt();
      notifier.value = reverse ? !readOption : readOption;
      update?.call(readOption);
    }
  }

  if (fakeValue != null) {
    notifier.value = fakeValue;
    enabled = false;
  }

  final isEnabled = enabled && !isOptFixed;
  return ValueListenableBuilder<bool>(
    valueListenable: notifier,
    builder: (context, value, child) => MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: isEnabled
            ? () {
                onChanged(!value);
              }
            : null,
        child: Row(
          children: [
            // 스타일 체크박스 (24px, 1px 테두리, 4px 둥글기)
            StyledCheckbox(
              value: value,
              onChanged: isEnabled ? onChanged : null,
              enabled: isEnabled,
              accentColor: _accentColor,
            ).marginOnly(right: 8),
            Offstage(
              offstage: !value || checkedIcon == null,
              child: checkedIcon?.marginOnly(right: 5),
            ),
            Expanded(
              child: Text(
                translate(label),
                style: TextStyle(
                  color: enabled
                      ? const Color(0xFF475569)
                      : const Color(0xFF94A3B8),
                  fontSize: _kContentFontSize,
                ),
              ),
            )
          ],
        ),
      ),
    ),
  );
}

/// 설정 옵션 라디오 버튼 위젯
/// 보라색 테마 적용
// ignore: non_constant_identifier_names
Widget _Radio<T>(BuildContext context,
    {required T value,
    required T groupValue,
    required String label,
    required Function(T value)? onChanged,
    bool autoNewLine = true}) {
  final onChange2 = onChanged != null
      ? (T? value) {
          if (value != null) {
            onChanged(value);
          }
        }
      : null;
  final bool enabled = onChange2 != null;
  return MouseRegion(
    cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
    child: GestureDetector(
      child: Row(
        children: [
          // 커스텀 라디오 버튼 (24px, 1px 테두리)
          StyledRadio<T>(
            value: value,
            groupValue: groupValue,
            onChanged: onChange2,
            enabled: enabled,
            accentColor: _accentColor,
          ),
          Expanded(
            child: Text(
              translate(label),
              overflow: autoNewLine ? null : TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _kContentFontSize,
                color:
                    enabled ? const Color(0xFF475569) : const Color(0xFF94A3B8),
              ),
            ).marginOnly(left: 8),
          ),
        ],
      ),
      onTap: () => onChange2?.call(value),
    ),
  );
}

class WaylandCard extends StatefulWidget {
  const WaylandCard({Key? key}) : super(key: key);

  @override
  State<WaylandCard> createState() => _WaylandCardState();
}

class _WaylandCardState extends State<WaylandCard> {
  final restoreTokenKey = 'wayland-restore-token';

  @override
  Widget build(BuildContext context) {
    return futureBuilder(
      future: bind.mainHandleWaylandScreencastRestoreToken(
          key: restoreTokenKey, value: "get"),
      hasData: (restoreToken) {
        final children = [
          if (restoreToken.isNotEmpty)
            _buildClearScreenSelection(context, restoreToken),
        ];
        return Offstage(
          offstage: children.isEmpty,
          child: _Card(title: 'Wayland', children: children),
        );
      },
    );
  }

  Widget _buildClearScreenSelection(BuildContext context, String restoreToken) {
    onConfirm() async {
      final msg = await bind.mainHandleWaylandScreencastRestoreToken(
          key: restoreTokenKey, value: "clear");
      gFFI.dialogManager.dismissAll();
      if (msg.isNotEmpty) {
        msgBox(gFFI.sessionId, 'custom-nocancel', 'Error', msg, '',
            gFFI.dialogManager);
      } else {
        setState(() {});
      }
    }

    showConfirmMsgBox() => msgBoxCommon(
            gFFI.dialogManager,
            'Confirmation',
            Text(
              translate('confirm_clear_Wayland_screen_selection_tip'),
            ),
            [
              dialogButton('OK', onPressed: onConfirm),
              dialogButton('Cancel',
                  onPressed: () => gFFI.dialogManager.dismissAll())
            ]);

    return _Button(
      'Clear Wayland screen selection',
      showConfirmMsgBox,
      tip: 'clear_Wayland_screen_selection_tip',
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all<Color>(
            Theme.of(context).colorScheme.error.withValues(alpha: 0.75)),
      ),
    );
  }
}

/// 설정 페이지 버튼 위젯
/// StyledCompactButton 사용 (styled_form_widgets.dart)
// ignore: non_constant_identifier_names
Widget _Button(String label, Function() onPressed,
    {bool enabled = true, String? tip, ButtonStyle? style}) {
  return Row(children: [
    StyledCompactButton(
      label: translate(label),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      onPressed: enabled ? onPressed : null,
      fontSize: _kContentFontSize,
      tooltip: tip != null ? translate(tip) : null,
    ),
  ]);
}

/// 설정 페이지 서브 버튼 위젯
/// 아웃라인 스타일 서브 버튼
// ignore: non_constant_identifier_names
Widget _SubButton(String label, Function() onPressed, [bool enabled = true]) {
  return Row(
    children: [
      IntrinsicWidth(
        child: StyledOutlinedButton(
          label: translate(label),
          onPressed: enabled ? onPressed : null,
          height: 38,
          fontSize: _kContentFontSize,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        ),
      ),
    ],
  ); // _CardChildWrapper가 이미 20px 적용
}

// ignore: non_constant_identifier_names
Widget _SubLabeledWidget(BuildContext context, String label, Widget child,
    {bool enabled = true}) {
  return Row(
    children: [
      Text(
        '${translate(label)}: ',
        style: TextStyle(color: disabledTextColor(context, enabled)),
      ),
      SizedBox(
        width: 10,
      ),
      child,
    ],
  ).marginOnly(left: _kContentHSubMargin);
}

Widget _lock(
  bool locked,
  String label,
  Function() onUnlock,
) {
  return Offstage(
      offstage: !locked,
      child: Row(
        children: [
          Flexible(
            child: SizedBox(
              width: _kCardFixedWidth,
              child: Card(
                child: ElevatedButton(
                  child: SizedBox(
                      height: 25,
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.security_sharp,
                              size: 20,
                            ),
                            Text(translate(label)).marginOnly(left: 5),
                          ]).marginSymmetric(vertical: 2)),
                  onPressed: () async {
                    final unlockPin = bind.mainGetUnlockPin();
                    if (unlockPin.isEmpty) {
                      bool checked = await callMainCheckSuperUserPermission();
                      if (checked) {
                        onUnlock();
                      }
                    } else {
                      checkUnlockPinDialog(unlockPin, onUnlock);
                    }
                  },
                ).marginSymmetric(horizontal: 2, vertical: 4),
              ).marginOnly(left: _kCardLeftMargin),
            ).marginOnly(top: 10),
          ),
        ],
      ));
}

_LabeledTextField(
    BuildContext context,
    String label,
    TextEditingController controller,
    String errorText,
    bool enabled,
    bool secure) {
  return Table(
    columnWidths: const {
      0: FixedColumnWidth(150),
      1: FlexColumnWidth(),
    },
    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
    children: [
      TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(
              '${translate(label)}:',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: _kContentFontSize,
                color: disabledTextColor(context, enabled),
              ),
            ),
          ),
          TextField(
            controller: controller,
            enabled: enabled,
            obscureText: secure,
            autocorrect: false,
            decoration: InputDecoration(
              errorText: errorText.isNotEmpty ? errorText : null,
            ),
            style: TextStyle(
              color: disabledTextColor(context, enabled),
            ),
          ).workaroundFreezeLinuxMint(),
        ],
      ),
    ],
  ).marginOnly(bottom: 8);
}

class _CountDownButton extends StatefulWidget {
  _CountDownButton({
    Key? key,
    required this.text,
    required this.second,
    required this.onPressed,
  }) : super(key: key);
  final String text;
  final VoidCallback? onPressed;
  final int second;

  @override
  State<_CountDownButton> createState() => _CountDownButtonState();
}

class _CountDownButtonState extends State<_CountDownButton> {
  bool _isButtonDisabled = false;

  late int _countdownSeconds = widget.second;

  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdownTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_countdownSeconds <= 0) {
        setState(() {
          _isButtonDisabled = false;
        });
        timer.cancel();
      } else {
        setState(() {
          _countdownSeconds--;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StyledCompactButton(
      label:
          _isButtonDisabled ? '$_countdownSeconds s' : translate(widget.text),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      onPressed: _isButtonDisabled
          ? null
          : () {
              widget.onPressed?.call();
              setState(() {
                _isButtonDisabled = true;
                _countdownSeconds = widget.second;
              });
              _startCountdownTimer();
            },
      fontSize: _kContentFontSize,
    );
  }
}

//#endregion

//#region dialogs

void changeSocks5Proxy() async {
  var socks = await bind.mainGetSocks();

  String proxy = '';
  String proxyMsg = '';
  String username = '';
  String password = '';
  if (socks.length == 3) {
    proxy = socks[0];
    username = socks[1];
    password = socks[2];
  }
  var proxyController = TextEditingController(text: proxy);
  var userController = TextEditingController(text: username);
  var pwdController = TextEditingController(text: password);
  RxBool obscure = true.obs;

  // proxy settings
  // The following option is a not real key, it is just used for custom client advanced settings.
  const String optionProxyUrl = "proxy-url";
  final isOptFixed = isOptionFixed(optionProxyUrl);

  var isInProgress = false;
  gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      setState(() {
        proxyMsg = '';
        isInProgress = true;
      });
      cancel() {
        setState(() {
          isInProgress = false;
        });
      }

      proxy = proxyController.text.trim();
      username = userController.text.trim();
      password = pwdController.text.trim();

      if (proxy.isNotEmpty) {
        String domainPort = proxy;
        if (domainPort.contains('://')) {
          domainPort = domainPort.split('://')[1];
        }
        proxyMsg = translate(await bind.mainTestIfValidServer(
            server: domainPort, testWithProxy: false));
        if (proxyMsg.isEmpty) {
          // ignore
        } else {
          cancel();
          return;
        }
      }
      await bind.mainSetSocks(
          proxy: proxy, username: username, password: password);
      close();
    }

    return CustomAlertDialog(
      title: Text(translate('Socks5/Http(s) Proxy')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (!isMobile)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 140),
                    child: Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          children: [
                            Text(
                              translate('Server'),
                            ).marginOnly(right: 4),
                            Tooltip(
                              waitDuration: Duration(milliseconds: 0),
                              message: translate("default_proxy_tip"),
                              child: Icon(
                                Icons.help_outline_outlined,
                                size: 16,
                                color: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.color
                                    ?.withOpacity(0.5),
                              ),
                            ),
                          ],
                        )).marginOnly(right: 10),
                  ),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      errorText: proxyMsg.isNotEmpty ? proxyMsg : null,
                      labelText: isMobile ? translate('Server') : null,
                      helperText:
                          isMobile ? translate("default_proxy_tip") : null,
                      helperMaxLines: isMobile ? 3 : null,
                    ),
                    controller: proxyController,
                    autofocus: true,
                    enabled: !isOptFixed,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ).marginOnly(bottom: 8),
            Row(
              children: [
                if (!isMobile)
                  ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 140),
                      child: Text(
                        '${translate("Username")}:',
                        textAlign: TextAlign.right,
                      ).marginOnly(right: 10)),
                Expanded(
                  child: TextField(
                    controller: userController,
                    decoration: InputDecoration(
                      labelText: isMobile ? translate('Username') : null,
                    ),
                    enabled: !isOptFixed,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ).marginOnly(bottom: 8),
            Row(
              children: [
                if (!isMobile)
                  ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 140),
                      child: Text(
                        '${translate("Password")}:',
                        textAlign: TextAlign.right,
                      ).marginOnly(right: 10)),
                Expanded(
                  child: Obx(() => TextField(
                        obscureText: obscure.value,
                        decoration: InputDecoration(
                            labelText: isMobile ? translate('Password') : null,
                            suffixIcon: IconButton(
                                onPressed: () => obscure.value = !obscure.value,
                                icon: Icon(obscure.value
                                    ? Icons.visibility_off
                                    : Icons.visibility))),
                        controller: pwdController,
                        enabled: !isOptFixed,
                        maxLength: bind.mainMaxEncryptLen(),
                      ).workaroundFreezeLinuxMint()),
                ),
              ],
            ),
            // NOT use Offstage to wrap LinearProgressIndicator
            if (isInProgress)
              const LinearProgressIndicator().marginOnly(top: 8),
          ],
        ),
      ),
      actions: [
        Row(
          children: [
            Expanded(child: dialogButton('Cancel', onPressed: close, isOutline: true)),
            if (!isOptFixed) ...[
              const SizedBox(width: 12),
              Expanded(child: dialogButton('OK', onPressed: submit)),
            ],
          ],
        ),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

//#endregion
