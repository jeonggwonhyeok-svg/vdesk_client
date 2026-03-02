import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../common.dart';
import '../../common/widgets/overlay.dart';
import '../../common/widgets/dialog.dart';
import '../../common/widgets/remote_input.dart';
import '../../models/input_model.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../../utils/image.dart';
import '../widgets/toolbar_overlay.dart';
import 'remote_page.dart';

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

class ViewCameraPage extends StatefulWidget {
  ViewCameraPage(
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
  State<ViewCameraPage> createState() => _ViewCameraPageState(id);
}

class _ViewCameraPageState extends State<ViewCameraPage>
    with WidgetsBindingObserver {
  Timer? _timer;
  final _showBar = (!isWebDesktop).obs;
  bool _showGestureHelp = false;
  Orientation? _currentOrientation;
  double _viewInsetsBottom = 0;

  Timer? _timerDidChangeMetrics;

  final _blockableOverlayState = BlockableOverlayState();

  final keyboardVisibilityController = KeyboardVisibilityController();
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

  InputModel get inputModel => gFFI.inputModel;
  SessionID get sessionId => gFFI.sessionId;

  final TextEditingController _textController =
      TextEditingController(text: initText);

  _ViewCameraPageState(String id) {
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
      isViewCamera: true,
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
    removeSharedStates(widget.id);
    // `on_voice_call_closed` should be called when the connection is ended.
    // The inner logic of `on_voice_call_closed` will check if the voice call is active.
    // Only one client is considered here for now.
    gFFI.chatModel.onVoiceCallClosed("End connetion");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}

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

  // ===== Voice Call =====

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

  void _toggleRecording() {
    gFFI.recordingModel.toggle();
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

  void _takeScreenshot() {
    bind.sessionTakeScreenshot(
        sessionId: sessionId, display: gFFI.ffiModel.pi.currentDisplay);
  }

  @override
  Widget build(BuildContext context) {
    final keyboardIsVisible =
        keyboardVisibilityController.isVisible && _showEdit;
    final showDismissFab = keyboardIsVisible || _showGestureHelp;

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
          floatingActionButton: !showDismissFab
              ? null
              : FloatingActionButton(
                  mini: !keyboardIsVisible,
                  child: Icon(Icons.expand_more, color: Colors.white),
                  backgroundColor: MyTheme.accent,
                  onPressed: () {
                    setState(() {
                      if (keyboardIsVisible) {
                        _showEdit = false;
                        gFFI.invokeMethod("enable_soft_keyboard", false);
                        _mobileFocusNode.unfocus();
                        _physicalFocusNode.requestFocus();
                      } else if (_showGestureHelp) {
                        _showGestureHelp = false;
                      }
                    });
                  }),
          bottomNavigationBar: Obx(() => Stack(
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
            final showToolbar = gFFI.ffiModel.pi.isSet.isTrue &&
                gFFI.ffiModel.waitForFirstImage.isFalse;
            final isPortrait =
                MediaQuery.of(context).orientation == Orientation.portrait;
            final kbVisible =
                keyboardVisibilityController.isVisible && _showEdit;

            return getRawPointerAndKeyBody(
              Stack(
                children: [
                  Overlay(
                    initialEntries: [
                      OverlayEntry(builder: (context) {
                        return Container(
                          color: kColorCanvas,
                          child: SafeArea(
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
                                child: inputModel.isPhysicalMouse.value
                                    ? getBodyForMobile()
                                    : RawTouchGestureDetectorRegion(
                                        child: getBodyForMobile(),
                                        ffi: gFFI,
                                        isCamera: true,
                                      ),
                              );
                            }),
                          ),
                        );
                      })
                    ],
                  ),
                  // Toolbar overlay
                  if (showToolbar && _showBar.value)
                    _buildToolbarOverlay(isPortrait),
                  // Mini button
                  if (showToolbar && !_showBar.value && !kbVisible)
                    _buildMiniButton(isPortrait),
                ],
              ),
            );
          })),
    );
  }

  Widget getRawPointerAndKeyBody(Widget child) {
    return CameraRawPointerMouseRegion(
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
    return Positioned(
      left: 0,
      right: 0,
      top: (isPortrait && !Platform.isIOS) ? 8 : null,
      bottom: (isPortrait && !Platform.isIOS) ? null : 8,
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
    final voiceCallStatus = gFFI.chatModel.voiceCallStatus.value;
    final isInVoiceCall = voiceCallStatus == VoiceCallStatus.connected;
    final isWaitingVoiceCall =
        voiceCallStatus == VoiceCallStatus.waitingForResponse;
    final isRecording = gFFI.recordingModel.start;

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
    ];

    // More menu items
    final moreItems = <SimpleMenuItem>[
      SimpleMenuItem('Display Settings', () {
        setState(() => _showEdit = false);
        showOptions(context, widget.id, gFFI.dialogManager);
      }),
      if (gFFI.ffiModel.isPeerAndroid)
        SimpleMenuItem('Mobile Actions', () {
          gFFI.dialogManager.toggleMobileActionsOverlay(ffi: gFFI);
        }),
      SimpleMenuItem(
        'Disconnect',
        () => clientClose(sessionId, gFFI),
        assetPath: 'assets/icons/remote-connection-end.svg',
        iconColor: const Color(0xFFFE3E3E),
      ),
    ];

    // Left group
    final leftButtons = <Widget>[
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
      // More (popup)
      toolbarPopupButton(
        asset: 'assets/icons/remote_more.svg',
        label: 'More',
        items: moreItems,
        isPortrait: isPortrait,
      ),
    ];

    // Right group: fold only (no fullscreen for camera view)
    final rightButtons = <Widget>[
      toolbarIconButton(
        asset: 'assets/icons/remote-fold.svg',
        onPressed: () => _showBar.value = false,
      ),
    ];

    // Voice call controls
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
          if (isRecording && !Platform.isIOS) ...[
            const SizedBox(width: 6),
            _buildRecordingBox(),
          ],
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
        if (isRecording && !Platform.isIOS) ...[
          const SizedBox(height: 6),
          _buildRecordingBox(),
        ],
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

  Widget _buildRecordingBox() {
    return toolbarCard(
      child: Obx(() => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              toolbarIconButton(
                asset: 'assets/icons/remote-record-stop.svg',
                onPressed: _stopRecording,
              ),
              toolbarIconButton(
                asset: _recordingPaused.value
                    ? 'assets/icons/remote-record-start.svg'
                    : 'assets/icons/remote-record-pause.svg',
                onPressed: _toggleRecordingPause,
              ),
              toolbarIconButton(
                asset: _recordingSound.value
                    ? 'assets/icons/remote-record-sound-off.svg'
                    : 'assets/icons/remote-record-sound.svg',
                onPressed: _toggleRecordingSound,
              ),
              const SizedBox(width: 4),
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
      top: (isPortrait && !Platform.isIOS) ? 8 : null,
      bottom: (isPortrait && !Platform.isIOS) ? null : 8,
      child: miniShowButton(onTap: () => _showBar.value = true),
    );
  }

  Widget getBodyForMobile() {
    return Container(
        color: MyTheme.canvasColor,
        child: Stack(children: () {
          final paints = [
            ImagePaint(),
            Positioned(
              top: 10,
              right: 10,
              child: QualityMonitor(gFFI.qualityMonitorModel),
            ),
            SizedBox(
              width: 0,
              height: 0,
              child: !_showEdit
                  ? Container()
                  : TextFormField(
                      textInputAction: TextInputAction.newline,
                      autocorrect: false,
                      autofocus: true,
                      focusNode: _mobileFocusNode,
                      maxLines: null,
                      controller: _textController,
                      keyboardType: TextInputType.multiline,
                      onChanged: null,
                    ).workaroundFreezeLinuxMint(),
            ),
          ];
          return paints;
        }()));
  }

  Widget getBodyForDesktopWithListener() {
    var paints = <Widget>[ImagePaint()];
    return Container(
        color: MyTheme.canvasColor, child: Stack(children: paints));
  }

  onPressedTextChat(String id) {
    gFFI.chatModel.changeCurrentKey(MessageKey(id, ChatModel.clientModeID));
    gFFI.chatModel.toggleChatOverlay();
  }
}

class ImagePaint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final m = Provider.of<ImageModel>(context);
    final c = Provider.of<CanvasModel>(context);
    var s = c.scale;
    final adjust = c.getAdjustY();
    return CustomPaint(
      painter: ImagePainter(
          image: m.image, x: c.x / s, y: (c.y + adjust) / s, scale: s),
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
