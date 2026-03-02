import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/animated_rotation_widget.dart';
import 'package:flutter_hbb/common/widgets/custom_password.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/pages/my_page.dart' show showDesktopAddonSessionDialog;
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/plugin/ui_manager.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;
import '../widgets/button.dart';
import '../../common/widgets/sidebar_icon_button.dart';
import '../../common/widgets/auth_layout.dart';
import '../../common/widgets/styled_form_widgets.dart';

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({Key? key}) : super(key: key);

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

const borderColor = Color(0xFF2F65BA);

class _DesktopHomePageState extends State<DesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _leftPaneScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;
  var systemError = '';
  StreamSubscription? _uniLinksSubscription;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  bool isCardClosed = false;

  final RxBool _block = false.obs;

  final GlobalKey _childKey = GlobalKey();

  // Light sidebar theme colors (matching design)
  static const _sidebarTextPrimary = Color(0xFF111827);
  static const _sidebarTextSecondary = Color(0xFF6B7280);
  static const _sidebarTextTertiary = Color(0xFF9CA3AF);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncomingOnly = bind.isIncomingOnly();
    return _buildBlock(
        child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildLeftPane(context),
        if (!isIncomingOnly) Expanded(child: buildRightPane(context)),
      ],
    ));
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
        block: _block, mask: true, use: canBeBlocked, child: child);
  }

  Widget buildLeftPane(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    final isOutgoingOnly = bind.isOutgoingOnly();
    final theme = MyTheme.settingTab(context);

    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Container(
        width: theme.sidebarWidth,
        decoration: BoxDecoration(
          color: theme.sidebarBackgroundColor,
        ),
        child: Column(
          children: [
            // Main content area
            Expanded(
              child: SingleChildScrollView(
                controller: _leftPaneScrollController,
                child: Column(
                  key: _childKey,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    // Header section
                    _buildSidebarHeader(context),
                    const SizedBox(height: 16),
                    // Status indicator
                    if (!isOutgoingOnly) _buildStatusIndicator(context),
                    const SizedBox(height: 20),
                    // Desktop code section
                    if (!isOutgoingOnly) _buildDesktopCodeSection(context),
                    const SizedBox(height: 16),
                    if (!isOutgoingOnly)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Divider(color: Color(0xFFF2F1F6), height: 1),
                      ),
                    const SizedBox(height: 16),
                    // One-time password section
                    if (!isOutgoingOnly) _buildPasswordSection(context),
                    buildPluginEntry(),
                    if (isIncomingOnly) ...[
                      const Divider(color: Color(0xFF374151)),
                      OnlineStatusWidget(
                        onSvcStatusChanged: () {
                          if (isInHomePage()) {
                            Future.delayed(Duration(milliseconds: 300), () {
                              _updateWindowSize();
                            });
                          }
                        },
                      ).marginOnly(bottom: 6, right: 6)
                    ],
                  ],
                ),
              ),
            ),
            // Connection count card & Plan card (프리플랜이면 업그레이드 버튼만 표시)
            Obx(() {
              final planType = gFFI.userModel.planType.value;
              final isFree = planType == 'FREE' || planType.isEmpty;
              if (isFree) {
                return _buildPlanUpgradeButton(context);
              } else {
                return Column(
                  children: [
                    _buildConnectionCountCard(context),
                    _buildPlanCard(context),
                  ],
                );
              }
            }),
            // Bottom buttons (settings + user)
            _buildBottomButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            translate("Your Desktop"),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 15),
          Text(
            translate("desk_tip"),
            style: const TextStyle(
              color: _sidebarTextSecondary,
              fontSize: 14,
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(BuildContext context) {
    return Obx(() {
      final status = stateGlobal.svcStatus.value;

      // Define colors and text based on status
      Color bgColor;
      Color borderColor;
      Color dotColor;
      Color textColor;
      String statusText;

      switch (status) {
        case SvcStatus.ready:
          bgColor = const Color(0xFFDCFCE7);
          borderColor = const Color(0xFF62A93E);
          dotColor = const Color(0xFF599A38);
          textColor = const Color(0xFF62A93E);
          statusText = translate("Available");
          break;
        case SvcStatus.connecting:
          bgColor = const Color(0xFFFEF3C7);
          borderColor = const Color(0xFFF59E0B);
          dotColor = const Color(0xFFF59E0B);
          textColor = const Color(0xFFD97706);
          statusText = translate("Connecting");
          break;
        case SvcStatus.notReady:
          bgColor = const Color(0xFFFEE2E2);
          borderColor = const Color(0xFFEF4444);
          dotColor = const Color(0xFFEF4444);
          textColor = const Color(0xFFDC2626);
          statusText = translate("Connection Failed");
          break;
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                statusText,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildDesktopCodeSection(BuildContext context) {
    return Consumer<ServerModel>(
      builder: (context, model, child) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                translate("ID"),
                style: const TextStyle(
                  color: _sidebarTextSecondary,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onDoubleTap: () {
                  Clipboard.setData(ClipboardData(text: model.serverId.text));
                  showToast(translate("Copied"));
                },
                child: Text(
                  model.serverId.text.isEmpty ? "..." : model.serverId.text,
                  style: const TextStyle(
                    color: _sidebarTextPrimary,
                    fontSize: 20,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPasswordSection(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(
        builder: (context, model, child) {
          final showOneTime = model.approveMode != 'click' &&
              model.verificationMethod != kUsePermanentPassword;
          RxBool refreshHover = false.obs;
          RxBool copyHover = false.obs;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  translate("One-time Password"),
                  style: const TextStyle(
                    color: _sidebarTextSecondary,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onDoubleTap: () {
                          if (showOneTime) {
                            Clipboard.setData(
                                ClipboardData(text: model.serverPasswd.text));
                            showToast(translate("Copied"));
                          }
                        },
                        child: Text(
                          showOneTime ? model.serverPasswd.text : "******",
                          style: const TextStyle(
                            color: _sidebarTextPrimary,
                            fontSize: 20,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                    if (showOneTime) ...[
                      Builder(builder: (context) {
                        final iconTheme = MyTheme.sidebarIconButton(context);
                        return InkWell(
                          onTap: () {
                            Clipboard.setData(
                                ClipboardData(text: model.serverPasswd.text));
                            showToast(translate("Copied"));
                          },
                          onHover: (value) => copyHover.value = value,
                          child: Obx(() => SvgPicture.asset(
                                'assets/icons/left-password-copy.svg',
                                width: 25,
                                height: 25,
                                colorFilter: ColorFilter.mode(
                                  copyHover.value
                                      ? iconTheme.hoverIconColor
                                      : iconTheme.iconColor,
                                  BlendMode.srcIn,
                                ),
                              )),
                        );
                      }),
                      const SizedBox(width: 12),
                      Builder(builder: (context) {
                        final iconTheme = MyTheme.sidebarIconButton(context);
                        return AnimatedRotationWidget(
                          onPressed: () => bind.mainUpdateTemporaryPassword(),
                          child: Obx(() => SvgPicture.asset(
                                'assets/icons/left-password-f5.svg',
                                width: 25,
                                height: 25,
                                colorFilter: ColorFilter.mode(
                                  refreshHover.value
                                      ? iconTheme.hoverIconColor
                                      : iconTheme.iconColor,
                                  BlendMode.srcIn,
                                ),
                              )),
                          onHover: (value) => refreshHover.value = value,
                        );
                      }),
                    ],
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 현재 플랜 이름 (API planType 기준) - 반응형 버전
  String _getCurrentPlanName() {
    final planType = gFFI.userModel.planType.value; // 반응형 변수 사용
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

  /// 동시 접속 수 카드
  Widget _buildConnectionCountCard(BuildContext context) {
    final RxBool buttonHover = false.obs;

    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDEDEE2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 현재 동시 접속 가능 수
          Row(
            children: [
              Text(
                translate("Current Connection Count"),
                style: const TextStyle(
                  color: Color(0xFF646368),
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              Obx(() {
                final connectionCount = gFFI.userModel.connectionCount.value;
                return Text(
                  '${connectionCount}${translate("person_count")}',
                  style: const TextStyle(
                    color: Color(0xFF2F2E31),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 12),
          // 동시 접속 수 추가 버튼
          InkWell(
            onTap: () {
              showDesktopAddonSessionDialog();
            },
            onHover: (value) => buttonHover.value = value,
            borderRadius: BorderRadius.circular(8),
            child: Obx(() => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: buttonHover.value
                      ? const Color(0xFF5F71FF)
                      : const Color(0xFFB9B8BF),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    'assets/icons/left-plus-session.svg',
                    width: 18,
                    height: 18,
                    colorFilter: ColorFilter.mode(
                      buttonHover.value
                          ? const Color(0xFF5F71FF)
                          : const Color(0xFFB9B8BF),
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    translate("Add Connection Number"),
                    style: TextStyle(
                      color: buttonHover.value
                          ? const Color(0xFF5F71FF)
                          : const Color(0xFF8F8E95),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(BuildContext context) {
    return InkWell(
      onTap: () {
        // 플랜 선택 탭 열기
        DesktopTabPage.onAddPlanSelection();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF5F71FF), Color(0xFF4350B5)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  translate("Current Plan"),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.chevron_right,
                  color: Colors.white.withOpacity(0.7),
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: SvgPicture.asset(
                'assets/icons/left-plancard-logo.svg',
                width: 40,
                height: 40,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              // _getCurrentPlanName()이 planType.value를 사용하므로 Obx에서 자동 반응형
              child: Obx(() => Text(
                _getCurrentPlanName(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                ),
              )),
            ),
          ],
        ),
      ),
    );
  }

  /// 프리플랜일 때 표시되는 플랜 업그레이드 버튼
  Widget _buildPlanUpgradeButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
      child: InkWell(
        onTap: () => DesktopTabPage.onAddPlanSelection(),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF5F71FF), Color(0xFF4350B5)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Text(
                translate('Plan Upgrade'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.chevron_right,
                color: Colors.white,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomButtons(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 6, bottom: 12),
      child: Row(
        children: [
          SidebarIconButton(
            iconPath: 'assets/icons/left-bottom-setting.svg',
            onTap: () {
              if (DesktopSettingPage.tabKeys.isNotEmpty) {
                DesktopSettingPage.switch2page(DesktopSettingPage.tabKeys[0]);
              }
            },
          ),
          const SizedBox(width: 13),
          SidebarIconButton(
            iconPath: 'assets/icons/left-bottom-userinfo.svg',
            onTap: () => DesktopTabPage.onAddMyPage(),
          ),
        ],
      ),
    );
  }

  buildRightPane(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ConnectionPage(),
    );
  }

  buildIDBoard(BuildContext context) {
    final model = gFFI.serverModel;
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 11),
      height: 57,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 2,
            decoration: const BoxDecoration(color: MyTheme.accent),
          ).marginOnly(top: 5),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 25,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          translate("ID"),
                          style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.color
                                  ?.withOpacity(0.5)),
                        ).marginOnly(top: 5),
                        buildPopupMenu(context)
                      ],
                    ),
                  ),
                  Flexible(
                    child: GestureDetector(
                      onDoubleTap: () {
                        Clipboard.setData(
                            ClipboardData(text: model.serverId.text));
                        showToast(translate("Copied"));
                      },
                      child: TextFormField(
                        controller: model.serverId,
                        readOnly: true,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.only(top: 10, bottom: 10),
                        ),
                        style: TextStyle(
                          fontSize: 22,
                        ),
                      ).workaroundFreezeLinuxMint(),
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPopupMenu(BuildContext context) {
    RxBool hover = false.obs;
    return InkWell(
      onTap: DesktopTabPage.onAddSetting,
      borderRadius: BorderRadius.circular(12),
      child: Tooltip(
        message: translate('Settings'),
        child: Obx(
          () => Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: hover.value ? const Color(0xFFF3F4F6) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.more_vert_outlined,
              size: 18,
              color: hover.value ? _sidebarTextPrimary : _sidebarTextSecondary,
            ),
          ),
        ),
      ),
      onHover: (value) => hover.value = value,
    );
  }

  buildPasswordBoard(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
          builder: (context, model, child) {
            return buildPasswordBoard2(context, model);
          },
        ));
  }

  buildPasswordBoard2(BuildContext context, ServerModel model) {
    RxBool refreshHover = false.obs;
    RxBool editHover = false.obs;
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final showOneTime = model.approveMode != 'click' &&
        model.verificationMethod != kUsePermanentPassword;
    return Container(
      margin: EdgeInsets.only(left: 20.0, right: 16, top: 13, bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 2,
            height: 52,
            decoration: BoxDecoration(color: MyTheme.accent),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AutoSizeText(
                    translate("One-time Password"),
                    style: TextStyle(
                        fontSize: 14, color: textColor?.withOpacity(0.5)),
                    maxLines: 1,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onDoubleTap: () {
                            if (showOneTime) {
                              Clipboard.setData(
                                  ClipboardData(text: model.serverPasswd.text));
                              showToast(translate("Copied"));
                            }
                          },
                          child: TextFormField(
                            controller: model.serverPasswd,
                            readOnly: true,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              contentPadding:
                                  EdgeInsets.only(top: 14, bottom: 10),
                            ),
                            style: TextStyle(fontSize: 15),
                          ).workaroundFreezeLinuxMint(),
                        ),
                      ),
                      if (showOneTime)
                        AnimatedRotationWidget(
                          onPressed: () => bind.mainUpdateTemporaryPassword(),
                          child: Tooltip(
                            message: translate('Refresh Password'),
                            child: Obx(() => RotatedBox(
                                quarterTurns: 2,
                                child: Icon(
                                  Icons.refresh,
                                  color: refreshHover.value
                                      ? textColor
                                      : Color(0xFFDDDDDD),
                                  size: 22,
                                ))),
                          ),
                          onHover: (value) => refreshHover.value = value,
                        ).marginOnly(right: 8, top: 4),
                      if (!bind.isDisableSettings())
                        InkWell(
                          child: Tooltip(
                            message: translate('Change Password'),
                            child: Obx(
                              () => Icon(
                                Icons.edit,
                                color: editHover.value
                                    ? textColor
                                    : Color(0xFFDDDDDD),
                                size: 22,
                              ).marginOnly(right: 8, top: 4),
                            ),
                          ),
                          onTap: () => DesktopSettingPage.switch2page(
                              SettingsTabKey.safety),
                          onHover: (value) => editHover.value = value,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  buildTip(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    return Padding(
      padding:
          const EdgeInsets.only(left: 20.0, right: 16, top: 16.0, bottom: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              if (!isOutgoingOnly)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    translate("Your Desktop"),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 10.0,
          ),
          if (!isOutgoingOnly)
            Text(
              translate("desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (isOutgoingOnly)
            Text(
              translate("outgoing_only_desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget buildHelpCards(String updateUrl) {
    if (!bind.isCustomClient() &&
        updateUrl.isNotEmpty &&
        !isCardClosed &&
        bind.mainUriPrefixSync().contains('onedesk')) {
      final isToUpdate = (isWindows || isMacOS) && bind.mainIsInstalled();
      String btnText = isToUpdate ? 'Update' : 'Download';
      GestureTapCallback onPressed = () async {
        final Uri url = Uri.parse('https://rustdesk.com/download');
        await launchUrl(url);
      };
      if (isToUpdate) {
        onPressed = () {
          handleUpdate(updateUrl);
        };
      }
      return buildInstallCard(
          "Status",
          "${translate("new-version-of-{${bind.mainGetAppNameSync()}}-tip")} (${bind.mainGetNewVersion()}).",
          btnText,
          onPressed,
          closeButton: true);
    }
    if (systemError.isNotEmpty) {
      return buildInstallCard("", systemError, "", () {});
    }

    if (isWindows && !bind.isDisableInstallation()) {
      if (!bind.mainIsInstalled()) {
        return buildInstallCard(
            "", bind.isOutgoingOnly() ? "" : "install_tip", "Install",
            () async {
          await oneDeskWinManager.closeAllSubWindows();
          bind.mainGotoInstall();
        });
      } else if (bind.mainIsInstalledLowerVersion()) {
        return buildInstallCard(
            "Status", "Your installation is lower version.", "Click to upgrade",
            () async {
          await oneDeskWinManager.closeAllSubWindows();
          bind.mainUpdateMe();
        });
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return buildInstallCard("Permissions", "config_screen", "Configure",
            () async {
          bind.mainIsCanScreenRecording(prompt: true);
          watchIsCanScreenRecording = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return buildInstallCard("Permissions", "config_acc", "Configure",
            () async {
          bind.mainIsProcessTrusted(prompt: true);
          watchIsProcessTrust = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return buildInstallCard("", "install_daemon_tip", "Install", () async {
          bind.mainIsInstalledDaemon(prompt: true);
        });
      }
      //// Disable microphone configuration for macOS. We will request the permission when needed.
      // else if ((await osxCanRecordAudio() !=
      //     PermissionAuthorizeType.authorized)) {
      //   return buildInstallCard("Permissions", "config_microphone", "Configure",
      //       () async {
      //     osxRequestAudio();
      //     watchIsCanRecordAudio = true;
      //   });
      // }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) {
        return Container();
      }
      final LinuxCards = <Widget>[];
      if (bind.isSelinuxEnforcing()) {
        // Check is SELinux enforcing, but show user a tip of is SELinux enabled for simple.
        final keyShowSelinuxHelpTip = "show-selinux-help-tip";
        if (bind.mainGetLocalOption(key: keyShowSelinuxHelpTip) != 'N') {
          LinuxCards.add(buildInstallCard(
            "Warning",
            "selinux_tip",
            "",
            () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link:
                'https://rustdesk.com/docs/en/client/linux/#permissions-issue',
            closeButton: true,
            closeOption: keyShowSelinuxHelpTip,
          ));
        }
      }
      if (bind.mainCurrentIsWayland()) {
        LinuxCards.add(buildInstallCard(
            "Warning", "wayland_experiment_tip", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#x11-required'));
      } else if (bind.mainIsLoginWayland()) {
        LinuxCards.add(buildInstallCard("Warning",
            "Login screen using Wayland is not supported", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#login-screen'));
      }
      if (LinuxCards.isNotEmpty) {
        return Column(
          children: LinuxCards,
        );
      }
    }
    if (bind.isIncomingOnly()) {
      return Align(
        alignment: Alignment.centerRight,
        child: StyledOutlinedButton(
          label: translate('Quit'),
          fillWidth: false,
          onPressed: () {
            SystemNavigator.pop(); // Close the application
            // https://github.com/flutter/flutter/issues/66631
            if (isWindows) {
              exit(0);
            }
          },
        ),
      ).marginAll(14);
    }
    return Container();
  }

  Widget buildInstallCard(String title, String content, String btnText,
      GestureTapCallback onPressed,
      {double marginTop = 20.0,
      String? help,
      String? link,
      bool? closeButton,
      String? closeOption}) {
    if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y' &&
        content != 'install_daemon_tip') {
      return const SizedBox();
    }
    void closeCard() async {
      if (closeOption != null) {
        await bind.mainSetLocalOption(key: closeOption, value: 'N');
        if (bind.mainGetLocalOption(key: closeOption) == 'N') {
          setState(() {
            isCardClosed = true;
          });
        }
      } else {
        setState(() {
          isCardClosed = true;
        });
      }
    }

    return Stack(
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(
              0, marginTop, 0, bind.isIncomingOnly() ? marginTop : 0),
          child: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.fromARGB(255, 226, 66, 188),
                  Color.fromARGB(255, 244, 114, 124),
                ],
              )),
              padding: EdgeInsets.all(20),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: (title.isNotEmpty
                          ? <Widget>[
                              Center(
                                  child: Text(
                                translate(title),
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ).marginOnly(bottom: 6)),
                            ]
                          : <Widget>[]) +
                      <Widget>[
                        if (content.isNotEmpty)
                          Text(
                            translate(content),
                            style: TextStyle(
                                height: 1.5,
                                color: Colors.white,
                                fontWeight: FontWeight.normal,
                                fontSize: 13),
                          ).marginOnly(bottom: 20)
                      ] +
                      (btnText.isNotEmpty
                          ? <Widget>[
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FixedWidthButton(
                                      width: 150,
                                      padding: 8,
                                      isOutline: true,
                                      text: translate(btnText),
                                      textColor: Colors.white,
                                      borderColor: Colors.white,
                                      textSize: 20,
                                      radius: 10,
                                      onTap: onPressed,
                                    )
                                  ])
                            ]
                          : <Widget>[]) +
                      (help != null
                          ? <Widget>[
                              Center(
                                  child: InkWell(
                                      onTap: () async =>
                                          await launchUrl(Uri.parse(link!)),
                                      child: Text(
                                        translate(help),
                                        style: TextStyle(
                                            decoration:
                                                TextDecoration.underline,
                                            color: Colors.white,
                                            fontSize: 12),
                                      )).marginOnly(top: 6)),
                            ]
                          : <Widget>[]))),
        ),
        if (closeButton != null && closeButton == true)
          Positioned(
            top: 18,
            right: 0,
            child: IconButton(
              icon: Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
              onPressed: closeCard,
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    // Prompt macOS permissions on every launch.
    // _promptAllMacPermissions only prompts for permissions not yet granted,
    // so it's safe to call every time.
    if (isMacOS) {
      _promptAllMacPermissions();
    }
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      // Update svcStatus for the status indicator
      try {
        final status = jsonDecode(await bind.mainGetConnectStatus())
            as Map<String, dynamic>;
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
      } catch (e) {
        debugPrint("Error updating svcStatus: $e");
      }
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        setState(() {});
      }
      if (watchIsCanScreenRecording) {
        if (bind.mainIsCanScreenRecording(prompt: false)) {
          watchIsCanScreenRecording = false;
          setState(() {});
        }
      }
      if (watchIsProcessTrust) {
        if (bind.mainIsProcessTrusted(prompt: false)) {
          watchIsProcessTrust = false;
          setState(() {});
        }
      }
      if (watchIsInputMonitoring) {
        if (bind.mainIsCanInputMonitoring(prompt: false)) {
          watchIsInputMonitoring = false;
          // Do not notify for now.
          // Monitoring may not take effect until the process is restarted.
          // oneDeskWinManager.call(
          //     WindowType.RemoteDesktop, kWindowDisableGrabKeyboard, '');
          setState(() {});
        }
      }
      if (watchIsCanRecordAudio) {
        if (isMacOS) {
          Future.microtask(() async {
            if ((await osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized)) {
              watchIsCanRecordAudio = false;
              setState(() {});
            }
          });
        } else {
          watchIsCanRecordAudio = false;
          setState(() {});
        }
      }
    });
    Get.put<RxBool>(svcStopped, tag: 'stop-service');
    oneDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);

    screenToMap(window_size.Screen screen) => {
          'frame': {
            'l': screen.frame.left,
            't': screen.frame.top,
            'r': screen.frame.right,
            'b': screen.frame.bottom,
          },
          'visibleFrame': {
            'l': screen.visibleFrame.left,
            't': screen.visibleFrame.top,
            'r': screen.visibleFrame.right,
            'b': screen.visibleFrame.bottom,
          },
          'scaleFactor': screen.scaleFactor,
        };

    bool isChattyMethod(String methodName) {
      switch (methodName) {
        case kWindowBumpMouse:
          return true;
      }

      return false;
    }

    oneDeskWinManager.setMethodHandler((call, fromWindowId) async {
      if (!isChattyMethod(call.method)) {
        debugPrint(
            "[Main] call ${call.method} with args ${call.arguments} from window $fromWindowId");
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowGetWindowInfo) {
        final screen = (await window_size.getWindowInfo()).screen;
        if (screen == null) {
          return '';
        } else {
          return jsonEncode(screenToMap(screen));
        }
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode(
            (await window_size.getScreenList()).map(screenToMap).toList());
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await oneDeskWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await oneDeskWinManager.unregisterActiveWindow(call.arguments['id']);
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'],
          isViewCamera: call.arguments['isViewCamera'],
          isTerminal: call.arguments['isTerminal'],
          isTcpTunneling: call.arguments['isTcpTunneling'],
          isRDP: call.arguments['isRDP'],
          password: call.arguments['password'],
          forceRelay: call.arguments['forceRelay'],
          connToken: call.arguments['connToken'],
        );
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance
            .bumpMouse(dx: call.arguments['dx'], dy: call.arguments['dy']);
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try {
          windowId = int.parse(args[0]);
        } catch (e) {
          debugPrint("Failed to parse window id '${call.arguments}': $e");
        }
        WindowType? windowType;
        try {
          windowType = WindowType.values.byName(args[3]);
        } catch (e) {
          debugPrint("Failed to parse window type '${call.arguments}': $e");
        }
        if (windowId != null && windowType != null) {
          await oneDeskWinManager.moveTabToNewWindow(
              windowId, args[1], args[2], windowType);
        }
      } else if (call.method == kWindowEventOpenMonitorSession) {
        final args = jsonDecode(call.arguments);
        final windowId = args['window_id'] as int;
        final peerId = args['peer_id'] as String;
        final display = args['display'] as int;
        final displayCount = args['display_count'] as int;
        final windowType = args['window_type'] as int;
        final screenRect = parseParamScreenRect(args);
        await oneDeskWinManager.openMonitorSession(
            windowId, peerId, display, displayCount, screenRect, windowType);
      } else if (call.method == kWindowEventRemoteWindowCoords) {
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(
              await oneDeskWinManager.getOtherRemoteWindowCoords(windowId));
        }
      } else if (call.method == kWindowEventShowVoiceCallDialog) {
        debugPrint("Received kWindowEventShowVoiceCallDialog event");
        final args = jsonDecode(call.arguments);
        final clientId = args['client_id'] as int;
        final clientName = args['client_name'] as String;
        final clientPeerId = args['client_peer_id'] as String;
        debugPrint(
            "Voice call dialog: clientId=$clientId, clientName=$clientName, clientPeerId=$clientPeerId");
        // globalKey.currentContext 사용하여 메인 창에서 다이얼로그 표시
        final ctx = globalKey.currentContext;
        debugPrint(
            "globalKey.currentContext is ${ctx != null ? 'available' : 'null'}");
        if (ctx != null) {
          _showVoiceCallDialog(ctx, clientId, clientName, clientPeerId);
        }
      } else if (call.method == kWindowEventOpenSettings) {
        // 메인 창을 앞으로 가져오고 설정 페이지 열기
        windowOnTop(null);
        final tabName = call.arguments as String?;
        SettingsTabKey tabKey = SettingsTabKey.general;
        if (tabName == 'display') {
          tabKey = SettingsTabKey.display;
        } else if (tabName == 'safety') {
          tabKey = SettingsTabKey.safety;
        } else if (tabName == 'about') {
          tabKey = SettingsTabKey.about;
        }
        if (DesktopSettingPage.tabKeys.contains(tabKey)) {
          DesktopSettingPage.switch2page(tabKey);
        } else if (DesktopSettingPage.tabKeys.isNotEmpty) {
          DesktopSettingPage.switch2page(DesktopSettingPage.tabKeys[0]);
        }
      }
    });
    _uniLinksSubscription = listenUniLinks();

    if (bind.isIncomingOnly()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  _updateWindowSize() {
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
  }

  void _promptAllMacPermissions() {
    final isOutgoingOnly = bind.isOutgoingOnly();
    if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
      bind.mainIsCanScreenRecording(prompt: true);
      watchIsCanScreenRecording = true;
    }
    if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
      bind.mainIsProcessTrusted(prompt: true);
      watchIsProcessTrust = true;
    }
    // Input monitoring prompt removed — not essential for basic remote control.
    // Users who need keyboard grab can enable it manually in System Settings.
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }

  Widget buildPluginEntry() {
    final entries = PluginUiManager.instance.entries.entries;
    return Offstage(
      offstage: entries.isEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...entries.map((entry) {
            return entry.value;
          })
        ],
      ),
    );
  }

  /// 음성 채팅 요청 다이얼로그 표시 (메인 창에서)
  void _showVoiceCallDialog(BuildContext context, int clientId,
      String clientName, String clientPeerId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: EdgeInsets.zero,
          content: Container(
            width: 360,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  translate('Voice Chat Request'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                // 유저 아바타
                Container(
                  width: 80,
                  height: 80,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: str2color(clientName),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    clientName.isNotEmpty ? clientName[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 유저 이름
                Text(
                  '[${clientName.isNotEmpty ? clientName : translate('Unknown')}]',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                // 유저 ID
                Text(
                  '[$clientPeerId]',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 32),
                // 버튼들
                Row(
                  children: [
                    Expanded(
                      child: StyledOutlinedButton(
                        label: translate('Reject'),
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          // CM으로 거절 명령 전송
                          bind.cmHandleIncomingVoiceCall(
                              id: clientId, accept: false);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          // CM으로 수락 명령 전송
                          bind.cmHandleIncomingVoiceCall(
                              id: clientId, accept: true);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MyTheme.accent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          translate('Accept'),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
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
}

void setPasswordDialog({VoidCallback? notEmptyCallback}) async {
  final pw = await bind.mainGetPermanentPassword();
  final p0 = TextEditingController(text: pw);
  final p1 = TextEditingController(text: pw);
  var errMsg0 = "";
  var errMsg1 = "";
  bool obscurePassword = true;
  bool obscureConfirm = true;
  final RxString rxPass = pw.trim().obs;
  final rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    MinCharactersValidationRule(8),
  ];

  gFFI.dialogManager.show((setState, close, context) {
    submit() {
      setState(() {
        errMsg0 = "";
        errMsg1 = "";
      });
      final pass = p0.text.trim();
      if (pass.isNotEmpty) {
        final Iterable violations = rules.where((r) => !r.validate(pass));
        if (violations.isNotEmpty) {
          setState(() {
            errMsg0 = translate("Password requirements not met");
          });
          return;
        }
      }
      if (p1.text.trim() != pass) {
        setState(() {
          errMsg1 = translate("The confirmation is not identical.");
        });
        return;
      }
      bind.mainSetPermanentPassword(password: pass);
      if (pass.isNotEmpty) {
        notEmptyCallback?.call();
      }
      close();
      // 비밀번호가 설정된 경우 완료 다이얼로그 표시
      if (pass.isNotEmpty) {
        _showPasswordSettingCompleteDialog();
      }
    }

    return CustomAlertDialog(
      title: Text(
        translate("Set permanent password"),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 340, maxWidth: 340),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
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
            AuthTextField(
              controller: p0,
              obscureText: obscurePassword,
              hintText: translate('Enter password'),
              errorText: errMsg0.isNotEmpty ? errMsg0 : null,
              suffixIcon: IconButton(
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: Colors.grey[500],
                ),
                onPressed: () =>
                    setState(() => obscurePassword = !obscurePassword),
              ),
              onChanged: (value) {
                rxPass.value = value.trim();
                setState(() => errMsg0 = '');
              },
            ),
            const SizedBox(height: 12),
            // 비밀번호 규칙 칩
            Obx(() => Wrap(
                  runSpacing: 8,
                  spacing: 8,
                  children: rules.map((e) {
                    var checked = e.validate(rxPass.value.trim());
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: checked
                            ? const Color(0xFFEEF2FF)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color:
                              checked ? kFormPrimaryColor : kFormDisabledColor,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check,
                            size: 14,
                            color: checked
                                ? kFormPrimaryColor
                                : kFormDisabledColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            e.name,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: checked
                                      ? kFormPrimaryColor
                                      : kFormDisabledColor,
                                ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                )),
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
            AuthTextField(
              controller: p1,
              obscureText: obscureConfirm,
              hintText: translate('Re-enter password'),
              errorText: errMsg1.isNotEmpty ? errMsg1 : null,
              suffixIcon: IconButton(
                icon: Icon(
                  obscureConfirm
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: Colors.grey[500],
                ),
                onPressed: () =>
                    setState(() => obscureConfirm = !obscureConfirm),
              ),
              onChanged: (value) {
                setState(() => errMsg1 = '');
              },
            ),
            const SizedBox(height: 24),
            // 버튼 영역
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
                  child: StyledCompactButton(
                    label: translate('OK'),
                    onPressed: submit,
                    fillWidth: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      onSubmit: submit,
      onCancel: close,
    );
  });
}

/// 비밀번호 설정 완료 다이얼로그
void _showPasswordSettingCompleteDialog() {
  gFFI.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(
        translate("Password setting complete"),
        style: MyTheme.dialogTitleStyle,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 300, maxWidth: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(
              translate("Password setting has been completed."),
              style: const TextStyle(fontSize: 16, color: Color(0xFF454447)),
              textAlign: TextAlign.left,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: StyledCompactButton(
                label: translate('OK'),
                onPressed: close,
                fillWidth: true,
              ),
            ),
          ],
        ),
      ),
      onSubmit: close,
      onCancel: close,
    );
  });
}
