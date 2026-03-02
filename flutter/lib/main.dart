import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/widgets/overlay.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/pages/auth_wrapper.dart';
import 'package:flutter_hbb/desktop/pages/install_page.dart';
import 'package:flutter_hbb/desktop/pages/server_page.dart';
import 'package:flutter_hbb/desktop/screen/desktop_file_transfer_screen.dart';
import 'package:flutter_hbb/desktop/screen/desktop_view_camera_screen.dart';
import 'package:flutter_hbb/desktop/screen/desktop_port_forward_screen.dart';
import 'package:flutter_hbb/desktop/screen/desktop_remote_screen.dart';
import 'package:flutter_hbb/desktop/screen/desktop_terminal_screen.dart';
import 'package:flutter_hbb/desktop/screen/desktop_plan_selection_screen.dart';
import 'package:flutter_hbb/desktop/pages/voice_call_dialog_page.dart';
import 'package:flutter_hbb/desktop/pages/camera_request_dialog_page.dart';
import 'package:flutter_hbb/desktop/widgets/refresh_wrapper.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'common.dart';
import 'consts.dart';
import 'mobile/pages/home_page.dart';
import 'mobile/pages/mobile_auth_wrapper.dart';
import 'mobile/pages/server_page.dart';
import 'models/platform_model.dart';

import 'package:flutter_hbb/plugin/handlers.dart'
    if (dart.library.html) 'package:flutter_hbb/web/plugin/handlers.dart';

/// Basic window and launch properties.
int? kWindowId;
WindowType? kWindowType;
late List<String> kBootArgs;

Future<void> main(List<String> args) async {
  earlyAssert();
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint("launch args: $args");
  kBootArgs = List.from(args);

  if (!isDesktop) {
    runMobileApp();
    return;
  }
  // main window
  if (args.isNotEmpty && args.first == 'multi_window') {
    kWindowId = int.parse(args[1]);
    stateGlobal.setWindowId(kWindowId!);
    if (!isMacOS) {
      WindowController.fromWindowId(kWindowId!).showTitleBar(false);
    }
    final argument = args[2].isEmpty
        ? <String, dynamic>{}
        : jsonDecode(args[2]) as Map<String, dynamic>;
    int type = argument['type'] ?? -1;
    // to-do: No need to parse window id ?
    // Because stateGlobal.windowId is a global value.
    argument['windowId'] = kWindowId;
    kWindowType = type.windowType;
    switch (kWindowType) {
      case WindowType.RemoteDesktop:
        desktopType = DesktopType.remote;
        runMultiWindow(
          argument,
          kAppTypeDesktopRemote,
        );
        break;
      case WindowType.FileTransfer:
        desktopType = DesktopType.fileTransfer;
        runMultiWindow(
          argument,
          kAppTypeDesktopFileTransfer,
        );
        break;
      case WindowType.ViewCamera:
        desktopType = DesktopType.viewCamera;
        runMultiWindow(
          argument,
          kAppTypeDesktopViewCamera,
        );
        break;
      case WindowType.PortForward:
        desktopType = DesktopType.portForward;
        runMultiWindow(
          argument,
          kAppTypeDesktopPortForward,
        );
        break;
      case WindowType.Terminal:
        desktopType = DesktopType.terminal;
        runMultiWindow(
          argument,
          kAppTypeDesktopTerminal,
        );
        break;
      case WindowType.PlanSelection:
        desktopType = DesktopType.planSelection;
        runPlanSelectionScreen(argument);
        break;
      case WindowType.VoiceCallDialog:
        desktopType = DesktopType.voiceCallDialog;
        runVoiceCallDialogScreen(argument);
        break;
      case WindowType.CameraRequestDialog:
        desktopType = DesktopType.cameraRequestDialog;
        runCameraRequestDialogScreen(argument);
        break;
      default:
        break;
    }
  } else if (args.isNotEmpty && args.first == '--cm') {
    debugPrint("--cm started");
    desktopType = DesktopType.cm;
    await windowManager.ensureInitialized();
    runConnectionManagerScreen();
  } else if (args.contains('--install')) {
    runInstallPage();
  } else {
    desktopType = DesktopType.main;
    await windowManager.ensureInitialized();
    windowManager.setPreventClose(true);
    if (isMacOS) {
      disableWindowMovable(kWindowId);
    }
    runMainApp(true);
  }
}

Future<void> initEnv(String appType) async {
  // global shared preference
  await platformFFI.init(appType);
  // global FFI, use this **ONLY** for global configuration
  // for convenience, use global FFI on mobile platform
  // focus on multi-ffi on desktop first
  await initGlobalFFI();
  // await Firebase.initializeApp();
  _registerEventHandler();
  // Update the system theme.
  updateSystemWindowTheme();
}

void runMainApp(bool startService) async {
  // register uni links
  await initEnv(kAppTypeMain);
  checkUpdate();
  // trigger connection status updater
  await bind.mainCheckConnectStatus();
  if (startService) {
    gFFI.serverModel.startService();
    bind.pluginSyncUi(syncTo: kAppTypeMain);
    bind.pluginListReload();
  }
  await Future.wait([gFFI.abModel.loadCache(), gFFI.groupModel.loadCache()]);
  gFFI.userModel.refreshCurrentUser();
  runApp(App());

  bool? alwaysOnTop;
  if (isDesktop) {
    alwaysOnTop =
        bind.mainGetBuildinOption(key: "main-window-always-on-top") == 'Y';
  }

  // Set window option.
  WindowOptions windowOptions = getHiddenTitleBarWindowOptions(
      isMainWindow: true,
      minimumSize: const Size(kMainWindowMinWidth, kMainWindowMinHeight),
      alwaysOnTop: alwaysOnTop);
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    // 최소 창 크기 강제 설정
    await windowManager.setMinimumSize(const Size(kMainWindowMinWidth, kMainWindowMinHeight));
    // Restore the location of the main window before window hide or show.
    await restoreWindowPosition(WindowType.Main);
    // Check the startup argument, if we successfully handle the argument, we keep the main window hidden.
    final handledByUniLinks = await initUniLinks();
    debugPrint("handled by uni links: $handledByUniLinks");
    if (handledByUniLinks || handleUriLink(cmdArgs: kBootArgs)) {
      windowManager.hide();
    } else {
      windowManager.show();
      windowManager.focus();
      // Move registration of active main window here to prevent from async visible check.
      oneDeskWinManager.registerActiveWindow(kWindowMainId);
    }
    windowManager.setOpacity(1);
    windowManager.setTitle(getWindowName());
    // Do not use `windowManager.setResizable()` here.
    setResizable(!bind.isIncomingOnly());
  });
}

void runMobileApp() async {
  await initEnv(kAppTypeMain);
  checkUpdate();
  if (isAndroid) androidChannelInit();
  if (isAndroid) platformFFI.syncAndroidServiceAppDirConfigPath();
  draggablePositions.load();
  await Future.wait([gFFI.abModel.loadCache(), gFFI.groupModel.loadCache()]);
  gFFI.userModel.refreshCurrentUser();
  runApp(App());
  await initUniLinks();
}

void runMultiWindow(
  Map<String, dynamic> argument,
  String appType,
) async {
  await initEnv(appType);
  final title = getWindowName();
  // set prevent close to true, we handle close event manually
  WindowController.fromWindowId(kWindowId!).setPreventClose(true);
  if (isMacOS) {
    disableWindowMovable(kWindowId);
  }
  late Widget widget;
  switch (appType) {
    case kAppTypeDesktopRemote:
      draggablePositions.load();
      widget = DesktopRemoteScreen(
        params: argument,
      );
      break;
    case kAppTypeDesktopFileTransfer:
      widget = DesktopFileTransferScreen(
        params: argument,
      );
      break;
    case kAppTypeDesktopViewCamera:
      draggablePositions.load();
      widget = DesktopViewCameraScreen(
        params: argument,
      );
      break;
    case kAppTypeDesktopPortForward:
      widget = DesktopPortForwardScreen(
        params: argument,
      );
      break;
    case kAppTypeDesktopTerminal:
      widget = DesktopTerminalScreen(
        params: argument,
      );
      break;
    default:
      // no such appType
      exit(0);
  }
  _runApp(
    title,
    widget,
    ThemeMode.light,
  );
  // we do not hide titlebar on win7 because of the frame overflow.
  if (kUseCompatibleUiMode) {
    WindowController.fromWindowId(kWindowId!).showTitleBar(true);
  }
  switch (appType) {
    case kAppTypeDesktopRemote:
      // If screen rect is set, the window will be moved to the target screen and then set fullscreen.
      if (argument['screen_rect'] == null) {
        // display can be used to control the offset of the window.
        await restoreWindowPosition(
          WindowType.RemoteDesktop,
          windowId: kWindowId!,
          peerId: argument['id'] as String?,
          display: argument['display'] as int?,
        );
      }
      break;
    case kAppTypeDesktopFileTransfer:
      await restoreWindowPosition(WindowType.FileTransfer,
          windowId: kWindowId!);
      break;
    case kAppTypeDesktopViewCamera:
      // If screen rect is set, the window will be moved to the target screen and then set fullscreen.
      if (argument['screen_rect'] == null) {
        // display can be used to control the offset of the window.
        await restoreWindowPosition(
          WindowType.ViewCamera,
          windowId: kWindowId!,
          peerId: argument['id'] as String?,
          // FIXME: fix display index.
          display: argument['display'] as int?,
        );
      }
      break;
    case kAppTypeDesktopPortForward:
      await restoreWindowPosition(WindowType.PortForward, windowId: kWindowId!);
      break;
    case kAppTypeDesktopTerminal:
      await restoreWindowPosition(WindowType.Terminal, windowId: kWindowId!);
      break;
    default:
      // no such appType
      exit(0);
  }
  // show window from hidden status
  WindowController.fromWindowId(kWindowId!).show();
}

void runConnectionManagerScreen() async {
  debugPrint('[CM] runConnectionManagerScreen started');
  await initEnv(kAppTypeConnectionManager);
  // 이벤트 리스너 시작 전에 isConnManager를 먼저 설정
  gFFI.chatModel.isConnManager = true;
  debugPrint('[CM] initEnv completed, isConnManager set to true');
  _runApp(
    '',
    const DesktopServerPage(),
    ThemeMode.light,
  );
  debugPrint('[CM] _runApp completed');
  final hide = await bind.cmGetConfig(name: "hide_cm") == 'true';
  debugPrint('[CM] hide_cm config: $hide');
  gFFI.serverModel.hideCm = hide;
  if (hide) {
    debugPrint('[CM] Calling hideCmWindow...');
    await hideCmWindow(isStartup: true);
  } else {
    debugPrint('[CM] Calling showCmWindow...');
    await showCmWindow(isStartup: true);
  }
  debugPrint('[CM] CM initialization complete');
  setResizable(false);
  // Start the uni links handler and redirect links to Native, not for Flutter.
  listenUniLinks(handleByFlutter: false);
}

bool _isCmReadyToShow = false;

showCmWindow({bool isStartup = false}) async {
  debugPrint('[CM] showCmWindow called, isStartup: $isStartup');
  if (isStartup) {
    debugPrint('[CM] Creating window options...');
    WindowOptions windowOptions = getHiddenTitleBarWindowOptions(
        size: kConnectionManagerWindowSizeClosedChat, alwaysOnTop: true);
    debugPrint('[CM] Waiting until ready to show...');
    await windowManager.waitUntilReadyToShow(windowOptions, null);
    debugPrint('[CM] Window ready, calling show/focus/opacity...');
    bind.mainHideDock();
    await Future.wait([
      windowManager.show(),
      windowManager.focus(),
      windowManager.setOpacity(1)
    ]);
    debugPrint('[CM] Setting size alignment...');
    // ensure initial window size to be changed
    await windowManager.setSizeAlignment(
        kConnectionManagerWindowSizeClosedChat, Alignment.topRight);
    _isCmReadyToShow = true;
    debugPrint('[CM] CM window shown successfully!');
  } else if (_isCmReadyToShow) {
    if (await windowManager.getOpacity() != 1) {
      await windowManager.setOpacity(1);
      await windowManager.focus();
      await windowManager.minimize(); //needed
      await windowManager.setSizeAlignment(
          kConnectionManagerWindowSizeClosedChat, Alignment.topRight);
      windowOnTop(null);
    }
  }
}

hideCmWindow({bool isStartup = false}) async {
  if (isStartup) {
    WindowOptions windowOptions = getHiddenTitleBarWindowOptions(
        size: kConnectionManagerWindowSizeClosedChat);
    windowManager.setOpacity(0);
    await windowManager.waitUntilReadyToShow(windowOptions, null);
    bind.mainHideDock();
    await windowManager.minimize();
    await windowManager.hide();
    _isCmReadyToShow = true;
  } else if (_isCmReadyToShow) {
    if (await windowManager.getOpacity() != 0) {
      await windowManager.setOpacity(0);
      bind.mainHideDock();
      await windowManager.minimize();
      await windowManager.hide();
    }
  }
}

void _runApp(
  String title,
  Widget home,
  ThemeMode themeMode,
) {
  // 모바일 상태바 배경색 설정
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Color(0xFFFEFEFE),
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light, // iOS
    ));
  }
  final botToastBuilder = BotToastInit();
  final isMobile = Platform.isAndroid || Platform.isIOS;
  runApp(RefreshWrapper(
    builder: (context) => GetMaterialApp(
      navigatorKey: globalKey,
      debugShowCheckedModeBanner: false,
      title: title,
      theme: MyTheme.lightTheme,
      darkTheme: MyTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: isMobile
          ? AnnotatedRegion<SystemUiOverlayStyle>(
              value: const SystemUiOverlayStyle(
                statusBarColor: Color(0xFFFEFEFE),
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
              ),
              child: home,
            )
          : home,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: supportedLocales,
      navigatorObservers: [
        // FirebaseAnalyticsObserver(analytics: analytics),
        BotToastNavigatorObserver(),
      ],
      builder: (context, child) {
        child = _keepScaleBuilder(context, child);
        child = botToastBuilder(context, child);
        if (isWindows) {
          child = _buildRoundedWindow(context, child);
        }
        return child;
      },
    ),
  ));
}

void runInstallPage() async {
  await windowManager.ensureInitialized();
  await initEnv(kAppTypeMain);
  _runApp('', const InstallPage(), MyTheme.currentThemeMode());
  WindowOptions windowOptions = getHiddenTitleBarWindowOptions(
      size: const Size(kMainWindowMinWidth, kMainWindowMinHeight),
      minimumSize: const Size(kMainWindowMinWidth, kMainWindowMinHeight),
      center: true);
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    windowManager.show();
    windowManager.focus();
    windowManager.setOpacity(1);
    windowManager.setAlignment(Alignment.center); // ensure
  });
}

/// 플랜 선택 창 실행
void runPlanSelectionScreen(Map<String, dynamic> argument) async {
  await initEnv(kAppTypeDesktopPlanSelection);
  final title = translate('Plan Selection');
  WindowController.fromWindowId(kWindowId!).setPreventClose(false);
  _runApp(
    title,
    DesktopPlanSelectionScreen(params: argument),
    ThemeMode.light,
  );
  WindowController.fromWindowId(kWindowId!).show();
}

/// 음성 채팅 요청 다이얼로그 창 실행
void runVoiceCallDialogScreen(Map<String, dynamic> argument) async {
  await initEnv(kAppTypeDesktopVoiceCallDialog);
  final title = translate('Voice Chat Request');
  final clientId = argument['client_id'] as int;
  final clientName = argument['client_name'] as String;
  final clientPeerId = argument['client_peer_id'] as String;
  WindowController.fromWindowId(kWindowId!).setPreventClose(false);
  _runApp(
    title,
    VoiceCallDialogPage(
      clientId: clientId,
      clientName: clientName,
      clientPeerId: clientPeerId,
    ),
    ThemeMode.light,
  );
  WindowController.fromWindowId(kWindowId!).show();
}

/// 카메라 공유 요청 다이얼로그 창 실행
void runCameraRequestDialogScreen(Map<String, dynamic> argument) async {
  await initEnv(kAppTypeDesktopCameraRequestDialog);
  final title = translate('Camera Share Request');
  final clientId = argument['client_id'] as int;
  final clientName = argument['client_name'] as String;
  final clientPeerId = argument['client_peer_id'] as String;
  WindowController.fromWindowId(kWindowId!).setPreventClose(false);
  _runApp(
    title,
    CameraRequestDialogPage(
      clientId: clientId,
      clientName: clientName,
      clientPeerId: clientPeerId,
    ),
    ThemeMode.light,
  );
  WindowController.fromWindowId(kWindowId!).show();
}

WindowOptions getHiddenTitleBarWindowOptions(
    {bool isMainWindow = false,
    Size? size,
    Size? minimumSize,
    bool center = false,
    bool? alwaysOnTop}) {
  var defaultTitleBarStyle = TitleBarStyle.hidden;
  // we do not hide titlebar on win7 because of the frame overflow.
  if (kUseCompatibleUiMode) {
    defaultTitleBarStyle = TitleBarStyle.normal;
  }
  return WindowOptions(
    size: size,
    minimumSize: minimumSize,
    center: center,
    backgroundColor: (isMacOS && isMainWindow) ? null : Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: defaultTitleBarStyle,
    alwaysOnTop: alwaysOnTop,
  );
}

class App extends StatefulWidget {
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.window.onPlatformBrightnessChanged = () {
      // 라이트 모드 고정
      Get.changeThemeMode(ThemeMode.light);
      // Synchronize the window theme of the system.
      updateSystemWindowTheme();
      if (desktopType == DesktopType.main) {
        bind.mainChangeTheme(dark: ThemeMode.light.toShortString());
      }
    };
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateOrientation());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _updateOrientation();
  }

  void _updateOrientation() {
    if (isDesktop) return;

    // Don't use `MediaQuery.of(context).orientation` in `didChangeMetrics()`,
    // my test (Flutter 3.19.6, Android 14) is always the reverse value.
    // https://github.com/flutter/flutter/issues/60899
    // stateGlobal.isPortrait.value =
    //     MediaQuery.of(context).orientation == Orientation.portrait;

    final orientation = View.of(context).physicalSize.aspectRatio > 1
        ? Orientation.landscape
        : Orientation.portrait;
    stateGlobal.isPortrait.value = orientation == Orientation.portrait;
  }

  @override
  Widget build(BuildContext context) {
    // final analytics = FirebaseAnalytics.instance;
    final botToastBuilder = BotToastInit();
    return RefreshWrapper(builder: (context) {
      return MultiProvider(
        providers: [
          // global configuration
          // use session related FFI when in remote control or file transfer page
          ChangeNotifierProvider.value(value: gFFI.ffiModel),
          ChangeNotifierProvider.value(value: gFFI.imageModel),
          ChangeNotifierProvider.value(value: gFFI.cursorModel),
          ChangeNotifierProvider.value(value: gFFI.canvasModel),
          ChangeNotifierProvider.value(value: gFFI.peerTabModel),
        ],
        child: GetMaterialApp(
          navigatorKey: globalKey,
          debugShowCheckedModeBanner: false,
          title: isWeb
              ? '${bind.mainGetAppNameSync()} Web Client V2 (Preview)'
              : bind.mainGetAppNameSync(),
          theme: MyTheme.lightTheme,
          darkTheme: MyTheme.darkTheme,
          themeMode: ThemeMode.light,
          home: isDesktop
              ? const AuthWrapper()
              : isWeb
                  ? WebHomePage()
                  : const AnnotatedRegion<SystemUiOverlayStyle>(
                      value: SystemUiOverlayStyle(
                        statusBarColor: Color(0xFFFEFEFE),
                        statusBarIconBrightness: Brightness.dark,
                        statusBarBrightness: Brightness.light,
                      ),
                      child: MobileAuthWrapper(),
                    ),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: supportedLocales,
          navigatorObservers: [
            // FirebaseAnalyticsObserver(analytics: analytics),
            BotToastNavigatorObserver(),
          ],
          builder: isAndroid
              ? (context, child) => AccessibilityListener(
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(1.0),
                      ),
                      child: child ?? Container(),
                    ),
                  )
              : (context, child) {
                  child = _keepScaleBuilder(context, child);
                  child = botToastBuilder(context, child);
                  if ((isDesktop && desktopType == DesktopType.main) ||
                      isWebDesktop) {
                    child = keyListenerBuilder(context, child);
                  }
                  if (isLinux) {
                    return buildVirtualWindowFrame(context, child);
                  } else if (isWindows) {
                    return _buildRoundedWindow(context, child);
                  } else {
                    return workaroundWindowBorder(context, child);
                  }
                },
        ),
      );
    });
  }
}

Widget _keepScaleBuilder(BuildContext context, Widget? child) {
  final data = MediaQuery.of(context);
  child = child ?? Container();

  // Override text scaling to ignore system text size settings
  var newData = data.copyWith(
    textScaler: TextScaler.linear(1.0),
  );

  // On Windows/Linux, compensate for system DPI scaling (125%, 150% etc.)
  // macOS Retina displays always report devicePixelRatio=2.0 regardless of
  // display scaling settings, so DPI compensation is not applicable on macOS.
  if ((Platform.isWindows || Platform.isLinux) && data.devicePixelRatio > 1.0) {
    final dpr = data.devicePixelRatio;
    newData = newData.copyWith(
      devicePixelRatio: 1.0,
      size: Size(data.size.width * dpr, data.size.height * dpr),
    );
    return MediaQuery(
      data: newData,
      child: Transform.scale(
        scale: 1.0 / dpr,
        alignment: Alignment.topLeft,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          maxWidth: data.size.width * dpr,
          maxHeight: data.size.height * dpr,
          child: child,
        ),
      ),
    );
  }

  return MediaQuery(
    data: newData,
    child: child,
  );
}

/// Windows 전용: 기본 창 래퍼 (Windows 11 네이티브 8px 둥근 모서리 적용)
/// Windows 11의 네이티브 둥근 모서리(8px)에 맞춰 Flutter 컨텐츠도 클리핑
Widget _buildRoundedWindow(BuildContext context, Widget? child) {
  // Windows 11 스타일 8px 둥근 모서리로 클리핑
  // Container와 ClipRRect 모두 동일한 borderRadius 적용
  return Container(
    decoration: BoxDecoration(
      color: Theme.of(context).scaffoldBackgroundColor,
      borderRadius: BorderRadius.circular(8),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: child ?? Container(),
    ),
  );
}

_registerEventHandler() {
  if (isDesktop && desktopType != DesktopType.main) {
    platformFFI.registerEventHandler('theme', 'theme', (evt) async {
      String? dark = evt['dark'];
      if (dark != null) {
        await MyTheme.changeDarkMode(MyTheme.themeModeFromString(dark));
      }
    });
    platformFFI.registerEventHandler('language', 'language', (_) async {
      reloadAllWindows();
    });
  }
  // Register native handlers.
  if (isDesktop) {
    platformFFI.registerEventHandler('native_ui', 'native_ui', (evt) async {
      NativeUiHandler.instance.onEvent(evt);
    });
  }
}

Widget keyListenerBuilder(BuildContext context, Widget? child) {
  return RawKeyboardListener(
    focusNode: FocusNode(),
    child: child ?? Container(),
    onKey: (RawKeyEvent event) {
      if (event.logicalKey == LogicalKeyboardKey.shiftLeft) {
        if (event is RawKeyDownEvent) {
          gFFI.peerTabModel.setShiftDown(true);
        } else if (event is RawKeyUpEvent) {
          gFFI.peerTabModel.setShiftDown(false);
        }
      }
    },
  );
}
