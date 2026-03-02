import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/mobile/widgets/dialog.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../common/widgets/chat_page.dart';
import '../../common/widgets/dialog.dart';
import '../../common/widgets/cm_custom_toggle.dart';
import '../../consts.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';
import 'home_page.dart';

class ServerPage extends StatefulWidget implements PageShape {
  @override
  final title = translate("Screen Share");

  @override
  final icon = const Icon(Icons.mobile_screen_share);

  @override
  final appBarActions = <Widget>[];

  ServerPage({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ServerPageState();
}

class _DropDownAction extends StatelessWidget {
  _DropDownAction();

  // should only have one action
  final actions = [
    PopupMenuButton<String>(
        tooltip: "",
        icon: const Icon(Icons.more_vert),
        itemBuilder: (context) {
          listTile(String text, bool checked) {
            return ListTile(
                title: Text(translate(text)),
                trailing: Icon(
                  Icons.check,
                  color: checked ? null : Colors.transparent,
                ));
          }

          final approveMode = gFFI.serverModel.approveMode;
          final verificationMethod = gFFI.serverModel.verificationMethod;
          final showPasswordOption = approveMode != 'click';
          final isApproveModeFixed = isOptionFixed(kOptionApproveMode);
          final isNumericOneTimePasswordFixed =
              isOptionFixed(kOptionAllowNumericOneTimePassword);
          final isAllowNumericOneTimePassword =
              gFFI.serverModel.allowNumericOneTimePassword;
          return [
            PopupMenuItem(
              enabled: gFFI.serverModel.connectStatus > 0,
              value: "changeID",
              child: Text(translate("Change ID")),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'AcceptSessionsViaPassword',
              child: listTile(
                  'Accept sessions via password', approveMode == 'password'),
              enabled: !isApproveModeFixed,
            ),
            PopupMenuItem(
              value: 'AcceptSessionsViaClick',
              child:
                  listTile('Accept sessions via click', approveMode == 'click'),
              enabled: !isApproveModeFixed,
            ),
            PopupMenuItem(
              value: "AcceptSessionsViaBoth",
              child: listTile("Accept sessions via both",
                  approveMode != 'password' && approveMode != 'click'),
              enabled: !isApproveModeFixed,
            ),
            if (showPasswordOption) const PopupMenuDivider(),
            if (showPasswordOption &&
                verificationMethod != kUseTemporaryPassword)
              PopupMenuItem(
                value: "setPermanentPassword",
                child: Text(translate("Set permanent password")),
              ),
            if (showPasswordOption &&
                verificationMethod != kUsePermanentPassword)
              PopupMenuItem(
                value: "setTemporaryPasswordLength",
                child: Text(translate("One-time password length")),
              ),
            if (showPasswordOption &&
                verificationMethod != kUsePermanentPassword)
              PopupMenuItem(
                value: "allowNumericOneTimePassword",
                child: listTile(translate("Numeric one-time password"),
                    isAllowNumericOneTimePassword),
                enabled: !isNumericOneTimePasswordFixed,
              ),
            if (showPasswordOption) const PopupMenuDivider(),
            if (showPasswordOption)
              PopupMenuItem(
                value: kUseTemporaryPassword,
                child: listTile('Use one-time password',
                    verificationMethod == kUseTemporaryPassword),
              ),
            if (showPasswordOption)
              PopupMenuItem(
                value: kUsePermanentPassword,
                child: listTile('Use permanent password',
                    verificationMethod == kUsePermanentPassword),
              ),
            if (showPasswordOption)
              PopupMenuItem(
                value: kUseBothPasswords,
                child: listTile(
                    'Use both passwords',
                    verificationMethod != kUseTemporaryPassword &&
                        verificationMethod != kUsePermanentPassword),
              ),
          ];
        },
        onSelected: (value) async {
          if (value == "changeID") {
            changeIdDialog();
          } else if (value == "setPermanentPassword") {
            setPasswordDialog();
          } else if (value == "setTemporaryPasswordLength") {
            setTemporaryPasswordLengthDialog(gFFI.dialogManager);
          } else if (value == "allowNumericOneTimePassword") {
            gFFI.serverModel.switchAllowNumericOneTimePassword();
            gFFI.serverModel.updatePasswordModel();
          } else if (value == kUsePermanentPassword ||
              value == kUseTemporaryPassword ||
              value == kUseBothPasswords) {
            callback() {
              bind.mainSetOption(key: kOptionVerificationMethod, value: value);
              gFFI.serverModel.updatePasswordModel();
            }

            if (value == kUsePermanentPassword &&
                (await bind.mainGetPermanentPassword()).isEmpty) {
              setPasswordDialog(notEmptyCallback: callback);
            } else {
              callback();
            }
          } else if (value.startsWith("AcceptSessionsVia")) {
            value = value.substring("AcceptSessionsVia".length);
            if (value == "Password") {
              gFFI.serverModel.setApproveMode('password');
            } else if (value == "Click") {
              gFFI.serverModel.setApproveMode('click');
            } else {
              gFFI.serverModel.setApproveMode(defaultOptionApproveMode);
            }
          }
        })
  ];

  @override
  Widget build(BuildContext context) {
    return actions[0];
  }
}

class _ServerPageState extends State<ServerPage> {
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(const Duration(seconds: 3), () async {
      await gFFI.serverModel.fetchID();
    });
    gFFI.serverModel.checkAndroidPermission();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    checkService();
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
            builder: (context, serverModel, child) => Container(
                  color: const Color(0xFFFEFEFE),
                  child: Column(
                    children: [
                      // Content
                      Expanded(
                        child: SingleChildScrollView(
                          controller: gFFI.serverModel.controller,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                buildPresetPasswordWarningMobile(),
                                gFFI.serverModel.isStart
                                    ? ServerInfo()
                                    : ServiceNotRunningNotification(),
                                ConnectionManager(),
                                const PermissionChecker(),
                                SizedBox.fromSize(size: const Size(0, 15.0)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )));
  }

}

void checkService() async {
  gFFI.invokeMethod("check_service");
  // for Android 10/11, request MANAGE_EXTERNAL_STORAGE permission from system setting page
  if (AndroidPermissionManager.isWaitingFile() && !gFFI.serverModel.fileOk) {
    AndroidPermissionManager.complete(kManageExternalStorage,
        await AndroidPermissionManager.check(kManageExternalStorage));
    debugPrint("file permission finished");
  }
}

class ServiceNotRunningNotification extends StatelessWidget {
  ServiceNotRunningNotification({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFEFEFE),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF333C87).withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            translate("Service is not running"),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5F71FF),
            ),
          ),
          const SizedBox(height: 8),
          // Description
          Text(
            translate("android_start_service_tip"),
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF646368),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          // Start service button (홈페이지 연결 버튼 스타일)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                _showServiceWarningDialog(context, serverModel);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5B7BF8),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                translate("Start service"),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScamWarningDialog extends StatefulWidget {
  final ServerModel serverModel;

  ScamWarningDialog({required this.serverModel});

  @override
  ScamWarningDialogState createState() => ScamWarningDialogState();
}

class ScamWarningDialogState extends State<ScamWarningDialog> {
  int _countdown = bind.isCustomClient() ? 0 : 12;
  bool show_warning = false;
  late Timer _timer;
  late ServerModel _serverModel;

  @override
  void initState() {
    super.initState();
    _serverModel = widget.serverModel;
    startCountdown();
  }

  void startCountdown() {
    const oneSecond = Duration(seconds: 1);
    _timer = Timer.periodic(oneSecond, (timer) {
      setState(() {
        _countdown--;
        if (_countdown <= 0) {
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isButtonLocked = _countdown > 0;

    return AlertDialog(
      content: ClipRRect(
        borderRadius: BorderRadius.circular(20.0),
        child: SingleChildScrollView(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Color(0xffe242bc),
                  Color(0xfff4727c),
                ],
              ),
            ),
            padding: EdgeInsets.all(25.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_sharp,
                      color: Colors.white,
                    ),
                    SizedBox(width: 10),
                    Text(
                      translate("Warning"),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20.0,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                Center(
                  child: Image.asset(
                    'assets/scam.png',
                    width: 180,
                  ),
                ),
                SizedBox(height: 18),
                Text(
                  translate("scam_title"),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 22.0,
                  ),
                ),
                SizedBox(height: 18),
                Text(
                  "${translate("scam_text1")}\n\n${translate("scam_text2")}\n",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16.0,
                  ),
                ),
                Row(
                  children: <Widget>[
                    Checkbox(
                      value: show_warning,
                      onChanged: (value) {
                        setState(() {
                          show_warning = value!;
                        });
                      },
                    ),
                    Text(
                      translate("Don't show again"),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15.0,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      constraints: BoxConstraints(maxWidth: 150),
                      child: ElevatedButton(
                        onPressed: isButtonLocked
                            ? null
                            : () {
                                Navigator.of(context).pop();
                                _serverModel.toggleService();
                                if (show_warning) {
                                  bind.mainSetLocalOption(
                                      key: "show-scam-warning", value: "N");
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                        ),
                        child: Text(
                          isButtonLocked
                              ? "${translate("I Agree")} (${_countdown}s)"
                              : translate("I Agree"),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.0,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    SizedBox(width: 15),
                    Container(
                      constraints: BoxConstraints(maxWidth: 150),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                        ),
                        child: Text(
                          translate("Decline"),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.0,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      contentPadding: EdgeInsets.all(0.0),
    );
  }
}

class ServerInfo extends StatelessWidget {
  final model = gFFI.serverModel;

  ServerInfo({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);

    void copyToClipboard(String value) {
      Clipboard.setData(ClipboardData(text: value));
      showToast(translate('Copied'));
    }

    // 연결 상태 배지
    Widget connectionStatusBadge() {
      if (serverModel.connectStatus == -1) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEBEB),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFFFE6565),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                translate('not_ready_status'),
                style: const TextStyle(
                  color: Color(0xFFFE6565),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      } else if (serverModel.connectStatus == 0) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFFF9800),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                translate('connecting_status'),
                style: const TextStyle(
                  color: Color(0xFFFF9800),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      } else {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF4CAF50),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                translate('Ready'),
                style: const TextStyle(
                  color: Color(0xFF4CAF50),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }
    }

    final showOneTime = serverModel.approveMode != 'click' &&
        serverModel.verificationMethod != kUsePermanentPassword;

    // 사용자 이름 가져오기
    final userName = gFFI.userModel.userName.value.isNotEmpty
        ? gFFI.userModel.userName.value
        : translate('Your Device');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFEFEFE),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF333C87).withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목
          Text(
            '$userName${translate("device_suffix")}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5F71FF),
            ),
          ),
          const SizedBox(height: 4),
          // 설명
          Text(
            translate('device_access_tip'),
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF646368),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          // 연결 상태 배지
          connectionStatusBadge(),
          const SizedBox(height: 16),
          // Device code 섹션
          Text(
            translate('Device code'),
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF646368),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            model.serverId.value.text,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2F2E31),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          // 구분선
          Container(
            height: 1,
            color: const Color(0xFFE5E5E5),
          ),
          const SizedBox(height: 16),
          // 일회용 비밀번호 섹션 - 레이블, 값, 아이콘 수직 가운데 정렬
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 왼쪽: 레이블과 비밀번호 값
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      translate('One-time Password'),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF646368),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      !showOneTime ? '-' : model.serverPasswd.value.text,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2F2E31),
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
              // 오른쪽: 복사 및 새로고침 아이콘
              if (showOneTime)
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        copyToClipboard(model.serverPasswd.value.text.trim());
                      },
                      child: const Icon(
                        Icons.copy_outlined,
                        size: 20,
                        color: Color(0xFF8F8E95),
                      ),
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () => bind.mainUpdateTemporaryPassword(),
                      child: const Icon(
                        Icons.refresh,
                        size: 20,
                        color: Color(0xFF8F8E95),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 20),
          // 액세스 비활성화 버튼 (홈페이지 연결 버튼 스타일)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                _showCaptureWarningDialog(context, serverModel);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5B7BF8),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                translate('Disable Access'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PermissionChecker extends StatefulWidget {
  const PermissionChecker({Key? key}) : super(key: key);

  @override
  State<PermissionChecker> createState() => _PermissionCheckerState();
}

class _PermissionCheckerState extends State<PermissionChecker> {
  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    final hasAudioPermission = androidVersion >= 30;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            translate("Permissions"),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF646368),
            ),
          ),
          const SizedBox(height: 16),
          // Permission rows
          _PermissionRowNew(
            iconPath: 'assets/icons/mobile-access-capture.svg',
            name: translate("Screen Capture"),
            isOk: serverModel.mediaOk,
            onPressed: () => _showCaptureWarningDialog(context, serverModel),
          ),
          _PermissionRowNew(
            iconPath: 'assets/icons/mobile-access-input.svg',
            name: translate("Input Control"),
            isOk: serverModel.inputOk,
            onPressed: serverModel.toggleInput,
          ),
          _PermissionRowNew(
            iconPath: 'assets/icons/mobile-access-filesend.svg',
            name: translate("Transfer file"),
            isOk: serverModel.fileOk,
            onPressed: serverModel.toggleFile,
          ),
          if (hasAudioPermission)
            _PermissionRowNew(
              iconPath: 'assets/icons/mobile-access-audio.svg',
              name: translate("Audio Capture"),
              isOk: serverModel.audioOk,
              onPressed: serverModel.toggleAudio,
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                const Icon(Icons.info_outline, size: 20, color: Color(0xFF8F8E95))
                    .marginOnly(right: 12),
                Expanded(
                  child: Text(
                    translate("android_version_audio_tip"),
                    style: const TextStyle(
                      color: Color(0xFF646368),
                      fontSize: 13,
                    ),
                  ),
                ),
              ]),
            ),
          _PermissionRowNew(
            iconPath: 'assets/icons/mobile-access-clipboard.svg',
            name: translate("Enable clipboard"),
            isOk: serverModel.clipboardOk,
            onPressed: serverModel.toggleClipboard,
          ),
        ],
      ),
    );
  }
}

class _PermissionRowNew extends StatelessWidget {
  final String iconPath;
  final String name;
  final bool isOk;
  final VoidCallback onPressed;

  const _PermissionRowNew({
    required this.iconPath,
    required this.name,
    required this.isOk,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SvgPicture.asset(
            iconPath,
            width: 20,
            height: 20,
            colorFilter: const ColorFilter.mode(
              Color(0xFF5F71FF),
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF454447),
              ),
            ),
          ),
          CmCustomToggle(
            value: isOk,
            onChanged: (value) => onPressed(),
          ),
        ],
      ),
    );
  }
}


class ConnectionManager extends StatefulWidget {
  ConnectionManager({Key? key}) : super(key: key);

  @override
  State<ConnectionManager> createState() => _ConnectionManagerState();
}

class _ConnectionManagerState extends State<ConnectionManager> {
  final Map<int, bool> _micStates = {};
  final Map<int, bool> _speakerStates = {};
  String _savedMicDevice = '';

  @override
  void initState() {
    super.initState();
    _initMicDevice();
  }

  Future<void> _initMicDevice() async {
    _savedMicDevice = await bind.getVoiceCallInputDevice(isCm: true);
    if (_savedMicDevice.isEmpty) {
      final devices = (await bind.mainGetSoundInputs()).toList();
      if (devices.isNotEmpty) {
        _savedMicDevice = devices.first;
      }
    }
  }

  void _toggleMic(int clientId) async {
    final current = _micStates[clientId] ?? true;
    setState(() {
      _micStates[clientId] = !current;
    });
    if (!current) {
      await bind.setVoiceCallInputDevice(isCm: true, device: _savedMicDevice);
    } else {
      await bind.setVoiceCallInputDevice(isCm: true, device: '');
    }
  }

  void _toggleSpeaker(int clientId) {
    final current = _speakerStates[clientId] ?? true;
    setState(() {
      _speakerStates[clientId] = !current;
    });
    bind.cmSwitchPermission(
      connId: clientId,
      name: 'audio',
      enabled: !current,
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    final authorizedClients =
        serverModel.clients.where((c) => c.authorized).toList();
    final Map<String, List<Client>> grouped = {};
    for (final client in authorizedClients) {
      grouped.putIfAbsent(client.peerId, () => []).add(client);
    }

    if (authorizedClients.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      children: grouped.entries.map((entry) {
        final clients = entry.value;
        final primary = clients.first;
        return _buildClientCard(context, serverModel, primary, clients);
      }).toList(),
    );
  }

  List<Widget> _buildAllSubCards(List<Client> clients, ServerModel serverModel) {
    final List<Widget> cards = [];
    for (final client in clients) {
      cards.add(_buildSubCard(client, serverModel));
    }
    for (final client in clients) {
      if (client.inVoiceCall) {
        cards.add(_buildVoiceCallCard(client));
      }
      if (client.incomingVoiceCall) {
        cards.add(_buildVoiceCallRequestCard(client, serverModel));
      }
    }
    return cards;
  }

  /// 음성 채팅 활성 카드
  Widget _buildVoiceCallCard(Client client) {
    final isMicOn = _micStates[client.id] ?? true;
    final isSpeakerOn = _speakerStates[client.id] ?? true;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                'assets/icons/mobile-remote-mic.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(
                  Color(0xFF5F71FF),
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                translate('Voice Chatting'),
                style: const TextStyle(
                  color: Color(0xFF454447),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // 마이크 토글
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  border: Border.all(color: isMicOn ? const Color(0xFFB9B8BF) : const Color(0xFFFE3E3E)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: InkWell(
                  onTap: () => _toggleMic(client.id),
                  borderRadius: BorderRadius.circular(8),
                  child: Center(
                    child: SvgPicture.asset(
                      isMicOn ? 'assets/icons/mobile-remote-mic.svg' : 'assets/icons/mobile-remote-mic-off.svg',
                      width: 24,
                      height: 24,
                      colorFilter: ColorFilter.mode(
                        isMicOn ? const Color(0xFFB9B8BF) : const Color(0xFFFE3E3E),
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 스피커 토글
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  border: Border.all(color: isSpeakerOn ? const Color(0xFFB9B8BF) : const Color(0xFFFE3E3E)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: InkWell(
                  onTap: () => _toggleSpeaker(client.id),
                  borderRadius: BorderRadius.circular(8),
                  child: Center(
                    child: SvgPicture.asset(
                      isSpeakerOn ? 'assets/icons/mobile-remote-sound.svg' : 'assets/icons/mobile-remote-sound-off.svg',
                      width: 24,
                      height: 24,
                      colorFilter: ColorFilter.mode(
                        isSpeakerOn ? const Color(0xFFB9B8BF) : const Color(0xFFFE3E3E),
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 연결 끊기 버튼
              Container(
                width: 117,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFE3E3E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: InkWell(
                  onTap: () => bind.cmCloseVoiceCall(id: client.id),
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        'assets/icons/mobile-remote-voice-call-off.svg',
                        width: 18,
                        height: 18,
                        colorFilter: const ColorFilter.mode(
                          Color(0xFFFEFEFE),
                          BlendMode.srcIn,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        translate('Disconnect'),
                        style: const TextStyle(
                          color: Color(0xFFFEFEFE),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

  /// 음성 채팅 요청 카드
  Widget _buildVoiceCallRequestCard(Client client, ServerModel serverModel) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                'assets/icons/mobile-remote-mic.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(
                  Color(0xFFFF9800),
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                translate('Voice chat request'),
                style: const TextStyle(
                  color: Color(0xFF454447),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFE3E3E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: InkWell(
                  onTap: () => serverModel.handleVoiceCall(client, false),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: Text(
                        translate('Dismiss'),
                        style: const TextStyle(
                          color: Color(0xFFFEFEFE),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF5F71FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: InkWell(
                  onTap: () => serverModel.handleVoiceCall(client, true),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: Text(
                        translate('Accept'),
                        style: const TextStyle(
                          color: Color(0xFFFEFEFE),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 카메라/파일전송/화면공유 서브카드
  Widget _buildSubCard(Client client, ServerModel serverModel) {
    String label;
    String iconPath;
    if (client.isFileTransfer) {
      label = translate('File transfer');
      iconPath = 'assets/icons/mobile-remote-file-sender.svg';
    } else if (client.isViewCamera) {
      label = translate('Camera Sharing');
      iconPath = 'assets/icons/mobile-remote-camera.svg';
    } else {
      label = translate('Screen sharing');
      iconPath = 'assets/icons/mobile-remote-screen.svg';
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                iconPath,
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(
                  Color(0xFF5F71FF),
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF454447),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 102,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFE3E3E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: InkWell(
                  onTap: () {
                    bind.cmCloseConnection(connId: client.id);
                    gFFI.invokeMethod("cancel_notification", client.id);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Center(
                    child: Text(
                      translate('End Access'),
                      style: const TextStyle(
                        color: Color(0xFFFEFEFE),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClientCard(BuildContext context, ServerModel serverModel,
      Client primary, List<Client> clients) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEFEFE),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0x26333C87),
            blurRadius: 15,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 게스트 정보 라벨
          Text(
            translate('Guest Infomation'),
            style: const TextStyle(
              color: Color(0xFF646368),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          // 유저 정보 Row
          Row(
            children: [
              // 피어 OS 아이콘
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF1FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: getPlatformImage(
                    _getPeerPlatform(primary.peerId, peerPlatform: primary.peerPlatform),
                    size: 24,
                    color: const Color(0xFF5F71FF),
                    version: _getPeerOsVersion(primary.peerId),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 이름 + 코드
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '[${primary.name.isEmpty ? 'Unknown' : primary.name}]',
                      style: const TextStyle(
                        color: Color(0xFF646368),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '[${primary.peerId}]',
                      style: const TextStyle(color: Color(0xFF646368), fontSize: 13),
                    ),
                  ],
                ),
              ),
              // 채팅 아이콘
              SizedBox(
                width: 40,
                height: 40,
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MobileChatPage(
                          peerId: primary.peerId,
                          connId: primary.id,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: SvgPicture.asset(
                    'assets/icons/mobile-cm-chat.svg',
                    width: 40,
                    height: 40,
                    colorFilter: const ColorFilter.mode(
                      Color(0xFF8F8E95),
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // 서브카드들
          ..._buildAllSubCards(clients, serverModel),
        ],
      ),
    );
  }

}

class PaddingCard extends StatelessWidget {
  const PaddingCard({Key? key, required this.child, this.title, this.titleIcon})
      : super(key: key);

  final String? title;
  final Icon? titleIcon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final children = [child];
    if (title != null) {
      children.insert(
          0,
          Padding(
              padding: const EdgeInsets.fromLTRB(0, 5, 0, 8),
              child: Row(
                children: [
                  titleIcon?.marginOnly(right: 10) ?? const SizedBox.shrink(),
                  Expanded(
                    child: Text(title!,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.merge(TextStyle(fontWeight: FontWeight.bold))),
                  )
                ],
              )));
    }
    return SizedBox(
        width: double.maxFinite,
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          margin: const EdgeInsets.fromLTRB(12.0, 10.0, 12.0, 0),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 15.0, horizontal: 20.0),
            child: Column(
              children: children,
            ),
          ),
        ));
  }
}

class ClientInfo extends StatelessWidget {
  final Client client;
  ClientInfo(this.client);

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: [
          Row(
            children: [
              Expanded(
                  flex: -1,
                  child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: CircleAvatar(
                          backgroundColor: str2color(
                              client.name,
                              Theme.of(context).brightness == Brightness.light
                                  ? 255
                                  : 150),
                          child: Text(client.name[0])))),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(client.name, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Text(client.peerId, style: const TextStyle(fontSize: 10))
                  ]))
            ],
          ),
        ]));
  }
}

void androidChannelInit() {
  gFFI.setMethodCallHandler((method, arguments) {
    debugPrint("flutter got android msg,$method,$arguments");
    try {
      switch (method) {
        case "start_capture":
          {
            gFFI.dialogManager.dismissAll();
            gFFI.serverModel.updateClientState();
            break;
          }
        case "on_state_changed":
          {
            var name = arguments["name"] as String;
            var value = arguments["value"] as String == "true";
            debugPrint("from jvm:on_state_changed,$name:$value");
            gFFI.serverModel.changeStatue(name, value);
            break;
          }
        case "on_android_permission_result":
          {
            var type = arguments["type"] as String;
            var result = arguments["result"] as bool;
            AndroidPermissionManager.complete(type, result);
            break;
          }
        case "on_media_projection_canceled":
          {
            gFFI.serverModel.stopService();
            break;
          }
        case "msgbox":
          {
            var type = arguments["type"] as String;
            var title = arguments["title"] as String;
            var text = arguments["text"] as String;
            var link = (arguments["link"] ?? '') as String;
            msgBox(gFFI.sessionId, type, title, text, link, gFFI.dialogManager);
            break;
          }
        case "stop_service":
          {
            print(
                "stop_service by kotlin, isStart:${gFFI.serverModel.isStart}");
            if (gFFI.serverModel.isStart) {
              gFFI.serverModel.stopService();
            }
            break;
          }
      }
    } catch (e) {
      debugPrintStack(label: "MethodCallHandler err:$e");
    }
    return "";
  });
}

void showScamWarning(BuildContext context, ServerModel serverModel) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return ScamWarningDialog(serverModel: serverModel);
    },
  );
}

/// 화면 공유 서비스 활성화 경고 다이얼로그
void _showServiceWarningDialog(BuildContext context, ServerModel serverModel) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        contentPadding: MyTheme.dialogContentPadding(actions: true),
        actionsPadding: MyTheme.dialogActionsPadding(),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Warning title
            Text(
              translate("Warning"),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFE6565),
              ),
            ),
            const SizedBox(height: 16),
            // Main message
            Text(
              translate("android_service_will_start"),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF454447),
              ),
            ),
            const SizedBox(height: 8),
            // Description
            Text(
              translate("android_service_will_start_tip"),
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF454447),
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: dialogButton(
                  'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                  isOutline: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: dialogButton(
                  'OK',
                  onPressed: () {
                    Navigator.of(context).pop();
                    serverModel.toggleService();
                  },
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}

/// 화면 캡처 토글 경고 다이얼로그
void _showCaptureWarningDialog(BuildContext context, ServerModel serverModel) {
  // 현재 상태: mediaOk가 true면 끄기, false면 켜기
  final isStop = serverModel.mediaOk;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        contentPadding: MyTheme.dialogContentPadding(actions: true),
        actionsPadding: MyTheme.dialogActionsPadding(),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Warning title
            Text(
              translate("Warning"),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFE6565),
              ),
            ),
            const SizedBox(height: 16),
            // Main message - 끌 때와 켤 때 다른 메시지
            Text(
              isStop
                  ? translate("android_stop_service_tip")
                  : translate("android_capture_will_start"),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF454447),
              ),
            ),
            if (!isStop) ...[
              const SizedBox(height: 8),
              // Description (켤 때만 표시)
              Text(
                translate("android_capture_will_start_tip"),
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF454447),
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: dialogButton(
                  'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                  isOutline: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: dialogButton(
                  'OK',
                  onPressed: () {
                    Navigator.of(context).pop();
                    serverModel.toggleService();
                  },
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}
