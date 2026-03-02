import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/widgets/connection_page_title.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../../common.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../common/widgets/autocomplete.dart';
import '../../common/widgets/content_card.dart';
import '../../consts.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import 'plan_selection_page.dart' show showMobileAddonSessionDialog;
import 'home_page.dart';

/// Connection page for connecting to a remote peer.
class ConnectionPage extends StatefulWidget implements PageShape {
  ConnectionPage({Key? key, required this.appBarActions}) : super(key: key);

  @override
  final icon = const Icon(Icons.connected_tv);

  @override
  final title = translate("Connection");

  @override
  final List<Widget> appBarActions;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

/// State for the connection page.
class _ConnectionPageState extends State<ConnectionPage> {
  /// Controller for the id input bar.
  final _idController = IDTextEditingController();
  final RxBool _idEmpty = true.obs;

  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();

  final AllPeersLoader _allPeersLoader = AllPeersLoader();

  StreamSubscription? _uniLinksSubscription;

  // https://github.com/flutter/flutter/issues/157244
  Iterable<Peer> _autocompleteOpts = [];

  _ConnectionPageState() {
    if (!isWeb) _uniLinksSubscription = listenUniLinks();
    _idController.addListener(() {
      _idEmpty.value = _idController.text.isEmpty;
    });
    Get.put<IDTextEditingController>(_idController);
  }

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
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<FfiModel>(context);
    return CustomScrollView(
      slivers: [
        SliverList(
            delegate: SliverChildListDelegate([
          if (!bind.isCustomClient() && !isIOS)
            Obx(() => _buildUpdateUI(stateGlobal.updateUrl.value)),
          _buildRemoteIDTextField(),
          const SizedBox(height: 20), // 연결카드와 피어탭 사이 간격
        ])),
        SliverFillRemaining(
          hasScrollBody: true,
          child: PeerTabPage(),
        )
      ],
    ).marginOnly(top: 2, left: 20, right: 20);
  }

  /// Callback for the connect button.
  /// Connects to the selected peer.
  void onConnect() {
    var id = _idController.id;
    connect(context, id);
  }

  void onFocusChanged() {
    _idEmpty.value = _idEditingController.text.isEmpty;
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

  /// UI for software update.
  /// If _updateUrl] is not empty, shows a button to update the software.
  Widget _buildUpdateUI(String updateUrl) {
    return updateUrl.isEmpty
        ? const SizedBox(height: 0)
        : InkWell(
            onTap: () async {
              final url = 'https://rustdesk.com/download';
              // https://pub.dev/packages/url_launcher#configuration
              // https://developer.android.com/training/package-visibility/use-cases#open-urls-custom-tabs
              //
              // `await launchUrl(Uri.parse(url))` can also run if skip
              // 1. The following check
              // 2. `<action android:name="android.support.customtabs.action.CustomTabsService" />` in AndroidManifest.xml
              //
              // But it is better to add the check.
              await launchUrl(Uri.parse(url));
            },
            child: Container(
                alignment: AlignmentDirectional.center,
                width: double.infinity,
                color: Colors.pinkAccent,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(translate('Download new version'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold))));
  }

  /// UI for the remote ID TextField.
  /// Search for a peer and connect to it if the id exists.
  Widget _buildRemoteIDTextField() {
    final w = ContentCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            translate("Desktop Code"),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 16),
          // Input field with autocomplete
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
            fieldViewBuilder: (BuildContext context,
                TextEditingController fieldTextEditingController,
                FocusNode fieldFocusNode,
                VoidCallback onFieldSubmitted) {
              updateTextAndPreserveSelection(
                  fieldTextEditingController, _idController.text);
              return TextField(
                controller: fieldTextEditingController,
                focusNode: fieldFocusNode,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                onChanged: (String text) {
                  _idController.id = text;
                },
                style: const TextStyle(
                  fontFamily: 'WorkSans',
                  fontSize: 16,
                  height: 1.4,
                  color: Color(0xFF111827),
                ),
                maxLines: 1,
                cursorColor: const Color(0xFF5B7BF8),
                decoration: InputDecoration(
                  hintText: translate('Enter desktop code to connect'),
                  hintStyle: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFF5B7BF8),
                      width: 1.5,
                    ),
                  ),
                  suffixIcon: Obx(() => _idEmpty.value
                      ? const SizedBox.shrink()
                      : IconButton(
                          onPressed: () {
                            setState(() {
                              _idController.clear();
                              fieldTextEditingController.clear();
                            });
                          },
                          icon: Icon(Icons.clear,
                              color: Colors.grey[400], size: 20),
                        )),
                ),
                inputFormatters: [IDTextInputFormatter()],
                onSubmitted: (_) {
                  onConnect();
                },
              );
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
                          maxWidth: MediaQuery.of(context).size.width - 40,
                        ),
                        child: _allPeersLoader.peers.isEmpty &&
                                !_allPeersLoader.isPeersLoaded
                            ? Container(
                                height: 80,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF5B7BF8),
                                  ),
                                ),
                              )
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
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          // Button row
          Row(
            children: [
              // Connect button
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: onConnect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5B7BF8),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      translate("Connect"),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // More options button (dropdown)
              _buildMoreOptionsButton(),
            ],
          ),
          // 동시 접속 수 섹션 (FREE 플랜이 아닐 때만 표시)
          Obx(() {
            if (gFFI.userModel.planType.value == 'FREE') {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _buildConnectionCountSection(),
            );
          }),
        ],
      ),
    );

    final child = Column(children: [
      if (isWebDesktop)
        getConnectionPageTitle(context, true)
            .marginOnly(bottom: 10, top: 15, left: 12),
      w
    ]);
    return Align(
        alignment: Alignment.topCenter,
        child: Container(constraints: kMobilePageConstraints, child: child));
  }

  /// 동시 접속 수 섹션
  Widget _buildConnectionCountSection() {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                translate("Current Connection Count"),
                style: const TextStyle(
                  color: Color(0xFF646368),
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              Obx(() {
                final connectionCount = gFFI.userModel.connectionCount.value;
                return Text(
                  '$connectionCount${translate("person_count")}',
                  style: const TextStyle(
                    color: Color(0xFF2F2E31),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }),
            ],
          ),
          GestureDetector(
            onTap: () {
              showMobileAddonSessionDialog(context);
            },
            child: Text(
              translate("Add Connection"),
              style: const TextStyle(
                color: Color(0xFF5F71FF),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// More options button (파일 전송, 카메라 보기)
  Widget _buildMoreOptionsButton() {
    return Container(
      height: 48,
      width: 48,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: PopupMenuButton<String>(
        icon: SvgPicture.asset(
          'assets/icons/arrow-connect.svg',
          width: 20,
          height: 20,
          colorFilter: ColorFilter.mode(
            Colors.grey[600]!,
            BlendMode.srcIn,
          ),
        ),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        onSelected: (value) {
          var id = _idController.id;
          if (value == 'file_transfer') {
            connect(context, id, isFileTransfer: true);
          } else if (value == 'view_camera') {
            connect(context, id, isViewCamera: true);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'file_transfer',
            child: Text(translate('Transfer file')),
          ),
          PopupMenuItem(
            value: 'view_camera',
            child: Text(translate('View camera')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    _idController.dispose();
    _idFocusNode.removeListener(onFocusChanged);
    _allPeersLoader.clear();
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
}
