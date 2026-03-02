// main window right pane

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/popup_menu.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../../common.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../common/formatter/id_formatter.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../common/widgets/autocomplete.dart';
import '../../common/widgets/content_card.dart';
import '../../common/widgets/styled_form_widgets.dart';
import '../../models/platform_model.dart';
import '../../desktop/widgets/material_mod_popup_menu.dart' as mod_menu;

class OnlineStatusWidget extends StatefulWidget {
  const OnlineStatusWidget({Key? key, this.onSvcStatusChanged})
      : super(key: key);

  final VoidCallback? onSvcStatusChanged;

  @override
  State<OnlineStatusWidget> createState() => _OnlineStatusWidgetState();
}

/// State for the connection page.
class _OnlineStatusWidgetState extends State<OnlineStatusWidget> {
  final _svcStopped = Get.find<RxBool>(tag: 'stop-service');
  final _svcIsUsingPublicServer = true.obs;
  Timer? _updateTimer;

  double get em => 14.0;
  double? get height => bind.isIncomingOnly() ? null : em * 3;

  void onUsePublicServerGuide() {
    const url = "https://rustdesk.com/pricing";
    canLaunchUrlString(url).then((can) {
      if (can) {
        launchUrlString(url);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(Duration(seconds: 1), () async {
      updateStatus();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    startServiceWidget() => Offstage(
          offstage: !_svcStopped.value,
          child: InkWell(
                  onTap: () async {
                    await start_service(true);
                  },
                  child: Text(translate("Start service"),
                      style: TextStyle(
                          decoration: TextDecoration.underline, fontSize: em)))
              .marginOnly(left: em),
        );

    setupServerWidget() => Flexible(
          child: Offstage(
            offstage: !(!_svcStopped.value &&
                stateGlobal.svcStatus.value == SvcStatus.ready &&
                _svcIsUsingPublicServer.value),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(', ', style: TextStyle(fontSize: em)),
                Flexible(
                  child: InkWell(
                    onTap: onUsePublicServerGuide,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            translate('setup_server_tip'),
                            style: TextStyle(
                                decoration: TextDecoration.underline,
                                fontSize: em),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        );

    basicWidget() => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              height: 8,
              width: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: _svcStopped.value ||
                        stateGlobal.svcStatus.value == SvcStatus.connecting
                    ? kColorWarn
                    : (stateGlobal.svcStatus.value == SvcStatus.ready
                        ? Color.fromARGB(255, 50, 190, 166)
                        : Color.fromARGB(255, 224, 79, 95)),
              ),
            ).marginSymmetric(horizontal: em),
            Container(
              width: isIncomingOnly ? 226 : null,
              child: _buildConnStatusMsg(),
            ),
            // stop
            if (!isIncomingOnly) startServiceWidget(),
            // ready && public
            // No need to show the guide if is custom client.
            if (!isIncomingOnly) setupServerWidget(),
          ],
        );

    return Container(
      height: height,
      child: Obx(() => isIncomingOnly
          ? Column(
              children: [
                basicWidget(),
                Align(
                        child: startServiceWidget(),
                        alignment: Alignment.centerLeft)
                    .marginOnly(top: 2.0, left: 22.0),
              ],
            )
          : basicWidget()),
    ).paddingOnly(right: isIncomingOnly ? 8 : 0);
  }

  _buildConnStatusMsg() {
    widget.onSvcStatusChanged?.call();
    return Text(
      _svcStopped.value
          ? translate("Service is not running")
          : stateGlobal.svcStatus.value == SvcStatus.connecting
              ? translate("connecting_status")
              : stateGlobal.svcStatus.value == SvcStatus.notReady
                  ? translate("not_ready_status")
                  : translate('Ready'),
      style: TextStyle(fontSize: em),
    );
  }

  updateStatus() async {
    final status =
        jsonDecode(await bind.mainGetConnectStatus()) as Map<String, dynamic>;
    final statusNum = status['status_num'] as int;
    if (statusNum == 0) {
      stateGlobal.svcStatus.value = SvcStatus.connecting;
    } else if (statusNum == -1) {
      stateGlobal.svcStatus.value = SvcStatus.notReady;
    } else if (statusNum == 1) {
      stateGlobal.svcStatus.value = SvcStatus.ready;
    } else {
      stateGlobal.svcStatus.value = SvcStatus.notReady;
    }
    _svcIsUsingPublicServer.value = await bind.mainIsUsingPublicServer();
    try {
      stateGlobal.videoConnCount.value = status['video_conn_count'] as int;
    } catch (_) {}
  }
}

/// Connection page for connecting to a remote peer.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({Key? key}) : super(key: key);

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

/// State for the connection page.
class _ConnectionPageState extends State<ConnectionPage>
    with SingleTickerProviderStateMixin, WindowListener {
  /// Controller for the id input bar.
  final _idController = IDTextEditingController();

  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();

  String selectedConnectionType = 'Connect';

  bool isWindowMinimized = false;

  final AllPeersLoader _allPeersLoader = AllPeersLoader();

  // https://github.com/flutter/flutter/issues/157244
  Iterable<Peer> _autocompleteOpts = [];

  final _menuOpen = false.obs;

  @override
  void initState() {
    super.initState();
    _allPeersLoader.init(setState);
    _idFocusNode.addListener(onFocusChanged);
    if (_idController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final lastRemoteId = await bind.mainGetLastRemoteId();
        if (lastRemoteId != _idController.id) {
          setState(() {
            _idController.id = lastRemoteId;
          });
        }
      });
    }
    Get.put<TextEditingController>(_idEditingController);
    Get.put<IDTextEditingController>(_idController);
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    _idController.dispose();
    windowManager.removeListener(this);
    _allPeersLoader.clear();
    _idFocusNode.removeListener(onFocusChanged);
    _idFocusNode.dispose();
    _idEditingController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }

  @override
  void onWindowEvent(String eventName) {
    super.onWindowEvent(eventName);
    if (eventName == 'minimize') {
      isWindowMinimized = true;
    } else if (eventName == 'maximize' || eventName == 'restore') {
      if (isWindowMinimized && isWindows) {
        // windows can't update when minimized.
        Get.forceAppUpdate();
      }
      isWindowMinimized = false;
    }
  }

  @override
  void onWindowEnterFullScreen() {
    // Remove edge border by setting the value to zero.
    stateGlobal.resizeEdgeSize.value = 0;
  }

  @override
  void onWindowLeaveFullScreen() {
    // Restore edge border to default edge size.
    stateGlobal.resizeEdgeSize.value = stateGlobal.isMaximized.isTrue
        ? kMaximizeEdgeSize
        : windowResizeEdgeSize;
  }

  @override
  void onWindowClose() {
    super.onWindowClose();
    bind.mainOnMainWindowClose();
  }

  void onFocusChanged() {
    if (_idFocusNode.hasFocus) {
      if (_allPeersLoader.needLoad) {
        _allPeersLoader.getAllPeers();
      }

      final textLength = _idEditingController.value.text.length;
      // Select all to facilitate removing text, just following the behavior of address input of chrome.
      _idEditingController.selection =
          TextSelection(baseOffset: 0, extentOffset: textLength);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFEFEFE),
      child: Column(
        children: [
          Expanded(
              child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _buildRemoteIDTextField(context),
              ),
              const SizedBox(height: 16),
              Expanded(child: PeerTabPage()),
            ],
          ))
        ],
      ),
    );
  }

  /// Callback for the connect button.
  /// Connects to the selected peer.
  void onConnect(
      {bool isFileTransfer = false,
      bool isViewCamera = false,
      bool isTerminal = false}) {
    var id = _idController.id;
    connect(context, id,
        isFileTransfer: isFileTransfer,
        isViewCamera: isViewCamera,
        isTerminal: isTerminal);
  }

  /// UI for the remote ID TextField.
  /// Search for a peer.
  Widget _buildRemoteIDTextField(BuildContext context) {
    var w = IntrinsicHeight(
        child: ContentCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            translate("Desktop Code"),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          // Input field
          RawAutocomplete<Peer>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text == '') {
                _autocompleteOpts = const Iterable<Peer>.empty();
              } else if (_allPeersLoader.peers.isEmpty &&
                  !_allPeersLoader.isPeersLoaded) {
                Peer emptyPeer = Peer(
                  id: '',
                  username: '',
                  hostname: '',
                  alias: '',
                  platform: '',
                  tags: [],
                  hash: '',
                  password: '',
                  forceAlwaysRelay: false,
                  rdpPort: '',
                  rdpUsername: '',
                  loginName: '',
                  device_group_name: '',
                  note: '',
                );
                _autocompleteOpts = [emptyPeer];
              } else {
                String textWithoutSpaces =
                    textEditingValue.text.replaceAll(" ", "");
                if (int.tryParse(textWithoutSpaces) != null) {
                  textEditingValue = TextEditingValue(
                    text: textWithoutSpaces,
                    selection: textEditingValue.selection,
                  );
                }
                String textToFind = textEditingValue.text.toLowerCase();
                _autocompleteOpts = _allPeersLoader.peers
                    .where((peer) =>
                        peer.id.toLowerCase().contains(textToFind) ||
                        peer.username.toLowerCase().contains(textToFind) ||
                        peer.hostname.toLowerCase().contains(textToFind) ||
                        peer.alias.toLowerCase().contains(textToFind))
                    .toList();
              }
              return _autocompleteOpts;
            },
            focusNode: _idFocusNode,
            textEditingController: _idEditingController,
            fieldViewBuilder: (
              BuildContext context,
              TextEditingController fieldTextEditingController,
              FocusNode fieldFocusNode,
              VoidCallback onFieldSubmitted,
            ) {
              updateTextAndPreserveSelection(
                  fieldTextEditingController, _idController.text);
              return TextField(
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                focusNode: fieldFocusNode,
                style: const TextStyle(
                  fontFamily: 'WorkSans',
                  fontSize: 16,
                  height: 1.4,
                  color: Color(0xFF111827),
                ),
                maxLines: 1,
                cursorColor: const Color(0xFF5B7BF8),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: translate('Enter desktop code to connect'),
                ),
                controller: fieldTextEditingController,
                inputFormatters: [IDTextInputFormatter()],
                onChanged: (v) {
                  _idController.id = v;
                },
                onSubmitted: (_) {
                  onConnect();
                },
              ).workaroundFreezeLinuxMint();
            },
            onSelected: (option) {
              setState(() {
                _idController.id = option.id;
                FocusScope.of(context).unfocus();
              });
            },
            optionsViewBuilder: (BuildContext context,
                AutocompleteOnSelected<Peer> onSelected,
                Iterable<Peer> options) {
              options = _autocompleteOpts;
              double maxHeight = options.length * 50;
              if (options.length == 1) {
                maxHeight = 52;
              } else if (options.length == 3) {
                maxHeight = 146;
              } else if (options.length == 4) {
                maxHeight = 193;
              }
              maxHeight = maxHeight.clamp(0, 200);

              return Align(
                alignment: Alignment.topLeft,
                child: Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 10,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Material(
                          elevation: 0,
                          color: Colors.white,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: maxHeight,
                              maxWidth: 400,
                            ),
                            child: _allPeersLoader.peers.isEmpty &&
                                    !_allPeersLoader.isPeersLoaded
                                ? Container(
                                    height: 80,
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF3B82F6),
                                      ),
                                    ))
                                : Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: ListView(
                                      children: options
                                          .map((peer) => AutocompletePeerTile(
                                              onSelect: () => onSelected(peer),
                                              peer: peer))
                                          .toList(),
                                    ),
                                  ),
                          ),
                        ))),
              );
            },
          ),
          const SizedBox(height: 16),
          // Button row
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Connect button
              StyledCompactButton(
                label: translate("Connect"),
                height: 54,
                onPressed: () => onConnect(),
              ),
              const SizedBox(width: 8),
              // More options button
              Builder(builder: (context) {
                final theme = MyTheme.sidebarIconButton(context);
                final RxBool isHovered = false.obs;
                var offset = Offset(0, 0);
                return InkWell(
                  onHover: (value) => isHovered.value = value,
                  borderRadius: BorderRadius.circular(theme.borderRadius),
                  onTapDown: (e) => offset = e.globalPosition,
                  onTap: () async {
                    _menuOpen.value = true;
                    final x = offset.dx;
                    final y = offset.dy;
                    await mod_menu
                        .showMenu(
                          context: context,
                          position: RelativeRect.fromLTRB(x, y, x, y),
                          items: [
                            (
                              'Transfer file',
                              () => onConnect(isFileTransfer: true)
                            ),
                            (
                              'View camera',
                              () => onConnect(isViewCamera: true)
                            ),
                          ]
                              .map((e) => MenuEntryButton<String>(
                                    childBuilder: (TextStyle? style) => Text(
                                      translate(e.$1),
                                      style: style,
                                    ),
                                    proc: () => e.$2(),
                                    padding: EdgeInsets.symmetric(
                                        horizontal: kDesktopMenuPadding.left),
                                    dismissOnClicked: true,
                                  ))
                              .map((e) => e.build(
                                  context,
                                  const MenuConfig(
                                      commonColor:
                                          CustomPopupMenuTheme.commonColor,
                                      height: CustomPopupMenuTheme.height,
                                      dividerHeight:
                                          CustomPopupMenuTheme.dividerHeight)))
                              .expand((i) => i)
                              .toList(),
                          elevation: 8,
                        )
                        .then((_) => _menuOpen.value = false);
                  },
                  child: Obx(() => Container(
                        padding: theme.padding,
                        decoration: BoxDecoration(
                          color: theme.backgroundColor,
                          borderRadius:
                              BorderRadius.circular(theme.borderRadius),
                          border: Border.all(
                            color: isHovered.value || _menuOpen.value
                                ? theme.hoverBorderColor
                                : theme.borderColor,
                            width: theme.borderWidth,
                          ),
                        ),
                        child: Transform.rotate(
                          angle: _menuOpen.value ? pi : 0,
                          child: SvgPicture.asset(
                            'assets/icons/arrow-connect.svg',
                            width: theme.iconSize,
                            height: theme.iconSize,
                            colorFilter: ColorFilter.mode(
                              isHovered.value || _menuOpen.value
                                  ? theme.hoverIconColor
                                  : theme.iconColor,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      )),
                );
              }),
            ],
          ),
        ],
      ),
    ));
    return w;
  }
}
