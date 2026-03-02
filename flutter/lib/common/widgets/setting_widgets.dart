import 'package:debounce_throttle/debounce_throttle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/styled_text_field.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

customImageQualityWidget(
    {required double initQuality,
    required double initFps,
    required Function(double)? setQuality,
    required Function(double)? setFps,
    required bool showFps,
    required bool showMoreQuality}) {
  if (initQuality < kMinQuality ||
      initQuality > (showMoreQuality ? kMaxMoreQuality : kMaxQuality)) {
    initQuality = kDefaultQuality;
  }
  if (initFps < kMinFps || initFps > kMaxFps) {
    initFps = kDefaultFps;
  }
  final qualityValue = initQuality.obs;
  final fpsValue = initFps.obs;

  final RxBool moreQualityChecked = RxBool(qualityValue.value > kMaxQuality);
  final debouncerQuality = Debouncer<double>(
    Duration(milliseconds: 1000),
    onChanged: setQuality,
    initialValue: qualityValue.value,
  );
  final debouncerFps = Debouncer<double>(
    Duration(milliseconds: 1000),
    onChanged: setFps,
    initialValue: fpsValue.value,
  );

  onMoreChanged(bool? value) {
    if (value == null) return;
    moreQualityChecked.value = value;
    if (!value && qualityValue.value > 100) {
      qualityValue.value = 100;
    }
    debouncerQuality.value = qualityValue.value;
  }

  return Column(
    children: [
      Obx(() => Row(
            children: [
              Expanded(
                flex: 3,
                child: Slider(
                  value: qualityValue.value,
                  min: kMinQuality,
                  max: moreQualityChecked.value ? kMaxMoreQuality : kMaxQuality,
                  divisions: moreQualityChecked.value
                      ? ((kMaxMoreQuality - kMinQuality) / 10).round()
                      : ((kMaxQuality - kMinQuality) / 5).round(),
                  onChanged: setQuality == null
                      ? null
                      : (double value) async {
                          qualityValue.value = value;
                          debouncerQuality.value = value;
                        },
                ),
              ),
              Expanded(
                  flex: 1,
                  child: Text(
                    '${qualityValue.value.round()}%',
                    style: const TextStyle(fontSize: 15),
                  )),
              Expanded(
                  flex: isMobile ? 2 : 1,
                  child: Text(
                    translate('Bitrate'),
                    style: const TextStyle(fontSize: 15),
                  )),
              // mobile doesn't have enough space
              if (showMoreQuality && !isMobile)
                Expanded(
                    flex: 1,
                    child: Row(
                      children: [
                        Checkbox(
                          value: moreQualityChecked.value,
                          onChanged: onMoreChanged,
                        ),
                        Expanded(
                          child: Text(translate('More')),
                        )
                      ],
                    ))
            ],
          )),
      if (showMoreQuality && isMobile)
        Obx(() => Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Checkbox(
                      value: moreQualityChecked.value,
                      onChanged: onMoreChanged,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(translate('More')),
                )
              ],
            )),
      if (showFps)
        Obx(() => Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Slider(
                    value: fpsValue.value,
                    min: kMinFps,
                    max: kMaxFps,
                    divisions: ((kMaxFps - kMinFps) / 5).round(),
                    onChanged: setFps == null
                        ? null
                        : (double value) async {
                            fpsValue.value = value;
                            debouncerFps.value = value;
                          },
                  ),
                ),
                Expanded(
                    flex: 1,
                    child: Text(
                      '${fpsValue.value.round()}',
                      style: const TextStyle(fontSize: 15),
                    )),
                Expanded(
                    flex: 2,
                    child: Text(
                      translate('FPS'),
                      style: const TextStyle(fontSize: 15),
                    ))
              ],
            )),
    ],
  );
}

customImageQualitySetting() {
  final qualityKey = 'custom_image_quality';
  final fpsKey = 'custom-fps';

  final initQuality =
      (double.tryParse(bind.mainGetUserDefaultOption(key: qualityKey)) ??
          kDefaultQuality);
  final isQuanlityFixed = isOptionFixed(qualityKey);
  final initFps =
      (double.tryParse(bind.mainGetUserDefaultOption(key: fpsKey)) ??
          kDefaultFps);
  final isFpsFixed = isOptionFixed(fpsKey);

  return customImageQualityWidget(
      initQuality: initQuality,
      initFps: initFps,
      setQuality: isQuanlityFixed
          ? null
          : (v) {
              bind.mainSetUserDefaultOption(
                  key: qualityKey, value: v.toString());
            },
      setFps: isFpsFixed
          ? null
          : (v) {
              bind.mainSetUserDefaultOption(key: fpsKey, value: v.toString());
            },
      showFps: true,
      showMoreQuality: true);
}

List<Widget> ServerConfigImportExportWidgets(
  List<TextEditingController> controllers,
  List<RxString> errMsgs,
) {
  import() {
    Clipboard.getData(Clipboard.kTextPlain).then((value) {
      importConfig(controllers, errMsgs, value?.text);
    });
  }

  export() {
    final text = ServerConfig(
            idServer: controllers[0].text.trim(),
            relayServer: controllers[1].text.trim(),
            apiServer: controllers[2].text.trim(),
            key: controllers[3].text.trim())
        .encode();
    debugPrint("ServerConfig export: $text");
    Clipboard.setData(ClipboardData(text: text));
    showToast(translate('Export server configuration successfully'));
  }

  return [
    Tooltip(
      message: translate('Import server config'),
      child: IconButton(
          icon: Icon(Icons.paste, color: Colors.grey), onPressed: import),
    ),
    Tooltip(
        message: translate('Export Server Config'),
        child: IconButton(
            icon: Icon(Icons.copy, color: Colors.grey), onPressed: export))
  ];
}

/// 디스플레이 옵션 정의 클래스
/// - optionKey: 사용자 기본 설정 키 (예: kOptionShowRemoteCursor)
/// - sessionKey: 세션 토글 키 (예: 'show-remote-cursor'), null이면 optionKey 값 사용
/// - label: 번역 가능한 라벨
class DisplayOptionDef {
  final String optionKey;
  final String? sessionKey;
  final String label;

  const DisplayOptionDef(this.optionKey, this.label, {this.sessionKey});

  /// 세션 토글에 사용할 키 반환
  String get toggleKey => sessionKey ?? optionKey;
}

/// 공통 디스플레이 옵션 목록 (원격 툴바 다이얼로그와 설정 페이지에서 공유)
/// 주의: 일부 옵션은 userDefault 키와 세션 토글 키가 다름 (underscore vs hyphen)
List<DisplayOptionDef> getCommonDisplayOptions({bool forToolbarDialog = false}) {
  return [
    // 설정 페이지 전용 옵션 (툴바 다이얼로그에서는 제외)
    if (!forToolbarDialog)
      const DisplayOptionDef(kOptionViewOnly, 'View Mode', sessionKey: 'view-only'),
    // if (!forToolbarDialog && (isDesktop || isWebDesktop))
    //   const DisplayOptionDef(kKeyShowMonitorsToolbar, 'show_monitors_tip'),
    // if (!forToolbarDialog && (isDesktop || isWebDesktop))
    //   const DisplayOptionDef(kOptionCollapseToolbar, 'Collapse toolbar'),
    // 세션 토글 키가 다른 경우 sessionKey 명시
    const DisplayOptionDef(kOptionShowRemoteCursor, 'Show remote cursor', sessionKey: 'show-remote-cursor'),
    const DisplayOptionDef(kOptionFollowRemoteCursor, 'Follow remote cursor', sessionKey: 'follow-remote-cursor'),
    const DisplayOptionDef(kOptionFollowRemoteWindow, 'Follow remote window focus', sessionKey: 'follow-remote-window'),
    if (isDesktop || isWebDesktop)
      const DisplayOptionDef(kOptionZoomCursor, 'Zoom cursor'),
    const DisplayOptionDef(kOptionDisableAudio, 'Mute'),
    if (isDesktop)
      const DisplayOptionDef(kOptionEnableFileCopyPaste, 'Enable file copy and paste'),
    const DisplayOptionDef(kOptionDisableClipboard, 'Disable clipboard'),
    const DisplayOptionDef(kOptionLockAfterSessionEnd, 'Lock after session end'),
    const DisplayOptionDef(kOptionPrivacyMode, 'Privacy mode', sessionKey: 'privacy-mode'),
    const DisplayOptionDef(kOptionI444, 'True color (4:4:4)'),
    const DisplayOptionDef(kKeyReverseMouseWheel, 'Reverse mouse wheel'),
    const DisplayOptionDef(kOptionSwapLeftRightMouse, 'swap-left-right-mouse'),
    // 디스플레이 관련 옵션 (데스크톱 전용)
    if (isDesktop)
      const DisplayOptionDef(kKeyShowDisplaysAsIndividualWindows, 'Show displays as individual windows'),
    if (isDesktop)
      const DisplayOptionDef(kKeyUseAllMyDisplaysForTheRemoteSession, 'Use all my displays for the remote session'),
  ];
}

List<(String, String)> otherDefaultSettings() {
  List<(String, String)> v = [
    ('View Mode', kOptionViewOnly),
    // if ((isDesktop || isWebDesktop))
    //   ('show_monitors_tip', kKeyShowMonitorsToolbar),
    // if ((isDesktop || isWebDesktop))
    //   ('Collapse toolbar', kOptionCollapseToolbar),
    ('Show remote cursor', kOptionShowRemoteCursor),
    ('Follow remote cursor', kOptionFollowRemoteCursor),
    ('Follow remote window focus', kOptionFollowRemoteWindow),
    if ((isDesktop || isWebDesktop)) ('Zoom cursor', kOptionZoomCursor),
    ('Mute', kOptionDisableAudio),
    if (isDesktop) ('Enable file copy and paste', kOptionEnableFileCopyPaste),
    ('Disable clipboard', kOptionDisableClipboard),
    ('Lock after session end', kOptionLockAfterSessionEnd),
    ('Privacy mode', kOptionPrivacyMode),
    ('True color (4:4:4)', kOptionI444),
    ('Reverse mouse wheel', kKeyReverseMouseWheel),
    ('swap-left-right-mouse', kOptionSwapLeftRightMouse),
    if (isDesktop)
      (
        'Show displays as individual windows',
        kKeyShowDisplaysAsIndividualWindows
      ),
    if (isDesktop)
      (
        'Use all my displays for the remote session',
        kKeyUseAllMyDisplaysForTheRemoteSession
      ),
  ];

  return v;
}

class TrackpadSpeedWidget extends StatefulWidget {
  final SimpleWrapper<int> value;
  // If null, no debouncer will be applied.
  final Function(int)? onDebouncer;

  TrackpadSpeedWidget({Key? key, required this.value, this.onDebouncer});

  @override
  TrackpadSpeedWidgetState createState() => TrackpadSpeedWidgetState();
}

class TrackpadSpeedWidgetState extends State<TrackpadSpeedWidget> {
  final TextEditingController _controller = TextEditingController();
  late final Debouncer<int> debouncerSpeed;

  set value(int v) => widget.value.value = v;
  int get value => widget.value.value;

  void updateValue(int newValue) {
    setState(() {
      value = newValue.clamp(kMinTrackpadSpeed, kMaxTrackpadSpeed);
      // Scale the trackpad speed value to a percentage for display purposes.
      _controller.text = value.toString();
      if (widget.onDebouncer != null) {
        debouncerSpeed.setValue(value);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    debouncerSpeed = Debouncer<int>(
      Duration(milliseconds: 1000),
      onChanged: widget.onDebouncer,
      initialValue: widget.value.value,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.text.isEmpty) {
      _controller.text = value.toString();
    }
    const sliderColor = Color(0xFF5F71FF);
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: sliderColor,
              inactiveTrackColor: sliderColor.withValues(alpha: 0.2),
              thumbColor: sliderColor,
              thumbShape: const BorderedRoundSliderThumbShape(
                enabledThumbRadius: 12,
                borderColor: Color(0xFFFEFEFE),
                borderWidth: 3,
                elevation: 3,
              ),
              overlayColor: sliderColor.withValues(alpha: 0.1),
              trackHeight: 4,
            ),
            child: Slider(
              value: value.toDouble(),
              min: kMinTrackpadSpeed.toDouble(),
              max: kMaxTrackpadSpeed.toDouble(),
              divisions: ((kMaxTrackpadSpeed - kMinTrackpadSpeed) / 10).round(),
              onChanged: (double v) => updateValue(v.round()),
            ),
          ),
        ),
        Expanded(
            flex: 1,
            child: Row(
              children: [
                SizedBox(
                  width: 70,
                  child: StyledTextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    onSubmitted: (text) {
                      int? v = int.tryParse(text);
                      if (v != null) {
                        updateValue(v);
                      }
                    },
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ).marginOnly(right: 8.0),
                Text(
                  '%',
                  style: const TextStyle(fontSize: 15),
                )
              ],
            )),
      ],
    );
  }
}

/// 테두리가 있는 원형 슬라이더 Thumb Shape
class BorderedRoundSliderThumbShape extends SliderComponentShape {
  final double enabledThumbRadius;
  final Color borderColor;
  final double borderWidth;
  final double elevation;

  const BorderedRoundSliderThumbShape({
    this.enabledThumbRadius = 10.0,
    required this.borderColor,
    required this.borderWidth,
    this.elevation = 0,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(enabledThumbRadius);
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

    // 그림자 그리기
    if (elevation > 0) {
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, elevation);
      canvas.drawCircle(center + Offset(0, elevation * 0.5), enabledThumbRadius, shadowPaint);
    }

    // 테두리 그리기
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, enabledThumbRadius, borderPaint);

    // 내부 원 그리기
    final thumbPaint = Paint()
      ..color = sliderTheme.thumbColor ?? const Color(0xFF5F71FF)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, enabledThumbRadius - borderWidth, thumbPaint);
  }
}
