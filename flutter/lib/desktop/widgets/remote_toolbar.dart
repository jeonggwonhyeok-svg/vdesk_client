import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/widgets/audio_input.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/common/widgets/setting_widgets.dart';
import 'package:flutter_hbb/common/widgets/styled_form_widgets.dart';
import 'package:flutter_hbb/common/widgets/toolbar.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/plugin/widgets/desc_ui.dart';
import 'package:flutter_hbb/plugin/common.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:debounce_throttle/debounce_throttle.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_size/window_size.dart' as window_size;

import '../../common.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../../common/shared_state.dart';
import './popup_menu.dart';
import './kb_layout_type_chooser.dart';
import 'package:flutter_hbb/utils/scale.dart';
import 'package:flutter_hbb/common/widgets/custom_scale_base.dart';

class ToolbarState {
  late RxBool _pin;

  bool isShowInited = false;
  RxBool show = false.obs;

  ToolbarState() {
    _pin = RxBool(false);
    final s = bind.getLocalFlutterOption(k: kOptionRemoteMenubarState);
    if (s.isEmpty) {
      return;
    }

    try {
      final m = jsonDecode(s);
      if (m != null) {
        _pin = RxBool(m['pin'] ?? false);
      }
    } catch (e) {
      debugPrint('Failed to decode toolbar state ${e.toString()}');
    }
  }

  bool get pin => _pin.value;

  switchShow(SessionID sessionId) async {
    bind.sessionToggleOption(
        sessionId: sessionId, value: kOptionCollapseToolbar);
    show.value = !show.value;
  }

  initShow(SessionID sessionId) async {
    if (!isShowInited) {
      show.value = !(await bind.sessionGetToggleOption(
              sessionId: sessionId, arg: kOptionCollapseToolbar) ??
          false);
      isShowInited = true;
    }
  }

  switchPin() async {
    _pin.value = !_pin.value;
    // Save everytime changed, as this func will not be called frequently
    await _savePin();
  }

  setPin(bool v) async {
    if (_pin.value != v) {
      _pin.value = v;
      // Save everytime changed, as this func will not be called frequently
      await _savePin();
    }
  }

  _savePin() async {
    bind.setLocalFlutterOption(
        k: kOptionRemoteMenubarState, v: jsonEncode({'pin': _pin.value}));
  }
}

class _ToolbarTheme {
  static const Color blueColor = MyTheme.button;
  static const Color hoverBlueColor = MyTheme.accent;
  static Color inactiveColor = Colors.grey[800]!;
  static Color hoverInactiveColor = Colors.grey[850]!;

  static const Color redColor = Colors.redAccent;
  static const Color hoverRedColor = Colors.red;
  // 연결 중(Connecting) 상태 색상 - 메인창 연결상태카드와 동일
  static const Color orangeColor = Color(0xFFF59E0B);
  static const Color hoverOrangeColor = Color(0xFFD97706);
  // kMinInteractiveDimension
  static const double height = 20.0;
  static const double dividerHeight = 12.0;

  static const double buttonSize = 32;
  static const double buttonHMargin = 2;
  static const double buttonVMargin = 6;
  static const double iconRadius = 8;
  static const double elevation = 3;

  static double dividerSpaceToAction = isWindows ? 8 : 14;

  static double menuBorderRadius = isWindows ? 5.0 : 7.0;
  static EdgeInsets menuPadding = isWindows
      ? EdgeInsets.fromLTRB(4, 12, 4, 12)
      : EdgeInsets.fromLTRB(6, 14, 6, 14);
  static const double menuButtonBorderRadius = 3.0;

  static Color borderColor(BuildContext context) =>
      MyTheme.color(context).border3 ?? MyTheme.border;

  static Color? dividerColor(BuildContext context) =>
      MyTheme.color(context).divider;

  static MenuStyle defaultMenuStyle(BuildContext context) => MenuStyle(
        side: MaterialStateProperty.all(BorderSide(
          width: 1,
          color: borderColor(context),
        )),
        shape: MaterialStatePropertyAll(RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(_ToolbarTheme.menuBorderRadius))),
        padding: MaterialStateProperty.all(_ToolbarTheme.menuPadding),
      );
  static final defaultMenuButtonStyle = ButtonStyle(
    backgroundColor: MaterialStatePropertyAll(Colors.transparent),
    padding: MaterialStatePropertyAll(EdgeInsets.zero),
    overlayColor: MaterialStatePropertyAll(Colors.transparent),
  );

  static Widget borderWrapper(
      BuildContext context, Widget child, BorderRadius borderRadius) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: borderColor(context),
          width: 1,
        ),
        borderRadius: borderRadius,
      ),
      child: child,
    );
  }
}

typedef DismissFunc = void Function();

class RemoteMenuEntry {
  static MenuEntryButton<String> insertLock(
    SessionID sessionId,
    EdgeInsets? padding, {
    DismissFunc? dismissFunc,
    DismissCallback? dismissCallback,
  }) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Insert Lock'),
        style: style,
      ),
      proc: () {
        bind.sessionLockScreen(sessionId: sessionId);
        if (dismissFunc != null) {
          dismissFunc();
        }
      },
      padding: padding,
      dismissOnClicked: true,
      dismissCallback: dismissCallback,
    );
  }

  static insertCtrlAltDel(
    SessionID sessionId,
    EdgeInsets? padding, {
    DismissFunc? dismissFunc,
    DismissCallback? dismissCallback,
  }) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate("Insert Ctrl + Alt + Del"),
        style: style,
      ),
      proc: () {
        bind.sessionCtrlAltDel(sessionId: sessionId);
        if (dismissFunc != null) {
          dismissFunc();
        }
      },
      padding: padding,
      dismissOnClicked: true,
      dismissCallback: dismissCallback,
    );
  }
}

class RemoteToolbar extends StatefulWidget {
  final String id;
  final FFI ffi;
  final ToolbarState state;
  final Function(int, Function(bool)) onEnterOrLeaveImageSetter;
  final Function(int) onEnterOrLeaveImageCleaner;
  final Function(VoidCallback) setRemoteState;

  RemoteToolbar({
    Key? key,
    required this.id,
    required this.ffi,
    required this.state,
    required this.onEnterOrLeaveImageSetter,
    required this.onEnterOrLeaveImageCleaner,
    required this.setRemoteState,
  }) : super(key: key);

  @override
  State<RemoteToolbar> createState() => _RemoteToolbarState();
}

class _RemoteToolbarState extends State<RemoteToolbar> {
  final _fractionX = 0.5.obs;
  final _dragging = false.obs;

  // 녹화 관련 상태
  Timer? _recordingTimer;
  final _recordingSeconds = 0.obs;
  final _recordingPaused = false.obs;
  final _recordingSound = true.obs;

  // 보이스 콜 관련 상태
  final _voiceCallMicOn = true.obs;
  final _voiceCallSoundOn = true.obs;
  String _savedVoiceCallMicDevice = '';

  // 보기 모드 상태 (ffiModel.viewOnly를 반응형으로 추적)
  final _isViewOnly = false.obs;

  int get windowId => stateGlobal.windowId;

  void _setFullscreen(bool v) {
    stateGlobal.setFullscreen(v);
    // stateGlobal.fullscreen is RxBool now, no need to call setState.
    // setState(() {});
  }

  RxBool get show => widget.state.show;
  bool get pin => widget.state.pin;

  PeerInfo get pi => widget.ffi.ffiModel.pi;
  FfiModel get ffiModel => widget.ffi.ffiModel;


  void _minimize() async =>
      await WindowController.fromWindowId(windowId).minimize();

  @override
  initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _fractionX.value = double.tryParse(await bind.sessionGetOption(
                  sessionId: widget.ffi.sessionId,
                  arg: 'remote-menubar-drag-x') ??
              '0.5') ??
          0.5;
    });

    widget.onEnterOrLeaveImageSetter(identityHashCode(this), (enter) {
    });

    // 녹화 모델 리스너
    widget.ffi.recordingModel.addListener(_onRecordingChanged);

    // 보이스 콜 상태 리스너
    widget.ffi.chatModel.voiceCallStatus.listen(_onVoiceCallStatusChanged);

    // ffiModel 리스너 (viewOnly 상태 추적)
    widget.ffi.ffiModel.addListener(_onFfiModelChanged);
    _isViewOnly.value = widget.ffi.ffiModel.viewOnly;
  }

  void _onFfiModelChanged() {
    _isViewOnly.value = widget.ffi.ffiModel.viewOnly;
  }

  void _onVoiceCallStatusChanged(VoiceCallStatus status) async {
    if (status == VoiceCallStatus.connected ||
        status == VoiceCallStatus.waitingForResponse) {
      // 보이스 콜 시작 시 현재 마이크 장치 저장
      _savedVoiceCallMicDevice =
          await bind.getVoiceCallInputDevice(isCm: false);
      if (_savedVoiceCallMicDevice.isEmpty) {
        // 기본 마이크 장치 찾기
        final devices = (await bind.mainGetSoundInputs()).toList();
        if (devices.isNotEmpty) {
          _savedVoiceCallMicDevice = devices.first;
        }
      }
      // 상태 초기화
      _voiceCallMicOn.value = true;
      _voiceCallSoundOn.value = true;
    }
  }

  void _onRecordingChanged() {
    final isRecording = widget.ffi.recordingModel.start;
    if (isRecording && _recordingTimer == null) {
      _startRecordingTimer();
    } else if (!isRecording && _recordingTimer != null) {
      _stopRecordingTimer();
    }
  }

  void _startRecordingTimer() {
    _recordingSeconds.value = 0;
    _recordingPaused.value = false;
    _recordingTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (!_recordingPaused.value) {
        _recordingSeconds.value++;
      }
    });
  }

  void _stopRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingSeconds.value = 0;
  }

  String _formatRecordingTime(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Widget _buildRecordingBox(BuildContext context, BorderRadius borderRadius) {
    return Material(
      elevation: _ToolbarTheme.elevation,
      shadowColor: MyTheme.color(context).shadow,
      borderRadius: borderRadius,
      color: Colors.white,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(color: Colors.grey[300]!, width: 1),
        ),
        child: Obx(() => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 중지 버튼
                _CustomToolbarButton(
                  assetName: 'assets/icons/remote-record-stop.svg',
                  tooltip: translate('Stop Recording'),
                  onPressed: _stopRecording,
                ),
                // 일시정지/재개 토글
                _CustomToolbarButton(
                  assetName: _recordingPaused.value
                      ? 'assets/icons/remote-record-start.svg'
                      : 'assets/icons/remote-record-pause.svg',
                  tooltip: translate(_recordingPaused.value
                      ? 'Resume Recording'
                      : 'Pause Recording'),
                  onPressed: _toggleRecordingPause,
                ),
                // 시스템 소리 토글
                _CustomToolbarButton(
                  assetName: _recordingSound.value
                      ? 'assets/icons/remote-record-sound-off.svg'
                      : 'assets/icons/remote-record-sound.svg',
                  tooltip: translate(_recordingSound.value
                      ? 'Mute System Sound'
                      : 'Unmute System Sound'),
                  onPressed: _toggleRecordingSound,
                ),
                SizedBox(width: 8),
                // 녹화 시간 표시
                Text(
                  _formatRecordingTime(_recordingSeconds.value),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF5F71FF),
                  ),
                ),
              ],
            )),
      ),
    );
  }

  void _stopRecording() {
    widget.ffi.recordingModel.toggle();
  }

  void _toggleRecordingPause() {
    _recordingPaused.value = !_recordingPaused.value;
  }

  void _toggleRecordingSound() {
    _recordingSound.value = !_recordingSound.value;
  }

  // 보이스 콜 박스
  Widget _buildVoiceCallBox(BuildContext context, BorderRadius borderRadius) {
    return Material(
      elevation: _ToolbarTheme.elevation,
      shadowColor: MyTheme.color(context).shadow,
      borderRadius: borderRadius,
      color: Colors.white,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(color: Colors.grey[300]!, width: 1),
        ),
        child: Obx(() => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 통화 종료
                _CustomToolbarButton(
                  assetName: 'assets/icons/remote_voice_call_off.svg',
                  tooltip: translate('End Call'),
                  onPressed: _endVoiceCall,
                  backgroundColor: const Color(0xFFFE3E3E),
                  iconColor: Colors.white,
                ),
                // 마이크 토글
                _CustomToolbarButton(
                  assetName: _voiceCallMicOn.value
                      ? 'assets/icons/remote_mic.svg'
                      : 'assets/icons/remote_mic_off.svg',
                  tooltip: translate(_voiceCallMicOn.value ? 'Mute' : 'Unmute'),
                  onPressed: _toggleVoiceCallMic,
                ),
                // 스피커 토글
                _CustomToolbarButton(
                  assetName: _voiceCallSoundOn.value
                      ? 'assets/icons/remote_sound.svg'
                      : 'assets/icons/remote_sound_off.svg',
                  tooltip: translate(
                      _voiceCallSoundOn.value ? 'Mute Sound' : 'Unmute Sound'),
                  onPressed: _toggleVoiceCallSound,
                ),
              ],
            )),
      ),
    );
  }

  // 보이스 콜 대기 중 박스 (주황색 아이콘)
  Widget _buildVoiceCallWaitingBox(
      BuildContext context, BorderRadius borderRadius) {
    return Material(
      elevation: _ToolbarTheme.elevation,
      shadowColor: MyTheme.color(context).shadow,
      borderRadius: borderRadius,
      color: Colors.white,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(color: Colors.grey[300]!, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 통화 취소 (주황색)
            _CustomToolbarButton(
              assetName: 'assets/call_wait.svg',
              tooltip: translate('Cancel'),
              onPressed: _endVoiceCall,
              backgroundColor: _ToolbarTheme.orangeColor,
              iconColor: Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  void _endVoiceCall() {
    bind.sessionCloseVoiceCall(sessionId: widget.ffi.sessionId);
  }

  void _toggleVoiceCallMic() async {
    _voiceCallMicOn.value = !_voiceCallMicOn.value;
    if (_voiceCallMicOn.value) {
      // 마이크 켜기 - 저장된 장치로 복원
      await bind.setVoiceCallInputDevice(
          isCm: false, device: _savedVoiceCallMicDevice);
    } else {
      // 마이크 끄기 - 빈 문자열로 설정
      await bind.setVoiceCallInputDevice(isCm: false, device: '');
    }
  }

  void _toggleVoiceCallSound() {
    _voiceCallSoundOn.value = !_voiceCallSoundOn.value;
    // 클라이언트 측 오디오 비활성화 토글
    bind.sessionToggleOption(
      sessionId: widget.ffi.sessionId,
      value: 'disable-audio',
    );
  }


  @override
  dispose() {
    widget.ffi.ffiModel.removeListener(_onFfiModelChanged);
    super.dispose();

    widget.onEnterOrLeaveImageCleaner(identityHashCode(this));
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => Padding(
          padding: EdgeInsets.only(top: show.value ? 16 : 0),
          child: Align(
            alignment: Alignment.topCenter,
            child: show.value
                ? _buildToolbar(context)
                : _buildDraggableShowHide(context),
          ),
        ));
  }

  Widget _buildDraggableShowHide(BuildContext context) {
    return Obx(() {
      final borderRadius = BorderRadius.vertical(
        bottom: Radius.circular(8),
      );
      return Align(
        alignment: FractionalOffset(_fractionX.value, 0),
        child: Offstage(
          offstage: _dragging.isTrue,
          child: _MiniToolbar(
            show: show,
            fractionX: _fractionX,
            dragging: _dragging,
            sessionId: widget.ffi.sessionId,
            borderRadius: borderRadius,
          ),
        ),
      );
    });
  }

  Widget _buildToolbar(BuildContext context) {
    final toolbarBorderRadius = BorderRadius.all(Radius.circular(8.0));
    final isFullscreen = stateGlobal.fullscreen;

    return ListenableBuilder(
      listenable: widget.ffi.recordingModel,
      builder: (context, child) {
        final isRecording = widget.ffi.recordingModel.start;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 왼쪽 그룹: 파일전송, 녹화/스크린샷, 채팅/음성/카메라, 더보기
            Material(
              elevation: _ToolbarTheme.elevation,
              shadowColor: MyTheme.color(context).shadow,
              borderRadius: toolbarBorderRadius,
              color: Colors.white,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: toolbarBorderRadius,
                  border: Border.all(color: Colors.grey[300]!, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 파일 전송
                    _CustomToolbarButton(
                      assetName: 'assets/icons/remote_file.svg',
                      tooltip: translate('File Transfer'),
                      onPressed: () => _openFileTransfer(),
                    ),
                    // 녹화/스크린샷
                    _CustomToolbarPopupMenu(
                      assetName: 'assets/icons/remote_screen.svg',
                      tooltip: translate('Recording'),
                      menuItems: [
                        _PopupMenuItem(
                          text: translate('Record Screen'),
                          onTap: () => _startRecording(),
                        ),
                        _PopupMenuItem(
                          text: translate('Screenshot'),
                          onTap: () => _takeScreenshot(),
                        ),
                      ],
                    ),
                    // 채팅/음성/카메라/보기모드
                    Obx(() {
                      final voiceCallStatus =
                          widget.ffi.chatModel.voiceCallStatus.value;
                      final isVoiceCallActive = voiceCallStatus ==
                              VoiceCallStatus.waitingForResponse ||
                          voiceCallStatus == VoiceCallStatus.connected;
                      final isViewOnly = _isViewOnly.value;
                      return _CustomToolbarPopupMenu(
                        assetName: 'assets/icons/remote_group.svg',
                        tooltip: translate('Communication'),
                        menuItems: [
                          _PopupMenuItem(
                            text: translate('Chat'),
                            onTap: () => _openChat(),
                          ),
                          _PopupMenuItem(
                            text: translate(isVoiceCallActive
                                ? 'End Voice Call'
                                : 'Voice Call'),
                            onTap: () => isVoiceCallActive
                                ? _endVoiceCall()
                                : _startVoiceCall(),
                          ),
                          _PopupMenuItem(
                            text: translate('View Camera'),
                            onTap: () => _viewCamera(),
                          ),
                          _PopupMenuItem(
                            text: translate(
                                isViewOnly ? 'Control Mode' : 'View Mode'),
                            onTap: () => _toggleViewMode(),
                          ),
                        ],
                      );
                    }),
                    // 더보기
                    _CustomToolbarPopupMenu(
                      assetName: 'assets/icons/remote_more.svg',
                      tooltip: translate('More'),
                      menuItems: [
                        _PopupMenuItem(
                          text: translate('Display Settings'),
                          onTap: () => _openDisplaySettings(),
                        ),
                        _PopupMenuItem(
                          text: translate('Restart Remote'),
                          onTap: () => _restartRemote(),
                        ),
                        _PopupMenuItem(
                          assetPath: 'assets/icons/remote-connection-end.svg',
                          text: translate('Shutdown Remote'),
                          onTap: () => _shutdownRemote(),
                          iconColor: const Color(0xFFFE3E3E),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 8),
            // 녹화 중일 때 녹화 박스 표시
            if (isRecording) ...[
              _buildRecordingBox(context, toolbarBorderRadius),
              SizedBox(width: 8),
            ],
            // 보이스 콜 상태에 따라 다른 UI 표시
            Obx(() {
              final voiceCallStatus =
                  widget.ffi.chatModel.voiceCallStatus.value;
              if (voiceCallStatus == VoiceCallStatus.waitingForResponse) {
                // 수락 대기 중: 주황색 대기 아이콘
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildVoiceCallWaitingBox(context, toolbarBorderRadius),
                    SizedBox(width: 8),
                  ],
                );
              } else if (voiceCallStatus == VoiceCallStatus.connected) {
                // 연결됨: 빨간 종료 버튼 + 마이크/스피커 토글
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildVoiceCallBox(context, toolbarBorderRadius),
                    SizedBox(width: 8),
                  ],
                );
              }
              return SizedBox.shrink();
            }),
            // 오른쪽 그룹: 풀스크린, 접기
            Material(
              elevation: _ToolbarTheme.elevation,
              shadowColor: MyTheme.color(context).shadow,
              borderRadius: toolbarBorderRadius,
              color: Colors.white,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: toolbarBorderRadius,
                  border: Border.all(color: Colors.grey[300]!, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 풀스크린 토글
                    Obx(() => _CustomToolbarButton(
                          assetName: 'assets/icons/remote_full.svg',
                          tooltip: translate(isFullscreen.isTrue
                              ? 'Exit Fullscreen'
                              : 'Fullscreen'),
                          onPressed: () => _setFullscreen(!isFullscreen.value),
                          isPressed: isFullscreen.value,
                        )),
                    // 접기
                    _CustomToolbarButton(
                      assetName: 'assets/icons/remote_up_arrow.svg',
                      tooltip: translate('Collapse'),
                      onPressed: () => show.value = false,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // 파일 전송 열기
  void _openFileTransfer() async {
    // 현재 세션의 connToken을 가져와서 파일 전송 시 비밀번호 재입력 없이 연결
    final connToken = bind.sessionGetConnToken(sessionId: widget.ffi.sessionId);
    debugPrint('[FileTransfer] connToken: ${connToken != null ? "exists (${connToken.length} chars)" : "NULL"}');
    await oneDeskWinManager.newFileTransfer(widget.id,
        forceRelay: false,
        connToken: connToken);
  }

  // 녹화 시작
  void _startRecording() {
    widget.ffi.recordingModel.toggle();
  }

  // 스크린샷
  void _takeScreenshot() {
    bind.sessionTakeScreenshot(
        sessionId: widget.ffi.sessionId, display: pi.currentDisplay);
  }

  // 채팅 열기
  void _openChat() {
    widget.ffi.chatModel
        .changeCurrentKey(MessageKey(widget.ffi.id, ChatModel.clientModeID));
    widget.ffi.chatModel.toggleChatOverlay();
  }

  // 음성 통화
  void _startVoiceCall() {
    bind.sessionRequestVoiceCall(sessionId: widget.ffi.sessionId);
  }

  // 카메라 보기
  void _viewCamera() async {
    await oneDeskWinManager.newViewCamera(widget.id, forceRelay: false);
  }

  // 보기 모드 토글
  void _toggleViewMode() async {
    await bind.sessionToggleOption(
      sessionId: widget.ffi.sessionId,
      value: kOptionToggleViewOnly,
    );
    final viewOnly = await bind.sessionGetToggleOption(
      sessionId: widget.ffi.sessionId,
      arg: kOptionToggleViewOnly,
    );
    widget.ffi.ffiModel.setViewOnly(widget.id, viewOnly ?? !_isViewOnly.value);
  }

  // 디스플레이 설정 - 원격 세션에 직접 적용되는 팝업 (메인 설정 디자인)
  void _openDisplaySettings() async {
    final sessionId = widget.ffi.sessionId;
    final ffi = widget.ffi;

    // 메인 설정의 기본값 가져오기 (원격창 팝업은 메인 설정값을 표시)
    String viewStyleValue =
        bind.mainGetUserDefaultOption(key: kOptionViewStyle);
    if (viewStyleValue.isEmpty) viewStyleValue = kRemoteViewStyleAdaptive;
    String imageQualityValue =
        bind.mainGetUserDefaultOption(key: kOptionImageQuality);
    if (imageQualityValue.isEmpty)
      imageQualityValue = kRemoteImageQualityBalanced;
    String scrollStyleValue =
        bind.mainGetUserDefaultOption(key: kOptionScrollStyle);
    if (scrollStyleValue.isEmpty) scrollStyleValue = kRemoteScrollStyleAuto;
    String codecValue =
        bind.mainGetUserDefaultOption(key: kOptionCodecPreference);
    if (codecValue.isEmpty) codecValue = 'auto';

    // 트랙패드 속도 가져오기 (사용자 기본 설정에서 읽음)
    int trackpadSpeedValue = int.tryParse(
            bind.mainGetUserDefaultOption(key: kKeyTrackpadSpeed)) ??
        kDefaultTrackpadSpeed;

    // 코덱 옵션 가져오기
    final alternativeCodecs =
        await bind.sessionAlternativeCodecs(sessionId: sessionId);
    Map<String, bool> availableCodecs = {
      'vp8': false,
      'av1': false,
      'h264': false,
      'h265': false
    };
    try {
      final codecsJson = jsonDecode(alternativeCodecs);
      availableCodecs = {
        'vp8': codecsJson['vp8'] ?? false,
        'av1': codecsJson['av1'] ?? false,
        'h264': codecsJson['h264'] ?? false,
        'h265': codecsJson['h265'] ?? false,
      };
    } catch (e) {
      debugPrint("Failed to parse codecs: $e");
    }

    // Other 옵션들 가져오기 (공통 정의에서 읽기)
    // 모든 옵션을 세션 상태에서 읽어서 현재 상태를 정확히 표시
    Map<String, bool> otherOptions = {};
    final displayOptions = getCommonDisplayOptions(forToolbarDialog: true);
    for (final opt in displayOptions) {
      final value = bind.sessionGetToggleOptionSync(
          sessionId: sessionId, arg: opt.toggleKey);
      otherOptions[opt.optionKey] = value;
    }

    widget.ffi.dialogManager.show((setState, close, context) {
      // 카드 디자인 상수 (메인 설정과 동일)
      const cardBgColor = Colors.white;
      const accentColor = Color(0xFF5F71FF);
      const textColor = Color(0xFF475569);

      // 라디오 버튼 빌더 (메인 설정 스타일)
      Widget buildRadio<T>({
        required T value,
        required T groupValue,
        required String label,
        required Function(T) onChanged,
      }) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => onChanged(value),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: value == groupValue
                            ? accentColor
                            : const Color(0xFFD1D5DB),
                        width: 1,
                      ),
                    ),
                    child: value == groupValue
                        ? Center(
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: accentColor,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      translate(label),
                      style: const TextStyle(fontSize: 14, color: textColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      // 체크박스 빌더 (Other 옵션용)
      Widget buildCheckbox({
        required String optionKey,
        required String label,
        required bool value,
        required Function(bool) onChanged,
      }) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => onChanged(!value),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: value ? accentColor : const Color(0xFFD1D5DB),
                        width: 1,
                      ),
                      color: value ? accentColor : Colors.transparent,
                    ),
                    child: value
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      translate(label),
                      style: const TextStyle(fontSize: 14, color: textColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      // 카드 빌더 (메인 설정 스타일)
      Widget buildCard(
          {required String title, required List<Widget> children}) {
        return Container(
          margin: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0x1A1B2151),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 타이틀
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(
                  translate(title),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF454447),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: const Divider(height: 1),
              ),
              ...children,
              const SizedBox(height: 14),
            ],
          ),
        );
      }

      return CustomAlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, -8),
        title: Row(
          children: [
            SvgPicture.asset(
              'assets/icons/topbar-logo.svg',
              width: 18,
              height: 18,
              colorFilter:
                  const ColorFilter.mode(Color(0xFF5B7BF8), BlendMode.srcIn),
            ),
            const SizedBox(width: 8),
            Text(
              translate('Display'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        contentBoxConstraints: const BoxConstraints(maxWidth: 530),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return SizedBox(
              height: 520,
              child: Column(
                children: [
                  // 타이틀 하단 구분선
                  const Divider(height: 1),
                  const SizedBox(height: 4),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 보기 스타일
                          buildCard(
                            title: 'Default View Style',
                            children: [
                              buildRadio<String>(
                                value: kRemoteViewStyleOriginal,
                                groupValue: viewStyleValue,
                                label: 'Scale original',
                                onChanged: (value) {
                                  setDialogState(() => viewStyleValue = value);
                                  bind.mainSetUserDefaultOption(
                                      key: kOptionViewStyle, value: value);
                                  bind
                                      .sessionSetViewStyle(
                                          sessionId: sessionId, value: value)
                                      .then((_) =>
                                          ffi.canvasModel.updateViewStyle());
                                },
                              ),
                              buildRadio<String>(
                                value: kRemoteViewStyleAdaptive,
                                groupValue: viewStyleValue,
                                label: 'Scale adaptive',
                                onChanged: (value) {
                                  setDialogState(() => viewStyleValue = value);
                                  bind.mainSetUserDefaultOption(
                                      key: kOptionViewStyle, value: value);
                                  bind
                                      .sessionSetViewStyle(
                                          sessionId: sessionId, value: value)
                                      .then((_) =>
                                          ffi.canvasModel.updateViewStyle());
                                },
                              ),
                            ],
                          ),

                          // 스크롤 스타일
                          buildCard(
                            title: 'Scroll Style',
                            children: [
                              buildRadio<String>(
                                value: kRemoteScrollStyleAuto,
                                groupValue: scrollStyleValue,
                                label: 'ScrollAuto',
                                onChanged: (value) {
                                  setDialogState(
                                      () => scrollStyleValue = value);
                                  bind.mainSetUserDefaultOption(
                                      key: kOptionScrollStyle, value: value);
                                  bind
                                      .sessionSetScrollStyle(
                                          sessionId: sessionId, value: value)
                                      .then((_) =>
                                          ffi.canvasModel.updateScrollStyle());
                                },
                              ),
                              buildRadio<String>(
                                value: kRemoteScrollStyleBar,
                                groupValue: scrollStyleValue,
                                label: 'Scrollbar',
                                onChanged: (value) {
                                  setDialogState(
                                      () => scrollStyleValue = value);
                                  bind.mainSetUserDefaultOption(
                                      key: kOptionScrollStyle, value: value);
                                  bind
                                      .sessionSetScrollStyle(
                                          sessionId: sessionId, value: value)
                                      .then((_) =>
                                          ffi.canvasModel.updateScrollStyle());
                                },
                              ),
                            ],
                          ),

                          // 이미지 품질
                          buildCard(
                            title: 'Image Quality',
                            children: [
                              buildRadio<String>(
                                value: kRemoteImageQualityBest,
                                groupValue: imageQualityValue,
                                label: 'Good image quality',
                                onChanged: (value) {
                                  setDialogState(
                                      () => imageQualityValue = value);
                                  bind.mainSetUserDefaultOption(
                                      key: kOptionImageQuality, value: value);
                                  bind.sessionSetImageQuality(
                                      sessionId: sessionId, value: value);
                                },
                              ),
                              buildRadio<String>(
                                value: kRemoteImageQualityBalanced,
                                groupValue: imageQualityValue,
                                label: 'Balanced',
                                onChanged: (value) {
                                  setDialogState(
                                      () => imageQualityValue = value);
                                  bind.mainSetUserDefaultOption(
                                      key: kOptionImageQuality, value: value);
                                  bind.sessionSetImageQuality(
                                      sessionId: sessionId, value: value);
                                },
                              ),
                              buildRadio<String>(
                                value: kRemoteImageQualityLow,
                                groupValue: imageQualityValue,
                                label: 'Optimize reaction time',
                                onChanged: (value) {
                                  setDialogState(
                                      () => imageQualityValue = value);
                                  bind.mainSetUserDefaultOption(
                                      key: kOptionImageQuality, value: value);
                                  bind.sessionSetImageQuality(
                                      sessionId: sessionId, value: value);
                                },
                              ),
                            ],
                          ),

                          // 코덱
                          buildCard(
                            title: 'Codec',
                            children: [
                              buildRadio<String>(
                                value: 'auto',
                                groupValue: codecValue,
                                label: 'Auto',
                                onChanged: (value) async {
                                  setDialogState(() => codecValue = value);
                                  bind.mainSetUserDefaultOption(
                                      key: kOptionCodecPreference, value: value);
                                  await bind.sessionPeerOption(
                                      sessionId: sessionId,
                                      name: kOptionCodecPreference,
                                      value: value);
                                  bind.sessionChangePreferCodec(
                                      sessionId: sessionId);
                                },
                              ),
                              if (availableCodecs['vp8'] == true)
                                buildRadio<String>(
                                  value: 'vp8',
                                  groupValue: codecValue,
                                  label: 'VP8',
                                  onChanged: (value) async {
                                    setDialogState(() => codecValue = value);
                                    bind.mainSetUserDefaultOption(
                                        key: kOptionCodecPreference, value: value);
                                    await bind.sessionPeerOption(
                                        sessionId: sessionId,
                                        name: kOptionCodecPreference,
                                        value: value);
                                    bind.sessionChangePreferCodec(
                                        sessionId: sessionId);
                                  },
                                ),
                              buildRadio<String>(
                                value: 'vp9',
                                groupValue: codecValue,
                                label: 'VP9',
                                onChanged: (value) async {
                                  setDialogState(() => codecValue = value);
                                  bind.mainSetUserDefaultOption(
                                      key: kOptionCodecPreference, value: value);
                                  await bind.sessionPeerOption(
                                      sessionId: sessionId,
                                      name: kOptionCodecPreference,
                                      value: value);
                                  bind.sessionChangePreferCodec(
                                      sessionId: sessionId);
                                },
                              ),
                              if (availableCodecs['av1'] == true)
                                buildRadio<String>(
                                  value: 'av1',
                                  groupValue: codecValue,
                                  label: 'AV1',
                                  onChanged: (value) async {
                                    setDialogState(() => codecValue = value);
                                    bind.mainSetUserDefaultOption(
                                        key: kOptionCodecPreference, value: value);
                                    await bind.sessionPeerOption(
                                        sessionId: sessionId,
                                        name: kOptionCodecPreference,
                                        value: value);
                                    bind.sessionChangePreferCodec(
                                        sessionId: sessionId);
                                  },
                                ),
                              if (availableCodecs['h264'] == true)
                                buildRadio<String>(
                                  value: 'h264',
                                  groupValue: codecValue,
                                  label: 'H264',
                                  onChanged: (value) async {
                                    setDialogState(() => codecValue = value);
                                    bind.mainSetUserDefaultOption(
                                        key: kOptionCodecPreference, value: value);
                                    await bind.sessionPeerOption(
                                        sessionId: sessionId,
                                        name: kOptionCodecPreference,
                                        value: value);
                                    bind.sessionChangePreferCodec(
                                        sessionId: sessionId);
                                  },
                                ),
                              if (availableCodecs['h265'] == true)
                                buildRadio<String>(
                                  value: 'h265',
                                  groupValue: codecValue,
                                  label: 'H265',
                                  onChanged: (value) async {
                                    setDialogState(() => codecValue = value);
                                    bind.mainSetUserDefaultOption(
                                        key: kOptionCodecPreference, value: value);
                                    await bind.sessionPeerOption(
                                        sessionId: sessionId,
                                        name: kOptionCodecPreference,
                                        value: value);
                                    bind.sessionChangePreferCodec(
                                        sessionId: sessionId);
                                  },
                                ),
                            ],
                          ),

                          // 트랙패드 속도
                          buildCard(
                            title: 'Trackpad speed',
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Slider(
                                        value: trackpadSpeedValue.toDouble(),
                                        min: kMinTrackpadSpeed.toDouble(),
                                        max: kMaxTrackpadSpeed.toDouble(),
                                        activeColor: accentColor,
                                        onChanged: (value) async {
                                          setDialogState(() =>
                                              trackpadSpeedValue =
                                                  value.toInt());
                                          // 사용자 기본 설정에 저장
                                          bind.mainSetUserDefaultOption(
                                              key: kKeyTrackpadSpeed,
                                              value: value.toInt().toString());
                                          // 현재 세션에도 적용
                                          await bind.sessionSetTrackpadSpeed(
                                              sessionId: sessionId,
                                              value: value.toInt());
                                          ffi.inputModel.updateTrackpadSpeed();
                                        },
                                      ),
                                    ),
                                    SizedBox(
                                      width: 50,
                                      child: Text(
                                        '$trackpadSpeedValue%',
                                        style: const TextStyle(
                                            fontSize: 13, color: textColor),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          // 기타 옵션 (공통 정의 사용)
                          buildCard(
                            title: 'Other Default Options',
                            children: displayOptions.map((opt) {
                              return buildCheckbox(
                                optionKey: opt.optionKey,
                                label: opt.label,
                                value: otherOptions[opt.optionKey] ?? false,
                                onChanged: (value) async {
                                  setDialogState(() =>
                                      otherOptions[opt.optionKey] = value);
                                  // 보기 모드는 특별 처리 (세션 옵션이므로 user default 저장 안함)
                                  if (opt.optionKey == kOptionViewOnly) {
                                    await bind.sessionToggleOption(
                                        sessionId: sessionId,
                                        value: opt.toggleKey);
                                    ffi.ffiModel.setViewOnly(widget.id, value);
                                  } else {
                                    bind.mainSetUserDefaultOption(
                                        key: opt.optionKey,
                                        value: value ? 'Y' : '');
                                    await bind.sessionToggleOption(
                                        sessionId: sessionId,
                                        value: opt.toggleKey);
                                  }
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          StyledPrimaryButton(
            label: translate('Close'),
            onPressed: close,
            height: 44,
          ),
        ],
      );
    });
  }

  // 원격 다시시작
  void _restartRemote() {
    showRestartRemoteDevice(
        pi, widget.id, widget.ffi.sessionId, widget.ffi.dialogManager);
  }

  // 원격 종료
  void _shutdownRemote() {
    // 확인 다이얼로그 표시
    widget.ffi.dialogManager.show((setState, close, context) {
      return CustomAlertDialog(
        title: Text(
          translate('Shutdown Remote'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          translate('Would you like to study remotely?'),
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: StyledOutlinedButton(
                  label: translate('Cancel'),
                  onPressed: close,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    close();
                    // 원격 연결 종료 및 탭 닫기
                    closeConnection(id: widget.id);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyTheme.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    translate('OK'),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    });
  }

  ThemeData themeData() {
    return Theme.of(context).copyWith(
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          minimumSize: MaterialStatePropertyAll(Size(64, 32)),
          textStyle: MaterialStatePropertyAll(
            TextStyle(fontWeight: FontWeight.normal),
          ),
          shape: MaterialStatePropertyAll(RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(_ToolbarTheme.menuButtonBorderRadius))),
        ),
      ),
      dividerTheme: DividerThemeData(
        space: _ToolbarTheme.dividerSpaceToAction,
        color: _ToolbarTheme.dividerColor(context),
      ),
      menuBarTheme: MenuBarThemeData(
          style: MenuStyle(
        padding: MaterialStatePropertyAll(EdgeInsets.zero),
        elevation: MaterialStatePropertyAll(0),
        shape: MaterialStatePropertyAll(BeveledRectangleBorder()),
      ).copyWith(
              backgroundColor:
                  Theme.of(context).menuBarTheme.style?.backgroundColor)),
    );
  }
}

class _PinMenu extends StatelessWidget {
  final ToolbarState state;
  const _PinMenu({Key? key, required this.state}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => _IconMenuButton(
        assetName: state.pin ? "assets/pinned.svg" : "assets/unpinned.svg",
        tooltip: state.pin ? 'Unpin Toolbar' : 'Pin Toolbar',
        onPressed: state.switchPin,
        color:
            state.pin ? _ToolbarTheme.blueColor : _ToolbarTheme.inactiveColor,
        hoverColor: state.pin
            ? _ToolbarTheme.hoverBlueColor
            : _ToolbarTheme.hoverInactiveColor,
      ),
    );
  }
}

class _MobileActionMenu extends StatelessWidget {
  final FFI ffi;
  const _MobileActionMenu({Key? key, required this.ffi}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!ffi.ffiModel.isPeerAndroid) return Offstage();
    return Obx(() => _IconMenuButton(
          assetName: 'assets/actions_mobile.svg',
          tooltip: 'Mobile Actions',
          onPressed: () => ffi.dialogManager.setMobileActionsOverlayVisible(
              !ffi.dialogManager.mobileActionsOverlayVisible.value),
          color: ffi.dialogManager.mobileActionsOverlayVisible.isTrue
              ? _ToolbarTheme.blueColor
              : _ToolbarTheme.inactiveColor,
          hoverColor: ffi.dialogManager.mobileActionsOverlayVisible.isTrue
              ? _ToolbarTheme.hoverBlueColor
              : _ToolbarTheme.hoverInactiveColor,
        ));
  }
}

class _MonitorMenu extends StatelessWidget {
  final String id;
  final FFI ffi;
  final Function(VoidCallback) setRemoteState;
  const _MonitorMenu({
    Key? key,
    required this.id,
    required this.ffi,
    required this.setRemoteState,
  }) : super(key: key);

  bool get showMonitorsToolbar =>
      bind.mainGetUserDefaultOption(key: kKeyShowMonitorsToolbar) == 'Y';

  bool get supportIndividualWindows =>
      !isWeb && ffi.ffiModel.pi.isSupportMultiDisplay;

  @override
  Widget build(BuildContext context) => showMonitorsToolbar
      ? buildMultiMonitorMenu(context)
      : Obx(() => buildMonitorMenu(context));

  Widget buildMonitorMenu(BuildContext context) {
    final width = SimpleWrapper<double>(0);
    final monitorsIcon =
        globalMonitorsWidget(width, Colors.white, Colors.black38);
    return _IconSubmenuButton(
        tooltip: 'Select Monitor',
        icon: monitorsIcon,
        ffi: ffi,
        width: width.value,
        color: _ToolbarTheme.blueColor,
        hoverColor: _ToolbarTheme.hoverBlueColor,
        menuStyle: MenuStyle(
            padding:
                MaterialStatePropertyAll(EdgeInsets.symmetric(horizontal: 6))),
        menuChildrenGetter: (_) => [buildMonitorSubmenuWidget(context)]);
  }

  Widget buildMultiMonitorMenu(BuildContext context) {
    return Row(children: buildMonitorList(context, true));
  }

  Widget buildMonitorSubmenuWidget(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: buildMonitorList(context, false)),
        supportIndividualWindows ? Divider() : Offstage(),
        supportIndividualWindows ? chooseDisplayBehavior() : Offstage(),
      ],
    );
  }

  Widget chooseDisplayBehavior() {
    final value =
        bind.sessionGetDisplaysAsIndividualWindows(sessionId: ffi.sessionId) ==
            'Y';
    return CkbMenuButton(
        value: value,
        onChanged: (value) async {
          if (value == null) return;
          await bind.sessionSetDisplaysAsIndividualWindows(
              sessionId: ffi.sessionId, value: value ? 'Y' : 'N');
        },
        ffi: ffi,
        child: Text(translate('Show displays as individual windows')));
  }

  buildOneMonitorButton(i, curDisplay) => Text(
        '${i + 1}',
        style: TextStyle(
          color: i == curDisplay
              ? _ToolbarTheme.blueColor
              : _ToolbarTheme.inactiveColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );

  List<Widget> buildMonitorList(BuildContext context, bool isMulti) {
    final List<Widget> monitorList = [];
    final pi = ffi.ffiModel.pi;

    buildMonitorButton(int i) => Obx(() {
          RxInt display = CurrentDisplayState.find(id);

          final isAllMonitors = i == kAllDisplayValue;
          final width = SimpleWrapper<double>(0);
          Widget? monitorsIcon;
          if (isAllMonitors) {
            monitorsIcon = globalMonitorsWidget(
                width, Colors.white, _ToolbarTheme.blueColor);
          }
          return _IconMenuButton(
            tooltip: isMulti
                ? ''
                : isAllMonitors
                    ? 'all monitors'
                    : '#${i + 1} monitor',
            hMargin: isMulti ? null : 6,
            vMargin: isMulti ? null : 12,
            topLevel: false,
            color: i == display.value
                ? _ToolbarTheme.blueColor
                : _ToolbarTheme.inactiveColor,
            hoverColor: i == display.value
                ? _ToolbarTheme.hoverBlueColor
                : _ToolbarTheme.hoverInactiveColor,
            width: isAllMonitors ? width.value : null,
            icon: isAllMonitors
                ? monitorsIcon
                : Container(
                    alignment: AlignmentDirectional.center,
                    constraints:
                        const BoxConstraints(minHeight: _ToolbarTheme.height),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SvgPicture.asset(
                          "assets/screen.svg",
                          colorFilter:
                              ColorFilter.mode(Colors.white, BlendMode.srcIn),
                        ),
                        Obx(() => buildOneMonitorButton(i, display.value)),
                      ],
                    ),
                  ),
            onPressed: () => onPressed(i, pi, isMulti),
          );
        });

    for (int i = 0; i < pi.displays.length; i++) {
      monitorList.add(buildMonitorButton(i));
    }
    if (supportIndividualWindows && pi.displays.length > 1) {
      monitorList.add(buildMonitorButton(kAllDisplayValue));
    }
    return monitorList;
  }

  globalMonitorsWidget(
      SimpleWrapper<double> width, Color activeTextColor, Color activeBgColor) {
    getMonitors() {
      final pi = ffi.ffiModel.pi;
      RxInt display = CurrentDisplayState.find(id);
      final rect = ffi.ffiModel.globalDisplaysRect();
      if (rect == null) {
        return Offstage();
      }

      final scale = _ToolbarTheme.buttonSize / rect.height * 0.75;
      final startY = (_ToolbarTheme.buttonSize - rect.height * scale) * 0.5;
      final startX = startY;

      final children = <Widget>[];
      for (var i = 0; i < pi.displays.length; i++) {
        final d = pi.displays[i];
        double s = d.scale;
        int dWidth = d.width.toDouble() ~/ s;
        int dHeight = d.height.toDouble() ~/ s;
        final fontSize = (dWidth * scale < dHeight * scale
                ? dWidth * scale
                : dHeight * scale) *
            0.65;
        children.add(Positioned(
          left: (d.x - rect.left) * scale + startX,
          top: (d.y - rect.top) * scale + startY,
          width: dWidth * scale,
          height: dHeight * scale,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.grey,
                width: 1.0,
              ),
              color: display.value == i ? activeBgColor : Colors.white,
            ),
            child: Center(
                child: Text(
              '${i + 1}',
              style: TextStyle(
                color: display.value == i
                    ? activeTextColor
                    : _ToolbarTheme.inactiveColor,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
              ),
            )),
          ),
        ));
      }
      width.value = rect.width * scale + startX * 2;
      return SizedBox(
        width: width.value,
        height: rect.height * scale + startY * 2,
        child: Stack(
          children: children,
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(height: _ToolbarTheme.buttonSize),
        getMonitors(),
      ],
    );
  }

  onPressed(int i, PeerInfo pi, bool isMulti) {
    if (!isMulti) {
      // If show monitors in toolbar(`buildMultiMonitorMenu()`), then the menu will dismiss automatically.
      _menuDismissCallback(ffi);
    }
    RxInt display = CurrentDisplayState.find(id);
    if (display.value != i) {
      final isChooseDisplayToOpenInNewWindow = pi.isSupportMultiDisplay &&
          bind.sessionGetDisplaysAsIndividualWindows(
                  sessionId: ffi.sessionId) ==
              'Y';
      if (isChooseDisplayToOpenInNewWindow) {
        openMonitorInNewTabOrWindow(i, ffi.id, pi);
      } else {
        openMonitorInTheSameTab(i, ffi, pi, updateCursorPos: !isMulti);
      }
    }
  }
}

class _ControlMenu extends StatelessWidget {
  final String id;
  final FFI ffi;
  final ToolbarState state;
  _ControlMenu(
      {Key? key, required this.id, required this.ffi, required this.state})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return _IconSubmenuButton(
        tooltip: 'Control Actions',
        svg: "assets/actions.svg",
        color: _ToolbarTheme.blueColor,
        hoverColor: _ToolbarTheme.hoverBlueColor,
        ffi: ffi,
        menuChildrenGetter: (_) => toolbarControls(context, id, ffi).map((e) {
              if (e.divider) {
                return Divider();
              } else {
                return MenuButton(
                    child: e.child,
                    onPressed: e.onPressed,
                    ffi: ffi,
                    trailingIcon: e.trailingIcon);
              }
            }).toList());
  }
}

class ScreenAdjustor {
  final String id;
  final FFI ffi;
  final VoidCallback cbExitFullscreen;
  window_size.Screen? _screen;

  ScreenAdjustor({
    required this.id,
    required this.ffi,
    required this.cbExitFullscreen,
  });

  bool get isFullscreen => stateGlobal.fullscreen.isTrue;
  int get windowId => stateGlobal.windowId;

  adjustWindow(BuildContext context) {
    return futureBuilder(
        future: isWindowCanBeAdjusted(),
        hasData: (data) {
          final visible = data as bool;
          if (!visible) return Offstage();
          return Column(
            children: [
              MenuButton(
                  child: Text(translate('Adjust Window')),
                  onPressed: () => doAdjustWindow(context),
                  ffi: ffi),
              Divider(),
            ],
          );
        });
  }

  doAdjustWindow(BuildContext context) async {
    await updateScreen();
    if (_screen != null) {
      cbExitFullscreen();
      double scale = _screen!.scaleFactor;
      final wndRect = await WindowController.fromWindowId(windowId).getFrame();
      final mediaSize = MediaQueryData.fromView(View.of(context)).size;
      // On windows, wndRect is equal to GetWindowRect and mediaSize is equal to GetClientRect.
      // https://stackoverflow.com/a/7561083
      double magicWidth =
          wndRect.right - wndRect.left - mediaSize.width * scale;
      double magicHeight =
          wndRect.bottom - wndRect.top - mediaSize.height * scale;
      final canvasModel = ffi.canvasModel;
      final width = (canvasModel.getDisplayWidth() * canvasModel.scale +
                  CanvasModel.leftToEdge +
                  CanvasModel.rightToEdge) *
              scale +
          magicWidth;
      final height = (canvasModel.getDisplayHeight() * canvasModel.scale +
                  CanvasModel.topToEdge +
                  CanvasModel.bottomToEdge) *
              scale +
          magicHeight;
      double left = wndRect.left + (wndRect.width - width) / 2;
      double top = wndRect.top + (wndRect.height - height) / 2;

      Rect frameRect = _screen!.frame;
      if (!isFullscreen) {
        frameRect = _screen!.visibleFrame;
      }
      if (left < frameRect.left) {
        left = frameRect.left;
      }
      if (top < frameRect.top) {
        top = frameRect.top;
      }
      if ((left + width) > frameRect.right) {
        left = frameRect.right - width;
      }
      if ((top + height) > frameRect.bottom) {
        top = frameRect.bottom - height;
      }
      await WindowController.fromWindowId(windowId)
          .setFrame(Rect.fromLTWH(left, top, width, height));
      stateGlobal.setMaximized(false);
    }
  }

  updateScreen() async {
    final String info =
        isWeb ? screenInfo : await _getScreenInfoDesktop() ?? '';
    if (info.isEmpty) {
      _screen = null;
    } else {
      final screenMap = jsonDecode(info);
      _screen = window_size.Screen(
          Rect.fromLTRB(screenMap['frame']['l'], screenMap['frame']['t'],
              screenMap['frame']['r'], screenMap['frame']['b']),
          Rect.fromLTRB(
              screenMap['visibleFrame']['l'],
              screenMap['visibleFrame']['t'],
              screenMap['visibleFrame']['r'],
              screenMap['visibleFrame']['b']),
          screenMap['scaleFactor']);
    }
  }

  _getScreenInfoDesktop() async {
    final v =
        await oneDeskWinManager.call(WindowType.Main, kWindowGetWindowInfo, '');
    return v.result;
  }

  Future<bool> isWindowCanBeAdjusted() async {
    final viewStyle =
        await bind.sessionGetViewStyle(sessionId: ffi.sessionId) ?? '';
    if (viewStyle != kRemoteViewStyleOriginal) {
      return false;
    }
    if (!isWeb) {
      final remoteCount = RemoteCountState.find().value;
      if (remoteCount != 1) {
        return false;
      }
    }
    if (_screen == null) {
      return false;
    }
    final scale = kIgnoreDpi ? 1.0 : _screen!.scaleFactor;
    double selfWidth = _screen!.visibleFrame.width;
    double selfHeight = _screen!.visibleFrame.height;
    if (isFullscreen) {
      selfWidth = _screen!.frame.width;
      selfHeight = _screen!.frame.height;
    }

    final canvasModel = ffi.canvasModel;
    final displayWidth = canvasModel.getDisplayWidth();
    final displayHeight = canvasModel.getDisplayHeight();
    final requiredWidth =
        CanvasModel.leftToEdge + displayWidth + CanvasModel.rightToEdge;
    final requiredHeight =
        CanvasModel.topToEdge + displayHeight + CanvasModel.bottomToEdge;
    return selfWidth > (requiredWidth * scale) &&
        selfHeight > (requiredHeight * scale);
  }
}

class _DisplayMenu extends StatefulWidget {
  final String id;
  final FFI ffi;
  final ToolbarState state;
  final Function(bool) setFullscreen;
  final Widget pluginItem;
  _DisplayMenu(
      {Key? key,
      required this.id,
      required this.ffi,
      required this.state,
      required this.setFullscreen})
      : pluginItem = LocationItem.createLocationItem(
          id,
          ffi,
          kLocationClientRemoteToolbarDisplay,
          true,
        ),
        super(key: key);

  @override
  State<_DisplayMenu> createState() => _DisplayMenuState();
}

class _DisplayMenuState extends State<_DisplayMenu> {
  final RxInt _customPercent = 100.obs;
  late final ScreenAdjustor _screenAdjustor = ScreenAdjustor(
    id: widget.id,
    ffi: widget.ffi,
    cbExitFullscreen: () => widget.setFullscreen(false),
  );

  int get windowId => stateGlobal.windowId;
  Map<String, bool> get perms => widget.ffi.ffiModel.permissions;
  PeerInfo get pi => widget.ffi.ffiModel.pi;
  FfiModel get ffiModel => widget.ffi.ffiModel;
  FFI get ffi => widget.ffi;
  String get id => widget.id;

  @override
  void initState() {
    super.initState();
    // Initialize custom percent from stored option once
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final v = await getSessionCustomScalePercent(widget.ffi.sessionId);
        if (_customPercent.value != v) {
          _customPercent.value = v;
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    _screenAdjustor.updateScreen();
    menuChildrenGetter(_IconSubmenuButtonState state) {
      final menuChildren = <Widget>[
        _screenAdjustor.adjustWindow(context),
        viewStyle(customPercent: _customPercent),
        scrollStyle(state, colorScheme),
        imageQuality(),
        codec(),
        if (ffi.connType == ConnType.defaultConn)
          _ResolutionsMenu(
            id: widget.id,
            ffi: widget.ffi,
            screenAdjustor: _screenAdjustor,
          ),
        if (showVirtualDisplayMenu(ffi) && ffi.connType == ConnType.defaultConn)
          _SubmenuButton(
            ffi: widget.ffi,
            menuChildren: getVirtualDisplayMenuChildren(ffi, id, null),
            child: Text(translate("Virtual display")),
          ),
        if (ffi.connType == ConnType.defaultConn) cursorToggles(),
        Divider(),
        toggles(),
      ];
      // privacy mode
      if (ffi.connType == ConnType.defaultConn &&
          ffiModel.keyboard &&
          pi.features.privacyMode) {
        final privacyModeState = PrivacyModeState.find(id);
        final privacyModeList =
            toolbarPrivacyMode(privacyModeState, context, id, ffi);
        if (privacyModeList.length == 1) {
          menuChildren.add(CkbMenuButton(
              value: privacyModeList[0].value,
              onChanged: privacyModeList[0].onChanged,
              child: privacyModeList[0].child,
              ffi: ffi));
        } else if (privacyModeList.length > 1) {
          menuChildren.addAll([
            Divider(),
            _SubmenuButton(
                ffi: widget.ffi,
                child: Text(translate('Privacy mode')),
                menuChildren: privacyModeList
                    .map((e) => CkbMenuButton(
                        value: e.value,
                        onChanged: e.onChanged,
                        child: e.child,
                        ffi: ffi))
                    .toList()),
          ]);
        }
      }
      if (ffi.connType == ConnType.defaultConn) {
        menuChildren.add(widget.pluginItem);
      }
      return menuChildren;
    }

    return _IconSubmenuButton(
      tooltip: 'Display Settings',
      svg: "assets/display.svg",
      ffi: widget.ffi,
      color: _ToolbarTheme.blueColor,
      hoverColor: _ToolbarTheme.hoverBlueColor,
      menuChildrenGetter: menuChildrenGetter,
    );
  }

  viewStyle({required RxInt customPercent}) {
    return futureBuilder(
        future: toolbarViewStyle(context, widget.id, widget.ffi),
        hasData: (data) {
          final v = data as List<TRadioMenu<String>>;
          final bool isCustomSelected = v.isNotEmpty
              ? v.first.groupValue == kRemoteViewStyleCustom
              : false;
          return Column(children: [
            ...v.map((e) {
              final isCustom = e.value == kRemoteViewStyleCustom;
              final child =
                  isCustom ? Text(translate('Scale custom')) : e.child;
              // Whether the current selection is already custom
              final bool isGroupCustomSelected =
                  e.groupValue == kRemoteViewStyleCustom;
              // Keep menu open when switching INTO custom so the slider is visible immediately
              final bool keepOpenForThisItem =
                  isCustom && !isGroupCustomSelected;
              return RdoMenuButton<String>(
                  value: e.value,
                  groupValue: e.groupValue,
                  onChanged: (value) {
                    // Perform the original change
                    e.onChanged?.call(value);
                    // Only force a rebuild when we keep the menu open to reveal the slider
                    if (keepOpenForThisItem) {
                      setState(() {});
                    }
                  },
                  child: child,
                  ffi: ffi,
                  // When entering custom, keep submenu open to show the slider controls
                  closeOnActivate: !keepOpenForThisItem);
            }).toList(),
            // Only show a divider when custom is NOT selected
            if (!isCustomSelected) Divider(),
            _customControlsIfCustomSelected(
                onChanged: (v) => customPercent.value = v),
          ]);
        });
  }

  Widget _customControlsIfCustomSelected({ValueChanged<int>? onChanged}) {
    return futureBuilder(future: () async {
      final current = await bind.sessionGetViewStyle(sessionId: ffi.sessionId);
      return current == kRemoteViewStyleCustom;
    }(), hasData: (data) {
      final isCustom = data as bool;
      return AnimatedSwitcher(
        duration: Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: isCustom
            ? _CustomScaleMenuControls(ffi: ffi, onChanged: onChanged)
            : SizedBox.shrink(),
      );
    });
  }

  scrollStyle(_IconSubmenuButtonState state, ColorScheme colorScheme) {
    return futureBuilder(future: () async {
      final viewStyle =
          await bind.sessionGetViewStyle(sessionId: ffi.sessionId) ?? '';
      final visible = viewStyle == kRemoteViewStyleOriginal ||
          viewStyle == kRemoteViewStyleCustom;
      final scrollStyle =
          await bind.sessionGetScrollStyle(sessionId: ffi.sessionId) ?? '';
      final edgeScrollEdgeThickness = await bind
          .sessionGetEdgeScrollEdgeThickness(sessionId: ffi.sessionId);
      return {
        'visible': visible,
        'scrollStyle': scrollStyle,
        'edgeScrollEdgeThickness': edgeScrollEdgeThickness,
      };
    }(), hasData: (data) {
      final visible = data['visible'] as bool;
      if (!visible) return Offstage();
      final groupValue = data['scrollStyle'] as String;
      final edgeScrollEdgeThickness = data['edgeScrollEdgeThickness'] as int;

      onChangeScrollStyle(String? value) async {
        if (value == null) return;
        await bind.sessionSetScrollStyle(
            sessionId: ffi.sessionId, value: value);
        widget.ffi.canvasModel.updateScrollStyle();
        state.setState(() {});
      }

      onChangeEdgeScrollEdgeThickness(double? value) async {
        if (value == null) return;
        final newThickness = value.round();
        await bind.sessionSetEdgeScrollEdgeThickness(
            sessionId: ffi.sessionId, value: newThickness);
        widget.ffi.canvasModel.updateEdgeScrollEdgeThickness(newThickness);
        state.setState(() {});
      }

      return Obx(() => Column(children: [
            RdoMenuButton<String>(
              child: Text(translate('ScrollAuto')),
              value: kRemoteScrollStyleAuto,
              groupValue: groupValue,
              onChanged: widget.ffi.canvasModel.imageOverflow.value
                  ? (value) => onChangeScrollStyle(value)
                  : null,
              closeOnActivate: groupValue != kRemoteScrollStyleEdge,
              ffi: widget.ffi,
            ),
            RdoMenuButton<String>(
              child: Text(translate('Scrollbar')),
              value: kRemoteScrollStyleBar,
              groupValue: groupValue,
              onChanged: widget.ffi.canvasModel.imageOverflow.value
                  ? (value) => onChangeScrollStyle(value)
                  : null,
              closeOnActivate: groupValue != kRemoteScrollStyleEdge,
              ffi: widget.ffi,
            ),
            if (!isWeb) ...[
              RdoMenuButton<String>(
                child: Text(translate('ScrollEdge')),
                value: kRemoteScrollStyleEdge,
                groupValue: groupValue,
                closeOnActivate: false,
                onChanged: widget.ffi.canvasModel.imageOverflow.value
                    ? (value) => onChangeScrollStyle(value)
                    : null,
                ffi: widget.ffi,
              ),
              Offstage(
                  offstage: groupValue != kRemoteScrollStyleEdge,
                  child: EdgeThicknessControl(
                    value: edgeScrollEdgeThickness.toDouble(),
                    onChanged: onChangeEdgeScrollEdgeThickness,
                    colorScheme: colorScheme,
                  )),
            ],
            Divider(),
          ]));
    });
  }

  imageQuality() {
    return futureBuilder(
        future: toolbarImageQuality(context, widget.id, widget.ffi),
        hasData: (data) {
          final v = data as List<TRadioMenu<String>>;
          return _SubmenuButton(
            ffi: widget.ffi,
            child: Text(translate('Image Quality')),
            menuChildren: v
                .map((e) => RdoMenuButton<String>(
                    value: e.value,
                    groupValue: e.groupValue,
                    onChanged: e.onChanged,
                    child: e.child,
                    ffi: ffi))
                .toList(),
          );
        });
  }

  codec() {
    return futureBuilder(
        future: toolbarCodec(context, id, ffi),
        hasData: (data) {
          final v = data as List<TRadioMenu<String>>;
          if (v.isEmpty) return Offstage();

          return _SubmenuButton(
              ffi: widget.ffi,
              child: Text(translate('Codec')),
              menuChildren: v
                  .map((e) => RdoMenuButton(
                      value: e.value,
                      groupValue: e.groupValue,
                      onChanged: e.onChanged,
                      child: e.child,
                      ffi: ffi))
                  .toList());
        });
  }

  cursorToggles() {
    return futureBuilder(
        future: toolbarCursor(context, id, ffi),
        hasData: (data) {
          final v = data as List<TToggleMenu>;
          if (v.isEmpty) return Offstage();
          return Column(children: [
            Divider(),
            ...v
                .map((e) => CkbMenuButton(
                    value: e.value,
                    onChanged: e.onChanged,
                    child: e.child,
                    ffi: ffi))
                .toList(),
          ]);
        });
  }

  toggles() {
    return futureBuilder(
        future: toolbarDisplayToggle(context, id, ffi),
        hasData: (data) {
          final v = data as List<TToggleMenu>;
          if (v.isEmpty) return Offstage();
          return Column(
              children: v
                  .map((e) => CkbMenuButton(
                      value: e.value,
                      onChanged: e.onChanged,
                      child: e.child,
                      ffi: ffi))
                  .toList());
        });
  }
}

class _CustomScaleMenuControls extends StatefulWidget {
  final FFI ffi;
  final ValueChanged<int>? onChanged;
  const _CustomScaleMenuControls({Key? key, required this.ffi, this.onChanged})
      : super(key: key);

  @override
  State<_CustomScaleMenuControls> createState() =>
      _CustomScaleMenuControlsState();
}

class _CustomScaleMenuControlsState
    extends CustomScaleControls<_CustomScaleMenuControls> {
  @override
  FFI get ffi => widget.ffi;

  @override
  ValueChanged<int>? get onScaleChanged => widget.onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const smallBtnConstraints = BoxConstraints(minWidth: 28, minHeight: 28);

    final sliderControl = Semantics(
      label: translate('Custom scale slider'),
      value: '$scaleValue%',
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: colorScheme.primary,
          thumbColor: colorScheme.primary,
          overlayColor: colorScheme.primary.withOpacity(0.1),
          showValueIndicator: ShowValueIndicator.never,
          thumbShape: _RectValueThumbShape(
            min: CustomScaleControls.minPercent.toDouble(),
            max: CustomScaleControls.maxPercent.toDouble(),
            width: 52,
            height: 24,
            radius: 4,
            displayValueForNormalized: (t) => mapPosToPercent(t),
          ),
        ),
        child: Slider(
          value: scalePos,
          min: 0.0,
          max: 1.0,
          // Use a wide range of divisions (calculated as (CustomScaleControls.maxPercent - CustomScaleControls.minPercent)) to provide ~1% precision increments.
          // This allows users to set precise scale values. Lower values would require more fine-tuning via the +/- buttons, which is undesirable for big ranges.
          divisions:
              (CustomScaleControls.maxPercent - CustomScaleControls.minPercent)
                  .round(),
          onChanged: onSliderChanged,
        ),
      ),
    );

    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: Row(children: [
          Tooltip(
            message: translate('Decrease'),
            waitDuration: Duration.zero,
            child: IconButton(
              iconSize: 16,
              padding: EdgeInsets.all(1),
              constraints: smallBtnConstraints,
              icon: const Icon(Icons.remove),
              onPressed: () => nudgeScale(-1),
            ),
          ),
          Expanded(child: sliderControl),
          Tooltip(
            message: translate('Increase'),
            waitDuration: Duration.zero,
            child: IconButton(
              iconSize: 16,
              padding: EdgeInsets.all(1),
              constraints: smallBtnConstraints,
              icon: const Icon(Icons.add),
              onPressed: () => nudgeScale(1),
            ),
          ),
        ]),
      ),
      Divider(),
    ]);
  }
}

// Lightweight rectangular thumb that paints the current percentage.
// Stateless and uses only SliderTheme colors; avoids allocations beyond a TextPainter per frame.
class _RectValueThumbShape extends SliderComponentShape {
  final double min;
  final double max;
  final double width;
  final double height;
  final double radius;
  final String unit;
  // Optional mapper to compute display value from normalized position [0,1]
  // If null, falls back to linear interpolation between min and max.
  final int Function(double normalized)? displayValueForNormalized;

  const _RectValueThumbShape({
    required this.min,
    required this.max,
    required this.width,
    required this.height,
    required this.radius,
    this.displayValueForNormalized,
    this.unit = '%',
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size(width, height);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    // Resolve color based on enabled/disabled animation, with safe fallbacks.
    final ColorTween colorTween = ColorTween(
      begin: sliderTheme.disabledThumbColor,
      end: sliderTheme.thumbColor,
    );
    final Color? evaluatedColor = colorTween.evaluate(enableAnimation);
    final Color? thumbColor = sliderTheme.thumbColor;
    final Color fillColor = evaluatedColor ?? thumbColor ?? Colors.blueAccent;

    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: width, height: height),
      Radius.circular(radius),
    );
    final Paint paint = Paint()..color = fillColor;
    canvas.drawRRect(rrect, paint);

    // Compute displayed value from normalized slider value.
    final int displayValue = displayValueForNormalized != null
        ? displayValueForNormalized!(value)
        : (min + value * (max - min)).round();
    final TextSpan span = TextSpan(
      text: '$displayValue$unit',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
    final TextPainter tp = TextPainter(
      text: span,
      textAlign: TextAlign.center,
      textDirection: textDirection,
    );
    tp.layout(maxWidth: width - 4);
    tp.paint(
        canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }
}

class _ResolutionsMenu extends StatefulWidget {
  final String id;
  final FFI ffi;
  final ScreenAdjustor screenAdjustor;

  _ResolutionsMenu({
    Key? key,
    required this.id,
    required this.ffi,
    required this.screenAdjustor,
  }) : super(key: key);

  @override
  State<_ResolutionsMenu> createState() => _ResolutionsMenuState();
}

const double _kCustomResolutionEditingWidth = 42;
const _kCustomResolutionValue = 'custom';

class _ResolutionsMenuState extends State<_ResolutionsMenu> {
  String _groupValue = '';
  Resolution? _localResolution;

  late final TextEditingController _customWidth =
      TextEditingController(text: rect?.width.toInt().toString() ?? '');
  late final TextEditingController _customHeight =
      TextEditingController(text: rect?.height.toInt().toString() ?? '');

  FFI get ffi => widget.ffi;
  PeerInfo get pi => widget.ffi.ffiModel.pi;
  FfiModel get ffiModel => widget.ffi.ffiModel;
  Rect? get rect => scaledRect();
  List<Resolution> get resolutions => pi.resolutions;
  bool get isWayland => bind.mainCurrentIsWayland();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getLocalResolutionWayland();
    });
  }

  Rect? scaledRect() {
    final scale = pi.scaleOfDisplay(pi.currentDisplay);
    final rect = ffiModel.rect;
    if (rect == null) {
      return null;
    }
    return Rect.fromLTWH(
      rect.left,
      rect.top,
      rect.width / scale,
      rect.height / scale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVirtualDisplay = ffiModel.isVirtualDisplayResolution;
    final visible = ffiModel.keyboard &&
        (isVirtualDisplay || resolutions.length > 1) &&
        pi.currentDisplay != kAllDisplayValue;
    if (!visible) return Offstage();
    final showOriginalBtn =
        ffiModel.isOriginalResolutionSet && !ffiModel.isOriginalResolution;
    final showFitLocalBtn = !_isRemoteResolutionFitLocal();
    _setGroupValue();
    return _SubmenuButton(
      ffi: widget.ffi,
      menuChildren: <Widget>[
            _OriginalResolutionMenuButton(context, showOriginalBtn),
            _FitLocalResolutionMenuButton(context, showFitLocalBtn),
            _customResolutionMenuButton(context, isVirtualDisplay),
            _menuDivider(showOriginalBtn, showFitLocalBtn, isVirtualDisplay),
          ] +
          _supportedResolutionMenuButtons(),
      child: Text(translate("Resolution")),
    );
  }

  _setGroupValue() {
    if (pi.currentDisplay == kAllDisplayValue) {
      return;
    }
    final lastGroupValue =
        stateGlobal.getLastResolutionGroupValue(widget.id, pi.currentDisplay);
    if (lastGroupValue == _kCustomResolutionValue) {
      _groupValue = _kCustomResolutionValue;
    } else {
      _groupValue =
          '${(rect?.width ?? 0).toInt()}x${(rect?.height ?? 0).toInt()}';
    }
  }

  _menuDivider(
      bool showOriginalBtn, bool showFitLocalBtn, bool isVirtualDisplay) {
    return Offstage(
      offstage: !(showOriginalBtn || showFitLocalBtn || isVirtualDisplay),
      child: Divider(),
    );
  }

  Future<void> _getLocalResolutionWayland() async {
    if (!isWayland) return _getLocalResolution();
    final window = await window_size.getWindowInfo();
    final screen = window.screen;
    if (screen != null) {
      setState(() {
        _localResolution = Resolution(
          screen.frame.width.toInt(),
          screen.frame.height.toInt(),
        );
      });
    }
  }

  _getLocalResolution() {
    _localResolution = null;
    final String mainDisplay = bind.mainGetMainDisplay();
    if (mainDisplay.isNotEmpty) {
      try {
        final display = json.decode(mainDisplay);
        if (display['w'] != null && display['h'] != null) {
          _localResolution = Resolution(display['w'], display['h']);
          if (isWeb) {
            if (display['scaleFactor'] != null) {
              _localResolution = Resolution(
                (display['w'] / display['scaleFactor']).toInt(),
                (display['h'] / display['scaleFactor']).toInt(),
              );
            }
          }
        }
      } catch (e) {
        debugPrint('Failed to decode $mainDisplay, $e');
      }
    }
  }

  // This widget has been unmounted, so the State no longer has a context
  _onChanged(String? value) async {
    if (pi.currentDisplay == kAllDisplayValue) {
      return;
    }
    stateGlobal.setLastResolutionGroupValue(
        widget.id, pi.currentDisplay, value);
    if (value == null) return;

    int? w;
    int? h;
    if (value == _kCustomResolutionValue) {
      w = int.tryParse(_customWidth.text);
      h = int.tryParse(_customHeight.text);
    } else {
      final list = value.split('x');
      if (list.length == 2) {
        w = int.tryParse(list[0]);
        h = int.tryParse(list[1]);
      }
    }

    if (w != null && h != null) {
      if (w != rect?.width.toInt() || h != rect?.height.toInt()) {
        await _changeResolution(w, h);
      }
    }
  }

  _changeResolution(int w, int h) async {
    if (pi.currentDisplay == kAllDisplayValue) {
      return;
    }
    await bind.sessionChangeResolution(
      sessionId: ffi.sessionId,
      display: pi.currentDisplay,
      width: w,
      height: h,
    );
    Future.delayed(Duration(seconds: 3), () async {
      final rect = ffiModel.rect;
      if (rect == null) {
        return;
      }
      if (w == rect.width.toInt() && h == rect.height.toInt()) {
        if (await widget.screenAdjustor.isWindowCanBeAdjusted()) {
          widget.screenAdjustor.doAdjustWindow(context);
        }
      }
    });
  }

  Widget _OriginalResolutionMenuButton(
      BuildContext context, bool showOriginalBtn) {
    final display = pi.tryGetDisplayIfNotAllDisplay();
    if (display == null) {
      return Offstage();
    }
    if (!resolutions.any((e) =>
        e.width == display.originalWidth &&
        e.height == display.originalHeight)) {
      return Offstage();
    }
    return Offstage(
      offstage: !showOriginalBtn,
      child: MenuButton(
        onPressed: () =>
            _changeResolution(display.originalWidth, display.originalHeight),
        ffi: widget.ffi,
        child: Text(
            '${translate('resolution_original_tip')} ${display.originalWidth}x${display.originalHeight}'),
      ),
    );
  }

  Widget _FitLocalResolutionMenuButton(
      BuildContext context, bool showFitLocalBtn) {
    return Offstage(
      offstage: !showFitLocalBtn,
      child: MenuButton(
        onPressed: () {
          final resolution = _getBestFitResolution();
          if (resolution != null) {
            _changeResolution(resolution.width, resolution.height);
          }
        },
        ffi: widget.ffi,
        child: Text(
            '${translate('resolution_fit_local_tip')} ${_localResolution?.width ?? 0}x${_localResolution?.height ?? 0}'),
      ),
    );
  }

  Widget _customResolutionMenuButton(BuildContext context, isVirtualDisplay) {
    return Offstage(
      offstage: !isVirtualDisplay,
      child: RdoMenuButton(
        value: _kCustomResolutionValue,
        groupValue: _groupValue,
        onChanged: (String? value) => _onChanged(value),
        ffi: widget.ffi,
        child: Row(
          children: [
            Text('${translate('resolution_custom_tip')} '),
            SizedBox(
              width: _kCustomResolutionEditingWidth,
              child: _resolutionInput(_customWidth),
            ),
            Text(' x '),
            SizedBox(
              width: _kCustomResolutionEditingWidth,
              child: _resolutionInput(_customHeight),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resolutionInput(TextEditingController controller) {
    return TextField(
      decoration: InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.fromLTRB(3, 3, 3, 3),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
        FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
      ],
      controller: controller,
    ).workaroundFreezeLinuxMint();
  }

  List<Widget> _supportedResolutionMenuButtons() => resolutions
      .map((e) => RdoMenuButton(
          value: '${e.width}x${e.height}',
          groupValue: _groupValue,
          onChanged: (String? value) => _onChanged(value),
          ffi: widget.ffi,
          child: Text('${e.width}x${e.height}')))
      .toList();

  Resolution? _getBestFitResolution() {
    if (_localResolution == null) {
      return null;
    }

    if (ffiModel.isVirtualDisplayResolution) {
      return _localResolution!;
    }

    for (final r in resolutions) {
      if (r.width == _localResolution!.width &&
          r.height == _localResolution!.height) {
        return r;
      }
    }

    return null;
  }

  bool _isRemoteResolutionFitLocal() {
    if (_localResolution == null) {
      return true;
    }
    final bestFitResolution = _getBestFitResolution();
    if (bestFitResolution == null) {
      return true;
    }
    return bestFitResolution.width == rect?.width.toInt() &&
        bestFitResolution.height == rect?.height.toInt();
  }
}

class _KeyboardMenu extends StatelessWidget {
  final String id;
  final FFI ffi;
  _KeyboardMenu({
    Key? key,
    required this.id,
    required this.ffi,
  }) : super(key: key);

  PeerInfo get pi => ffi.ffiModel.pi;

  @override
  Widget build(BuildContext context) {
    var ffiModel = Provider.of<FfiModel>(context);
    if (!ffiModel.keyboard) return Offstage();
    toolbarToggles() => toolbarKeyboardToggles(ffi)
        .map((e) => CkbMenuButton(
            value: e.value, onChanged: e.onChanged, child: e.child, ffi: ffi))
        .toList();
    return _IconSubmenuButton(
        tooltip: 'Keyboard Settings',
        svg: "assets/keyboard.svg",
        ffi: ffi,
        color: _ToolbarTheme.blueColor,
        hoverColor: _ToolbarTheme.hoverBlueColor,
        menuChildrenGetter: (_) => [
              keyboardMode(),
              localKeyboardType(),
              inputSource(),
              Divider(),
              viewMode(),
              if ([kPeerPlatformWindows, kPeerPlatformMacOS, kPeerPlatformLinux]
                  .contains(pi.platform))
                showMyCursor(),
              Divider(),
              ...toolbarToggles(),
              ...mouseSpeed(),
              ...mobileActions(),
            ]);
  }

  mouseSpeed() {
    final speedWidgets = [];
    final sessionId = ffi.sessionId;
    if (isDesktop) {
      if (ffi.ffiModel.keyboard) {
        final enabled = !ffi.ffiModel.viewOnly;
        final trackpad = MenuButton(
          child: Text(translate('Trackpad speed')).paddingOnly(left: 26.0),
          onPressed: enabled ? () => trackpadSpeedDialog(sessionId, ffi) : null,
          ffi: ffi,
        );
        speedWidgets.add(trackpad);
      }
    }
    return speedWidgets;
  }

  keyboardMode() {
    return futureBuilder(future: () async {
      return await bind.sessionGetKeyboardMode(sessionId: ffi.sessionId) ??
          kKeyLegacyMode;
    }(), hasData: (data) {
      final groupValue = data as String;
      List<InputModeMenu> modes = [
        InputModeMenu(key: kKeyLegacyMode, menu: 'Legacy mode'),
        InputModeMenu(key: kKeyMapMode, menu: 'Map mode'),
        InputModeMenu(key: kKeyTranslateMode, menu: 'Translate mode'),
      ];
      List<RdoMenuButton> list = [];
      final enabled = !ffi.ffiModel.viewOnly;
      onChanged(String? value) async {
        if (value == null) return;
        await bind.sessionSetKeyboardMode(
            sessionId: ffi.sessionId, value: value);
        await ffi.inputModel.updateKeyboardMode();
      }

      // If use flutter to grab keys, we can only use one mode.
      // Map mode and Legacy mode, at least one of them is supported.
      String? modeOnly;
      // Keep both map and legacy mode on web at the moment.
      // TODO: Remove legacy mode after web supports translate mode on web.
      if (isInputSourceFlutter && isDesktop) {
        if (bind.sessionIsKeyboardModeSupported(
            sessionId: ffi.sessionId, mode: kKeyMapMode)) {
          modeOnly = kKeyMapMode;
        } else if (bind.sessionIsKeyboardModeSupported(
            sessionId: ffi.sessionId, mode: kKeyLegacyMode)) {
          modeOnly = kKeyLegacyMode;
        }
      }

      for (InputModeMenu mode in modes) {
        if (modeOnly != null && mode.key != modeOnly) {
          continue;
        } else if (!bind.sessionIsKeyboardModeSupported(
            sessionId: ffi.sessionId, mode: mode.key)) {
          continue;
        }

        if (pi.isWayland && mode.key != kKeyMapMode) {
          continue;
        }

        var text = translate(mode.menu);
        if (mode.key == kKeyTranslateMode) {
          text = '$text beta';
        }
        list.add(RdoMenuButton<String>(
          child: Text(text),
          value: mode.key,
          groupValue: groupValue,
          onChanged: enabled ? onChanged : null,
          ffi: ffi,
        ));
      }
      return Column(children: list);
    });
  }

  localKeyboardType() {
    final localPlatform = getLocalPlatformForKBLayoutType(pi.platform);
    final visible = localPlatform != '';
    if (!visible) return Offstage();
    final enabled = !ffi.ffiModel.viewOnly;
    return Column(
      children: [
        Divider(),
        MenuButton(
          child: Text(
              '${translate('Local keyboard type')}: ${KBLayoutType.value}'),
          trailingIcon: const Icon(Icons.settings),
          ffi: ffi,
          onPressed: enabled
              ? () => showKBLayoutTypeChooser(localPlatform, ffi.dialogManager)
              : null,
        )
      ],
    );
  }

  inputSource() {
    final supportedInputSource = bind.mainSupportedInputSource();
    if (supportedInputSource.isEmpty) return Offstage();
    late final List<dynamic> supportedInputSourceList;
    try {
      supportedInputSourceList = jsonDecode(supportedInputSource);
    } catch (e) {
      debugPrint('Failed to decode $supportedInputSource, $e');
      return;
    }
    if (supportedInputSourceList.length < 2) return Offstage();
    final inputSource = stateGlobal.getInputSource();
    final enabled = !ffi.ffiModel.viewOnly;
    final children = <Widget>[Divider()];
    children.addAll(supportedInputSourceList.map((e) {
      final d = e as List<dynamic>;
      return RdoMenuButton<String>(
        child: Text(translate(d[1] as String)),
        value: d[0] as String,
        groupValue: inputSource,
        onChanged: enabled
            ? (v) async {
                if (v != null) {
                  await stateGlobal.setInputSource(ffi.sessionId, v);
                  await ffi.ffiModel.checkDesktopKeyboardMode();
                  await ffi.inputModel.updateKeyboardMode();
                }
              }
            : null,
        ffi: ffi,
      );
    }));
    return Column(children: children);
  }

  viewMode() {
    final ffiModel = ffi.ffiModel;
    final enabled = versionCmp(pi.version, '1.2.0') >= 0 && ffiModel.keyboard;
    return CkbMenuButton(
        value: ffiModel.viewOnly,
        onChanged: enabled
            ? (value) async {
                if (value == null) return;
                await bind.sessionToggleOption(
                    sessionId: ffi.sessionId, value: kOptionToggleViewOnly);
                final viewOnly = await bind.sessionGetToggleOption(
                    sessionId: ffi.sessionId, arg: kOptionToggleViewOnly);
                ffiModel.setViewOnly(id, viewOnly ?? value);
                final showMyCursor = await bind.sessionGetToggleOption(
                    sessionId: ffi.sessionId, arg: kOptionToggleShowMyCursor);
                ffiModel.setShowMyCursor(showMyCursor ?? value);
              }
            : null,
        ffi: ffi,
        child: Text(translate('View Mode')));
  }

  showMyCursor() {
    final ffiModel = ffi.ffiModel;
    return CkbMenuButton(
            value: ffiModel.showMyCursor,
            onChanged: (value) async {
              if (value == null) return;
              await bind.sessionToggleOption(
                  sessionId: ffi.sessionId, value: kOptionToggleShowMyCursor);
              final showMyCursor = await bind.sessionGetToggleOption(
                      sessionId: ffi.sessionId,
                      arg: kOptionToggleShowMyCursor) ??
                  value;
              ffiModel.setShowMyCursor(showMyCursor);

              // Also set view only if showMyCursor is enabled and viewOnly is not enabled.
              if (showMyCursor && !ffiModel.viewOnly) {
                await bind.sessionToggleOption(
                    sessionId: ffi.sessionId, value: kOptionToggleViewOnly);
                final viewOnly = await bind.sessionGetToggleOption(
                    sessionId: ffi.sessionId, arg: kOptionToggleViewOnly);
                ffiModel.setViewOnly(id, viewOnly ?? value);
              }
            },
            ffi: ffi,
            child: Text(translate('Show my cursor')))
        .paddingOnly(left: 26.0);
  }

  mobileActions() {
    if (pi.platform != kPeerPlatformAndroid) return [];
    final enabled = versionCmp(pi.version, '1.2.7') >= 0;
    if (!enabled) return [];
    return [
      Divider(),
      MenuButton(
          child: Text(translate('Back')),
          onPressed: () => ffi.inputModel.onMobileBack(),
          ffi: ffi),
      MenuButton(
          child: Text(translate('Home')),
          onPressed: () => ffi.inputModel.onMobileHome(),
          ffi: ffi),
      MenuButton(
          child: Text(translate('Apps')),
          onPressed: () => ffi.inputModel.onMobileApps(),
          ffi: ffi),
      MenuButton(
          child: Text(translate('Volume up')),
          onPressed: () => ffi.inputModel.onMobileVolumeUp(),
          ffi: ffi),
      MenuButton(
          child: Text(translate('Volume down')),
          onPressed: () => ffi.inputModel.onMobileVolumeDown(),
          ffi: ffi),
      MenuButton(
          child: Text(translate('Power')),
          onPressed: () => ffi.inputModel.onMobilePower(),
          ffi: ffi),
    ];
  }
}

class _ChatMenu extends StatefulWidget {
  final String id;
  final FFI ffi;
  _ChatMenu({
    Key? key,
    required this.id,
    required this.ffi,
  }) : super(key: key);

  @override
  State<_ChatMenu> createState() => _ChatMenuState();
}

class _ChatMenuState extends State<_ChatMenu> {
  // Using in StatelessWidget got `Looking up a deactivated widget's ancestor is unsafe`.
  final chatButtonKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    if (isWeb) {
      return buildTextChatButton();
    } else {
      return _IconSubmenuButton(
          tooltip: 'Chat',
          key: chatButtonKey,
          svg: 'assets/chat.svg',
          ffi: widget.ffi,
          color: _ToolbarTheme.blueColor,
          hoverColor: _ToolbarTheme.hoverBlueColor,
          menuChildrenGetter: (_) => [textChat(), voiceCall()]);
    }
  }

  buildTextChatButton() {
    return _IconMenuButton(
      assetName: 'assets/message_24dp_5F6368.svg',
      tooltip: 'Text chat',
      key: chatButtonKey,
      onPressed: _textChatOnPressed,
      color: _ToolbarTheme.blueColor,
      hoverColor: _ToolbarTheme.hoverBlueColor,
    );
  }

  textChat() {
    return MenuButton(
        child: Text(translate('Text chat')),
        ffi: widget.ffi,
        onPressed: _textChatOnPressed);
  }

  _textChatOnPressed() {
    RenderBox? renderBox =
        chatButtonKey.currentContext?.findRenderObject() as RenderBox?;
    Offset? initPos;
    if (renderBox != null) {
      final pos = renderBox.localToGlobal(Offset.zero);
      initPos = Offset(pos.dx, pos.dy + _ToolbarTheme.dividerHeight);
    }
    widget.ffi.chatModel
        .changeCurrentKey(MessageKey(widget.ffi.id, ChatModel.clientModeID));
    widget.ffi.chatModel.toggleChatOverlay(chatInitPos: initPos);
  }

  voiceCall() {
    return MenuButton(
      child: Text(translate('Voice call')),
      ffi: widget.ffi,
      onPressed: () =>
          bind.sessionRequestVoiceCall(sessionId: widget.ffi.sessionId),
    );
  }
}

class _VoiceCallMenu extends StatelessWidget {
  final String id;
  final FFI ffi;
  _VoiceCallMenu({
    Key? key,
    required this.id,
    required this.ffi,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    menuChildrenGetter(_IconSubmenuButtonState state) {
      final audioInput = AudioInput(
        builder: (devices, currentDevice, setDevice) {
          return Column(
            children: devices
                .map((d) => RdoMenuButton<String>(
                      child: Container(
                        child: Text(
                          d,
                          overflow: TextOverflow.ellipsis,
                        ),
                        constraints: BoxConstraints(maxWidth: 250),
                      ),
                      value: d,
                      groupValue: currentDevice,
                      onChanged: (v) {
                        if (v != null) setDevice(v);
                      },
                      ffi: ffi,
                    ))
                .toList(),
          );
        },
        isCm: false,
        isVoiceCall: true,
      );
      return [
        audioInput,
        Divider(),
        MenuButton(
          child: Text(translate('End call')),
          onPressed: () => bind.sessionCloseVoiceCall(sessionId: ffi.sessionId),
          ffi: ffi,
        ),
      ];
    }

    return Obx(
      () {
        switch (ffi.chatModel.voiceCallStatus.value) {
          case VoiceCallStatus.waitingForResponse:
            return buildCallWaiting(context);
          case VoiceCallStatus.connected:
            return _IconSubmenuButton(
              tooltip: 'Voice call',
              svg: 'assets/voice_call.svg',
              color: _ToolbarTheme.blueColor,
              hoverColor: _ToolbarTheme.hoverBlueColor,
              menuChildrenGetter: menuChildrenGetter,
              ffi: ffi,
            );
          default:
            return Offstage();
        }
      },
    );
  }

  Widget buildCallWaiting(BuildContext context) {
    return _IconMenuButton(
      assetName: "assets/call_wait.svg",
      tooltip: "Waiting",
      onPressed: () => bind.sessionCloseVoiceCall(sessionId: ffi.sessionId),
      color: _ToolbarTheme.orangeColor,
      hoverColor: _ToolbarTheme.hoverOrangeColor,
    );
  }
}

class _RecordMenu extends StatelessWidget {
  const _RecordMenu({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var ffi = Provider.of<FfiModel>(context);
    var recordingModel = Provider.of<RecordingModel>(context);
    final visible =
        (recordingModel.start || ffi.permissions['recording'] != false);
    if (!visible) return Offstage();
    return _IconMenuButton(
      assetName: 'assets/rec.svg',
      tooltip: recordingModel.start
          ? 'Stop session recording'
          : 'Start session recording',
      onPressed: () => recordingModel.toggle(),
      color: recordingModel.start
          ? _ToolbarTheme.redColor
          : _ToolbarTheme.blueColor,
      hoverColor: recordingModel.start
          ? _ToolbarTheme.hoverRedColor
          : _ToolbarTheme.hoverBlueColor,
    );
  }
}

class _CloseMenu extends StatelessWidget {
  final String id;
  final FFI ffi;
  const _CloseMenu({Key? key, required this.id, required this.ffi})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return _IconMenuButton(
      assetName: 'assets/close.svg',
      tooltip: 'Close',
      onPressed: () async {
        if (await showConnEndAuditDialogCloseCanceled(ffi: ffi)) {
          return;
        }
        closeConnection(id: id);
      },
      color: _ToolbarTheme.redColor,
      hoverColor: _ToolbarTheme.hoverRedColor,
    );
  }
}

class _IconMenuButton extends StatefulWidget {
  final String? assetName;
  final Widget? icon;
  final String tooltip;
  final Color color;
  final Color hoverColor;
  final VoidCallback? onPressed;
  final double? hMargin;
  final double? vMargin;
  final bool topLevel;
  final double? width;
  const _IconMenuButton({
    Key? key,
    this.assetName,
    this.icon,
    required this.tooltip,
    required this.color,
    required this.hoverColor,
    required this.onPressed,
    this.hMargin,
    this.vMargin,
    this.topLevel = true,
    this.width,
  }) : super(key: key);

  @override
  State<_IconMenuButton> createState() => _IconMenuButtonState();
}

class _IconMenuButtonState extends State<_IconMenuButton> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    assert(widget.assetName != null || widget.icon != null);
    final icon = widget.icon ??
        SvgPicture.asset(
          widget.assetName!,
          colorFilter: ColorFilter.mode(Colors.white, BlendMode.srcIn),
          width: _ToolbarTheme.buttonSize,
          height: _ToolbarTheme.buttonSize,
        );
    var button = SizedBox(
      width: widget.width ?? _ToolbarTheme.buttonSize,
      height: _ToolbarTheme.buttonSize,
      child: MenuItemButton(
          style: ButtonStyle(
              backgroundColor: MaterialStatePropertyAll(Colors.transparent),
              padding: MaterialStatePropertyAll(EdgeInsets.zero),
              overlayColor: MaterialStatePropertyAll(Colors.transparent)),
          onHover: (value) => setState(() {
                hover = value;
              }),
          onPressed: widget.onPressed,
          child: Tooltip(
            message: translate(widget.tooltip),
            waitDuration: Duration.zero,
            child: Material(
                type: MaterialType.transparency,
                child: Ink(
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(_ToolbarTheme.iconRadius),
                      color: hover ? widget.hoverColor : widget.color,
                    ),
                    child: icon)),
          )),
    ).marginSymmetric(
        horizontal: widget.hMargin ?? _ToolbarTheme.buttonHMargin,
        vertical: widget.vMargin ?? _ToolbarTheme.buttonVMargin);
    button = Tooltip(
      message: widget.tooltip,
      waitDuration: Duration.zero,
      child: button,
    );
    if (widget.topLevel) {
      return MenuBar(children: [button]);
    } else {
      return button;
    }
  }
}

class _IconSubmenuButton extends StatefulWidget {
  final String tooltip;
  final String? svg;
  final Widget? icon;
  final Color color;
  final Color hoverColor;
  final List<Widget> Function(_IconSubmenuButtonState state) menuChildrenGetter;
  final MenuStyle? menuStyle;
  final FFI? ffi;
  final double? width;

  _IconSubmenuButton({
    Key? key,
    this.svg,
    this.icon,
    required this.tooltip,
    required this.color,
    required this.hoverColor,
    required this.menuChildrenGetter,
    this.ffi,
    this.menuStyle,
    this.width,
  }) : super(key: key);

  @override
  State<_IconSubmenuButton> createState() => _IconSubmenuButtonState();
}

class _IconSubmenuButtonState extends State<_IconSubmenuButton> {
  bool hover = false;

  @override // discard @protected
  void setState(VoidCallback fn) {
    super.setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.svg != null || widget.icon != null);
    final icon = widget.icon ??
        SvgPicture.asset(
          widget.svg!,
          colorFilter: ColorFilter.mode(Colors.white, BlendMode.srcIn),
          width: _ToolbarTheme.buttonSize,
          height: _ToolbarTheme.buttonSize,
        );
    final button = SizedBox(
        width: widget.width ?? _ToolbarTheme.buttonSize,
        height: _ToolbarTheme.buttonSize,
        child: TooltipVisibility(
          visible: false,
          child: SubmenuButton(
            menuStyle:
                widget.menuStyle ?? _ToolbarTheme.defaultMenuStyle(context),
            style: _ToolbarTheme.defaultMenuButtonStyle,
            onHover: (value) => setState(() {
                  hover = value;
                }),
            child: Tooltip(
                message: translate(widget.tooltip),
                waitDuration: Duration.zero,
                child: Material(
                    type: MaterialType.transparency,
                    child: Ink(
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(_ToolbarTheme.iconRadius),
                          color: hover ? widget.hoverColor : widget.color,
                        ),
                        child: icon))),
            menuChildren: widget
                .menuChildrenGetter(this)
                .map((e) => _buildPointerTrackWidget(e, widget.ffi))
                .toList())));
    return MenuBar(children: [
      button.marginSymmetric(
          horizontal: _ToolbarTheme.buttonHMargin,
          vertical: _ToolbarTheme.buttonVMargin)
    ]);
  }
}

class _SubmenuButton extends StatelessWidget {
  final List<Widget> menuChildren;
  final Widget? child;
  final FFI ffi;
  const _SubmenuButton({
    Key? key,
    required this.menuChildren,
    required this.child,
    required this.ffi,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TooltipVisibility(
      visible: false,
      child: SubmenuButton(
        key: key,
        child: child,
        menuChildren:
            menuChildren.map((e) => _buildPointerTrackWidget(e, ffi)).toList(),
        menuStyle: _ToolbarTheme.defaultMenuStyle(context),
      ),
    );
  }
}

class MenuButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget? trailingIcon;
  final Widget? child;
  final FFI? ffi;
  MenuButton(
      {Key? key,
      this.onPressed,
      this.trailingIcon,
      required this.child,
      this.ffi})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MenuItemButton(
        key: key,
        onPressed: onPressed != null
            ? () {
                if (ffi != null) {
                  _menuDismissCallback(ffi!);
                }
                onPressed?.call();
              }
            : null,
        trailingIcon: trailingIcon,
        child: child);
  }
}

class CkbMenuButton extends StatelessWidget {
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final Widget? child;
  final FFI? ffi;
  const CkbMenuButton(
      {Key? key,
      required this.value,
      required this.onChanged,
      required this.child,
      this.ffi})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CheckboxMenuButton(
      key: key,
      value: value,
      child: child,
      onChanged: onChanged != null
          ? (bool? value) {
              if (ffi != null) {
                _menuDismissCallback(ffi!);
              }
              onChanged?.call(value);
            }
          : null,
    );
  }
}

class RdoMenuButton<T> extends StatelessWidget {
  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final Widget? child;
  final FFI? ffi;
  // When true, submenu will be dismissed on activate; when false, it stays open.
  final bool closeOnActivate;
  const RdoMenuButton({
    Key? key,
    required this.value,
    required this.groupValue,
    required this.child,
    this.ffi,
    this.onChanged,
    this.closeOnActivate = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RadioMenuButton(
      value: value,
      groupValue: groupValue,
      child: child,
      closeOnActivate: closeOnActivate,
      onChanged: onChanged != null
          ? (T? value) {
              if (ffi != null && closeOnActivate) {
                _menuDismissCallback(ffi!);
              }
              onChanged?.call(value);
            }
          : null,
    );
  }
}

class _DraggableShowHide extends StatefulWidget {
  final String id;
  final SessionID sessionId;
  final RxDouble fractionX;
  final RxBool dragging;
  final ToolbarState toolbarState;
  final BorderRadius borderRadius;

  final Function(bool) setFullscreen;
  final Function() setMinimize;

  const _DraggableShowHide({
    Key? key,
    required this.id,
    required this.sessionId,
    required this.fractionX,
    required this.dragging,
    required this.toolbarState,
    required this.setFullscreen,
    required this.setMinimize,
    required this.borderRadius,
  }) : super(key: key);

  @override
  State<_DraggableShowHide> createState() => _DraggableShowHideState();
}

class _DraggableShowHideState extends State<_DraggableShowHide> {
  Offset position = Offset.zero;
  Size size = Size.zero;
  double left = 0.0;
  double right = 1.0;

  RxBool get show => widget.toolbarState.show;

  @override
  initState() {
    super.initState();

    final confLeft = double.tryParse(
        bind.mainGetLocalOption(key: kOptionRemoteMenubarDragLeft));
    if (confLeft == null) {
      bind.mainSetLocalOption(
          key: kOptionRemoteMenubarDragLeft, value: left.toString());
    } else {
      left = confLeft;
    }
    final confRight = double.tryParse(
        bind.mainGetLocalOption(key: kOptionRemoteMenubarDragRight));
    if (confRight == null) {
      bind.mainSetLocalOption(
          key: kOptionRemoteMenubarDragRight, value: right.toString());
    } else {
      right = confRight;
    }
  }

  Widget _buildDraggable(BuildContext context) {
    return Draggable(
      axis: Axis.horizontal,
      child: Icon(
        Icons.drag_indicator,
        size: 20,
        color: MyTheme.color(context).drag_indicator,
      ),
      feedback: widget,
      onDragStarted: (() {
        final RenderObject? renderObj = context.findRenderObject();
        if (renderObj != null) {
          final RenderBox renderBox = renderObj as RenderBox;
          size = renderBox.size;
          position = renderBox.localToGlobal(Offset.zero);
        }
        widget.dragging.value = true;
      }),
      onDragEnd: (details) {
        final mediaSize = MediaQueryData.fromView(View.of(context)).size;
        widget.fractionX.value +=
            (details.offset.dx - position.dx) / (mediaSize.width - size.width);
        if (widget.fractionX.value < left) {
          widget.fractionX.value = left;
        }
        if (widget.fractionX.value > right) {
          widget.fractionX.value = right;
        }
        bind.sessionPeerOption(
          sessionId: widget.sessionId,
          name: 'remote-menubar-drag-x',
          value: widget.fractionX.value.toString(),
        );
        widget.dragging.value = false;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ButtonStyle buttonStyle = ButtonStyle(
      minimumSize: MaterialStateProperty.all(const Size(0, 0)),
      padding: MaterialStateProperty.all(EdgeInsets.zero),
    );
    final isFullscreen = stateGlobal.fullscreen;
    const double iconSize = 20;

    buttonWrapper(VoidCallback? onPressed, Widget child,
        {Color hoverColor = _ToolbarTheme.blueColor}) {
      final bgColor = buttonStyle.backgroundColor?.resolve({});
      return TextButton(
        onPressed: onPressed,
        child: child,
        style: buttonStyle.copyWith(
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.hovered)) {
              return (bgColor ?? hoverColor).withOpacity(0.15);
            }
            return bgColor;
          }),
        ),
      );
    }

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDraggable(context),
        Obx(() => buttonWrapper(
              () {
                widget.setFullscreen(!isFullscreen.value);
              },
              Tooltip(
                message: translate(
                    isFullscreen.isTrue ? 'Exit Fullscreen' : 'Fullscreen'),
                waitDuration: Duration.zero,
                child: Icon(
                  isFullscreen.isTrue
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  size: iconSize,
                ),
              ),
            )),
        if (!isMacOS && !isWebDesktop)
          Obx(() => Offstage(
                offstage: isFullscreen.isFalse,
                child: buttonWrapper(
                  widget.setMinimize,
                  Tooltip(
                    message: translate('Minimize'),
                    waitDuration: Duration.zero,
                    child: Icon(
                      Icons.remove,
                      size: iconSize,
                    ),
                  ),
                ),
              )),
        buttonWrapper(
          () => setState(() {
            widget.toolbarState.switchShow(widget.sessionId);
          }),
          Obx((() => Tooltip(
                message:
                    translate(show.isTrue ? 'Hide Toolbar' : 'Show Toolbar'),
                waitDuration: Duration.zero,
                child: Icon(
                  show.isTrue ? Icons.expand_less : Icons.expand_more,
                  size: iconSize,
                ),
              ))),
        ),
        if (isWebDesktop)
          Obx(() {
            if (show.isTrue) {
              return Offstage();
            } else {
              return buttonWrapper(
                () => closeConnection(id: widget.id),
                Tooltip(
                  message: translate('Close'),
                  waitDuration: Duration.zero,
                  child: Icon(
                    Icons.close,
                    size: iconSize,
                    color: _ToolbarTheme.redColor,
                  ),
                ),
                hoverColor: _ToolbarTheme.redColor,
              ).paddingOnly(left: iconSize / 2);
            }
          })
      ],
    );
    return TextButtonTheme(
      data: TextButtonThemeData(style: buttonStyle),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFEFEFE),
          border: Border.all(
            color: _ToolbarTheme.borderColor(context),
            width: 1,
          ),
          borderRadius: widget.borderRadius,
        ),
        child: SizedBox(
          height: 20,
          child: child,
        ),
      ),
    );
  }
}

class InputModeMenu {
  final String key;
  final String menu;

  InputModeMenu({required this.key, required this.menu});
}

_menuDismissCallback(FFI ffi) => ffi.inputModel.refreshMousePos();

Widget _buildPointerTrackWidget(Widget child, FFI? ffi) {
  return Listener(
    onPointerHover: (PointerHoverEvent e) => {
      if (ffi != null) {ffi.inputModel.lastMousePos = e.position}
    },
    child: MouseRegion(
      child: child,
    ),
  );
}

class EdgeThicknessControl extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged;
  final ColorScheme? colorScheme;

  const EdgeThicknessControl({
    Key? key,
    required this.value,
    this.onChanged,
    this.colorScheme,
  }) : super(key: key);

  static const double kMin = 20;
  static const double kMax = 150;

  @override
  Widget build(BuildContext context) {
    final colorScheme = this.colorScheme ?? Theme.of(context).colorScheme;

    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: colorScheme.primary,
        thumbColor: colorScheme.primary,
        overlayColor: colorScheme.primary.withOpacity(0.1),
        showValueIndicator: ShowValueIndicator.never,
        thumbShape: _RectValueThumbShape(
          min: EdgeThicknessControl.kMin,
          max: EdgeThicknessControl.kMax,
          width: 52,
          height: 24,
          radius: 4,
          unit: 'px',
        ),
      ),
      child: Semantics(
        value: value.toInt().toString(),
        child: Slider(
          value: value,
          min: EdgeThicknessControl.kMin,
          max: EdgeThicknessControl.kMax,
          divisions:
              (EdgeThicknessControl.kMax - EdgeThicknessControl.kMin).round(),
          semanticFormatterCallback: (double newValue) =>
              "${newValue.round()}px",
          onChanged: onChanged,
        ),
      ),
    );

    return slider;
  }
}

/// 팝업 메뉴 아이템 데이터 클래스
class _PopupMenuItem {
  final String? assetPath;
  final String text;
  final VoidCallback onTap;
  final Color? iconColor;

  _PopupMenuItem({
    this.assetPath,
    required this.text,
    required this.onTap,
    this.iconColor,
  });
}

/// 커스텀 툴바 버튼
class _CustomToolbarButton extends StatefulWidget {
  final String assetName;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isPressed;
  final Color? backgroundColor;
  final Color? iconColor;

  const _CustomToolbarButton({
    Key? key,
    required this.assetName,
    required this.tooltip,
    required this.onPressed,
    this.isPressed = false,
    this.backgroundColor,
    this.iconColor,
  }) : super(key: key);

  @override
  State<_CustomToolbarButton> createState() => _CustomToolbarButtonState();
}

class _CustomToolbarButtonState extends State<_CustomToolbarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: Duration.zero,
        child: GestureDetector(
          onTap: () {
            widget.onPressed();
          },
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: widget.backgroundColor != null
                  ? (widget.isPressed
                      ? widget.backgroundColor!.withOpacity(0.8)
                      : (_isHovered
                          ? widget.backgroundColor!.withOpacity(0.9)
                          : widget.backgroundColor))
                  : (widget.isPressed
                      ? MyTheme.accent.withOpacity(0.2)
                      : (_isHovered ? Colors.grey[100] : Colors.transparent)),
              borderRadius: BorderRadius.circular(6),
              border: widget.isPressed
                  ? Border.all(color: MyTheme.accent, width: 1.5)
                  : null,
            ),
            child: Center(
              child: SvgPicture.asset(
                widget.assetName,
                width: 20,
                height: 20,
                colorFilter: svgColor(
                  widget.iconColor ??
                      (widget.isPressed ? MyTheme.accent : Colors.grey[700]!),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 접혔을 때 표시되는 미니 툴바
class _MiniToolbar extends StatefulWidget {
  final RxBool show;
  final RxDouble fractionX;
  final RxBool dragging;
  final SessionID sessionId;
  final BorderRadius borderRadius;

  const _MiniToolbar({
    Key? key,
    required this.show,
    required this.fractionX,
    required this.dragging,
    required this.sessionId,
    required this.borderRadius,
  }) : super(key: key);

  @override
  State<_MiniToolbar> createState() => _MiniToolbarState();
}

class _MiniToolbarState extends State<_MiniToolbar> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => widget.show.value = true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SvgPicture.asset(
          'assets/icons/remote_mini.svg',
          width: 20,
          height: 20,
          colorFilter:
              const ColorFilter.mode(Color(0xFFFEFEFE), BlendMode.srcIn),
        ),
      ),
    );
  }
}

/// 커스텀 툴바 팝업 메뉴 버튼
class _CustomToolbarPopupMenu extends StatefulWidget {
  final String assetName;
  final String tooltip;
  final List<_PopupMenuItem> menuItems;

  const _CustomToolbarPopupMenu({
    Key? key,
    required this.assetName,
    required this.tooltip,
    required this.menuItems,
  }) : super(key: key);

  @override
  State<_CustomToolbarPopupMenu> createState() =>
      _CustomToolbarPopupMenuState();
}

class _CustomToolbarPopupMenuState extends State<_CustomToolbarPopupMenu> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: Duration.zero,
        child: Theme(
          data: Theme.of(context).copyWith(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
          ),
          child: PopupMenuButton<int>(
            tooltip: '', // 기본 "메뉴 표시" 툴팁 비활성화 (외부 Tooltip 사용)
            onSelected: (index) {
              if (index >= 0 && index < widget.menuItems.length) {
                widget.menuItems[index].onTap();
              }
            },
            offset: Offset(0, 40),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            itemBuilder: (context) =>
                widget.menuItems.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return PopupMenuItem<int>(
                value: index,
                height: 40,
                padding: EdgeInsets.zero,
                mouseCursor: SystemMouseCursors.click,
                child: _HoverMenuItem(
                  assetPath: item.assetPath,
                  text: item.text,
                  iconColor: item.iconColor,
                ),
              );
            }).toList(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _isHovered ? Colors.grey[100] : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: SvgPicture.asset(
                  widget.assetName,
                  width: 20,
                  height: 20,
                  colorFilter: svgColor(Colors.grey[700]!),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 2차 메뉴 아이템 호버 효과 위젯
class _HoverMenuItem extends StatefulWidget {
  final String? assetPath;
  final String text;
  final Color? iconColor;

  const _HoverMenuItem({
    Key? key,
    this.assetPath,
    required this.text,
    this.iconColor,
  }) : super(key: key);

  @override
  State<_HoverMenuItem> createState() => _HoverMenuItemState();
}

class _HoverMenuItemState extends State<_HoverMenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _isHovered ? const Color(0xFFEFF1FF) : Colors.transparent,
          border: _isHovered
              ? Border.all(color: const Color(0xFFCDD3FF), width: 1)
              : Border.all(color: Colors.transparent, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if (widget.assetPath != null) ...[
              SvgPicture.asset(
                widget.assetPath!,
                width: 20,
                height: 20,
                colorFilter: svgColor(widget.iconColor ?? Colors.grey[700]!),
              ),
              const SizedBox(width: 8),
            ],
            Text(widget.text,
                style: TextStyle(fontSize: 13, color: widget.iconColor)),
          ],
        ),
      ),
    );
  }
}
