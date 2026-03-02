import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_hbb/common/widgets/setting_widgets.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../common.dart';
import '../../common/widgets/cm_custom_toggle.dart';
import '../../common/widgets/dialog.dart';
import '../../common/widgets/login.dart';
import '../../consts.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../widgets/dialog.dart';
import 'home_page.dart';
import 'scan_page.dart';

class SettingsPage extends StatefulWidget implements PageShape {
  @override
  final title = translate("Settings");

  @override
  final icon = Icon(Icons.settings);

  @override
  final appBarActions = bind.isDisableSettings() ? [] : [ScanButton()];

  @override
  State<SettingsPage> createState() => _SettingsState();
}

const url = 'https://rustdesk.com/';

enum KeepScreenOn {
  never,
  duringControlled,
  serviceOn,
}

String _keepScreenOnToOption(KeepScreenOn value) {
  switch (value) {
    case KeepScreenOn.never:
      return 'never';
    case KeepScreenOn.duringControlled:
      return 'during-controlled';
    case KeepScreenOn.serviceOn:
      return 'service-on';
  }
}

KeepScreenOn optionToKeepScreenOn(String value) {
  switch (value) {
    case 'never':
      return KeepScreenOn.never;
    case 'service-on':
      return KeepScreenOn.serviceOn;
    default:
      return KeepScreenOn.duringControlled;
  }
}

class _SettingsState extends State<SettingsPage> with WidgetsBindingObserver {
  // 모바일 보안 설정 페이지와 동일한 색상
  static const Color _titleColor = Color(0xFF454447);
  static const Color _labelColor = Color(0xFF646368);

  final _hasIgnoreBattery =
      false; //androidVersion >= 26; // remove because not work on every device
  var _ignoreBatteryOpt = false;
  var _enableStartOnBoot = false;
  var _checkUpdateOnStartup = false;
  var _floatingWindowDisabled = false;
  var _keepScreenOn = KeepScreenOn.duringControlled; // relay on floating window
  var _enableAbr = false;
  var _denyLANDiscovery = false;
  var _onlyWhiteList = false;
  var _enableDirectIPAccess = false;
  var _enableRecordSession = false;
  var _enableHardwareCodec = false;
  var _allowWebSocket = false;
  var _autoRecordIncomingSession = false;
  var _autoRecordOutgoingSession = false;
  var _allowAutoDisconnect = false;
  var _localIP = "";
  var _directAccessPort = "";
  var _fingerprint = "";
  var _buildDate = "";
  var _autoDisconnectTimeout = "";
  var _hideServer = false;
  var _hideProxy = false;
  var _hideNetwork = false;
  var _hideWebSocket = false;
  var _enableTrustedDevices = false;
  var _enableUdpPunch = false;
  var _allowInsecureTlsFallback = false;
  var _disableUdp = false;
  var _enableIpv6Punch = false;
  var _isUsingPublicServer = false;
  var _allowAskForNoteAtEndOfConnection = false;

  // 언어 관련
  List<List<String>> _langs = [];
  String _currentLang = '';

  _SettingsState() {
    _enableAbr = option2bool(
        kOptionEnableAbr, bind.mainGetOptionSync(key: kOptionEnableAbr));
    _denyLANDiscovery = !option2bool(kOptionEnableLanDiscovery,
        bind.mainGetOptionSync(key: kOptionEnableLanDiscovery));
    _onlyWhiteList = whitelistNotEmpty();
    _enableDirectIPAccess = option2bool(
        kOptionDirectServer, bind.mainGetOptionSync(key: kOptionDirectServer));
    _enableRecordSession = option2bool(kOptionEnableRecordSession,
        bind.mainGetOptionSync(key: kOptionEnableRecordSession));
    _enableHardwareCodec = option2bool(kOptionEnableHwcodec,
        bind.mainGetOptionSync(key: kOptionEnableHwcodec));
    _allowWebSocket = mainGetBoolOptionSync(kOptionAllowWebSocket);
    _allowInsecureTlsFallback =
        mainGetBoolOptionSync(kOptionAllowInsecureTLSFallback);
    _disableUdp = bind.mainGetOptionSync(key: kOptionDisableUdp) == 'Y';
    _autoRecordIncomingSession = option2bool(kOptionAllowAutoRecordIncoming,
        bind.mainGetOptionSync(key: kOptionAllowAutoRecordIncoming));
    _autoRecordOutgoingSession = option2bool(kOptionAllowAutoRecordOutgoing,
        bind.mainGetLocalOption(key: kOptionAllowAutoRecordOutgoing));
    _localIP = bind.mainGetOptionSync(key: 'local-ip-addr');
    _directAccessPort = bind.mainGetOptionSync(key: kOptionDirectAccessPort);
    _allowAutoDisconnect = option2bool(kOptionAllowAutoDisconnect,
        bind.mainGetOptionSync(key: kOptionAllowAutoDisconnect));
    _autoDisconnectTimeout =
        bind.mainGetOptionSync(key: kOptionAutoDisconnectTimeout);
    _hideServer =
        bind.mainGetBuildinOption(key: kOptionHideServerSetting) == 'Y';
    _hideProxy = bind.mainGetBuildinOption(key: kOptionHideProxySetting) == 'Y';
    _hideNetwork =
        bind.mainGetBuildinOption(key: kOptionHideNetworkSetting) == 'Y';
    _hideWebSocket =
        bind.mainGetBuildinOption(key: kOptionHideWebSocketSetting) == 'Y' ||
            isWeb;
    _enableTrustedDevices = mainGetBoolOptionSync(kOptionEnableTrustedDevices);
    _enableUdpPunch = mainGetLocalBoolOptionSync(kOptionEnableUdpPunch);
    _enableIpv6Punch = mainGetLocalBoolOptionSync(kOptionEnableIpv6Punch);
    _allowAskForNoteAtEndOfConnection =
        mainGetLocalBoolOptionSync(kOptionAllowAskForNoteAtEndOfConnection);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLanguages();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      var update = false;

      if (_hasIgnoreBattery) {
        if (await checkAndUpdateIgnoreBatteryStatus()) {
          update = true;
        }
      }

      if (await checkAndUpdateStartOnBoot()) {
        update = true;
      }

      // start on boot depends on ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS and SYSTEM_ALERT_WINDOW
      var enableStartOnBoot =
          await gFFI.invokeMethod(AndroidChannel.kGetStartOnBootOpt);
      if (enableStartOnBoot) {
        if (!await canStartOnBoot()) {
          enableStartOnBoot = false;
          gFFI.invokeMethod(AndroidChannel.kSetStartOnBootOpt, false);
        }
      }

      if (enableStartOnBoot != _enableStartOnBoot) {
        update = true;
        _enableStartOnBoot = enableStartOnBoot;
      }

      var checkUpdateOnStartup =
          mainGetLocalBoolOptionSync(kOptionEnableCheckUpdate);
      if (checkUpdateOnStartup != _checkUpdateOnStartup) {
        update = true;
        _checkUpdateOnStartup = checkUpdateOnStartup;
      }

      var floatingWindowDisabled =
          bind.mainGetLocalOption(key: kOptionDisableFloatingWindow) == "Y" ||
              !await AndroidPermissionManager.check(kSystemAlertWindow);
      if (floatingWindowDisabled != _floatingWindowDisabled) {
        update = true;
        _floatingWindowDisabled = floatingWindowDisabled;
      }

      final keepScreenOn = _floatingWindowDisabled
          ? KeepScreenOn.never
          : optionToKeepScreenOn(
              bind.mainGetLocalOption(key: kOptionKeepScreenOn));
      if (keepScreenOn != _keepScreenOn) {
        update = true;
        _keepScreenOn = keepScreenOn;
      }

      final fingerprint = await bind.mainGetFingerprint();
      if (_fingerprint != fingerprint) {
        update = true;
        _fingerprint = fingerprint;
      }

      final buildDate = await bind.mainGetBuildDate();
      if (_buildDate != buildDate) {
        update = true;
        _buildDate = buildDate;
      }

      final isUsingPublicServer = await bind.mainIsUsingPublicServer();
      if (_isUsingPublicServer != isUsingPublicServer) {
        update = true;
        _isUsingPublicServer = isUsingPublicServer;
      }

      if (update) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      () async {
        final ibs = await checkAndUpdateIgnoreBatteryStatus();
        final sob = await checkAndUpdateStartOnBoot();
        if (ibs || sob) {
          setState(() {});
        }
      }();
    }
  }

  Future<bool> checkAndUpdateIgnoreBatteryStatus() async {
    final res = await AndroidPermissionManager.check(
        kRequestIgnoreBatteryOptimizations);
    if (_ignoreBatteryOpt != res) {
      _ignoreBatteryOpt = res;
      return true;
    } else {
      return false;
    }
  }

  Future<bool> checkAndUpdateStartOnBoot() async {
    if (!await canStartOnBoot() && _enableStartOnBoot) {
      _enableStartOnBoot = false;
      debugPrint(
          "checkAndUpdateStartOnBoot and set _enableStartOnBoot -> false");
      gFFI.invokeMethod(AndroidChannel.kSetStartOnBootOpt, false);
      return true;
    } else {
      return false;
    }
  }

  /// 언어 목록 로드
  Future<void> _loadLanguages() async {
    try {
      final langsJson = await bind.mainGetLangs();
      final langsList = json.decode(langsJson) as List<dynamic>;
      final langs =
          langsList.map((e) => [e[0] as String, e[1] as String]).toList();
      final keys = langs.map((e) => e[0]).toList();
      var lang = bind.mainGetLocalOption(key: kCommConfKeyLang);
      // 데스크탑과 동일: 비어있거나 default이거나 목록에 없으면 한국어로 설정
      if (lang.isEmpty || lang == 'default' || !keys.contains(lang)) {
        lang = 'ko';
      }
      setState(() {
        _langs = langs;
        _currentLang = lang;
      });
    } catch (e) {
      debugPrint('Failed to load languages: $e');
    }
  }

  /// 네비게이션 카드 (아이콘 + 제목 + 화살표)
  Widget _buildNavigationCard({
    required String title,
    IconData? icon,
    required VoidCallback? onTap,
    String? subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26333C87),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: _labelColor, size: 24),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: _titleColor,
                          fontSize: 14,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              color: _labelColor,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios,
                    color: Color(0xFF8F8E95), size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 스위치 카드 (제목 + 토글)
  Widget _buildSwitchCard({
    required String title,
    required bool value,
    required ValueChanged<bool>? onChanged,
    String? subtitle,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26333C87),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _titleColor,
                      fontSize: 14,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          color: _labelColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              trailing,
              const SizedBox(width: 12),
            ],
            CmCustomToggle(
              value: value,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  /// 정보 표시 카드 (제목 + 값)
  Widget _buildInfoCard({
    required String title,
    required String value,
    IconData? icon,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26333C87),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: _labelColor, size: 24),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: _titleColor,
                          fontSize: 14,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          value,
                          style: TextStyle(
                            color: _labelColor,
                            fontSize: 12,
                            decoration:
                                onTap != null ? TextDecoration.underline : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 드롭다운이 포함된 카드
  Widget _buildDropdownCard({
    required String title,
    required String value,
    required List<String> items,
    required Function(String)? onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26333C87),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              title,
              style: const TextStyle(
                color: _titleColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(
              height: 1, color: Color(0xFFEEEEEE), indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFDEDEE2)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<String>(
                value: items.contains(value) ? value : items.first,
                items: items.map((item) {
                  return DropdownMenuItem<String>(
                    value: item,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: _titleColor,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: onChanged == null
                    ? null
                    : (newValue) {
                        if (newValue != null) {
                          onChanged(newValue);
                        }
                      },
                isExpanded: true,
                underline: const SizedBox.shrink(),
                icon: const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Icon(Icons.expand_more, color: _labelColor, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// About 페이지 링크 버튼
  Widget _buildAboutLinkButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFDEDEE2)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: _titleColor,
          ),
        ),
      ),
    );
  }

  /// 토글 목록이 포함된 카드
  Widget _buildToggleCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26333C87),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              title,
              style: const TextStyle(
                color: _titleColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(
              height: 1, color: Color(0xFFEEEEEE), indent: 16, endIndent: 16),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// 토글 행 위젯
  Widget _buildToggleRow({
    required String label,
    required bool value,
    required ValueChanged<bool>? onChanged,
    String? subtitle,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _titleColor,
                    fontSize: 14,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        color: _labelColor,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            trailing,
            const SizedBox(width: 12),
          ],
          CmCustomToggle(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<FfiModel>(context);
    final outgoingOnly = bind.isOutgoingOnly();
    final incomingOnly = bind.isIncomingOnly();
    final disabledSettings = bind.isDisableSettings();
    final hideSecuritySettings =
        bind.mainGetBuildinOption(key: kOptionHideSecuritySetting) == 'Y';
    final enable2fa = bind.mainHasValid2FaSync();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: _titleColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          translate('Settings'),
          style: const TextStyle(
            color: _titleColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 로고
                  Center(
                    child: Column(
                      children: [
                        if (bind.isCustomClient()) loadPowered(context),
                        loadLogo(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 네트워크 옵션 카드
                  _buildToggleCard(
                    title: translate('Network'),
                    children: [
                      if (!_isUsingPublicServer)
                        _buildToggleRow(
                          label: translate('Allow insecure TLS fallback'),
                          value: _allowInsecureTlsFallback,
                          onChanged:
                              isOptionFixed(kOptionAllowInsecureTLSFallback)
                                  ? null
                                  : (v) async {
                                      await mainSetBoolOption(
                                          kOptionAllowInsecureTLSFallback, v);
                                      final newValue = mainGetBoolOptionSync(
                                          kOptionAllowInsecureTLSFallback);
                                      setState(() =>
                                          _allowInsecureTlsFallback = newValue);
                                    },
                        ),
                      if (isAndroid && !outgoingOnly && !_isUsingPublicServer)
                        _buildToggleRow(
                          label: translate('Disable UDP'),
                          value: _disableUdp,
                          onChanged: isOptionFixed(kOptionDisableUdp)
                              ? null
                              : (v) async {
                                  await bind.mainSetOption(
                                      key: kOptionDisableUdp,
                                      value: v ? 'Y' : 'N');
                                  final newValue = bind.mainGetOptionSync(
                                          key: kOptionDisableUdp) ==
                                      'Y';
                                  setState(() => _disableUdp = newValue);
                                },
                        ),
                      if (!incomingOnly)
                        _buildToggleRow(
                          label: translate('Enable UDP hole punching'),
                          value: _enableUdpPunch,
                          onChanged: (v) async {
                            await mainSetLocalBoolOption(
                                kOptionEnableUdpPunch, v);
                            final newValue = mainGetLocalBoolOptionSync(
                                kOptionEnableUdpPunch);
                            setState(() => _enableUdpPunch = newValue);
                          },
                        ),
                      if (!incomingOnly)
                        _buildToggleRow(
                          label: translate('Enable IPv6 P2P connection'),
                          value: _enableIpv6Punch,
                          onChanged: (v) async {
                            await mainSetLocalBoolOption(
                                kOptionEnableIpv6Punch, v);
                            final newValue = mainGetLocalBoolOptionSync(
                                kOptionEnableIpv6Punch);
                            setState(() => _enableIpv6Punch = newValue);
                          },
                        ),
                    ],
                  ),

                  // 언어
                  if (_langs.isNotEmpty)
                    _buildDropdownCard(
                      title: translate('Language'),
                      value: _langs.firstWhere(
                        (e) => e[0] == _currentLang,
                        orElse: () => _langs.first,
                      )[1],
                      items: _langs.map((e) => e[1]).toList(),
                      onChanged: isOptionFixed(kCommConfKeyLang)
                          ? null
                          : (value) async {
                              final langKey =
                                  _langs.firstWhere((e) => e[1] == value)[0];
                              if (langKey != _currentLang) {
                                await bind.mainSetLocalOption(
                                    key: kCommConfKeyLang, value: langKey);
                                bind.mainChangeLanguage(lang: langKey);
                                setState(() => _currentLang = langKey);
                                HomePage.homeKey.currentState?.refreshPages();
                              }
                            },
                    ),

                  // 하드웨어 코덱
                  if (isAndroid)
                    _buildToggleCard(
                      title: translate('Hardware Codec'),
                      children: [
                        _buildToggleRow(
                          label: translate('Enable hardware codec'),
                          value: _enableHardwareCodec,
                          onChanged: isOptionFixed(kOptionEnableHwcodec)
                              ? null
                              : (v) async {
                                  await mainSetBoolOption(
                                      kOptionEnableHwcodec, v);
                                  final newValue = await mainGetBoolOption(
                                      kOptionEnableHwcodec);
                                  setState(
                                      () => _enableHardwareCodec = newValue);
                                },
                        ),
                      ],
                    ),

                  // 녹화
                  if (isAndroid) ...[
                    _buildToggleCard(
                      title: translate('Recording'),
                      children: [
                        if (!outgoingOnly)
                          _buildToggleRow(
                            label: translate(
                                'Automatically record incoming sessions'),
                            value: _autoRecordIncomingSession,
                            onChanged: isOptionFixed(
                                    kOptionAllowAutoRecordIncoming)
                                ? null
                                : (v) async {
                                    await bind.mainSetOption(
                                        key: kOptionAllowAutoRecordIncoming,
                                        value: bool2option(
                                            kOptionAllowAutoRecordIncoming, v));
                                    final newValue = option2bool(
                                        kOptionAllowAutoRecordIncoming,
                                        await bind.mainGetOption(
                                            key:
                                                kOptionAllowAutoRecordIncoming));
                                    setState(() =>
                                        _autoRecordIncomingSession = newValue);
                                  },
                          ),
                        if (!incomingOnly)
                          _buildToggleRow(
                            label: translate(
                                'Automatically record outgoing sessions'),
                            value: _autoRecordOutgoingSession,
                            onChanged: isOptionFixed(
                                    kOptionAllowAutoRecordOutgoing)
                                ? null
                                : (v) async {
                                    await bind.mainSetLocalOption(
                                        key: kOptionAllowAutoRecordOutgoing,
                                        value: bool2option(
                                            kOptionAllowAutoRecordOutgoing, v));
                                    final newValue = option2bool(
                                        kOptionAllowAutoRecordOutgoing,
                                        bind.mainGetLocalOption(
                                            key:
                                                kOptionAllowAutoRecordOutgoing));
                                    setState(() =>
                                        _autoRecordOutgoingSession = newValue);
                                  },
                          ),
                        // 녹화 경로 (F7F7F7 배경 카드)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F7F7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!outgoingOnly) ...[
                                    Text(
                                      translate('Incoming'),
                                      style: const TextStyle(
                                        color: _titleColor,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      bind.mainVideoSaveDirectory(root: true),
                                      style: const TextStyle(
                                        color: _labelColor,
                                        fontSize: 11,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                  ],
                                  if (!outgoingOnly && !incomingOnly)
                                    const SizedBox(height: 12),
                                  if (!incomingOnly) ...[
                                    Text(
                                      translate('Outgoing'),
                                      style: const TextStyle(
                                        color: _titleColor,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      bind.mainVideoSaveDirectory(root: false),
                                      style: const TextStyle(
                                        color: _labelColor,
                                        fontSize: 11,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // 2FA
                  if (isAndroid &&
                      !disabledSettings &&
                      !outgoingOnly &&
                      !hideSecuritySettings) ...[
                    _buildSwitchCard(
                      title: translate('enable-2fa-title'),
                      value: enable2fa,
                      onChanged: (v) async {
                        update() async {
                          setState(() {});
                        }

                        if (v == false) {
                          CommonConfirmDialog(gFFI.dialogManager,
                              translate('cancel-2fa-confirm-tip'), () {
                            change2fa(callback: update);
                          });
                        } else {
                          change2fa(callback: update);
                        }
                      },
                    ),
                    if (enable2fa)
                      _buildSwitchCard(
                        title: translate('Telegram bot'),
                        value: bind.mainHasValidBotSync(),
                        onChanged: (v) async {
                          update() async {
                            setState(() {});
                          }

                          if (v == false) {
                            CommonConfirmDialog(gFFI.dialogManager,
                                translate('cancel-bot-confirm-tip'), () {
                              changeBot(callback: update);
                            });
                          } else {
                            changeBot(callback: update);
                          }
                        },
                      ),
                    if (enable2fa)
                      _buildSwitchCard(
                        title: translate('Enable trusted devices'),
                        subtitle:
                            '* ${translate('enable-trusted-devices-tip')}',
                        value: _enableTrustedDevices,
                        onChanged: isOptionFixed(kOptionEnableTrustedDevices)
                            ? null
                            : (v) async {
                                mainSetBoolOption(
                                    kOptionEnableTrustedDevices, v);
                                setState(() => _enableTrustedDevices = v);
                              },
                      ),
                    if (enable2fa && _enableTrustedDevices)
                      _buildNavigationCard(
                        title: translate('Manage trusted devices'),
                        icon: Icons.devices,
                        onTap: () {
                          Navigator.push(context,
                              MaterialPageRoute(builder: (context) {
                            return _ManageTrustedDevices();
                          }));
                        },
                      ),
                  ],

                  // 화면 공유
                  if (isAndroid &&
                      !disabledSettings &&
                      !outgoingOnly &&
                      !hideSecuritySettings) ...[
                    _buildToggleCard(
                      title: translate('Share screen'),
                      children: [
                        _buildToggleRow(
                          label: translate('Deny LAN discovery'),
                          value: _denyLANDiscovery,
                          onChanged: isOptionFixed(kOptionEnableLanDiscovery)
                              ? null
                              : (v) async {
                                  await bind.mainSetOption(
                                      key: kOptionEnableLanDiscovery,
                                      value: bool2option(
                                          kOptionEnableLanDiscovery, !v));
                                  final newValue = !option2bool(
                                      kOptionEnableLanDiscovery,
                                      await bind.mainGetOption(
                                          key: kOptionEnableLanDiscovery));
                                  setState(() => _denyLANDiscovery = newValue);
                                },
                        ),
                        _buildToggleRow(
                          label: translate('Use IP Whitelisting'),
                          value: _onlyWhiteList,
                          onChanged: (_) async {
                            update() async {
                              final onlyWhiteList = whitelistNotEmpty();
                              if (onlyWhiteList != _onlyWhiteList) {
                                setState(() => _onlyWhiteList = onlyWhiteList);
                              }
                            }

                            changeWhiteList(callback: update);
                          },
                          trailing: null,
                        ),
                        _buildToggleRow(
                          label: translate('Adaptive bitrate'),
                          value: _enableAbr,
                          onChanged: isOptionFixed(kOptionEnableAbr)
                              ? null
                              : (v) async {
                                  await mainSetBoolOption(kOptionEnableAbr, v);
                                  final newValue =
                                      await mainGetBoolOption(kOptionEnableAbr);
                                  setState(() => _enableAbr = newValue);
                                },
                        ),
                        _buildToggleRow(
                          label: translate('Enable recording session'),
                          value: _enableRecordSession,
                          onChanged: isOptionFixed(kOptionEnableRecordSession)
                              ? null
                              : (v) async {
                                  await mainSetBoolOption(
                                      kOptionEnableRecordSession, v);
                                  final newValue = await mainGetBoolOption(
                                      kOptionEnableRecordSession);
                                  setState(
                                      () => _enableRecordSession = newValue);
                                },
                        ),
                        _buildToggleRow(
                          label: translate('auto_disconnect_option_tip'),
                          value: _allowAutoDisconnect,
                          onChanged: isOptionFixed(kOptionAllowAutoDisconnect)
                              ? null
                              : (_) async {
                                  _allowAutoDisconnect = !_allowAutoDisconnect;
                                  String value = bool2option(
                                      kOptionAllowAutoDisconnect,
                                      _allowAutoDisconnect);
                                  await bind.mainSetOption(
                                      key: kOptionAllowAutoDisconnect,
                                      value: value);
                                  setState(() {});
                                },
                        ),
                        // 비활성 상태 시간 설정 (F7F7F7 배경 카드)
                        if (_allowAutoDisconnect)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F7F7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      translate('Timeout in minutes'),
                                      style: const TextStyle(
                                        color: _titleColor,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${_autoDisconnectTimeout.isEmpty ? '10' : _autoDisconnectTimeout} min',
                                    style: const TextStyle(
                                      color: _labelColor,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: isOptionFixed(
                                            kOptionAutoDisconnectTimeout)
                                        ? null
                                        : () async {
                                            final timeout =
                                                await changeAutoDisconnectTimeout(
                                                    _autoDisconnectTimeout);
                                            setState(() =>
                                                _autoDisconnectTimeout =
                                                    timeout);
                                          },
                                    child: SvgPicture.asset(
                                      'assets/icons/mobile-setting-pen.svg',
                                      width: 19,
                                      height: 19,
                                      colorFilter: const ColorFilter.mode(
                                        Color(0xFF8F8E95),
                                        BlendMode.srcIn,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],

                  // 디스플레이 설정
                  if (!bind.isIncomingOnly()) ...[
                    _buildNavigationCard(
                      title: translate('Display Settings'),
                      onTap: () {
                        Navigator.push(context,
                            MaterialPageRoute(builder: (context) {
                          return DisplayPage();
                        }));
                      },
                    ),
                  ],

                  // 개선 사항
                  if (isAndroid &&
                      !disabledSettings &&
                      !outgoingOnly &&
                      !hideSecuritySettings) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x26333C87),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Keep OneDesk background service
                          if (_hasIgnoreBattery)
                            _buildToggleRow(
                              label:
                                  translate('Keep OneDesk background service'),
                              subtitle:
                                  '* ${translate('Ignore Battery Optimizations')}',
                              value: _ignoreBatteryOpt,
                              onChanged: (v) async {
                                if (v) {
                                  await AndroidPermissionManager.request(
                                      kRequestIgnoreBatteryOptimizations);
                                } else {
                                  final res = await gFFI.dialogManager.show<
                                      bool>((setState, close,
                                          context) =>
                                      CustomAlertDialog(
                                        title: Text(
                                            translate("Open System Setting")),
                                        content: Text(translate(
                                            "android_open_battery_optimizations_tip")),
                                        actions: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: dialogButton("Cancel",
                                                    onPressed: () => close(),
                                                    isOutline: true),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: dialogButton("Open System Setting",
                                                    onPressed: () => close(true)),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ));
                                  if (res == true) {
                                    AndroidPermissionManager.startAction(
                                        kActionApplicationDetailsSettings);
                                  }
                                }
                              },
                            ),
                          // Start on boot
                          _buildToggleRow(
                            label: translate('Start on boot'),
                            subtitle:
                                '* ${translate('Start the screen sharing service on boot, requires special permissions')}',
                            value: _enableStartOnBoot,
                            onChanged: (toValue) async {
                              if (toValue) {
                                if (!await AndroidPermissionManager.check(
                                    kRequestIgnoreBatteryOptimizations)) {
                                  if (!await AndroidPermissionManager.request(
                                      kRequestIgnoreBatteryOptimizations)) {
                                    return;
                                  }
                                }
                                if (!await AndroidPermissionManager.check(
                                    kSystemAlertWindow)) {
                                  if (!await AndroidPermissionManager.request(
                                      kSystemAlertWindow)) {
                                    return;
                                  }
                                }
                              }
                              setState(() => _enableStartOnBoot = toValue);
                              gFFI.invokeMethod(
                                  AndroidChannel.kSetStartOnBootOpt, toValue);
                            },
                          ),
                          // Check for software update
                          if (!bind.isCustomClient())
                            _buildToggleRow(
                              label: translate(
                                  'Check for software update on startup'),
                              value: _checkUpdateOnStartup,
                              onChanged: (bool toValue) async {
                                await mainSetLocalBoolOption(
                                    kOptionEnableCheckUpdate, toValue);
                                setState(() => _checkUpdateOnStartup = toValue);
                              },
                            ),
                          // Floating window
                          _buildToggleRow(
                            label: translate('Floating window'),
                            subtitle: '* ${translate('floating_window_tip')}',
                            value: !_floatingWindowDisabled,
                            onChanged: bind.mainIsOptionFixed(
                                    key: kOptionDisableFloatingWindow)
                                ? null
                                : (bool toValue) async {
                                    if (toValue) {
                                      if (!await AndroidPermissionManager.check(
                                          kSystemAlertWindow)) {
                                        if (!await AndroidPermissionManager
                                            .request(kSystemAlertWindow)) {
                                          return;
                                        }
                                      }
                                    }
                                    final disable = !toValue;
                                    bind.mainSetLocalOption(
                                        key: kOptionDisableFloatingWindow,
                                        value: disable ? 'Y' : defaultOptionNo);
                                    setState(() =>
                                        _floatingWindowDisabled = disable);
                                    gFFI.serverModel
                                        .androidUpdatekeepScreenOn();
                                  },
                          ),
                          // 화면 켜짐 유지 드롭다운
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  translate('Keep screen on'),
                                  style: const TextStyle(
                                    color: _titleColor,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: const Color(0xFFDEDEE2)),
                                  ),
                                  child: DropdownButton<String>(
                                    value: _getKeepScreenOnLabel(
                                        _floatingWindowDisabled
                                            ? KeepScreenOn.never
                                            : optionToKeepScreenOn(
                                                bind.mainGetLocalOption(
                                                    key: kOptionKeepScreenOn))),
                                    items: [
                                      translate('Never'),
                                      translate('During controlled'),
                                      translate('During service is on'),
                                    ].map((item) {
                                      return DropdownMenuItem<String>(
                                        value: item,
                                        child: Text(
                                          item,
                                          style: const TextStyle(
                                            color: _titleColor,
                                            fontSize: 14,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (isOptionFixed(
                                                kOptionKeepScreenOn) ||
                                            _floatingWindowDisabled)
                                        ? null
                                        : (value) async {
                                            if (value == null) return;
                                            String optionValue;
                                            if (value == translate('Never')) {
                                              optionValue =
                                                  _keepScreenOnToOption(
                                                      KeepScreenOn.never);
                                            } else if (value ==
                                                translate(
                                                    'During controlled')) {
                                              optionValue =
                                                  _keepScreenOnToOption(
                                                      KeepScreenOn
                                                          .duringControlled);
                                            } else {
                                              optionValue =
                                                  _keepScreenOnToOption(
                                                      KeepScreenOn.serviceOn);
                                            }
                                            await bind.mainSetLocalOption(
                                                key: kOptionKeepScreenOn,
                                                value: optionValue);
                                            setState(() => _keepScreenOn =
                                                optionToKeepScreenOn(
                                                    optionValue));
                                            gFFI.serverModel
                                                .androidUpdatekeepScreenOn();
                                          },
                                    underline: const SizedBox.shrink(),
                                    icon: const Icon(Icons.keyboard_arrow_down,
                                        color: _labelColor),
                                    isExpanded: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x26333C87),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 카드 내부 타이틀
                          Text(
                            translate('About OneDesk'),
                            style: const TextStyle(
                              color: _titleColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Divider(color: Color(0xFFEEEEEE)),
                          const SizedBox(height: 12),
                          // 버전 정보
                          Text(
                            '${translate('Version')}: $version',
                            style: const TextStyle(
                              color: _titleColor,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 빌드 날짜
                          Text(
                            '${translate('Build Date')}: $_buildDate',
                            style: const TextStyle(
                              color: _titleColor,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // 링크 버튼들
                          Row(
                            children: [
                              // Onedesk 홈페이지 버튼
                              _buildAboutLinkButton(
                                label: translate('Website'),
                                onTap: () =>
                                    launchUrlString('https://onedesk.co.kr'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              // 개인정보 보호정책 버튼
                              _buildAboutLinkButton(
                                label: translate('Privacy Statement'),
                                onTap: () => launchUrlString(
                                    'https://onedesk.co.kr/terms'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Copyright 박스
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8ECFF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Copyright © ${DateTime.now().year} MarketingMonster Ltd.',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF5F71FF),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  translate('Slogan_tip'),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF5F71FF),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
          // 하단 버튼
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  // 취소 버튼
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF646368),
                        side: const BorderSide(color: Color(0xFFDEDEE2)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(translate('Cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 설정 완료 버튼
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5B7BF8),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        translate('Settings Complete'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getKeepScreenOnLabel(KeepScreenOn value) {
    switch (value) {
      case KeepScreenOn.never:
        return translate('Never');
      case KeepScreenOn.duringControlled:
        return translate('During controlled');
      case KeepScreenOn.serviceOn:
        return translate('During service is on');
    }
  }

  Future<bool> canStartOnBoot() async {
    // start on boot depends on ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS and SYSTEM_ALERT_WINDOW
    if (_hasIgnoreBattery && !_ignoreBatteryOpt) {
      return false;
    }
    if (!await AndroidPermissionManager.check(kSystemAlertWindow)) {
      return false;
    }
    return true;
  }

  defaultDisplaySection() {
    return SettingsSection(
      title: Text(translate("Display Settings")),
      tiles: [
        SettingsTile(
            title: Text(translate('Display Settings')),
            leading: Icon(Icons.desktop_windows_outlined),
            trailing: Icon(Icons.arrow_forward_ios),
            onPressed: (context) {
              Navigator.push(context, MaterialPageRoute(builder: (context) {
                return DisplayPage();
              }));
            })
      ],
    );
  }
}

void showLanguageSettings(OverlayDialogManager dialogManager) async {
  try {
    final langs = json.decode(await bind.mainGetLangs()) as List<dynamic>;
    var lang = bind.mainGetLocalOption(key: kCommConfKeyLang);
    // 기본값이 비어있거나 'default'면 한국어로 설정
    if (lang.isEmpty || lang == 'default') {
      lang = 'ko';
    }
    dialogManager.show((setState, close, context) {
      setLang(v) async {
        if (lang != v) {
          setState(() {
            lang = v;
          });
          await bind.mainSetLocalOption(key: kCommConfKeyLang, value: v);
          HomePage.homeKey.currentState?.refreshPages();
          Future.delayed(Duration(milliseconds: 200), close);
        }
      }

      final isOptFixed = isOptionFixed(kCommConfKeyLang);
      return CustomAlertDialog(
        content: Column(
          children: langs.map((e) {
            final key = e[0] as String;
            final name = e[1] as String;
            return getRadio(
                Text(translate(name)), key, lang, isOptFixed ? null : setLang);
          }).toList(),
        ),
      );
    }, backDismiss: true, clickMaskDismiss: true);
  } catch (e) {
    //
  }
}

void showThemeSettings(OverlayDialogManager dialogManager) async {
  var themeMode = MyTheme.getThemeModePreference();

  dialogManager.show((setState, close, context) {
    setTheme(v) {
      if (themeMode != v) {
        setState(() {
          themeMode = v;
        });
        MyTheme.changeDarkMode(themeMode);
        Future.delayed(Duration(milliseconds: 200), close);
      }
    }

    final isOptFixed = isOptionFixed(kCommConfKeyTheme);
    return CustomAlertDialog(
      content: Column(children: [
        getRadio(Text(translate('Light')), ThemeMode.light, themeMode,
            isOptFixed ? null : setTheme),
        getRadio(Text(translate('Dark')), ThemeMode.dark, themeMode,
            isOptFixed ? null : setTheme),
        getRadio(Text(translate('Follow System')), ThemeMode.system, themeMode,
            isOptFixed ? null : setTheme)
      ]),
    );
  }, backDismiss: true, clickMaskDismiss: true);
}

void showAbout(OverlayDialogManager dialogManager) {
  dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(translate('About OneDesk')),
      content: Wrap(direction: Axis.vertical, spacing: 12, children: [
        Text('Version: $version'),
        InkWell(
            onTap: () async {
              const url = 'https://rustdesk.com/';
              await launchUrl(Uri.parse(url));
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('onedesk.co.kr',
                  style: TextStyle()),
            )),
      ]),
      actions: [],
    );
  }, clickMaskDismiss: true, backDismiss: true);
}

class ScanButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.qr_code_scanner),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (BuildContext context) => ScanPage(),
          ),
        );
      },
    );
  }
}

class DisplayPage extends StatefulWidget {
  const DisplayPage({Key? key}) : super(key: key);

  @override
  State<DisplayPage> createState() => _DisplayPageState();
}

class _DisplayPageState extends State<DisplayPage> {
  // 모바일 보안 설정 페이지와 동일한 색상
  static const Color _titleColor = Color(0xFF454447);
  static const Color _labelColor = Color(0xFF646368);

  @override
  Widget build(BuildContext context) {
    final Map codecsJson = jsonDecode(bind.mainSupportedHwdecodings());
    final h264 = codecsJson['h264'] ?? false;
    final h265 = codecsJson['h265'] ?? false;
    var codecList = [
      _RadioEntry('Auto', 'auto'),
      _RadioEntry('VP8', 'vp8'),
      _RadioEntry('VP9', 'vp9'),
      _RadioEntry('AV1', 'av1'),
      if (h264) _RadioEntry('H264', 'h264'),
      if (h265) _RadioEntry('H265', 'h265')
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: _titleColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          translate('Display Settings'),
          style: const TextStyle(
            color: _titleColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 기본 보기 스타일 카드
                  _buildDropdownCard(
                    title: translate('Default View Style'),
                    value: _getViewStyleLabel(
                        bind.mainGetUserDefaultOption(key: kOptionViewStyle)),
                    items: [
                      translate('Scale original'),
                      translate('Scale adaptive'),
                    ],
                    onChanged: isOptionFixed(kOptionViewStyle)
                        ? null
                        : (value) async {
                            String key = value == translate('Scale original')
                                ? kRemoteViewStyleOriginal
                                : kRemoteViewStyleAdaptive;
                            await bind.mainSetUserDefaultOption(
                                key: kOptionViewStyle, value: key);
                            setState(() {});
                          },
                  ),
                  const SizedBox(height: 12),
                  // 기본 이미지 품질 카드
                  _buildDropdownCard(
                    title: translate('Default Image Quality'),
                    value: _getImageQualityLabel(
                        bind.mainGetUserDefaultOption(key: kOptionImageQuality)),
                    items: [
                      translate('Good image quality'),
                      translate('Balanced'),
                      translate('Optimize reaction time'),
                    ],
                    onChanged: isOptionFixed(kOptionImageQuality)
                        ? null
                        : (value) async {
                            String key;
                            if (value == translate('Good image quality')) {
                              key = kRemoteImageQualityBest;
                            } else if (value == translate('Balanced')) {
                              key = kRemoteImageQualityBalanced;
                            } else {
                              key = kRemoteImageQualityLow;
                            }
                            await bind.mainSetUserDefaultOption(
                                key: kOptionImageQuality, value: key);
                            setState(() {});
                          },
                  ),
                  const SizedBox(height: 12),
                  // 기본 코덱 카드
                  _buildDropdownCard(
                    title: translate('Default Codec'),
                    value: _getCodecLabel(
                        bind.mainGetUserDefaultOption(key: kOptionCodecPreference)),
                    items: codecList.map((e) => translate(e.label)).toList(),
                    onChanged: isOptionFixed(kOptionCodecPreference)
                        ? null
                        : (value) async {
                            final entry = codecList
                                .firstWhereOrNull((e) => translate(e.label) == value);
                            if (entry != null) {
                              await bind.mainSetUserDefaultOption(
                                  key: kOptionCodecPreference, value: entry.value);
                              setState(() {});
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  // 기타 기본 옵션 카드
                  _buildToggleCard(
                    title: translate('Other Default Options'),
                    children: otherDefaultSettings()
                        .map((e) => _buildToggleRow(e.$1, e.$2))
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          // 하단 버튼
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  // 취소 버튼
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF646368),
                        side: const BorderSide(color: Color(0xFFDEDEE2)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(translate('Cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 설정 완료 버튼
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5B7BF8),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        translate('Settings Complete'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 드롭다운이 포함된 개별 카드
  Widget _buildDropdownCard({
    required String title,
    required String value,
    required List<String> items,
    required Function(String)? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26333C87),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              title,
              style: const TextStyle(
                color: _titleColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(
              height: 1, color: Color(0xFFEEEEEE), indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFFDEDEE2),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<String>(
                value: value,
                items: items.map((item) {
                  return DropdownMenuItem<String>(
                    value: item,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: _titleColor,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: onChanged == null
                    ? null
                    : (newValue) {
                        if (newValue != null) {
                          onChanged(newValue);
                        }
                      },
                isExpanded: true,
                underline: const SizedBox.shrink(),
                icon: const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Icon(Icons.expand_more, color: _labelColor, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 토글 목록이 포함된 카드 (타이틀 + 토글들)
  Widget _buildToggleCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26333C87),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              title,
              style: const TextStyle(
                color: _titleColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(
              height: 1, color: Color(0xFFEEEEEE), indent: 16, endIndent: 16),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildToggleRow(String label, String key) {
    final value = bind.mainGetUserDefaultOption(key: key) == 'Y';
    final isOptFixed = isOptionFixed(key);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              translate(label),
              style: const TextStyle(
                color: _titleColor,
                fontSize: 14,
              ),
            ),
          ),
          CmCustomToggle(
            value: value,
            onChanged: isOptFixed
                ? null
                : (b) async {
                    await bind.mainSetUserDefaultOption(
                        key: key, value: b ? 'Y' : defaultOptionNo);
                    setState(() {});
                  },
          ),
        ],
      ),
    );
  }

  String _getViewStyleLabel(String value) {
    switch (value) {
      case kRemoteViewStyleOriginal:
        return translate('Scale original');
      case kRemoteViewStyleAdaptive:
        return translate('Scale adaptive');
      default:
        return translate('Scale adaptive');
    }
  }

  String _getImageQualityLabel(String value) {
    switch (value) {
      case kRemoteImageQualityBest:
        return translate('Good image quality');
      case kRemoteImageQualityBalanced:
        return translate('Balanced');
      case kRemoteImageQualityLow:
        return translate('Optimize reaction time');
      default:
        return translate('Balanced');
    }
  }

  String _getCodecLabel(String value) {
    switch (value) {
      case 'auto':
        return translate('Auto');
      case 'vp8':
        return translate('VP8');
      case 'vp9':
        return translate('VP9');
      case 'av1':
        return translate('AV1');
      case 'h264':
        return translate('H264');
      case 'h265':
        return translate('H265');
      default:
        return translate('Auto');
    }
  }
}

class _ManageTrustedDevices extends StatefulWidget {
  const _ManageTrustedDevices();

  @override
  State<_ManageTrustedDevices> createState() => __ManageTrustedDevicesState();
}

class __ManageTrustedDevicesState extends State<_ManageTrustedDevices> {
  RxList<TrustedDevice> trustedDevices = RxList.empty(growable: true);
  RxList<Uint8List> selectedDevices = RxList.empty();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(translate('Manage trusted devices')),
        centerTitle: true,
        actions: [
          Obx(() => IconButton(
              icon: Icon(Icons.delete, color: Colors.white),
              onPressed: selectedDevices.isEmpty
                  ? null
                  : () {
                      confrimDeleteTrustedDevicesDialog(
                          trustedDevices, selectedDevices);
                    }))
        ],
      ),
      body: FutureBuilder(
          future: TrustedDevice.get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            final devices = snapshot.data as List<TrustedDevice>;
            trustedDevices = devices.obs;
            return trustedDevicesTable(trustedDevices, selectedDevices);
          }),
    );
  }
}

class _RadioEntry {
  final String label;
  final String value;
  _RadioEntry(this.label, this.value);
}

typedef _RadioEntryGetter = String Function();
typedef _RadioEntrySetter = Future<void> Function(String);

SettingsTile _getPopupDialogRadioEntry({
  required String title,
  required List<_RadioEntry> list,
  required _RadioEntryGetter getter,
  required _RadioEntrySetter? asyncSetter,
  Widget? tail,
  RxBool? showTail,
  String? notCloseValue,
}) {
  RxString groupValue = ''.obs;
  RxString valueText = ''.obs;

  init() {
    groupValue.value = getter();
    final e = list.firstWhereOrNull((e) => e.value == groupValue.value);
    if (e != null) {
      valueText.value = e.label;
    }
  }

  init();

  void showDialog() async {
    gFFI.dialogManager.show((setState, close, context) {
      final onChanged = asyncSetter == null
          ? null
          : (String? value) async {
              if (value == null) return;
              await asyncSetter(value);
              init();
              if (value != notCloseValue) {
                close();
              }
            };

      return CustomAlertDialog(
          content: Obx(
        () => Column(children: [
          ...list
              .map((e) => getRadio(Text(translate(e.label)), e.value,
                  groupValue.value, onChanged))
              .toList(),
          Offstage(
            offstage:
                !(tail != null && showTail != null && showTail.value == true),
            child: tail,
          ),
        ]),
      ));
    }, backDismiss: true, clickMaskDismiss: true);
  }

  return SettingsTile(
    title: Text(translate(title)),
    onPressed: asyncSetter == null ? null : (context) => showDialog(),
    value: Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Obx(() => Text(translate(valueText.value))),
    ),
  );
}
