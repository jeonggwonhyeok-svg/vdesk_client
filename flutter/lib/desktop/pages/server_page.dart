// original cm window in Sciter version.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/audio_input.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/cm_file_model.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../common.dart';
import '../../common/widgets/chat_page.dart';
import '../../common/widgets/cm_custom_toggle.dart';
import '../../common/widgets/sidebar_icon_button.dart';
import '../../common/widgets/styled_form_widgets.dart';
import '../../models/file_model.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';

// CM 창 디자인 색상
const Color _cmBackgroundColor = Color(0xFFF7F7F7);
const Color _cmTextPrimary = Color(0xFF454447);
const Color _cmAccentColor = Color(0xFF5F71FF);
const Color _cmIconBgColor = Color(0xFFEFF1FF);

/// Client 데이터에서 platform 조회, 없으면 피어 캐시 fallback
String _getPeerPlatform(String peerId, {String peerPlatform = ''}) {
  if (peerPlatform.isNotEmpty) return peerPlatform;
  try {
    final peer = bind.mainGetPeerSync(id: peerId);
    final config = jsonDecode(peer);
    return config['info']?['platform'] ?? config['platform'] ?? '';
  } catch (e) {
    return '';
  }
}

/// 피어 캐시에서 OS 버전 정보 조회
String _getPeerOsVersion(String peerId) {
  try {
    final peer = bind.mainGetPeerSync(id: peerId);
    final config = jsonDecode(peer);
    return config['info']?['os_version'] ?? '';
  } catch (e) {
    return '';
  }
}

class DesktopServerPage extends StatefulWidget {
  const DesktopServerPage({Key? key}) : super(key: key);

  @override
  State<DesktopServerPage> createState() => _DesktopServerPageState();
}

class _DesktopServerPageState extends State<DesktopServerPage>
    with WindowListener, AutomaticKeepAliveClientMixin {
  final tabController = gFFI.serverModel.tabController;

  _DesktopServerPageState() {
    gFFI.ffiModel.updateEventListener(gFFI.sessionId, "");
    Get.put<DesktopTabController>(tabController);
    tabController.onRemoved = (_, id) {
      onRemoveId(id);
    };
  }

  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    Future.wait([gFFI.serverModel.closeAll(), gFFI.close()]).then((_) {
      if (isMacOS) {
        RdPlatformChannel.instance.terminate();
      } else {
        windowManager.setPreventClose(false);
        windowManager.close();
      }
    });
    super.onWindowClose();
  }

  void onRemoveId(String id) {
    if (tabController.state.value.tabs.isEmpty) {
      windowManager.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: gFFI.serverModel),
        ChangeNotifierProvider.value(value: gFFI.chatModel),
      ],
      child: Consumer<ServerModel>(
        builder: (context, serverModel, child) {
          final body = Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: ConnectionManager(),
          );
          return isLinux
              ? buildVirtualWindowFrame(context, body)
              : workaroundWindowBorder(context, body);
        },
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class ConnectionManager extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => ConnectionManagerState();
}

class ConnectionManagerState extends State<ConnectionManager>
    with WidgetsBindingObserver {
  final RxBool _controlPageBlock = false.obs;
  final RxBool _sidePageBlock = false.obs;

  ConnectionManagerState() {
    gFFI.serverModel.tabController.onSelected = (client_id_str) {
      final client_id = int.tryParse(client_id_str);
      if (client_id != null) {
        final client =
            gFFI.serverModel.clients.firstWhereOrNull((e) => e.id == client_id);
        if (client != null) {
          gFFI.chatModel.changeCurrentKey(MessageKey(client.peerId, client.id));
          if (client.unreadChatMessageCount.value > 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              client.unreadChatMessageCount.value = 0;
              gFFI.chatModel.showChatPage(MessageKey(client.peerId, client.id));
            });
          }
          windowManager.setTitle(getWindowNameWithId(client.peerId));
          gFFI.cmFileModel.updateCurrentClientId(client.id);
        }
      }
    };
    gFFI.chatModel.isConnManager = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      if (!allowRemoteCMModification()) {
        shouldBeBlocked(_controlPageBlock, null);
        shouldBeBlocked(_sidePageBlock, null);
      }
    }
  }

  @override
  void initState() {
    gFFI.serverModel.updateClientState();
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    pointerHandler(PointerEvent e) {
      if (serverModel.cmHiddenTimer != null) {
        serverModel.cmHiddenTimer!.cancel();
        serverModel.cmHiddenTimer = null;
        debugPrint("CM hidden timer has been canceled");
      }
    }

    return serverModel.clients.isEmpty
        ? Column(
            children: [
              buildTitleBar(),
              Expanded(
                child: Center(
                  child: Text(translate("Waiting")),
                ),
              ),
            ],
          )
        : Listener(
            onPointerDown: pointerHandler,
            onPointerMove: pointerHandler,
            child: DesktopTab(
              showTitle: false,
              showMaximize: false,
              showMinimize: true,
              showClose: true,
              onWindowCloseButton: handleWindowCloseButton,
              controller: serverModel.tabController,
              selectedBorderColor: MyTheme.accent,
              maxLabelWidth: 100,
              tail: null, //buildScrollJumper(),
              tabBuilder: (key, icon, label, themeConf) {
                final client = serverModel.clients
                    .firstWhereOrNull((client) => client.id.toString() == key);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Tooltip(
                        message: key,
                        waitDuration: Duration(seconds: 1),
                        child: label),
                    unreadMessageCountBuilder(client?.unreadChatMessageCount)
                        .marginOnly(left: 4),
                  ],
                );
              },
              pageViewBuilder: (pageView) => LayoutBuilder(
                builder: (context, constrains) {
                  var borderWidth = 0.0;
                  if (constrains.maxWidth >
                      kConnectionManagerWindowSizeClosedChat.width) {
                    borderWidth = kConnectionManagerWindowSizeOpenChat.width -
                        constrains.maxWidth;
                  } else {
                    borderWidth = kConnectionManagerWindowSizeClosedChat.width -
                        constrains.maxWidth;
                  }
                  if (borderWidth < 0 || borderWidth > 50) {
                    borderWidth = 0;
                  }
                  final realClosedWidth =
                      kConnectionManagerWindowSizeClosedChat.width -
                          borderWidth;
                  final realChatPageWidth =
                      constrains.maxWidth - realClosedWidth;
                  final row = Row(children: [
                    if (constrains.maxWidth >
                        kConnectionManagerWindowSizeClosedChat.width)
                      Consumer<ChatModel>(
                          builder: (_, model, child) => SizedBox(
                                width: realChatPageWidth,
                                child: allowRemoteCMModification()
                                    ? buildSidePage()
                                    : buildRemoteBlock(
                                        child: buildSidePage(),
                                        block: _sidePageBlock,
                                        mask: true),
                              )),
                    SizedBox(
                        width: realClosedWidth,
                        child: SizedBox(
                            width: realClosedWidth,
                            child: allowRemoteCMModification()
                                ? pageView
                                : buildRemoteBlock(
                                    child: _buildKeyEventBlock(pageView),
                                    block: _controlPageBlock,
                                    mask: false,
                                  ))),
                  ]);
                  return Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: row,
                  );
                },
              ),
            ),
          );
  }

  Widget buildSidePage() {
    final selected = gFFI.serverModel.tabController.state.value.selected;
    if (selected < 0 || selected >= gFFI.serverModel.clients.length) {
      return Offstage();
    }
    final clientType = gFFI.serverModel.clients[selected].type_();
    if (clientType == ClientType.file) {
      return _FileTransferLogPage();
    } else {
      return ChatPage(type: ChatPageType.desktopCM);
    }
  }

  Widget _buildKeyEventBlock(Widget child) {
    return ExcludeFocus(child: child, excluding: true);
  }

  Widget buildTitleBar() {
    return SizedBox(
      height: kDesktopRemoteTabBarHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _AppIcon(),
          Expanded(
            child: GestureDetector(
              onPanStart: (d) {
                windowManager.startDragging();
              },
              child: Container(
                color: Theme.of(context).colorScheme.surface,
              ),
            ),
          ),
          const SizedBox(
            width: 4.0,
          ),
          const _CloseButton()
        ],
      ),
    );
  }

  Widget buildScrollJumper() {
    final offstage = gFFI.serverModel.clients.length < 2;
    final sc = gFFI.serverModel.tabController.state.value.scrollController;
    return Offstage(
        offstage: offstage,
        child: Row(
          children: [
            ActionIcon(
                icon: Icons.arrow_left, iconSize: 22, onTap: sc.backward),
            ActionIcon(
                icon: Icons.arrow_right, iconSize: 22, onTap: sc.forward),
          ],
        ));
  }

  Future<bool> handleWindowCloseButton() async {
    var tabController = gFFI.serverModel.tabController;
    final connLength = tabController.length;
    if (connLength <= 1) {
      windowManager.close();
      return true;
    } else {
      final bool res;
      if (!option2bool(kOptionEnableConfirmClosingTabs,
          bind.mainGetLocalOption(key: kOptionEnableConfirmClosingTabs))) {
        res = true;
      } else {
        res = await closeConfirmDialog();
      }
      if (res) {
        windowManager.close();
      }
      return res;
    }
  }
}

Widget buildConnectionCard(Client client) {
  return Consumer<ServerModel>(
    builder: (context, value, child) {
      // 수락 전/후 모두 동일한 배경색 사용 (권한 카드가 보이도록)
      return Container(
        color: _cmBackgroundColor,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          key: ValueKey(client.id),
          children: [
            _CmHeader(client: client),
            const SizedBox(height: 10),
            // 음성 채팅 중일 때 카드 표시 (헤더와 권한 카드 사이)
            if (client.inVoiceCall) ...[
              _VoiceChatCard(client: client),
              const SizedBox(height: 10),
            ],
            client.type_() == ClientType.file ||
                    client.type_() == ClientType.portForward ||
                    client.type_() == ClientType.terminal ||
                    client.disconnected
                ? Offstage()
                : _PrivilegeBoard(client: client),
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _CmControlPanel(client: client),
              ),
            )
          ],
        ).paddingSymmetric(vertical: 4.0, horizontal: 8.0),
      );
    },
  );
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 4.0),
      child: loadIcon(30),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        windowManager.close();
      },
      icon: const Icon(
        IconFont.close,
        size: 18,
      ),
      splashColor: Colors.transparent,
      hoverColor: Colors.transparent,
    );
  }
}

class _CmHeader extends StatefulWidget {
  final Client client;

  const _CmHeader({Key? key, required this.client}) : super(key: key);

  @override
  State<_CmHeader> createState() => _CmHeaderState();
}

class _CmHeaderState extends State<_CmHeader>
    with AutomaticKeepAliveClientMixin {
  Client get client => widget.client;

  final _time = 0.obs;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(Duration(seconds: 1), (_) {
      if (client.authorized && !client.disconnected) {
        _time.value = _time.value + 1;
      }
    });
    // Call onSelected in post frame callback, since we cannot guarantee that the callback will not call setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      gFFI.serverModel.tabController.onSelected?.call(client.id.toString());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 피어 ID를 포맷팅 (123 456 789 형태)
  String _formatPeerId(String peerId) {
    final cleanId = peerId.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanId.length <= 3) return cleanId;

    final buffer = StringBuffer();
    for (int i = 0; i < cleanId.length; i++) {
      if (i > 0 && i % 3 == 0) buffer.write(' ');
      buffer.write(cleanId[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // 연결됨 상태일 때는 기존 스타일, 권한 요청 중일 때는 새 디자인
    if (client.authorized) {
      return _buildAuthorizedHeader(context);
    } else {
      return _buildAccessRequestHeader(context);
    }
  }

  /// 권한 요청 중 헤더 (새 디자인)
  Widget _buildAccessRequestHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // 타이틀 - 클라이언트 타입에 따라 다른 텍스트
          Text(
            client.type_() == ClientType.file
                ? translate('File transfer request')
                : translate('Request access to your device'),
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: _cmTextPrimary,
            ),
          ),
          const SizedBox(height: 20),
          // 시스템 아이콘 (OS에 따라 다름)
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _cmIconBgColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: getPlatformImage(
                _getPeerPlatform(client.peerId, peerPlatform: client.peerPlatform),
                size: 24,
                color: _cmAccentColor,
                version: _getPeerOsVersion(client.peerId),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 요청 유저 이름
          Text(
            '[${client.name}]',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: _cmTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          // 피어 ID
          Text(
            '[${_formatPeerId(client.peerId)}]',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 16,
              color: _cmTextPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// 연결됨 상태 헤더 (새 디자인)
  Widget _buildAuthorizedHeader(BuildContext context) {
    // 클라이언트 유형에 따른 상태 텍스트와 아이콘
    String statusText;
    String statusIcon;
    switch (client.type_()) {
      case ClientType.camera:
        statusText = translate('Camera sharing');
        statusIcon = 'assets/icons/camera.svg';
        break;
      case ClientType.file:
        statusText = translate('File transfer');
        statusIcon = 'assets/icons/file-sender-folder.svg';
        break;
      default:
        statusText = translate('Screen sharing');
        statusIcon = 'assets/icons/remote_screen.svg';
    }

    // 카드 스펙: 568x182, 배경 #FFFFFF, 그림자 #1B21511A 10%, 코너 16px
    return Container(
      width: 568,
      height: 182,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0x1A1B2151),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // 왼쪽: 상태 아이콘 + 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상태 텍스트 (유형에 따라 다름)
                Row(
                  children: [
                    SvgPicture.asset(
                      statusIcon,
                      width: 24,
                      height: 24,
                      colorFilter: const ColorFilter.mode(
                        Color(0xFF8F8E95),
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusText,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: _cmTextPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 시스템 아이콘 + 유저 정보
                Row(
                  children: [
                    // 시스템 아이콘 (OS에 따라 다름)
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: _cmIconBgColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: getPlatformImage(
                          _getPeerPlatform(client.peerId, peerPlatform: client.peerPlatform),
                          size: 24,
                          color: _cmAccentColor,
                          version: _getPeerOsVersion(client.peerId),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // 유저 정보
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '[${client.name}]',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: _cmTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '[${_formatPeerId(client.peerId)}]',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 16,
                              color: _cmTextPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 오른쪽: 채팅 버튼 + 연결해제 버튼 (시스템 아이콘과 같은 라인)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 상태 텍스트 라인과 맞추기 위한 스페이서 (24px)
              const SizedBox(height: 24),
              const SizedBox(height: 16),
              // 시스템 아이콘(80px)과 같은 높이에서 수직 가운데 정렬
              SizedBox(
                height: 80,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 채팅/파일 버튼 (SidebarIconButton 스타일 - 테마 기본값 52px)
                      if (client.type_() == ClientType.remote ||
                          client.type_() == ClientType.file ||
                          client.type_() == ClientType.camera)
                        SidebarIconButton(
                          iconPath: client.type_() == ClientType.file
                              ? 'assets/icons/file-sender-folder.svg'
                              : 'assets/icons/cm-chat.svg',
                          onTap: () => checkClickTime(client.id, () {
                            if (client.type_() == ClientType.file) {
                              gFFI.chatModel.toggleCMFilePage();
                            } else {
                              gFFI.chatModel.toggleCMChatPage(
                                  MessageKey(client.peerId, client.id));
                            }
                          }),
                        ),
                      const SizedBox(width: 8),
                      // 연결해제 버튼 (빨간색)
                      _buildDisconnectButton(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 연결해제 버튼 (빨간색 컴팩트 버튼)
  /// 높이는 모든 버튼과 동일 (52px)
  Widget _buildDisconnectButton() {
    // 파일전송일 때는 "전송 끊기", 그 외는 "연결 끊기"
    final buttonText = client.type_() == ClientType.file
        ? translate('Stop Transfer')
        : translate('Disconnect');

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => checkClickTime(client.id, () {
          bind.cmCloseConnection(connId: client.id);
        }),
        child: Container(
          height: 52, // 모든 버튼 동일 높이
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFFE3E3E),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              buttonText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _PrivilegeBoard extends StatefulWidget {
  final Client client;

  const _PrivilegeBoard({Key? key, required this.client}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _PrivilegeBoardState();
}

class _PrivilegeBoardState extends State<_PrivilegeBoard> {
  late final client = widget.client;

  /// 권한 카드 빌드 (새 디자인)
  /// 카드 스펙: 278x98, radius 16px, padding 16px
  Widget _buildPermissionCard({
    required String iconAsset,
    required String label,
    required bool enabled,
    required Function(bool) onChanged,
  }) {
    return Container(
      width: 278,
      height: 98,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0x1A1B2151),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 윗줄: 아이콘 + 텍스트
          Row(
            children: [
              SvgPicture.asset(
                iconAsset,
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(
                  _cmAccentColor,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    color: _cmTextPrimary,
                  ),
                ),
              ),
            ],
          ),
          // 아랫줄: 토글 (오른쪽 정렬)
          Align(
            alignment: Alignment.centerRight,
            child: CmCustomToggle(
              value: enabled,
              onChanged: (value) =>
                  checkClickTime(client.id, () => onChanged(value)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 권한 요청 중이든 연결됨 상태든 동일한 카드 스타일 사용
    return _buildAccessRequestPrivilegeBoard();
  }

  /// 권한 요청 중 - 새 디자인 (카드 형태)
  Widget _buildAccessRequestPrivilegeBoard() {
    final permissions = client.type_() == ClientType.camera
        ? [
            _buildPermissionCard(
              iconAsset: 'assets/icons/cm-access-audio.svg',
              label: translate('Enable audio'),
              enabled: client.audio,
              onChanged: (enabled) {
                bind.cmSwitchPermission(
                    connId: client.id, name: "audio", enabled: enabled);
                setState(() => client.audio = enabled);
              },
            ),
            _buildPermissionCard(
              iconAsset: 'assets/icons/cm-access-camera.svg',
              label: translate('Enable recording session'),
              enabled: client.recording,
              onChanged: (enabled) {
                bind.cmSwitchPermission(
                    connId: client.id, name: "recording", enabled: enabled);
                setState(() => client.recording = enabled);
              },
            ),
          ]
        : [
            _buildPermissionCard(
              iconAsset: 'assets/icons/cm-access-keyboard.svg',
              label: translate('Enable keyboard/mouse'),
              enabled: client.keyboard,
              onChanged: (enabled) {
                bind.cmSwitchPermission(
                    connId: client.id, name: "keyboard", enabled: enabled);
                setState(() => client.keyboard = enabled);
              },
            ),
            _buildPermissionCard(
              iconAsset: 'assets/icons/cm-access-clipboard.svg',
              label: translate('Enable clipboard'),
              enabled: client.clipboard,
              onChanged: (enabled) {
                bind.cmSwitchPermission(
                    connId: client.id, name: "clipboard", enabled: enabled);
                setState(() => client.clipboard = enabled);
              },
            ),
            _buildPermissionCard(
              iconAsset: 'assets/icons/cm-access-audio.svg',
              label: translate('Enable audio'),
              enabled: client.audio,
              onChanged: (enabled) {
                bind.cmSwitchPermission(
                    connId: client.id, name: "audio", enabled: enabled);
                setState(() => client.audio = enabled);
              },
            ),
            _buildPermissionCard(
              iconAsset: 'assets/icons/cm-access-filecontrol.svg',
              label: translate('Enable file copy and paste'),
              enabled: client.file,
              onChanged: (enabled) {
                bind.cmSwitchPermission(
                    connId: client.id, name: "file", enabled: enabled);
                setState(() => client.file = enabled);
              },
            ),
            _buildPermissionCard(
              iconAsset: 'assets/icons/cm-access-restart.svg',
              label: translate('Enable remote restart'),
              enabled: client.restart,
              onChanged: (enabled) {
                bind.cmSwitchPermission(
                    connId: client.id, name: "restart", enabled: enabled);
                setState(() => client.restart = enabled);
              },
            ),
            _buildPermissionCard(
              iconAsset: 'assets/icons/cm-access-camera.svg',
              label: translate('Enable recording session'),
              enabled: client.recording,
              onChanged: (enabled) {
                bind.cmSwitchPermission(
                    connId: client.id, name: "recording", enabled: enabled);
                setState(() => client.recording = enabled);
              },
            ),
          ];

    // 2열 그리드로 배치 (가운데 정렬, 카드 간격 10px)
    return Column(
      children: [
        for (int i = 0; i < permissions.length; i += 2)
          Padding(
            padding:
                EdgeInsets.only(bottom: i + 2 < permissions.length ? 10 : 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                permissions[i],
                const SizedBox(width: 10),
                if (i + 1 < permissions.length)
                  permissions[i + 1]
                else
                  const SizedBox(width: 278),
              ],
            ),
          ),
      ],
    );
  }
}

/// 음성 채팅 중 카드 (연결됨 상태 헤더와 유사한 스타일)
class _VoiceChatCard extends StatefulWidget {
  final Client client;

  const _VoiceChatCard({Key? key, required this.client}) : super(key: key);

  @override
  State<_VoiceChatCard> createState() => _VoiceChatCardState();
}

class _VoiceChatCardState extends State<_VoiceChatCard> {
  bool _isMicOn = true;
  bool _isSpeakerOn = true;
  String _savedMicDevice = '';

  @override
  void initState() {
    super.initState();
    // 현재 마이크 장치 저장
    Future.delayed(Duration.zero, () async {
      _savedMicDevice = await bind.getVoiceCallInputDevice(isCm: true);
      if (_savedMicDevice.isEmpty) {
        final devices = (await bind.mainGetSoundInputs()).toList();
        if (devices.isNotEmpty) {
          _savedMicDevice = devices.first;
        }
      }
    });
  }

  void _toggleMic() async {
    setState(() {
      _isMicOn = !_isMicOn;
    });
    if (_isMicOn) {
      await bind.setVoiceCallInputDevice(isCm: true, device: _savedMicDevice);
    } else {
      await bind.setVoiceCallInputDevice(isCm: true, device: '');
    }
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    bind.cmSwitchPermission(
      connId: widget.client.id,
      name: 'audio',
      enabled: _isSpeakerOn,
    );
  }

  void _disconnect() {
    bind.cmCloseVoiceCall(id: widget.client.id);
  }

  /// 피어 ID를 포맷팅 (123 456 789 형태)
  String _formatPeerId(String peerId) {
    final cleanId = peerId.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanId.length <= 3) return cleanId;

    final buffer = StringBuffer();
    for (int i = 0; i < cleanId.length; i++) {
      if (i > 0 && i % 3 == 0) buffer.write(' ');
      buffer.write(cleanId[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    // 카드 스펙: 568x182, 배경 #FFFFFF, 그림자, 코너 16px
    return Container(
      width: 568,
      height: 182,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0x1A1B2151),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // 왼쪽: 아이콘 + 유저 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상태 텍스트
                Row(
                  children: [
                    SvgPicture.asset(
                      'assets/icons/voice-mike.svg',
                      width: 24,
                      height: 24,
                      colorFilter: const ColorFilter.mode(
                        Color(0xFF8F8E95),
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      translate('Voice Chatting'),
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: _cmTextPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 시스템 아이콘 + 유저 정보
                Row(
                  children: [
                    // 시스템 아이콘
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: _cmIconBgColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: getPlatformImage(
                          _getPeerPlatform(widget.client.peerId, peerPlatform: widget.client.peerPlatform),
                          size: 24,
                          color: _cmAccentColor,
                          version: _getPeerOsVersion(widget.client.peerId),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // 유저 정보
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '[${widget.client.name}]',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: _cmTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '[${_formatPeerId(widget.client.peerId)}]',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 16,
                              color: _cmTextPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 오른쪽: 마이크/스피커 버튼 + 연결 끊기 버튼
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SizedBox(height: 24),
              const SizedBox(height: 16),
              SizedBox(
                height: 80,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 마이크 버튼
                      _buildControlButton(
                        iconPath: _isMicOn
                            ? 'assets/icons/voice-mike.svg'
                            : 'assets/icons/voice-mike-off.svg',
                        isActive: _isMicOn,
                        onPressed: _toggleMic,
                      ),
                      const SizedBox(width: 8),
                      // 스피커 버튼
                      _buildControlButton(
                        iconPath: _isSpeakerOn
                            ? 'assets/icons/voice-sound.svg'
                            : 'assets/icons/voice-sound-off.svg',
                        isActive: _isSpeakerOn,
                        onPressed: _toggleSpeaker,
                      ),
                      const SizedBox(width: 8),
                      // 연결 끊기 버튼
                      _buildDisconnectButton(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 컨트롤 버튼 (마이크/스피커) - 52px 높이, hover 효과 포함
  Widget _buildControlButton({
    required String iconPath,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    final RxBool isHovered = false.obs;
    // SidebarIconButton 테마 값 사용
    final theme = MyTheme.sidebarIconButton(context);

    return InkWell(
      onTap: onPressed,
      onHover: (value) => isHovered.value = value,
      borderRadius: BorderRadius.circular(8),
      child: Obx(() => Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive
                    ? (isHovered.value
                        ? theme.hoverBorderColor
                        : Colors.grey.shade300)
                    : Colors.red.shade300,
                width: 1,
              ),
            ),
            child: Center(
              child: SvgPicture.asset(
                iconPath,
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(
                  isActive
                      ? (isHovered.value
                          ? theme.hoverIconColor
                          : Colors.grey.shade700)
                      : Colors.red,
                  BlendMode.srcIn,
                ),
              ),
            ),
          )),
    );
  }

  /// 연결 끊기 버튼 (빨간색) - 52px 높이
  Widget _buildDisconnectButton() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _disconnect,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFFE3E3E),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                'assets/icons/voice-unconnection.svg',
                width: 20,
                height: 20,
                colorFilter:
                    const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              ),
              const SizedBox(width: 8),
              Text(
                translate('Disconnect'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
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

const double buttonBottomMargin = 8;

class _CmControlPanel extends StatelessWidget {
  final Client client;

  const _CmControlPanel({Key? key, required this.client}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return client.authorized
        ? client.disconnected
            ? buildDisconnected(context)
            : buildAuthorized(context)
        : buildUnAuthorized(context);
  }

  buildAuthorized(BuildContext context) {
    final bool canElevate = bind.cmCanElevate();
    final model = Provider.of<ServerModel>(context);
    final showElevation = canElevate &&
        model.showElevation &&
        client.type_() == ClientType.remote;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 하단 음성 통화 버튼들 주석 처리 (새로운 _VoiceChatCard로 대체됨)
        // Offstage(
        //   offstage: !client.inVoiceCall,
        //   child: Row(
        //     children: [
        //       Expanded(
        //         child: buildButton(context,
        //             color: MyTheme.accent,
        //             onClick: null, onTapDown: (details) async {
        //           final devicesInfo =
        //               await AudioInput.getDevicesInfo(true, true);
        //           List<String> devices = devicesInfo['devices'] as List<String>;
        //           if (devices.isEmpty) {
        //             msgBox(
        //               gFFI.sessionId,
        //               'custom-nocancel-info',
        //               'Prompt',
        //               'no_audio_input_device_tip',
        //               '',
        //               gFFI.dialogManager,
        //             );
        //             return;
        //           }
        //
        //           String currentDevice = devicesInfo['current'] as String;
        //           final x = details.globalPosition.dx;
        //           final y = details.globalPosition.dy;
        //           final position = RelativeRect.fromLTRB(x, y, x, y);
        //           showMenu(
        //             context: context,
        //             position: position,
        //             items: devices
        //                 .map((d) => PopupMenuItem<String>(
        //                       value: d,
        //                       height: 18,
        //                       padding: EdgeInsets.zero,
        //                       onTap: () => AudioInput.setDevice(d, true, true),
        //                       child: IgnorePointer(
        //                           child: RadioMenuButton(
        //                         value: d,
        //                         groupValue: currentDevice,
        //                         onChanged: (v) {
        //                           if (v != null) {
        //                             AudioInput.setDevice(v, true, true);
        //                           }
        //                         },
        //                         child: Container(
        //                           child: Text(
        //                             d,
        //                             overflow: TextOverflow.ellipsis,
        //                             maxLines: 1,
        //                           ),
        //                           constraints: BoxConstraints(
        //                               maxWidth:
        //                                   kConnectionManagerWindowSizeClosedChat
        //                                           .width -
        //                                       80),
        //                         ),
        //                       )),
        //                     ))
        //                 .toList(),
        //           );
        //         },
        //             icon: Icon(
        //               Icons.call_rounded,
        //               color: Colors.white,
        //               size: 14,
        //             ),
        //             text: "Audio input",
        //             textColor: Colors.white),
        //       ),
        //       Expanded(
        //         child: buildButton(
        //           context,
        //           color: Colors.red,
        //           onClick: () => closeVoiceCall(),
        //           icon: Icon(
        //             Icons.call_end_rounded,
        //             color: Colors.white,
        //             size: 14,
        //           ),
        //           text: "Stop voice call",
        //           textColor: Colors.white,
        //         ),
        //       )
        //     ],
        //   ),
        // ),
        // // 음성 채팅 요청 버튼 (CM 스타일 - 52px 높이)
        // Offstage(
        //   offstage: !client.incomingVoiceCall,
        //   child: Padding(
        //     padding: const EdgeInsets.symmetric(horizontal: 16),
        //     child: Row(
        //       children: [
        //         // 수락 버튼 (파란색 배경 + 전화 아이콘)
        //         Expanded(
        //           child: _buildVoiceCallButton(
        //             label: translate("Accept"),
        //             icon: Icons.call_rounded,
        //             backgroundColor: _cmAccentColor,
        //             onPressed: () => handleVoiceCall(true),
        //           ),
        //         ),
        //         const SizedBox(width: 12),
        //         // 거부 버튼 (빨간색 배경 + X 아이콘)
        //         Expanded(
        //           child: _buildVoiceCallButton(
        //             label: translate("Dismiss"),
        //             icon: Icons.close_rounded,
        //             backgroundColor: const Color(0xFFFE3E3E),
        //             onPressed: () => handleVoiceCall(false),
        //           ),
        //         ),
        //       ],
        //     ),
        //   ),
        // ),
        Offstage(
          offstage: !client.fromSwitch,
          child: buildButton(context,
              color: Colors.purple,
              onClick: () => handleSwitchBack(context),
              icon: Icon(Icons.reply, color: Colors.white),
              text: "Switch Sides",
              textColor: Colors.white),
        ),
        Offstage(
          offstage: !showElevation,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: StyledCompactButton(
              label: translate('Elevate'),
              fillWidth: true,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              onPressed: () {
                handleElevate(context);
                windowManager.minimize();
              },
            ),
          ),
        ),
        // 연결해제 버튼은 상단 헤더에 있으므로 하단에서 제거
      ],
    ).marginOnly(bottom: buttonBottomMargin);
  }

  buildDisconnected(BuildContext context) {
    // 파일 전송 타입은 상단 헤더에 "전송 끊기" 버튼이 있으므로 하단 닫기 버튼 숨김
    if (client.type_() == ClientType.file) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
            child: buildButton(context,
                color: MyTheme.accent,
                onClick: handleClose,
                text: 'Close',
                textColor: Colors.white)),
      ],
    ).marginOnly(bottom: buttonBottomMargin);
  }

  buildUnAuthorized(BuildContext context) {
    final bool canElevate = bind.cmCanElevate();
    final model = Provider.of<ServerModel>(context);
    final showElevation = canElevate &&
        model.showElevation &&
        client.type_() == ClientType.remote;
    final showAccept = model.approveMode != 'password';

    // 새 디자인: 거절/수락 버튼 (logOutConfirmDialog 스타일)
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 권한 상승 버튼 (두 카드 + 간격 너비: 278 + 10 + 278 = 566)
        Offstage(
          offstage: !showElevation || !showAccept,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildElevateButton(
              context,
              label: translate('Accept and Elevate'),
              onPressed: () {
                handleAccept(context);
                handleElevate(context);
                windowManager.minimize();
              },
            ),
          ),
        ),
        // 거절/수락 버튼 (각 카드 너비: 278, 간격: 10)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 거절 버튼 (Outlined) - 카드 너비
            SizedBox(
              width: 278,
              child: StyledOutlinedButton(
                label: translate("Decline"),
                onPressed: handleDisconnect,
                height: 52,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(width: 10),
            // 수락 버튼 (Primary) - 카드 너비
            if (showAccept)
              SizedBox(
                width: 278,
                child: StyledCompactButton(
                  label: translate("Accept"),
                  onPressed: () {
                    handleAccept(context);
                    windowManager.minimize();
                  },
                  height: 52,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  fillWidth: true,
                ),
              ),
          ],
        ),
      ],
    ).marginOnly(bottom: buttonBottomMargin);
  }

  // /// 음성 채팅 요청 버튼 (아이콘 + 텍스트, 52px 높이) - 새로운 _VoiceChatCard로 대체됨
  // Widget _buildVoiceCallButton({
  //   required String label,
  //   required IconData icon,
  //   required Color backgroundColor,
  //   required VoidCallback onPressed,
  // }) {
  //   return MouseRegion(
  //     cursor: SystemMouseCursors.click,
  //     child: GestureDetector(
  //       onTap: onPressed,
  //       child: Container(
  //         height: 52,
  //         decoration: BoxDecoration(
  //           color: backgroundColor,
  //           borderRadius: BorderRadius.circular(8),
  //         ),
  //         child: Row(
  //           mainAxisAlignment: MainAxisAlignment.center,
  //           children: [
  //             Icon(icon, color: Colors.white, size: 20),
  //             const SizedBox(width: 8),
  //             Text(
  //               label,
  //               style: const TextStyle(
  //                 color: Colors.white,
  //                 fontSize: 14,
  //                 fontWeight: FontWeight.w500,
  //               ),
  //             ),
  //           ],
  //         ),
  //       ),
  //     ),
  //   );
  // }

  Widget buildButton(BuildContext context,
      {required Color? color,
      GestureTapCallback? onClick,
      Widget? icon,
      BoxBorder? border,
      required String text,
      required Color? textColor,
      String? tooltip,
      GestureTapDownCallback? onTapDown}) {
    assert(!(onClick == null && onTapDown == null));
    Widget textWidget;
    if (icon != null) {
      textWidget = Text(
        translate(text),
        style: TextStyle(color: textColor),
        textAlign: TextAlign.center,
      );
    } else {
      textWidget = Expanded(
        child: Text(
          translate(text),
          style: TextStyle(color: textColor),
          textAlign: TextAlign.center,
        ),
      );
    }
    final borderRadius = BorderRadius.circular(10.0);
    final btn = Container(
      height: 28,
      decoration: BoxDecoration(
          color: color, borderRadius: borderRadius, border: border),
      child: InkWell(
        borderRadius: borderRadius,
        onTap: () {
          if (onClick == null) return;
          checkClickTime(client.id, onClick);
        },
        onTapDown: (details) {
          if (onTapDown == null) return;
          checkClickTime(client.id, () {
            onTapDown.call(details);
          });
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Offstage(offstage: icon == null, child: icon).marginOnly(right: 5),
            textWidget,
          ],
        ),
      ),
    );
    return (tooltip != null
            ? Tooltip(
                message: translate(tooltip),
                child: btn,
              )
            : btn)
        .marginAll(4);
  }

  void handleDisconnect() {
    bind.cmCloseConnection(connId: client.id);
  }

  void handleAccept(BuildContext context) {
    final model = Provider.of<ServerModel>(context, listen: false);
    model.sendLoginResponse(client, true);
  }

  void handleElevate(BuildContext context) {
    final model = Provider.of<ServerModel>(context, listen: false);
    model.setShowElevation(false);
    bind.cmElevatePortable(connId: client.id);
  }

  void handleClose() async {
    await bind.cmRemoveDisconnectedConnection(connId: client.id);
    if (await bind.cmGetClientsLength() == 0) {
      windowManager.close();
    }
  }

  void handleSwitchBack(BuildContext context) {
    bind.cmSwitchBack(connId: client.id);
  }

  void handleVoiceCall(bool accept) {
    bind.cmHandleIncomingVoiceCall(id: client.id, accept: accept);
  }

  void closeVoiceCall() {
    bind.cmCloseVoiceCall(id: client.id);
  }

  /// 권한 상승 버튼 (아이콘 포함 스타일)
  /// 권한 상승 버튼 (수락 버튼 스타일, 두 카드 너비)
  Widget _buildElevateButton(
    BuildContext context, {
    required String label,
    required VoidCallback onPressed,
  }) {
    // 두 카드 + 간격 너비: 278 + 10 + 278 = 566
    return SizedBox(
      width: 566,
      child: StyledCompactButton(
        label: label,
        onPressed: onPressed,
        height: 52,
        padding: const EdgeInsets.symmetric(vertical: 12),
        fillWidth: true,
      ),
    );
  }
}

void checkClickTime(int id, Function() callback) async {
  if (allowRemoteCMModification()) {
    callback();
    return;
  }
  var clickCallbackTime = DateTime.now().millisecondsSinceEpoch;
  await bind.cmCheckClickTime(connId: id);
  Timer(const Duration(milliseconds: 120), () async {
    var d = clickCallbackTime - await bind.cmGetClickTime();
    if (d > 120) callback();
  });
}

bool allowRemoteCMModification() {
  return option2bool(kOptionAllowRemoteCmModification,
      bind.mainGetLocalOption(key: kOptionAllowRemoteCmModification));
}

class _FileTransferLogPage extends StatefulWidget {
  _FileTransferLogPage({Key? key}) : super(key: key);

  @override
  State<_FileTransferLogPage> createState() => __FileTransferLogPageState();
}

class __FileTransferLogPageState extends State<_FileTransferLogPage> {
  @override
  Widget build(BuildContext context) {
    return statusList();
  }

  Widget generateCard(Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(
          Radius.circular(16.0),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0x1A1B2151),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  /// 파일 전송 아이콘 (파일 전송 창 스타일과 동일)
  Widget iconLabel(CmFileLog item) {
    const iconColor = Color(0xFF94A0FF);
    String iconPath;

    switch (item.action) {
      case CmFileAction.none:
        return Container();
      case CmFileAction.remove:
        // 삭제 아이콘
        iconPath = "assets/icons/file-sender-delete.svg";
        break;
      case CmFileAction.createDir:
        // 폴더 아이콘
        iconPath = "assets/icons/file-sender-folder.svg";
        break;
      case CmFileAction.localToRemote:
      case CmFileAction.remoteToLocal:
      case CmFileAction.rename:
        // 파일 아이콘
        iconPath = "assets/icons/file-sender-file.svg";
        break;
    }

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF1FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: SvgPicture.asset(
          iconPath,
          width: 24,
          height: 24,
          colorFilter: const ColorFilter.mode(iconColor, BlendMode.srcIn),
        ),
      ),
    );
  }

  Widget statusList() {
    return PreferredSize(
      preferredSize: const Size(200, double.infinity),
      child: Container(
          padding: const EdgeInsets.all(12.0),
          child: Obx(
            () {
              final jobTable = gFFI.cmFileModel.currentJobTable;
              statusListView(List<CmFileLog> jobs) => ListView.builder(
                    controller: ScrollController(),
                    itemBuilder: (BuildContext context, int index) {
                      final item = jobs[index];
                      final isTransferInProgress = item.state == JobState.inProgress &&
                          (item.action == CmFileAction.localToRemote ||
                           item.action == CmFileAction.remoteToLocal);
                      final progress = item.totalSize > 0
                          ? item.finishedSize / item.totalSize
                          : 0.0;
                      // 파일 전송 창과 동일한 카드 디자인
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: generateCard(
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // 왼쪽: 아이콘
                                iconLabel(item)
                                    .marginOnly(left: 10, right: 10),
                                  // 중앙: 파일명 + 상태 + 프로그레스바
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // 파일명 (비어있지 않을 때만 표시)
                                        if (item.fileName.isNotEmpty)
                                          Tooltip(
                                            waitDuration: Duration(milliseconds: 500),
                                            message: item.fileName,
                                            child: Text(
                                              item.fileName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: _cmTextPrimary,
                                              ),
                                            ),
                                          ),
                                        // Total 파일 크기
                                        if (item.totalSize > 0)
                                          Text(
                                            '${translate("Total")} ${readableFileSize(item.totalSize.toDouble())}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF8F8E95),
                                            ),
                                          ).marginOnly(top: 6),
                                        // Speed (전송 중일 때)
                                        if (item.totalSize > 0 && item.state == JobState.inProgress)
                                          Text(
                                            '${translate("Speed")} ${readableFileSize(item.speed)}/s',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF8F8E95),
                                            ),
                                          ),
                                        // 상태 텍스트 (전송 중이 아닐 때)
                                        if (item.isTransfer() && item.state != JobState.inProgress)
                                          Text(
                                            translate(item.display()),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF8F8E95),
                                            ),
                                          ),
                                        // 프로그레스 바 (전송 중일 때만 표시)
                                        if (isTransferInProgress)
                                          LinearPercentIndicator(
                                            animateFromLastPercent: true,
                                            center: Text(
                                              '${(progress * 100).toStringAsFixed(0)}%',
                                            ),
                                            barRadius: Radius.circular(15),
                                            percent: progress.clamp(0.0, 1.0),
                                            progressColor: MyTheme.accent,
                                            backgroundColor: Theme.of(context).hoverColor,
                                            lineHeight: kDesktopFileTransferRowHeight,
                                          ).paddingSymmetric(vertical: 8),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    itemCount: jobTable.length,
                  );

              return jobTable.isEmpty
                  ? Center(
                      child: Text(
                        translate("No transfers in progress"),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).tabBarTheme.labelColor,
                        ),
                      ),
                    )
                  : statusListView(jobTable);
            },
          )),
    );
  }
}
