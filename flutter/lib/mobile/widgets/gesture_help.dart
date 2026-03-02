import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/setting_widgets.dart';
import 'package:flutter_hbb/common/widgets/styled_form_widgets.dart';
import 'package:flutter_hbb/models/model.dart';

typedef OnTouchModeChange = void Function(bool);

class GestureHelp extends StatefulWidget {
  GestureHelp(
      {Key? key,
      required this.touchMode,
      required this.onTouchModeChange,
      required this.virtualMouseMode,
      this.onClose})
      : super(key: key);
  final bool touchMode;
  final OnTouchModeChange onTouchModeChange;
  final VirtualMouseMode virtualMouseMode;
  final VoidCallback? onClose;

  @override
  State<StatefulWidget> createState() =>
      _GestureHelpState(touchMode, virtualMouseMode);
}

class _GestureHelpState extends State<GestureHelp> {
  late bool _touchMode;
  final VirtualMouseMode _virtualMouseMode;

  _GestureHelpState(bool touchMode, VirtualMouseMode virtualMouseMode)
      : _virtualMouseMode = virtualMouseMode {
    _touchMode = touchMode;
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            translate('Mouse Setting'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E1E1E),
            ),
          ),
          GestureDetector(
            onTap: widget.onClose,
            child: const Icon(
              Icons.close,
              size: 24,
              color: Color(0xFF8F8E95),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (_touchMode) {
                  setState(() => _touchMode = false);
                  widget.onTouchModeChange(false);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: !_touchMode
                      ? const Color(0xFF454447)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    translate('Mouse mode'),
                    style: TextStyle(
                      color: !_touchMode
                          ? const Color(0xFFFEFEFE)
                          : const Color(0xFF454447),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!_touchMode) {
                  setState(() => _touchMode = true);
                  widget.onTouchModeChange(true);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _touchMode
                      ? const Color(0xFF454447)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    translate('Touch mode'),
                    style: TextStyle(
                      color: _touchMode
                          ? const Color(0xFFFEFEFE)
                          : const Color(0xFF454447),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckboxRow({
    required bool value,
    required String label,
    required VoidCallback onTap,
    double leftPadding = 0,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: leftPadding),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StyledCheckbox(
              value: value,
              onChanged: (_) => onTap(),
              size: 20,
              borderRadius: 4,
              iconSize: 14,
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 15)),
          ],
        ),
      ),
    );
  }

  Widget _buildStyledSlider() {
    const sliderColor = Color(0xFF5F71FF);
    return Row(
      children: [
        Text(translate('Small'), style: const TextStyle(fontSize: 12)),
        Expanded(
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
              activeTickMarkColor: Colors.transparent,
              inactiveTickMarkColor: Colors.transparent,
            ),
            child: Slider(
              value: _virtualMouseMode.virtualMouseScale,
              min: 0.8,
              max: 1.8,
              divisions: 10,
              onChanged: (value) {
                _virtualMouseMode.setVirtualMouseScale(value);
                setState(() {});
              },
            ),
          ),
        ),
        Text(translate('Large'), style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final space = 12.0;
    var width = size.width - 2 * space;
    final minWidth = 90;
    if (size.width > minWidth + 2 * space) {
      final n = (size.width / (minWidth + 2 * space)).floor();
      width = size.width / n - 2 * space;
    }
    return Center(
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildHeader(),
                const SizedBox(height: 24),
                _buildTabBar(),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCheckboxRow(
                        value: _virtualMouseMode.showVirtualMouse,
                        label: translate('Show virtual mouse'),
                        onTap: () async {
                          await _virtualMouseMode.toggleVirtualMouse();
                          setState(() {});
                        },
                      ),
                      if (_virtualMouseMode.showVirtualMouse)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F7F7),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_touchMode) ...[
                                Text(translate('Virtual mouse size'),
                                    style: const TextStyle(fontSize: 15)),
                                const SizedBox(height: 4),
                                _buildStyledSlider(),
                              ],
                              if (!_touchMode)
                                _buildCheckboxRow(
                                  value:
                                      _virtualMouseMode.showVirtualJoystick,
                                  label: translate("Show virtual joystick"),
                                  onTap: () async {
                                    await _virtualMouseMode
                                        .toggleVirtualJoystick();
                                    setState(() {});
                                  },
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                    width: double.infinity,
                    child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: space,
                  runSpacing: 2 * space,
                  children: _touchMode
                      ? [
                          GestureInfo(
                              width,
                              'assets/icons/mouse-help-one-finger-tap.png',
                              translate("One-Finger Tap"),
                              translate("Left Mouse")),
                          GestureInfo(
                              width,
                              'assets/icons/mouse-help-one-finger-long-tap.png',
                              translate("One-Long Tap"),
                              translate("Right Mouse")),
                          GestureInfo(
                              width,
                              'assets/icons/mouse-help-one-finger-drag.png',
                              translate("One-Finger Move"),
                              translate("Mouse Drag")),
                          GestureInfo(
                              width,
                              'assets/icons/mouse-help-three-finger-drag.png',
                              translate("Three-Finger vertically"),
                              translate("Mouse Wheel")),
                          GestureInfo(
                              width,
                              'assets/icons/mouse-help-two-finger-move.png',
                              translate("Two-Finger Move"),
                              translate("Canvas Move")),
                          GestureInfo(
                              width,
                              'assets/icons/mouse-help-two-finger-drag.png',
                              translate("Pinch to Zoom"),
                              translate("Canvas Zoom")),
                        ]
                      : [
                          GestureInfo(
                              width,
                              'assets/icons/mouse-help-one-finger-tap.png',
                              translate("One-Finger Tap"),
                              translate("Left Mouse")),
                          GestureInfo(
                              width,
                              'assets/icons/mouse-help-one-finger-long-tap.png',
                              translate("One-Long Tap"),
                              translate("Right Mouse")),
                          GestureInfo(
                              width,
                              'assets/icons/mouse-help-one-finger-drag.png',
                              translate("Double Tap & Move"),
                              translate("Mouse Drag")),
                          GestureInfo(
                              width,
                              'assets/icons/mouse-help-three-finger-drag.png',
                              translate("Three-Finger vertically"),
                              translate("Mouse Wheel")),
                          GestureInfo(
                              width,
                              'assets/icons/mouse-help-two-finger-move.png',
                              translate("Two-Finger Move"),
                              translate("Canvas Move")),
                          GestureInfo(
                              width,
                              'assets/icons/mouse-help-two-finger-drag.png',
                              translate("Pinch to Zoom"),
                              translate("Canvas Zoom")),
                        ],
                )),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: StyledPrimaryButton(
                    label: translate('OK'),
                    onPressed: widget.onClose,
                    height: 52,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            )));
  }
}

class GestureInfo extends StatelessWidget {
  const GestureInfo(this.width, this.imagePath, this.fromText, this.toText,
      {Key? key})
      : super(key: key);

  final String fromText;
  final String toText;
  final String imagePath;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
        width: width,
        child: Column(
          children: [
            Image.asset(
              imagePath,
              width: 80,
              height: 80,
            ),
            const SizedBox(height: 6),
            Text(fromText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 9, color: Color(0xFF8F8E95))),
            const SizedBox(height: 3),
            Text(toText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF5F71FF),
                    fontWeight: FontWeight.bold))
          ],
        ));
  }
}
