import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/common/widgets/toolbar.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/mobile/widgets/floating_mouse.dart';
import 'package:flutter_hbb/mobile/widgets/floating_mouse_widgets.dart';
import 'package:flutter_hbb/mobile/widgets/gesture_help.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../common.dart';
import '../../common/widgets/cm_custom_toggle.dart';
import '../../common/widgets/overlay.dart';
import '../../common/widgets/dialog.dart';
import '../../common/widgets/remote_input.dart';
import '../../models/input_model.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../../utils/image.dart';
import '../widgets/dialog.dart';
import '../widgets/toolbar_overlay.dart';
import 'file_manager_page.dart';

final initText = '1' * 1024;

// Workaround for Android (default input method, Microsoft SwiftKey keyboard) when using physical keyboard.
// When connecting a physical keyboard, `KeyEvent.physicalKey.usbHidUsage` are wrong is using Microsoft SwiftKey keyboard.
// https://github.com/flutter/flutter/issues/159384
// https://github.com/flutter/flutter/issues/159383
void _disableAndroidSoftKeyboard({bool? isKeyboardVisible}) {
  if (isAndroid) {
    if (isKeyboardVisible != true) {
      // `enable_soft_keyboard` will be set to `true` when clicking the keyboard icon, in `openKeyboard()`.
      gFFI.invokeMethod("enable_soft_keyboard", false);
    }
  }
}

class RemotePage extends StatefulWidget {
  RemotePage(
      {Key? key,
      required this.id,
      this.password,
      this.isSharedPassword,
      this.forceRelay})
      : super(key: key);

  final String id;
  final String? password;
  final bool? isSharedPassword;
  final bool? forceRelay;

  @override
  State<RemotePage> createState() => _RemotePageState(id);
}

class _RemotePageState extends State<RemotePage> with WidgetsBindingObserver {
  Timer? _timer;
  final _showBar = (!isWebDesktop).obs;
  bool _showGestureHelp = false;
  String _value = '';
  Orientation? _currentOrientation;
  double _viewInsetsBottom = 0;

  Timer? _timerDidChangeMetrics;

  final _blockableOverlayState = BlockableOverlayState();

  final keyboardVisibilityController = KeyboardVisibilityController();
  late final StreamSubscription<bool> keyboardSubscription;
  final FocusNode _mobileFocusNode = FocusNode();
  final FocusNode _physicalFocusNode = FocusNode();
  var _showEdit = false; // use soft keyboard

  // Voice call state
  final _voiceCallMicOn = true.obs;
  final _voiceCallSoundOn = true.obs;
  String _savedVoiceCallMicDevice = '';

  // Recording state
  Timer? _recordingTimer;
  final _recordingSeconds = 0.obs;
  final _recordingPaused = false.obs;
  final _recordingSound = true.obs;

  // Fullscreen (view style) state
  final _isOriginalViewStyle = false.obs;

  InputModel get inputModel => gFFI.inputModel;
  SessionID get sessionId => gFFI.sessionId;

  final TextEditingController _textController =
      TextEditingController(text: initText);

  _RemotePageState(String id) {
    initSharedStates(id);
    gFFI.chatModel.voiceCallStatus.value = VoiceCallStatus.notStarted;
    gFFI.dialogManager.loadMobileActionsOverlayVisible();
  }

  @override
  void initState() {
    super.initState();
    gFFI.ffiModel.updateEventListener(sessionId, widget.id);
    gFFI.start(
      widget.id,
      password: widget.password,
      isSharedPassword: widget.isSharedPassword,
      forceRelay: widget.forceRelay,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
      gFFI.dialogManager
          .showLoading(translate('Connecting...'), onCancel: closeConnection);
    });
    if (!isWeb) {
      WakelockPlus.enable();
    }
    _physicalFocusNode.requestFocus();
    gFFI.inputModel.listenToMouse(true);
    gFFI.qualityMonitorModel.checkShowQualityMonitor(sessionId);
    keyboardSubscription =
        keyboardVisibilityController.onChange.listen(onSoftKeyboardChanged);
    gFFI.chatModel
        .changeCurrentKey(MessageKey(widget.id, ChatModel.clientModeID));
    _blockableOverlayState.applyFfi(gFFI);
    // Voice call status listener
    gFFI.chatModel.voiceCallStatus.listen(_onVoiceCallStatusChanged);
    // Recording model listener
    gFFI.recordingModel.addListener(_onRecordingChanged);
    gFFI.imageModel.addCallbackOnFirstImage((String peerId) {
      gFFI.recordingModel
          .updateStatus(bind.sessionGetIsRecording(sessionId: gFFI.sessionId));
      if (gFFI.recordingModel.start) {
        showToast(translate('Automatically record outgoing sessions'));
      }
      _disableAndroidSoftKeyboard(
          isKeyboardVisible: keyboardVisibilityController.isVisible);
      _initViewStyleState();
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    // https://github.com/flutter/flutter/issues/64935
    super.dispose();
    gFFI.dialogManager.hideMobileActionsOverlay(store: false);
    gFFI.inputModel.listenToMouse(false);
    gFFI.imageModel.disposeImage();
    gFFI.cursorModel.disposeImages();
    await gFFI.invokeMethod("enable_soft_keyboard", true);
    _mobileFocusNode.dispose();
    _physicalFocusNode.dispose();
    await gFFI.close();
    _timer?.cancel();
    _timerDidChangeMetrics?.cancel();
    _recordingTimer?.cancel();
    gFFI.recordingModel.removeListener(_onRecordingChanged);
    gFFI.dialogManager.dismissAll();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    if (!isWeb) {
      await WakelockPlus.disable();
    }
    await keyboardSubscription.cancel();
    removeSharedStates(widget.id);
    // `on_voice_call_closed` should be called when the connection is ended.
    // The inner logic of `on_voice_call_closed` will check if the voice call is active.
    // Only one client is considered here for now.
    gFFI.chatModel.onVoiceCallClosed("End connetion");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      trySyncClipboard();
    }
  }

  // For client side
  // When swithing from other app to this app, try to sync clipboard.
  void trySyncClipboard() {
    gFFI.invokeMethod("try_sync_clipboard");
  }

  @override
  void didChangeMetrics() {
    // If the soft keyboard is visible and the canvas has been changed(panned or scaled)
    // Don't try reset the view style and focus the cursor.
    if (gFFI.cursorModel.lastKeyboardIsVisible &&
        gFFI.canvasModel.isMobileCanvasChanged) {
      return;
    }

    final newBottom = MediaQueryData.fromView(ui.window).viewInsets.bottom;
    _timerDidChangeMetrics?.cancel();
    _timerDidChangeMetrics = Timer(Duration(milliseconds: 100), () async {
      // We need this comparation because poping up the floating action will also trigger `didChangeMetrics()`.
      if (newBottom != _viewInsetsBottom) {
        gFFI.canvasModel.mobileFocusCanvasCursor();
        _viewInsetsBottom = newBottom;
      }
    });
  }

  // to-do: It should be better to use transparent color instead of the bgColor.
  // But for now, the transparent color will cause the canvas to be white.
  // I'm sure that the white color is caused by the Overlay widget in BlockableOverlay.
  // But I don't know why and how to fix it.
  Widget emptyOverlay(Color bgColor) => BlockableOverlay(
        /// the Overlay key will be set with _blockableOverlayState in BlockableOverlay
        /// see override build() in [BlockableOverlay]
        state: _blockableOverlayState,
        underlying: Container(
          color: bgColor,
        ),
      );

  void onSoftKeyboardChanged(bool visible) {
    if (!visible) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
      // [pi.version.isNotEmpty] -> check ready or not, avoid login without soft-keyboard
      if (gFFI.chatModel.chatWindowOverlayEntry == null &&
          gFFI.ffiModel.pi.version.isNotEmpty) {
        gFFI.invokeMethod("enable_soft_keyboard", false);
      }
    } else {
      _timer?.cancel();
      _timer = Timer(kMobileDelaySoftKeyboardFocus, () {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
            overlays: SystemUiOverlay.values);
        _mobileFocusNode.requestFocus();
      });
    }
    // update for Scaffold
    setState(() {});
  }

  void _onVoiceCallStatusChanged(VoiceCallStatus status) async {
    if (status == VoiceCallStatus.connected ||
        status == VoiceCallStatus.waitingForResponse) {
      _savedVoiceCallMicDevice =
          await bind.getVoiceCallInputDevice(isCm: false);
      if (_savedVoiceCallMicDevice.isEmpty) {
        final devices = (await bind.mainGetSoundInputs()).toList();
        if (devices.isNotEmpty) {
          _savedVoiceCallMicDevice = devices.first;
        }
      }
      _voiceCallMicOn.value = true;
      _voiceCallSoundOn.value = true;
    }
  }

  void _toggleVoiceCallMic() async {
    _voiceCallMicOn.value = !_voiceCallMicOn.value;
    if (_voiceCallMicOn.value) {
      await bind.setVoiceCallInputDevice(
          isCm: false, device: _savedVoiceCallMicDevice);
    } else {
      await bind.setVoiceCallInputDevice(isCm: false, device: '');
    }
  }

  void _toggleVoiceCallSound() {
    _voiceCallSoundOn.value = !_voiceCallSoundOn.value;
    bind.sessionToggleOption(
      sessionId: sessionId,
      value: 'disable-audio',
    );
  }

  void _endVoiceCall() {
    bind.sessionCloseVoiceCall(sessionId: sessionId);
  }

  void _startVoiceCall() async {
    if (isAndroid) {
      final hasPermission =
          await AndroidPermissionManager.check("android.permission.RECORD_AUDIO");
      if (!hasPermission) {
        final granted =
            await AndroidPermissionManager.request("android.permission.RECORD_AUDIO");
        if (!granted) {
          showToast('마이크 권한이 필요합니다.');
          return;
        }
      }
    }
    bind.sessionRequestVoiceCall(sessionId: sessionId);
  }

  // ===== Recording =====

  void _onRecordingChanged() {
    final isRecording = gFFI.recordingModel.start;
    if (isRecording && _recordingTimer == null) {
      _startRecordingTimer();
    } else if (!isRecording && _recordingTimer != null) {
      _stopRecordingTimer();
    }
    // UI updates handled by ListenableBuilder + Obx in toolbar overlay
  }

  void _startRecordingTimer() {
    _recordingSeconds.value = 0;
    _recordingPaused.value = false;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
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

  void _stopRecording() {
    gFFI.recordingModel.toggle();
  }

  void _toggleRecordingPause() {
    _recordingPaused.value = !_recordingPaused.value;
  }

  void _toggleRecordingSound() {
    _recordingSound.value = !_recordingSound.value;
  }

  // ===== View Mode (view-only toggle) =====

  void _toggleViewMode() async {
    await bind.sessionToggleOption(
      sessionId: sessionId,
      value: kOptionToggleViewOnly,
    );
    final viewOnly = await bind.sessionGetToggleOption(
      sessionId: sessionId,
      arg: kOptionToggleViewOnly,
    );
    gFFI.ffiModel.setViewOnly(
        widget.id, viewOnly ?? !gFFI.ffiModel.viewOnly);
  }

  // ===== Fullscreen (view style toggle) =====

  Future<void> _initViewStyleState() async {
    final current =
        await bind.sessionGetViewStyle(sessionId: sessionId) ?? '';
    _isOriginalViewStyle.value = (current == kRemoteViewStyleOriginal);
  }

  Future<void> _toggleViewStyleFullscreen() async {
    final current =
        await bind.sessionGetViewStyle(sessionId: sessionId) ?? '';
    if (current == kRemoteViewStyleOriginal) {
      await bind.sessionSetViewStyle(
          sessionId: sessionId, value: kRemoteViewStyleAdaptive);
      _isOriginalViewStyle.value = false;
    } else {
      await bind.sessionSetViewStyle(
          sessionId: sessionId, value: kRemoteViewStyleOriginal);
      _isOriginalViewStyle.value = true;
    }
    gFFI.canvasModel.updateViewStyle();
  }

  void _handleIOSSoftKeyboardInput(String newValue) {
    var oldValue = _value;
    _value = newValue;
    var i = newValue.length - 1;
    for (; i >= 0 && newValue[i] != '1'; --i) {}
    var j = oldValue.length - 1;
    for (; j >= 0 && oldValue[j] != '1'; --j) {}
    if (i < j) j = i;
    var subNewValue = newValue.substring(j + 1);
    var subOldValue = oldValue.substring(j + 1);

    // get common prefix of subNewValue and subOldValue
    var common = 0;
    for (;
        common < subOldValue.length &&
            common < subNewValue.length &&
            subNewValue[common] == subOldValue[common];
        ++common) {}

    // get newStr from subNewValue
    var newStr = "";
    if (subNewValue.length > common) {
      newStr = subNewValue.substring(common);
    }

    // Set the value to the old value and early return if is still composing. (1 && 2)
    // 1. The composing range is valid
    // 2. The new string is shorter than the composing range.
    if (_textController.value.isComposingRangeValid) {
      final composingLength = _textController.value.composing.end -
          _textController.value.composing.start;
      if (composingLength > newStr.length) {
        _value = oldValue;
        return;
      }
    }

    // Delete the different part in the old value.
    for (i = 0; i < subOldValue.length - common; ++i) {
      inputModel.inputKey('VK_BACK');
    }

    // Input the new string.
    if (newStr.length > 1) {
      bind.sessionInputString(sessionId: sessionId, value: newStr);
    } else {
      inputChar(newStr);
    }
  }

  void _handleNonIOSSoftKeyboardInput(String newValue) {
    var oldValue = _value;
    _value = newValue;
    if (oldValue.isNotEmpty &&
        newValue.isNotEmpty &&
        oldValue[0] == '1' &&
        newValue[0] != '1') {
      // clipboard
      oldValue = '';
    }
    if (newValue.length == oldValue.length) {
      // ?
    } else if (newValue.length < oldValue.length) {
      final char = 'VK_BACK';
      inputModel.inputKey(char);
    } else {
      final content = newValue.substring(oldValue.length);
      if (content.length > 1) {
        if (oldValue != '' &&
            content.length == 2 &&
            (content == '""' ||
                content == '()' ||
                content == '[]' ||
                content == '<>' ||
                content == "{}" ||
                content == '”“' ||
                content == '《》' ||
                content == '（）' ||
                content == '【】')) {
          // can not only input content[0], because when input ], [ are also auo insert, which cause ] never be input
          bind.sessionInputString(sessionId: sessionId, value: content);
          openKeyboard();
          return;
        }
        bind.sessionInputString(sessionId: sessionId, value: content);
      } else {
        inputChar(content);
      }
    }
  }

  // handle mobile virtual keyboard
  void handleSoftKeyboardInput(String newValue) {
    if (isIOS) {
      _handleIOSSoftKeyboardInput(newValue);
    } else {
      _handleNonIOSSoftKeyboardInput(newValue);
    }
  }

  void inputChar(String char) {
    if (char == '\n') {
      char = 'VK_RETURN';
    } else if (char == ' ') {
      char = 'VK_SPACE';
    }
    inputModel.inputKey(char);
  }

  void openKeyboard() {
    gFFI.invokeMethod("enable_soft_keyboard", true);
    // destroy first, so that our _value trick can work
    _value = initText;
    _textController.text = _value;
    setState(() => _showEdit = false);
    _timer?.cancel();
    _timer = Timer(kMobileDelaySoftKeyboard, () {
      // show now, and sleep a while to requestFocus to
      // make sure edit ready, so that keyboard won't show/hide/show/hide happen
      setState(() => _showEdit = true);
      _timer?.cancel();
      _timer = Timer(kMobileDelaySoftKeyboardFocus, () {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
            overlays: SystemUiOverlay.values);
        _mobileFocusNode.requestFocus();
      });
    });
  }

  Widget _bottomWidget() => _showGestureHelp
      ? getGestureHelp()
      : Offstage();

  @override
  Widget build(BuildContext context) {
    final keyboardIsVisible =
        keyboardVisibilityController.isVisible && _showEdit;
    return WillPopScope(
      onWillPop: () async {
        clientClose(sessionId, gFFI);
        return false;
      },
      child: Scaffold(
          // workaround for https://github.com/rustdesk/rustdesk/issues/3131
          floatingActionButtonLocation: keyboardIsVisible
              ? FABLocation(FloatingActionButtonLocation.endFloat, 0, -35)
              : null,
          floatingActionButton: !keyboardIsVisible
              ? null
              : FloatingActionButton(
                  mini: false,
                  child: Icon(Icons.expand_more, color: Colors.white),
                  backgroundColor: MyTheme.accent,
                  onPressed: () {
                    setState(() {
                      _showEdit = false;
                      gFFI.invokeMethod("enable_soft_keyboard", false);
                      _mobileFocusNode.unfocus();
                      _physicalFocusNode.requestFocus();
                    });
                  }),
          bottomNavigationBar: _showGestureHelp
              ? null
              : Obx(() => Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      gFFI.ffiModel.pi.isSet.isTrue &&
                              gFFI.ffiModel.waitForFirstImage.isTrue
                          ? emptyOverlay(MyTheme.canvasColor)
                          : () {
                              gFFI.ffiModel.tryShowAndroidActionsOverlay();
                              return Offstage();
                            }(),
                      gFFI.ffiModel.pi.isSet.isFalse
                          ? emptyOverlay(MyTheme.canvasColor)
                          : Offstage(),
                    ],
                  )),
          body: Obx(() {
            // Access Rx values here so Obx reacts to their changes
            final isPhysicalMouse = inputModel.isPhysicalMouse.value;
            final showToolbar = gFFI.ffiModel.pi.isSet.isTrue &&
                gFFI.ffiModel.waitForFirstImage.isFalse &&
                gFFI.ffiModel.pi.displays.isNotEmpty &&
                !_showGestureHelp;
            final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
            final kbVisible = keyboardVisibilityController.isVisible && _showEdit;

            return getRawPointerAndKeyBody(
              Stack(
                children: [
                  // Canvas (same rendering path as working c25b54b)
                  Overlay(
                    initialEntries: [
                      OverlayEntry(builder: (context) {
                        return Container(
                          color: kColorCanvas,
                          child: isWebDesktop
                              ? getBodyForDesktopWithListener()
                              : SafeArea(
                                  child:
                                      OrientationBuilder(builder: (ctx, orientation) {
                                    if (_currentOrientation != orientation) {
                                      Timer(const Duration(milliseconds: 200), () {
                                        gFFI.dialogManager
                                            .resetMobileActionsOverlay(ffi: gFFI);
                                        _currentOrientation = orientation;
                                        gFFI.canvasModel.updateViewStyle();
                                      });
                                    }
                                    return Container(
                                      color: MyTheme.canvasColor,
                                      child: isPhysicalMouse
                                          ? getBodyForMobile()
                                          : RawTouchGestureDetectorRegion(
                                              child: getBodyForMobile(),
                                              ffi: gFFI,
                                            ),
                                    );
                                  }),
                                ),
                        );
                      })
                    ],
                  ),
                  // Toolbar overlay (Positioned - direct Stack child)
                  if (showToolbar && _showBar.value)
                    _buildToolbarOverlay(isPortrait),
                  // Mini button (Positioned - direct Stack child)
                  if (showToolbar && !_showBar.value && !kbVisible)
                    _buildMiniButton(isPortrait),
                  // Gesture help overlay
                  if (_showGestureHelp)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: getGestureHelp(),
                    ),
                ],
              ),
            );
          })),
    );
  }

  Widget getRawPointerAndKeyBody(Widget child) {
    final ffiModel = Provider.of<FfiModel>(context);
    return RawPointerMouseRegion(
      cursor: ffiModel.keyboard ? SystemMouseCursors.none : MouseCursor.defer,
      inputModel: inputModel,
      // Disable RawKeyFocusScope before the connecting is established.
      // The "Delete" key on the soft keyboard may be grabbed when inputting the password dialog.
      child: gFFI.ffiModel.pi.isSet.isTrue
          ? RawKeyFocusScope(
              focusNode: _physicalFocusNode,
              inputModel: inputModel,
              child: child)
          : child,
    );
  }

  // ===== New Overlay Toolbar =====

  Widget _buildToolbarOverlay(bool isPortrait) {
    // Use ListenableBuilder to react to recordingModel changes
    return Positioned(
      left: 0,
      right: 0,
      bottom: 30,
      child: Center(
        child: ListenableBuilder(
          listenable: gFFI.recordingModel,
          builder: (context, child) {
            return Obx(() => _buildToolbarContent(isPortrait));
          },
        ),
      ),
    );
  }

  Widget _buildToolbarContent(bool isPortrait) {
    final ffiModel = Provider.of<FfiModel>(context);
    final voiceCallStatus = gFFI.chatModel.voiceCallStatus.value;
    final isInVoiceCall = voiceCallStatus == VoiceCallStatus.connected;
    final isWaitingVoiceCall =
        voiceCallStatus == VoiceCallStatus.waitingForResponse;
    final isRecording = gFFI.recordingModel.start;

    // File transfer popup items
    final fileItems = <SimpleMenuItem>[
      SimpleMenuItem('File Transfer', () => _openFileTransfer()),
    ];

    // Recording/Screenshot popup items
    final recordItems = <SimpleMenuItem>[
      SimpleMenuItem('Record Screen', () => _toggleRecording()),
      SimpleMenuItem('Screenshot', () => _takeScreenshot()),
    ];

    // Communication popup items
    final commItems = <SimpleMenuItem>[
      SimpleMenuItem('Chat', () => onPressedTextChat(widget.id)),
      if (!isWeb && !Platform.isIOS)
        SimpleMenuItem(
          (isInVoiceCall || isWaitingVoiceCall)
              ? 'End Voice Call'
              : 'Voice Call',
          () => (isInVoiceCall || isWaitingVoiceCall)
              ? _endVoiceCall()
              : _startVoiceCall(),
        ),
      SimpleMenuItem(
        ffiModel.viewOnly ? 'Control Mode' : 'View Mode',
        () => _toggleViewMode(),
      ),
    ];

    // More menu items (desktop-style)
    final moreItems = <SimpleMenuItem>[
      SimpleMenuItem('Display Settings', () {
        setState(() => _showEdit = false);
        showOptions(context, widget.id, gFFI.dialogManager);
      }),
      if (gFFI.ffiModel.isPeerAndroid)
        SimpleMenuItem('Mobile Actions', () {
          gFFI.dialogManager.toggleMobileActionsOverlay(ffi: gFFI);
        }),
      SimpleMenuItem('Restart Remote', () {
        showRestartRemoteDevice(
          gFFI.ffiModel.pi,
          widget.id,
          sessionId,
          gFFI.dialogManager,
        );
      }),
      SimpleMenuItem(
        'Shutdown Remote',
        () => _shutdownRemote(),
        assetPath: 'assets/icons/remote-connection-end.svg',
        iconColor: const Color(0xFFFE3E3E),
      ),
    ];

    // Left group: file, record, comm, keyboard, mouse, more
    final leftButtons = <Widget>[
      // File transfer (popup)
      toolbarPopupButton(
        asset: 'assets/icons/remote_file.svg',
        label: 'File Transfer',
        items: fileItems,
        isPortrait: isPortrait,
      ),
      // Recording/Screenshot (popup) - iOS에서는 불가능하므로 숨김
      if (!Platform.isIOS)
        toolbarPopupButton(
          asset: 'assets/icons/remote_screen.svg',
          label: 'Recording',
          items: recordItems,
          isPortrait: isPortrait,
        ),
      // Communication (popup)
      toolbarPopupButton(
        asset: 'assets/icons/remote_group.svg',
        label: 'Communication',
        items: commItems,
        isPortrait: isPortrait,
      ),
      // Keyboard (popup)
      if (!isWebDesktop && !ffiModel.viewOnly && ffiModel.keyboard)
        toolbarPopupButton(
          asset: 'assets/icons/remote-keyboard.svg',
          label: 'Keyboard Setting',
          items: [
            SimpleMenuItem('Open Keyboard', () => openKeyboard()),
          ],
          isPortrait: isPortrait,
        ),
      // Mouse/Touch mode (popup)
      if (!isWebDesktop &&
          !ffiModel.viewOnly &&
          ffiModel.keyboard &&
          !gFFI.ffiModel.isPeerAndroid)
        toolbarPopupButton(
          asset: 'assets/icons/remote-mouse.svg',
          label: 'Mouse Setting',
          items: [
            SimpleMenuItem('Mouse mode', () {
              if (gFFI.ffiModel.touchMode) {
                gFFI.ffiModel.toggleTouchMode();
                bind.mainSetLocalOption(key: kOptionTouchMode, value: 'N');
              }
              setState(() => _showGestureHelp = true);
            }),
            SimpleMenuItem('Touch mode', () {
              if (!gFFI.ffiModel.touchMode) {
                gFFI.ffiModel.toggleTouchMode();
                bind.mainSetLocalOption(key: kOptionTouchMode, value: 'Y');
              }
              setState(() => _showGestureHelp = true);
            }),
          ],
          isPortrait: isPortrait,
        ),
      // More (desktop-style popup)
      toolbarPopupButton(
        asset: 'assets/icons/remote_more.svg',
        label: 'More',
        items: moreItems,
        isPortrait: isPortrait,
      ),
    ];

    // Right group: fullscreen toggle, fold
    final rightButtons = <Widget>[
      Obx(() => toolbarIconButton(
            asset: _isOriginalViewStyle.value
                ? 'assets/icons/remote_full_restore.svg'
                : 'assets/icons/remote_full.svg',
            onPressed: _toggleViewStyleFullscreen,
            isPressed: _isOriginalViewStyle.value,
          )),
      toolbarIconButton(
        asset: 'assets/icons/remote-fold.svg',
        onPressed: () => _showBar.value = false,
      ),
    ];

    // Voice call controls (second row)
    List<Widget> voiceCallButtons = [];
    if (isInVoiceCall) {
      voiceCallButtons = [
        toolbarIconButton(
          asset: 'assets/icons/remote_voice_call_off.svg',
          bgColor: const Color(0xFFFE3E3E),
          iconColor: Colors.white,
          onPressed: _endVoiceCall,
        ),
        Obx(() => toolbarIconButton(
              asset: _voiceCallMicOn.value
                  ? 'assets/icons/remote_mic.svg'
                  : 'assets/icons/remote_mic_off.svg',
              onPressed: _toggleVoiceCallMic,
            )),
        Obx(() => toolbarIconButton(
              asset: _voiceCallSoundOn.value
                  ? 'assets/icons/remote_sound.svg'
                  : 'assets/icons/remote_sound_off.svg',
              onPressed: _toggleVoiceCallSound,
            )),
      ];
    } else if (isWaitingVoiceCall) {
      voiceCallButtons = [
        toolbarIconButton(
          asset: 'assets/call_wait.svg',
          bgColor: const Color(0xFFF59E0B),
          iconColor: Colors.white,
          onPressed: _endVoiceCall,
        ),
      ];
    }

    if (!isPortrait) {
      // Landscape: separate cards in a single row at bottom
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main toolbar card
          toolbarCard(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...leftButtons,
                toolbarSeparator(),
                ...rightButtons,
              ],
            ),
          ),
          // Recording card
          if (isRecording && !Platform.isIOS) ...[
            const SizedBox(width: 6),
            _buildRecordingBox(),
          ],
          // Voice call card
          if (voiceCallButtons.isNotEmpty) ...[
            const SizedBox(width: 6),
            toolbarCard(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: voiceCallButtons,
              ),
            ),
          ],
        ],
      );
    }

    // Portrait: multi-row at top
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Main toolbar row
        toolbarCard(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...leftButtons,
              toolbarSeparator(),
              ...rightButtons,
            ],
          ),
        ),
        // Recording box (when recording)
        if (isRecording && !Platform.isIOS) ...[
          const SizedBox(height: 6),
          _buildRecordingBox(),
        ],
        // Voice call row (if active)
        if (voiceCallButtons.isNotEmpty) ...[
          const SizedBox(height: 6),
          toolbarCard(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: voiceCallButtons,
            ),
          ),
        ],
      ],
    );
  }

  /// Recording control box (desktop-style)
  Widget _buildRecordingBox() {
    return toolbarCard(
      child: Obx(() => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Stop
              toolbarIconButton(
                asset: 'assets/icons/remote-record-stop.svg',
                onPressed: _stopRecording,
              ),
              // Pause/Resume
              toolbarIconButton(
                asset: _recordingPaused.value
                    ? 'assets/icons/remote-record-start.svg'
                    : 'assets/icons/remote-record-pause.svg',
                onPressed: _toggleRecordingPause,
              ),
              // System sound toggle
              toolbarIconButton(
                asset: _recordingSound.value
                    ? 'assets/icons/remote-record-sound-off.svg'
                    : 'assets/icons/remote-record-sound.svg',
                onPressed: _toggleRecordingSound,
              ),
              const SizedBox(width: 4),
              // Timer
              Text(
                _formatRecordingTime(_recordingSeconds.value),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF5F71FF),
                ),
              ),
              const SizedBox(width: 8),
            ],
          )),
    );
  }

  Widget _buildMiniButton(bool isPortrait) {
    return Positioned(
      left: 0,
      bottom: 30,
      child: miniShowButton(onTap: () => _showBar.value = true),
    );
  }

  void _openFileTransfer() {
    final connToken = bind.sessionGetConnToken(sessionId: gFFI.sessionId);
    final fileFFI = FFI(Uuid().v4obj());
    fileFFI.start(widget.id, isFileTransfer: true, connToken: connToken);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (BuildContext context) => FileManagerPage(
            id: widget.id,
            ffi: fileFFI),
      ),
    );
  }

  void _toggleRecording() {
    gFFI.recordingModel.toggle();
  }

  void _takeScreenshot() {
    bind.sessionTakeScreenshot(
        sessionId: sessionId, display: gFFI.ffiModel.pi.currentDisplay);
  }

  void _shutdownRemote() {
    gFFI.dialogManager.show((setState, close, context) {
      return CustomAlertDialog(
        title: Text(
          translate('Shutdown Remote'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Text(
          translate('Would you like to study remotely?'),
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: dialogButton('Cancel',
                    onPressed: close, isOutline: true),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: dialogButton('OK', onPressed: () {
                  close();
                  closeConnection();
                }),
              ),
            ],
          ),
        ],
      );
    });
  }

  bool get showCursorPaint =>
      !gFFI.ffiModel.isPeerAndroid && !gFFI.canvasModel.cursorEmbedded;

  Widget getBodyForMobile() {
    final keyboardIsVisible = keyboardVisibilityController.isVisible;
    return Container(
        color: MyTheme.canvasColor,
        child: Stack(children: () {
          final paints = [
            ImagePaint(ffiModel: gFFI.ffiModel),
            Positioned(
              top: 10,
              right: 10,
              child: QualityMonitor(gFFI.qualityMonitorModel),
            ),
            KeyHelpTools(
                keyboardIsVisible: keyboardIsVisible,
                showGestureHelp: _showGestureHelp),
            SizedBox(
              width: 0,
              height: 0,
              child: !_showEdit
                  ? Container()
                  : TextFormField(
                      textInputAction: TextInputAction.newline,
                      autocorrect: false,
                      // Flutter 3.16.9 Android.
                      // `enableSuggestions` causes secure keyboard to be shown.
                      // https://github.com/flutter/flutter/issues/139143
                      // https://github.com/flutter/flutter/issues/146540
                      // enableSuggestions: false,
                      autofocus: true,
                      focusNode: _mobileFocusNode,
                      maxLines: null,
                      controller: _textController,
                      // trick way to make backspace work always
                      keyboardType: TextInputType.multiline,
                      // `onChanged` may be called depending on the input method if this widget is wrapped in
                      // `Focus(onKeyEvent: ..., child: ...)`
                      // For `Backspace` button in the soft keyboard:
                      // en/fr input method:
                      //      1. The button will not trigger `onKeyEvent` if the text field is not empty.
                      //      2. The button will trigger `onKeyEvent` if the text field is empty.
                      // ko/zh/ja input method: the button will trigger `onKeyEvent`
                      //                     and the event will not popup if `KeyEventResult.handled` is returned.
                      onChanged: handleSoftKeyboardInput,
                    ).workaroundFreezeLinuxMint(),
            ),
          ];
          if (showCursorPaint) {
            paints.add(CursorPaint(widget.id));
          }
          if (gFFI.ffiModel.touchMode) {
            paints.add(FloatingMouse(
              ffi: gFFI,
            ));
          } else {
            paints.add(FloatingMouseWidgets(
              ffi: gFFI,
            ));
          }
          return paints;
        }()));
  }

  Widget getBodyForDesktopWithListener() {
    final ffiModel = Provider.of<FfiModel>(context);
    var paints = <Widget>[ImagePaint(ffiModel: ffiModel)];
    if (showCursorPaint) {
      final cursor = bind.sessionGetToggleOptionSync(
          sessionId: sessionId, arg: 'show-remote-cursor');
      if (ffiModel.keyboard || cursor) {
        paints.add(CursorPaint(widget.id));
      }
    }
    return Container(
        color: MyTheme.canvasColor, child: Stack(children: paints));
  }

  List<TTextMenu> _getMobileActionMenus() {
    if (gFFI.ffiModel.pi.platform != kPeerPlatformAndroid ||
        !gFFI.ffiModel.keyboard) {
      return [];
    }
    final enabled = versionCmp(gFFI.ffiModel.pi.version, '1.2.7') >= 0;
    if (!enabled) return [];
    return [
      TTextMenu(
        child: Text(translate('Back')),
        onPressed: () => gFFI.inputModel.onMobileBack(),
      ),
      TTextMenu(
        child: Text(translate('Home')),
        onPressed: () => gFFI.inputModel.onMobileHome(),
      ),
      TTextMenu(
        child: Text(translate('Apps')),
        onPressed: () => gFFI.inputModel.onMobileApps(),
      ),
      TTextMenu(
        child: Text(translate('Volume up')),
        onPressed: () => gFFI.inputModel.onMobileVolumeUp(),
      ),
      TTextMenu(
        child: Text(translate('Volume down')),
        onPressed: () => gFFI.inputModel.onMobileVolumeDown(),
      ),
      TTextMenu(
        child: Text(translate('Power')),
        onPressed: () => gFFI.inputModel.onMobilePower(),
      ),
    ];
  }

  void showActions(String id) async {
    final size = MediaQuery.of(context).size;
    final x = 120.0;
    final y = size.height;
    final mobileActionMenus = _getMobileActionMenus();
    final menus = toolbarControls(context, id, gFFI);

    final List<PopupMenuEntry<int>> more = [
      ...mobileActionMenus
          .asMap()
          .entries
          .map((e) =>
              PopupMenuItem<int>(child: e.value.getChild(), value: e.key))
          .toList(),
      if (mobileActionMenus.isNotEmpty) PopupMenuDivider(),
      ...menus
          .asMap()
          .entries
          .map((e) => PopupMenuItem<int>(
              child: e.value.getChild(),
              value: e.key + mobileActionMenus.length))
          .toList(),
    ];
    () async {
      var index = await showMenu(
        context: context,
        position: RelativeRect.fromLTRB(x, y, x, y),
        items: more,
        elevation: 8,
      );
      if (index != null) {
        if (index < mobileActionMenus.length) {
          mobileActionMenus[index].onPressed?.call();
        } else if (index < mobileActionMenus.length + more.length) {
          menus[index - mobileActionMenus.length].onPressed?.call();
        }
      }
    }();
  }

  onPressedTextChat(String id) {
    gFFI.chatModel.changeCurrentKey(MessageKey(id, ChatModel.clientModeID));
    gFFI.chatModel.toggleChatOverlay();
  }

  showChatOptions(String id) async {
    onPressVoiceCall() => bind.sessionRequestVoiceCall(sessionId: sessionId);
    onPressEndVoiceCall() => bind.sessionCloseVoiceCall(sessionId: sessionId);

    makeTextMenu(String label, Widget icon, VoidCallback onPressed,
            {TextStyle? labelStyle}) =>
        TTextMenu(
          child: Text(translate(label), style: labelStyle),
          trailingIcon: Transform.scale(
            scale: (isDesktop || isWebDesktop) ? 0.8 : 1,
            child: IgnorePointer(
              child: IconButton(
                onPressed: null,
                icon: icon,
              ),
            ),
          ),
          onPressed: onPressed,
        );

    final isInVoice = [
      VoiceCallStatus.waitingForResponse,
      VoiceCallStatus.connected
    ].contains(gFFI.chatModel.voiceCallStatus.value);
    final menus = [
      makeTextMenu('Text chat', Icon(Icons.message, color: MyTheme.accent),
          () => onPressedTextChat(widget.id)),
      isInVoice
          ? makeTextMenu(
              'End voice call',
              SvgPicture.asset(
                'assets/call_wait.svg',
                colorFilter:
                    ColorFilter.mode(Colors.redAccent, BlendMode.srcIn),
              ),
              onPressEndVoiceCall,
              labelStyle: TextStyle(color: Colors.redAccent))
          : makeTextMenu(
              'Voice call',
              SvgPicture.asset(
                'assets/call_wait.svg',
                colorFilter: ColorFilter.mode(MyTheme.accent, BlendMode.srcIn),
              ),
              onPressVoiceCall),
    ];

    final menuItems = menus
        .asMap()
        .entries
        .map((e) => PopupMenuItem<int>(child: e.value.getChild(), value: e.key))
        .toList();
    Future.delayed(Duration.zero, () async {
      final size = MediaQuery.of(context).size;
      final x = 120.0;
      final y = size.height;
      var index = await showMenu(
        context: context,
        position: RelativeRect.fromLTRB(x, y, x, y),
        items: menuItems,
        elevation: 8,
      );
      if (index != null && index < menus.length) {
        menus[index].onPressed?.call();
      }
    });
  }

  /// aka changeTouchMode
  Widget getGestureHelp() {
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16),
        topRight: Radius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      elevation: 8,
      child: SingleChildScrollView(
          controller: ScrollController(),
          padding: EdgeInsets.symmetric(vertical: 10),
          child: GestureHelp(
            touchMode: gFFI.ffiModel.touchMode,
            onTouchModeChange: (t) {
              gFFI.ffiModel.toggleTouchMode();
              final v = gFFI.ffiModel.touchMode ? 'Y' : 'N';
              bind.mainSetLocalOption(key: kOptionTouchMode, value: v);
            },
            virtualMouseMode: gFFI.ffiModel.virtualMouseMode,
            onClose: () {
              setState(() {
                _showGestureHelp = false;
              });
            },
          )),
    );
  }

  // * Currently mobile does not enable map mode
  // void changePhysicalKeyboardInputMode() async {
  //   var current = await bind.sessionGetKeyboardMode(id: widget.id) ?? "legacy";
  //   gFFI.dialogManager.show((setState, close) {
  //     void setMode(String? v) async {
  //       await bind.sessionSetKeyboardMode(id: widget.id, value: v ?? "");
  //       setState(() => current = v ?? '');
  //       Future.delayed(Duration(milliseconds: 300), close);
  //     }
  //
  //     return CustomAlertDialog(
  //         title: Text(translate('Physical Keyboard Input Mode')),
  //         content: Column(mainAxisSize: MainAxisSize.min, children: [
  //           getRadio('Legacy mode', 'legacy', current, setMode),
  //           getRadio('Map mode', 'map', current, setMode),
  //         ]));
  //   }, clickMaskDismiss: true);
  // }
}

class KeyHelpTools extends StatefulWidget {
  final bool keyboardIsVisible;
  final bool showGestureHelp;

  /// need to show by external request, etc [keyboardIsVisible] or [changeTouchMode]
  bool get requestShow => keyboardIsVisible || showGestureHelp;

  KeyHelpTools(
      {required this.keyboardIsVisible, required this.showGestureHelp});

  @override
  State<KeyHelpTools> createState() => _KeyHelpToolsState();
}

class _KeyHelpToolsState extends State<KeyHelpTools> {
  var _more = true;
  var _fn = false;
  var _pin = false;
  final _keyboardVisibilityController = KeyboardVisibilityController();
  final _key = GlobalKey();

  InputModel get inputModel => gFFI.inputModel;

  Widget wrap(String text, void Function() onPressed,
      {bool? active, IconData? icon, String? svgIcon}) {
    final Widget child;
    if (svgIcon != null) {
      child = SvgPicture.asset(svgIcon, width: 17, height: 17,
          colorFilter: ColorFilter.mode(Colors.white, BlendMode.srcIn));
    } else if (icon != null) {
      child = Icon(icon, size: 17, color: Colors.white);
    } else {
      child = Text(text,
          style: TextStyle(color: Colors.white, fontSize: 13));
    }
    return TextButton(
        style: TextButton.styleFrom(
          minimumSize: Size(0, 0),
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 9.75),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5.0),
          ),
          backgroundColor: active == true ? MyTheme.accent80 : null,
        ),
        child: child,
        onPressed: onPressed);
  }

  _updateRect() {
    RenderObject? renderObject = _key.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      Offset pos = renderObject.localToGlobal(Offset.zero);
      gFFI.cursorModel.keyHelpToolsVisibilityChanged(
          Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height),
          widget.keyboardIsVisible);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasModifierOn = inputModel.ctrl ||
        inputModel.alt ||
        inputModel.shift ||
        inputModel.command;

    if (!_pin && !hasModifierOn && !widget.requestShow) {
      gFFI.cursorModel
          .keyHelpToolsVisibilityChanged(null, widget.keyboardIsVisible);
      return Offstage();
    }
    final size = MediaQuery.of(context).size;

    final pi = gFFI.ffiModel.pi;
    final isMac = pi.platform == kPeerPlatformMacOS;
    final isWin = pi.platform == kPeerPlatformWindows;
    final isLinux = pi.platform == kPeerPlatformLinux;
    final modifiers = <Widget>[
      wrap('Ctrl ', () {
        setState(() => inputModel.ctrl = !inputModel.ctrl);
      }, active: inputModel.ctrl),
      wrap(' Alt ', () {
        setState(() => inputModel.alt = !inputModel.alt);
      }, active: inputModel.alt),
      wrap('Shift', () {
        setState(() => inputModel.shift = !inputModel.shift);
      }, active: inputModel.shift),
      wrap(isMac ? ' Cmd ' : ' Win ', () {
        setState(() => inputModel.command = !inputModel.command);
      }, active: inputModel.command),
    ];
    final keys = <Widget>[
      wrap(
          ' Fn ',
          () => setState(
                () {
                  _fn = !_fn;
                  if (_fn) {
                    _more = false;
                  }
                },
              ),
          active: _fn),
      wrap(
          '',
          () => setState(
                () => _pin = !_pin,
              ),
          active: _pin,
          svgIcon: 'assets/icons/keyboard-tool-pin.svg'),
      wrap(
          '',
          () => setState(
                () {
                  _more = !_more;
                  if (_more) {
                    _fn = false;
                  }
                },
              ),
          active: _more,
          icon: _more ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
    ];
    final fn = <Widget>[
      SizedBox(width: 9999),
    ];
    for (var i = 1; i <= 12; ++i) {
      final name = 'F$i';
      fn.add(wrap(name, () {
        inputModel.inputKey('VK_$name');
      }));
    }
    final more = <Widget>[
      SizedBox(width: 9999),
      wrap('Esc', () {
        inputModel.inputKey('VK_ESCAPE');
      }),
      wrap('Tab', () {
        inputModel.inputKey('VK_TAB');
      }),
      wrap('Home', () {
        inputModel.inputKey('VK_HOME');
      }),
      wrap('End', () {
        inputModel.inputKey('VK_END');
      }),
      wrap('Ins', () {
        inputModel.inputKey('VK_INSERT');
      }),
      wrap('Del', () {
        inputModel.inputKey('VK_DELETE');
      }),
      wrap('PgUp', () {
        inputModel.inputKey('VK_PRIOR');
      }),
      wrap('PgDn', () {
        inputModel.inputKey('VK_NEXT');
      }),
      // to-do: support PrtScr on Mac
      if (isWin || isLinux)
        wrap('PrtScr', () {
          inputModel.inputKey('VK_SNAPSHOT');
        }),
      if (isWin || isLinux)
        wrap('ScrollLock', () {
          inputModel.inputKey('VK_SCROLL');
        }),
      if (isWin || isLinux)
        wrap('Pause', () {
          inputModel.inputKey('VK_PAUSE');
        }),
      if (isWin || isLinux)
        // Maybe it's better to call it "Menu"
        // https://en.wikipedia.org/wiki/Menu_key
        wrap('Menu', () {
          inputModel.inputKey('Apps');
        }),
      wrap('Enter', () {
        inputModel.inputKey('VK_ENTER');
      }),
      SizedBox(width: 9999),
      wrap('', () {
        inputModel.inputKey('VK_LEFT');
      }, icon: Icons.keyboard_arrow_left),
      wrap('', () {
        inputModel.inputKey('VK_UP');
      }, icon: Icons.keyboard_arrow_up),
      wrap('', () {
        inputModel.inputKey('VK_DOWN');
      }, icon: Icons.keyboard_arrow_down),
      wrap('', () {
        inputModel.inputKey('VK_RIGHT');
      }, icon: Icons.keyboard_arrow_right),
      wrap(isMac ? 'Cmd+C' : 'Ctrl+C', () {
        sendPrompt(isMac, 'VK_C');
      }),
      wrap(isMac ? 'Cmd+V' : 'Ctrl+V', () {
        sendPrompt(isMac, 'VK_V');
      }),
      wrap(isMac ? 'Cmd+S' : 'Ctrl+S', () {
        sendPrompt(isMac, 'VK_S');
      }),
    ];
    final space = size.width > 320 ? 4.0 : 2.0;
    // 500 ms is long enough for this widget to be built!
    Future.delayed(Duration(milliseconds: 500), () {
      _updateRect();
    });
    return ClipRRect(
        key: _key,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: Colors.black.withValues(alpha: 0.3),
            padding: EdgeInsets.only(
                top: _keyboardVisibilityController.isVisible ? 24 : 4, bottom: 8),
            child: Wrap(
              spacing: space,
              runSpacing: space,
              children: <Widget>[SizedBox(width: 9999)] +
                  modifiers +
                  keys +
                  (_fn ? fn : []) +
                  (_more ? more : []),
            ),
          ),
        ));
  }
}

class ImagePaint extends StatelessWidget {
  final FfiModel ffiModel;
  ImagePaint({Key? key, required this.ffiModel}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final m = Provider.of<ImageModel>(context);
    final c = Provider.of<CanvasModel>(context);
    var s = c.scale;
    if (ffiModel.isPeerLinux) {
      final displays = ffiModel.pi.getCurDisplays();
      if (displays.isNotEmpty) {
        s = s / displays[0].scale;
      }
    }
    final adjust = c.getAdjustY();
    return CustomPaint(
      painter: ImagePainter(
          image: m.image, x: c.x / s, y: (c.y + adjust) / s, scale: s),
    );
  }
}

class CursorPaint extends StatelessWidget {
  late final String id;
  CursorPaint(this.id);

  @override
  Widget build(BuildContext context) {
    final m = Provider.of<CursorModel>(context);
    final c = Provider.of<CanvasModel>(context);
    final ffiModel = Provider.of<FfiModel>(context);
    final s = c.scale;
    double hotx = m.hotx;
    double hoty = m.hoty;
    var image = m.image;
    if (image == null) {
      if (preDefaultCursor.image != null) {
        image = preDefaultCursor.image;
        hotx = preDefaultCursor.image!.width / 2;
        hoty = preDefaultCursor.image!.height / 2;
      }
    }
    if (preForbiddenCursor.image != null &&
        !ffiModel.viewOnly &&
        !ffiModel.keyboard &&
        !ShowRemoteCursorState.find(id).value) {
      image = preForbiddenCursor.image;
      hotx = preForbiddenCursor.image!.width / 2;
      hoty = preForbiddenCursor.image!.height / 2;
    }
    if (image == null) {
      return Offstage();
    }

    final minSize = 12.0;
    double mins =
        minSize / (image.width > image.height ? image.width : image.height);
    double factor = 1.0;
    if (s < mins) {
      factor = s / mins;
    }
    final s2 = s < mins ? mins : s;
    final adjust = c.getAdjustY();
    return CustomPaint(
      painter: ImagePainter(
          image: image,
          x: (m.x - hotx) * factor + c.x / s2,
          y: (m.y - hoty) * factor + (c.y + adjust) / s2,
          scale: s2),
    );
  }
}

void showOptions(
    BuildContext context, String id, OverlayDialogManager dialogManager) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => MobileDisplaySettingsPage(id: id),
    ),
  );
}

class MobileDisplaySettingsPage extends StatefulWidget {
  final String id;
  const MobileDisplaySettingsPage({Key? key, required this.id}) : super(key: key);

  @override
  State<MobileDisplaySettingsPage> createState() => _MobileDisplaySettingsPageState();
}

class _MobileDisplaySettingsPageState extends State<MobileDisplaySettingsPage> {
  static const Color _titleColor = Color(0xFF454447);
  static const Color _labelColor = Color(0xFF646368);
  static const Color _accentColor = Color(0xFF5F71FF);

  List<TRadioMenu<String>> _viewStyleRadios = [];
  List<TRadioMenu<String>> _imageQualityRadios = [];
  List<TRadioMenu<String>> _codecRadios = [];
  List<TToggleMenu> _cursorToggles = [];
  List<TToggleMenu> _displayToggles = [];
  List<TToggleMenu> _privacyModeList = [];
  RxString? _privacyModeState;
  bool _loaded = false;

  late final RxString _viewStyle;
  late final RxString _imageQuality;
  late final RxString _codec;
  late final RxString _resolution;

  @override
  void initState() {
    super.initState();
    _viewStyle = ''.obs;
    _imageQuality = ''.obs;
    _codec = ''.obs;
    _resolution = ''.obs;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _viewStyleRadios = (await toolbarViewStyle(context, widget.id, gFFI))
        .where((e) => e.value != kRemoteViewStyleCustom)
        .toList();
    _imageQualityRadios = (await toolbarImageQuality(context, widget.id, gFFI))
        .where((e) => e.value != kRemoteImageQualityCustom)
        .toList();
    _codecRadios = await toolbarCodec(context, widget.id, gFFI);
    _cursorToggles = await toolbarCursor(context, widget.id, gFFI);
    _displayToggles = (await toolbarDisplayToggle(context, widget.id, gFFI))
        .where((e) => _extractText(e.child) != translate('Show quality monitor'))
        .toList();

    _privacyModeState = PrivacyModeState.find(widget.id);
    if (gFFI.ffiModel.keyboard && gFFI.ffiModel.pi.features.privacyMode) {
      _privacyModeList = toolbarPrivacyMode(
          _privacyModeState!, context, widget.id, gFFI);
      if (_privacyModeList.length == 1) {
        _displayToggles.add(_privacyModeList[0]);
      }
    }

    // Use defaults as source of truth, fallback to session value
    final sessionView = _viewStyleRadios.isNotEmpty
        ? _viewStyleRadios[0].groupValue : '';
    final sessionQuality = _imageQualityRadios.isNotEmpty
        ? _imageQualityRadios[0].groupValue : '';
    final sessionCodec = _codecRadios.isNotEmpty
        ? _codecRadios[0].groupValue : '';

    final defView = bind.mainGetUserDefaultOption(key: kOptionViewStyle);
    final defQuality = bind.mainGetUserDefaultOption(key: kOptionImageQuality);
    final defCodec = bind.mainGetUserDefaultOption(key: kOptionCodecPreference);

    _viewStyle.value = defView.isNotEmpty ? defView : sessionView;
    _imageQuality.value = defQuality.isNotEmpty ? defQuality : sessionQuality;
    _codec.value = defCodec.isNotEmpty ? defCodec : sessionCodec;

    // Apply defaults to current session if they differ
    if (_viewStyle.value != sessionView && _viewStyle.value.isNotEmpty) {
      final item = _viewStyleRadios.firstWhereOrNull(
          (e) => e.value == _viewStyle.value);
      item?.onChanged?.call(_viewStyle.value);
    }
    if (_imageQuality.value != sessionQuality && _imageQuality.value.isNotEmpty) {
      final item = _imageQualityRadios.firstWhereOrNull(
          (e) => e.value == _imageQuality.value);
      item?.onChanged?.call(_imageQuality.value);
    }
    if (_codec.value != sessionCodec && _codec.value.isNotEmpty) {
      final item = _codecRadios.firstWhereOrNull(
          (e) => e.value == _codec.value);
      item?.onChanged?.call(_codec.value);
    }

    // Sync toggle defaults to session
    _syncToggleListFromDefaults(_cursorToggles);
    _syncToggleListFromDefaults(_displayToggles);

    // Resolution
    final display = gFFI.ffiModel.pi.tryGetDisplayIfNotAllDisplay(
        display: gFFI.ffiModel.pi.currentDisplay);
    if (display != null) {
      _resolution.value = '${display.width}x${display.height}';
    }

    setState(() => _loaded = true);
  }

  void _syncToggleListFromDefaults(List<TToggleMenu> toggles) {
    for (final toggle in toggles) {
      final text = _extractText(toggle.child);
      for (final entry in _toggleDefaultKeyMap.entries) {
        if (translate(entry.key) == text) {
          final defVal = bind.mainGetUserDefaultOption(key: entry.value) == 'Y';
          if (defVal != toggle.value && toggle.onChanged != null) {
            toggle.onChanged!(defVal);
          }
          break;
        }
      }
    }
  }

  String _extractText(Widget w) {
    if (w is Text) return w.data ?? '';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: _titleColor, size: 20),
          onPressed: () => Navigator.of(context).pop(),
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
      body: _loaded
          ? Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Obx(() => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDisplaySelector(),
                        if (_viewStyleRadios.isNotEmpty)
                          _buildDropdownCard(
                            title: translate('Default View Style'),
                            value: _viewStyle.value,
                            items: _viewStyleRadios,
                            onChanged: (v) {
                              final item = _viewStyleRadios
                                  .firstWhereOrNull((e) => e.value == v);
                              if (item != null) {
                                item.onChanged?.call(v);
                                _viewStyle.value = v;
                                bind.mainSetUserDefaultOption(
                                    key: kOptionViewStyle, value: v);
                              }
                            },
                          ),
                        if (_imageQualityRadios.isNotEmpty)
                          _buildDropdownCard(
                            title: translate('Default Image Quality'),
                            value: _imageQuality.value,
                            items: _imageQualityRadios,
                            onChanged: (v) {
                              final item = _imageQualityRadios
                                  .firstWhereOrNull((e) => e.value == v);
                              if (item != null) {
                                item.onChanged?.call(v);
                                _imageQuality.value = v;
                                bind.mainSetUserDefaultOption(
                                    key: kOptionImageQuality, value: v);
                              }
                            },
                          ),
                        if (_codecRadios.isNotEmpty)
                          _buildDropdownCard(
                            title: translate('Default Codec'),
                            value: _codec.value,
                            items: _codecRadios,
                            onChanged: (v) {
                              final item = _codecRadios
                                  .firstWhereOrNull((e) => e.value == v);
                              if (item != null) {
                                item.onChanged?.call(v);
                                _codec.value = v;
                                bind.mainSetUserDefaultOption(
                                    key: kOptionCodecPreference, value: v);
                              }
                            },
                          ),
                        _buildResolutionDropdown(),
                        if (_cursorToggles.isNotEmpty || _displayToggles.isNotEmpty)
                          _buildToggleCard(
                            translate('Display'),
                            [
                              ..._buildToggles(_cursorToggles),
                              ..._buildToggles(_displayToggles),
                            ],
                          ),
                        _buildPrivacyMode(),
                        const SizedBox(height: 16),
                      ],
                    )),
                  ),
                ),
                // 하단 고정 닫기 버튼
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
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5B7BF8),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          translate('Close'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  BoxDecoration get _cardDecoration => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26333C87),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      );

  /// 드롭다운 카드 (View Style, Image Quality, Codec)
  Widget _buildDropdownCard({
    required String title,
    required String value,
    required List<TRadioMenu<String>> items,
    required ValueChanged<String> onChanged,
  }) {
    final labelMap = <String, String>{};
    for (final item in items) {
      labelMap[item.value] = _extractText(item.child);
    }
    final displayValue = labelMap[value] ?? value;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _cardDecoration,
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
                value: displayValue,
                items: items.map((item) {
                  final label = _extractText(item.child);
                  return DropdownMenuItem<String>(
                    value: label,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: _titleColor,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (newLabel) {
                  if (newLabel == null) return;
                  final item = items.firstWhereOrNull(
                      (e) => _extractText(e.child) == newLabel);
                  if (item != null) {
                    onChanged(item.value);
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

  /// 해상도 드롭다운 카드
  Widget _buildResolutionDropdown() {
    final pi = gFFI.ffiModel.pi;
    final resolutions = pi.resolutions;
    final display = pi.tryGetDisplayIfNotAllDisplay(display: pi.currentDisplay);
    final visible = gFFI.ffiModel.keyboard && resolutions.length > 1 && display != null;
    if (!visible) return const SizedBox.shrink();

    final currentRes = _resolution.value;
    final resItems = resolutions
        .map((e) => '${e.width}x${e.height}')
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              translate('Resolution'),
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
                value: resItems.contains(currentRes) ? currentRes : null,
                items: resItems.map((res) {
                  return DropdownMenuItem<String>(
                    value: res,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(
                        res,
                        style: const TextStyle(
                          color: _titleColor,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (newRes) {
                  if (newRes == null) return;
                  final parts = newRes.split('x');
                  if (parts.length == 2) {
                    final w = int.tryParse(parts[0]);
                    final h = int.tryParse(parts[1]);
                    if (w != null && h != null) {
                      _resolution.value = newRes;
                      bind.sessionChangeResolution(
                        sessionId: gFFI.sessionId,
                        display: pi.currentDisplay,
                        width: w,
                        height: h,
                      );
                    }
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

  /// 토글 카드
  Widget _buildToggleCard(String title, List<Widget> children) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _cardDecoration,
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
              height: 1,
              color: Color(0xFFEEEEEE),
              indent: 16,
              endIndent: 16),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildToggleRow({
    required Widget child,
    required bool value,
    required ValueChanged<bool?>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: DefaultTextStyle(
              style: const TextStyle(
                color: _titleColor,
                fontSize: 14,
              ),
              child: child,
            ),
          ),
          CmCustomToggle(
            value: value,
            onChanged: onChanged != null
                ? (v) => onChanged(v)
                : null,
          ),
        ],
      ),
    );
  }

  static const _toggleDefaultKeyMap = <String, String>{
    'Show remote cursor': kOptionShowRemoteCursor,
    'Follow remote cursor': kOptionFollowRemoteCursor,
    'Follow remote window focus': kOptionFollowRemoteWindow,
    'Mute': kOptionDisableAudio,
    'Enable file copy and paste': kOptionEnableFileCopyPaste,
    'Disable clipboard': kOptionDisableClipboard,
    'Lock after session end': kOptionLockAfterSessionEnd,
    'True color (4:4:4)': kOptionI444,
  };

  void _syncToggleToDefault(Widget child, bool value) {
    final text = _extractText(child);
    for (final entry in _toggleDefaultKeyMap.entries) {
      if (translate(entry.key) == text) {
        bind.mainSetUserDefaultOption(
            key: entry.value, value: value ? 'Y' : '');
        return;
      }
    }
  }

  List<Widget> _buildToggles(List<TToggleMenu> toggles) {
    final rxValues = toggles.map((e) => e.value.obs).toList();
    return toggles
        .asMap()
        .entries
        .map((e) => Obx(() => _buildToggleRow(
            child: e.value.child,
            value: rxValues[e.key].value,
            onChanged: e.value.onChanged != null
                ? (v) {
                    e.value.onChanged?.call(v);
                    if (v != null) {
                      rxValues[e.key].value = v;
                      _syncToggleToDefault(e.value.child, v);
                    }
                  }
                : null)))
        .toList();
  }

  Widget _buildDisplaySelector() {
    final pi = gFFI.ffiModel.pi;
    if (pi.displays.length <= 1 || pi.currentDisplay == kAllDisplayValue) {
      return const SizedBox.shrink();
    }
    final cur = pi.currentDisplay;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              translate('Display'),
              style: const TextStyle(
                color: _titleColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(
              height: 1,
              color: Color(0xFFEEEEEE),
              indent: 16,
              endIndent: 16),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              children: List.generate(pi.displays.length, (i) {
                final selected = i == cur;
                return GestureDetector(
                  onTap: () {
                    if (i == cur) return;
                    openMonitorInTheSameTab(i, gFFI, pi);
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: selected
                          ? _accentColor
                          : const Color(0xFFEFF1FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        (i + 1).toString(),
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : _accentColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyMode() {
    if (_privacyModeList.length <= 1) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _cardDecoration,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setPrivacyModeDialog(
              gFFI.dialogManager, _privacyModeList, _privacyModeState!),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    translate('Privacy mode'),
                    style: const TextStyle(
                      color: _titleColor,
                      fontSize: 14,
                    ),
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
}

TTextMenu? getVirtualDisplayMenu(FFI ffi, String id) {
  if (!showVirtualDisplayMenu(ffi)) {
    return null;
  }
  return TTextMenu(
    child: Text(translate("Virtual display")),
    onPressed: () {
      ffi.dialogManager.show((setState, close, context) {
        final children = getVirtualDisplayMenuChildren(ffi, id, close);
        return CustomAlertDialog(
          title: Text(translate('Virtual display')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        );
      }, clickMaskDismiss: true, backDismiss: true).then((value) {
        _disableAndroidSoftKeyboard();
      });
    },
  );
}

TTextMenu? getResolutionMenu(FFI ffi, String id) {
  final ffiModel = ffi.ffiModel;
  final pi = ffiModel.pi;
  final resolutions = pi.resolutions;
  final display = pi.tryGetDisplayIfNotAllDisplay(display: pi.currentDisplay);

  final visible =
      ffiModel.keyboard && (resolutions.length > 1) && display != null;
  if (!visible) return null;

  return TTextMenu(
    child: Text(translate("Resolution")),
    onPressed: () {
      ffi.dialogManager.show((setState, close, context) {
        final children = resolutions
            .map((e) => getRadio<String>(
                  Text('${e.width}x${e.height}'),
                  '${e.width}x${e.height}',
                  '${display.width}x${display.height}',
                  (value) {
                    close();
                    bind.sessionChangeResolution(
                      sessionId: ffi.sessionId,
                      display: pi.currentDisplay,
                      width: e.width,
                      height: e.height,
                    );
                  },
                ))
            .toList();
        return CustomAlertDialog(
          title: Text(translate('Resolution')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        );
      }, clickMaskDismiss: true, backDismiss: true).then((value) {
        _disableAndroidSoftKeyboard();
      });
    },
  );
}

void sendPrompt(bool isMac, String key) {
  final old = isMac ? gFFI.inputModel.command : gFFI.inputModel.ctrl;
  if (isMac) {
    gFFI.inputModel.command = true;
  } else {
    gFFI.inputModel.ctrl = true;
  }
  gFFI.inputModel.inputKey(key);
  if (isMac) {
    gFFI.inputModel.command = old;
  } else {
    gFFI.inputModel.ctrl = old;
  }
}

class FABLocation extends FloatingActionButtonLocation {
  FloatingActionButtonLocation location;
  double offsetX;
  double offsetY;
  FABLocation(this.location, this.offsetX, this.offsetY);

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final offset = location.getOffset(scaffoldGeometry);
    return Offset(offset.dx + offsetX, offset.dy + offsetY);
  }
}
