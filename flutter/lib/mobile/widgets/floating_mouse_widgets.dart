// These floating mouse widgets are used to simulate a physical mouse
// when "mobile" -> "desktop" in mouse mode.
// This file does not contain whole mouse widgets, it only contains
// parts that help to control, such as wheel scroll and wheel button.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/remote_input.dart';
import 'package:flutter_hbb/models/input_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

// Used for the wheel button and wheel scroll widgets
const double _kSpaceToHorizontalEdge = 25;
const double _wheelWidth = 50;
const double _wheelHeight = 192;
// Used for the left/right button widgets
const double _kSpaceToVerticalEdge = 15;
const double _kSpaceBetweenLeftRightButtons = 40;
const double _kLeftRightButtonWidth = 55;
const double _kLeftRightButtonHeight = 40;
// 실제 Stack 하단에서 위젯 하단까지 거리
const double _kBottomOffset = 100;
const double _kCenterToWidgetOffset = 125;
const double _kBorderWidth = 1;
final Color _kDefaultBorderColor = Colors.white.withOpacity(0.7);
final Color _kDefaultColor = Colors.black.withOpacity(0.4);
final Color _kTapDownColor = Colors.blue.withOpacity(0.7);
final Color _kWidgetHighlightColor = Colors.white.withOpacity(0.9);
const int _kInputTimerIntervalMillis = 100;

class FloatingMouseWidgets extends StatefulWidget {
  final FFI ffi;
  const FloatingMouseWidgets({
    super.key,
    required this.ffi,
  });

  @override
  State<FloatingMouseWidgets> createState() => _FloatingMouseWidgetsState();
}

class _FloatingMouseWidgetsState extends State<FloatingMouseWidgets> {
  InputModel get _inputModel => widget.ffi.inputModel;
  CursorModel get _cursorModel => widget.ffi.cursorModel;
  late final VirtualMouseMode _virtualMouseMode;
  bool _isLeftBtnDown = false;
  bool _isRightBtnDown = false;
  final GlobalKey _leftBtnKey = GlobalKey();
  final GlobalKey _rightBtnKey = GlobalKey();
  Rect? _leftBtnBlockedRect;
  Rect? _rightBtnBlockedRect;

  @override
  void initState() {
    super.initState();
    _virtualMouseMode = widget.ffi.ffiModel.virtualMouseMode;
    _virtualMouseMode.addListener(_onVirtualMouseModeChanged);
    _cursorModel.blockEvents = false;
    isSpecialHoldDragActive = false;
  }

  void _onVirtualMouseModeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _updateBlockedRects() {
    _updateBlockedRect(_leftBtnKey, _leftBtnBlockedRect, (rect) {
      _leftBtnBlockedRect = rect;
    });
    _updateBlockedRect(_rightBtnKey, _rightBtnBlockedRect, (rect) {
      _rightBtnBlockedRect = rect;
    });
  }

  void _updateBlockedRect(
      GlobalKey key, Rect? lastRect, void Function(Rect?) setRect) {
    final context = key.currentContext;
    if (context == null) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return;
    final newRect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    if (lastRect != null) {
      _cursorModel.removeBlockedRect(lastRect);
    }
    _cursorModel.addBlockedRect(newRect);
    setRect(newRect);
  }

  void _removeBlockedRects() {
    if (_leftBtnBlockedRect != null) {
      _cursorModel.removeBlockedRect(_leftBtnBlockedRect!);
      _leftBtnBlockedRect = null;
    }
    if (_rightBtnBlockedRect != null) {
      _cursorModel.removeBlockedRect(_rightBtnBlockedRect!);
      _rightBtnBlockedRect = null;
    }
  }

  @override
  void dispose() {
    _removeBlockedRects();
    _virtualMouseMode.removeListener(_onVirtualMouseModeChanged);
    super.dispose();
    _cursorModel.blockEvents = false;
    isSpecialHoldDragActive = false;
  }

  @override
  Widget build(BuildContext context) {
    final virtualMouseMode = _virtualMouseMode;
    if (!virtualMouseMode.showVirtualMouse) {
      return const Offstage();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackWidth = constraints.maxWidth;
        final stackHeight = constraints.maxHeight;
        final isLandscape = stackWidth > stackHeight;
        final offset = isLandscape ? _kCenterToWidgetOffset * 2.5 : _kCenterToWidgetOffset;
        final centerX = stackWidth / 2;
        final btnGap = 6.0;
        final wheelLeft = centerX + offset;
        final rightClickLeft = wheelLeft - btnGap - _kLeftRightButtonWidth;
        final leftClickLeft = rightClickLeft - btnGap - _kLeftRightButtonWidth;
        final btnTop = stackHeight - _kBottomOffset - _kLeftRightButtonWidth;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _updateBlockedRects();
        });
        return Stack(
          children: [
            FloatingWheel(
              inputModel: _inputModel,
              cursorModel: _cursorModel,
              stackSize: Size(stackWidth, stackHeight),
            ),
            if (virtualMouseMode.showVirtualJoystick)
              VirtualJoystick(
                cursorModel: _cursorModel,
                stackSize: Size(stackWidth, stackHeight),
              ),
            // 우클릭 버튼 - 스크롤 휠 바로 왼쪽
            Positioned(
              left: rightClickLeft,
              top: btnTop,
              child: _buildClickButton(false),
            ),
            // 좌클릭 버튼 - 우클릭 왼쪽
            Positioned(
              left: leftClickLeft,
              top: btnTop,
              child: _buildClickButton(true),
            ),
          ],
        );
      },
    );
  }

  Widget _buildClickButton(bool isLeft) {
    final iconPath = isLeft
        ? 'assets/icons/mouse-stick-left-click.png'
        : 'assets/icons/mouse-stick-right-click.png';
    final isDown = isLeft ? _isLeftBtnDown : _isRightBtnDown;
    final key = isLeft ? _leftBtnKey : _rightBtnKey;
    return Listener(
      key: key,
      onPointerDown: (_) {
        setState(() {
          if (isLeft) _isLeftBtnDown = true; else _isRightBtnDown = true;
        });
      },
      onPointerUp: (_) async {
        final btn = isLeft ? MouseButtons.left : MouseButtons.right;
        await _cursorModel.syncCursorPosition();
        await _inputModel.tapDown(btn);
        await Future.delayed(const Duration(milliseconds: 50));
        await _inputModel.tapUp(btn);
        if (mounted) {
          setState(() {
            if (isLeft) _isLeftBtnDown = false; else _isRightBtnDown = false;
          });
        }
      },
      onPointerCancel: (_) {
        setState(() {
          if (isLeft) _isLeftBtnDown = false; else _isRightBtnDown = false;
        });
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: _kLeftRightButtonWidth,
            height: _kLeftRightButtonWidth,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFEFEFE).withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDown
                    ? _kTapDownColor
                    : const Color(0xFFFFFFFF).withOpacity(0.3),
                width: isDown ? 1.5 : 1,
              ),
            ),
            child: Image.asset(
              iconPath,
              width: 28,
              height: 28,
            ),
          ),
        ),
      ),
    );
  }
}

class FloatingWheel extends StatefulWidget {
  final InputModel inputModel;
  final CursorModel cursorModel;
  final Size stackSize;
  const FloatingWheel(
      {super.key, required this.inputModel, required this.cursorModel, required this.stackSize});

  @override
  State<FloatingWheel> createState() => _FloatingWheelState();
}

class _FloatingWheelState extends State<FloatingWheel> {
  Offset _position = Offset.zero;
  bool _isInitialized = false;
  Rect? _lastBlockedRect;

  bool _isUpDown = false;
  bool _isMidDown = false;
  bool _isDownDown = false;

  Timer? _scrollTimer;

  InputModel get _inputModel => widget.inputModel;
  CursorModel get _cursorModel => widget.cursorModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resetPosition();
    });
  }

  @override
  void didUpdateWidget(FloatingWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stackSize != widget.stackSize) {
      _resetPosition();
    }
  }

  void _resetPosition() {
    final w = widget.stackSize.width;
    final h = widget.stackSize.height;
    final isLandscape = w > h;
    final offset = isLandscape ? _kCenterToWidgetOffset * 2.5 : _kCenterToWidgetOffset;
    setState(() {
      _position = Offset(
        w / 2 + offset,
        h - _wheelHeight - _kBottomOffset,
      );
      _isInitialized = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateBlockedRect();
    });
  }

  void _updateBlockedRect() {
    if (_lastBlockedRect != null) {
      _cursorModel.removeBlockedRect(_lastBlockedRect!);
    }
    final newRect =
        Rect.fromLTWH(_position.dx, _position.dy, _wheelWidth, _wheelHeight);
    _cursorModel.addBlockedRect(newRect);
    _lastBlockedRect = newRect;
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    if (_lastBlockedRect != null) {
      _cursorModel.removeBlockedRect(_lastBlockedRect!);
    }
    super.dispose();
  }

  Widget _buildUpDownButton(
      void Function(PointerDownEvent) onPointerDown,
      void Function(PointerUpEvent) onPointerUp,
      void Function(PointerCancelEvent) onPointerCancel,
      bool Function() flagGetter,
      BorderRadiusGeometry borderRadius,
      IconData iconData) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: onPointerDown,
      onPointerUp: onPointerUp,
      onPointerCancel: onPointerCancel,
      child: Container(
        width: _wheelWidth,
        height: 55,
        alignment: Alignment.center,
        child: Icon(iconData,
            color: flagGetter()
                ? _kTapDownColor
                : const Color(0xFFF2F1F6),
            size: 28),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Positioned(child: Offstage());
    }
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: _buildWidget(context),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        height: 1,
        color: const Color(0xFFF2F1F6),
      ),
    );
  }

  Widget _buildWidget(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: _wheelWidth,
          height: _wheelHeight,
          decoration: BoxDecoration(
            color: const Color(0xFFFEFEFE).withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFFFFFFF).withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              _buildUpDownButton(
                (event) {
                  setState(() {
                    _isUpDown = true;
                  });
                  _startScrollTimer(1);
                },
                (event) {
                  setState(() {
                    _isUpDown = false;
                  });
                  _stopScrollTimer();
                },
                (event) {
                  setState(() {
                    _isUpDown = false;
                  });
                  _stopScrollTimer();
                },
                () => _isUpDown,
                BorderRadius.vertical(top: Radius.circular(12)),
                Icons.keyboard_arrow_up,
              ),
              _buildDivider(),
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  setState(() {
                    _isMidDown = true;
                  });
                  _inputModel.tapDown(MouseButtons.wheel);
                },
                onPointerUp: (event) {
                  setState(() {
                    _isMidDown = false;
                  });
                  _inputModel.tapUp(MouseButtons.wheel);
                },
                onPointerCancel: (event) {
                  setState(() {
                    _isMidDown = false;
                  });
                  _inputModel.tapUp(MouseButtons.wheel);
                },
                child: Container(
                  width: _wheelWidth,
                  height: 80,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 14, height: 1.5, color: _isMidDown ? _kTapDownColor : const Color(0xFFFEFEFE)),
                        SizedBox(height: 5),
                        Container(width: 20, height: 1.5, color: _isMidDown ? _kTapDownColor : const Color(0xFFFEFEFE)),
                        SizedBox(height: 5),
                        Container(width: 14, height: 1.5, color: _isMidDown ? _kTapDownColor : const Color(0xFFFEFEFE)),
                      ],
                    ),
                  ),
                ),
              ),
              _buildDivider(),
              _buildUpDownButton(
                (event) {
                  setState(() {
                    _isDownDown = true;
                  });
                  _startScrollTimer(-1);
                },
                (event) {
                  setState(() {
                    _isDownDown = false;
                  });
                  _stopScrollTimer();
                },
                (event) {
                  setState(() {
                    _isDownDown = false;
                  });
                  _stopScrollTimer();
                },
                () => _isDownDown,
                BorderRadius.vertical(bottom: Radius.circular(12)),
                Icons.keyboard_arrow_down,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startScrollTimer(int direction) {
    _scrollTimer?.cancel();
    _inputModel.scroll(direction);
    _scrollTimer = Timer.periodic(
        Duration(milliseconds: _kInputTimerIntervalMillis), (timer) {
      _inputModel.scroll(direction);
    });
  }

  void _stopScrollTimer() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }
}

class FloatingLeftRightButton extends StatefulWidget {
  final bool isLeft;
  final InputModel inputModel;
  final CursorModel cursorModel;
  const FloatingLeftRightButton(
      {super.key,
      required this.isLeft,
      required this.inputModel,
      required this.cursorModel});

  @override
  State<FloatingLeftRightButton> createState() =>
      _FloatingLeftRightButtonState();
}

class _FloatingLeftRightButtonState extends State<FloatingLeftRightButton> {
  Offset _position = Offset.zero;
  bool _isInitialized = false;
  bool _isDown = false;
  Rect? _lastBlockedRect;

  Orientation? _previousOrientation;
  Offset _preSavedPos = Offset.zero;

  // Gesture ambiguity resolution
  Timer? _tapDownTimer;
  final Duration _pressTimeout = const Duration(milliseconds: 200);
  bool _isDragging = false;

  bool get _isLeft => widget.isLeft;
  InputModel get _inputModel => widget.inputModel;
  CursorModel get _cursorModel => widget.cursorModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentOrientation = MediaQuery.of(context).orientation;
      _previousOrientation = currentOrientation;
      _resetPosition(currentOrientation);
    });
  }

  @override
  void dispose() {
    if (_lastBlockedRect != null) {
      _cursorModel.removeBlockedRect(_lastBlockedRect!);
    }
    _tapDownTimer?.cancel();
    _trySavePosition();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentOrientation = MediaQuery.of(context).orientation;
    if (_previousOrientation == null ||
        _previousOrientation != currentOrientation) {
      _resetPosition(currentOrientation);
    }
    _previousOrientation = currentOrientation;
  }

  double _getOffsetX(double w) {
    if (_isLeft) {
      return (w - _kLeftRightButtonWidth * 2 - _kSpaceBetweenLeftRightButtons) *
          0.5;
    } else {
      return (w + _kSpaceBetweenLeftRightButtons) * 0.5;
    }
  }

  String _getPositionKey(Orientation ori) {
    final strLeftRight = _isLeft ? 'l' : 'r';
    final strOri = ori == Orientation.landscape ? 'l' : 'p';
    return '$strLeftRight$strOri-mouse-btn-pos';
  }

  static Offset? _loadPositionFromString(String s) {
    if (s.isEmpty) {
      return null;
    }
    try {
      final m = jsonDecode(s);
      return Offset(m['x'], m['y']);
    } catch (e) {
      debugPrintStack(label: 'Failed to load position "$s" $e');
      return null;
    }
  }

  void _trySavePosition() {
    if (_previousOrientation == null) return;
    if (((_position - _preSavedPos)).distanceSquared < 0.1) return;
    final pos = jsonEncode({
      'x': _position.dx,
      'y': _position.dy,
    });
    bind.setLocalFlutterOption(
        k: _getPositionKey(_previousOrientation!), v: pos);
    _preSavedPos = _position;
  }

  void _restorePosition(Orientation ori) {
    final ps = bind.getLocalFlutterOption(k: _getPositionKey(ori));
    final pos = _loadPositionFromString(ps);
    if (pos == null) {
      final size = MediaQuery.of(context).size;
      final padding = MediaQuery.of(context).padding;
      final availableHeight = size.height - padding.top - padding.bottom;
      _position = Offset(_getOffsetX(size.width),
          availableHeight - _kSpaceToVerticalEdge - _kLeftRightButtonHeight);
    } else {
      _position = pos;
      _preSavedPos = pos;
    }
  }

  void _resetPosition(Orientation ori) {
    setState(() {
      _restorePosition(ori);
      _isInitialized = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateBlockedRect();
    });
  }

  void _updateBlockedRect() {
    if (_lastBlockedRect != null) {
      _cursorModel.removeBlockedRect(_lastBlockedRect!);
    }
    final newRect = Rect.fromLTWH(_position.dx, _position.dy,
        _kLeftRightButtonWidth, _kLeftRightButtonHeight);
    _cursorModel.addBlockedRect(newRect);
    _lastBlockedRect = newRect;
  }

  void _onMoveUpdateDelta(Offset delta) {
    final context = this.context;
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final availableHeight = size.height - padding.top - padding.bottom;
    Offset newPosition = _position + delta;
    double minX = _kSpaceToHorizontalEdge;
    double minY = _kSpaceToVerticalEdge;
    double maxX = size.width - _kLeftRightButtonWidth - _kSpaceToHorizontalEdge;
    double maxY = availableHeight - _kLeftRightButtonHeight - _kSpaceToVerticalEdge;
    newPosition = Offset(
      newPosition.dx.clamp(minX, maxX),
      newPosition.dy.clamp(minY, maxY),
    );
    final isPositionChanged = !(isDoubleEqual(newPosition.dx, _position.dx) &&
        isDoubleEqual(newPosition.dy, _position.dy));
    setState(() {
      _position = newPosition;
    });
    if (isPositionChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateBlockedRect();
      });
    }
  }

  void _onBodyPointerMoveUpdate(PointerMoveEvent event) {
    _cursorModel.blockEvents = true;
    // If move, it's a drag, not a tap.
    _isDragging = true;
    // Cancel the timer to prevent it from being recognized as a tap/hold.
    _tapDownTimer?.cancel();
    _tapDownTimer = null;
    _onMoveUpdateDelta(event.delta);
  }

  Widget _buildButtonIcon() {
    final double w = _kLeftRightButtonWidth * 0.45;
    final double h = _kLeftRightButtonHeight * 0.75;
    final double borderRadius = w * 0.5;
    final double quarterCircleRadius = borderRadius * 0.9;
    return Stack(
      children: [
        Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_kLeftRightButtonWidth * 0.225),
            color: Colors.white,
          ),
        ),
        Positioned(
          left: _isLeft ? quarterCircleRadius * 0.25 : null,
          right: _isLeft ? null : quarterCircleRadius * 0.25,
          top: quarterCircleRadius * 0.25,
          child: CustomPaint(
            size: Size(quarterCircleRadius * 2, quarterCircleRadius * 2),
            painter: _QuarterCirclePainter(
              color: _kDefaultColor,
              isLeft: _isLeft,
              radius: quarterCircleRadius,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const SizedBox.shrink();
    }
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned(
            left: _position.dx,
            top: _position.dy,
            child: Listener(
        onPointerMove: _onBodyPointerMoveUpdate,
        onPointerDown: (event) async {
          _isDragging = false;
          setState(() {
            _isDown = true;
          });
          // Start a timer. If it fires, it's a hold.
          _tapDownTimer?.cancel();
          _tapDownTimer = Timer(_pressTimeout, () {
            isSpecialHoldDragActive = true;
            () async {
              await _cursorModel.syncCursorPosition();
              await _inputModel
                  .tapDown(_isLeft ? MouseButtons.left : MouseButtons.right);
            }();
            _tapDownTimer = null;
          });
        },
        onPointerUp: (event) {
          _cursorModel.blockEvents = false;
          setState(() {
            _isDown = false;
          });
          // If timer is active, it's a quick tap.
          if (_tapDownTimer != null) {
            _tapDownTimer!.cancel();
            _tapDownTimer = null;
            // Fire tap down and up quickly.
            _inputModel
                .tapDown(_isLeft ? MouseButtons.left : MouseButtons.right)
                .then(
                    (_) => Future.delayed(const Duration(milliseconds: 50), () {
                          _inputModel.tapUp(
                              _isLeft ? MouseButtons.left : MouseButtons.right);
                        }));
          } else {
            // If it's not a quick tap, it could be a hold or drag.
            // If it was a hold, isSpecialHoldDragActive is true.
            if (isSpecialHoldDragActive) {
              _inputModel
                  .tapUp(_isLeft ? MouseButtons.left : MouseButtons.right);
            }
          }

          if (_isDragging) {
            _trySavePosition();
          }
          isSpecialHoldDragActive = false;
        },
        onPointerCancel: (event) {
          _cursorModel.blockEvents = false;
          setState(() {
            _isDown = false;
          });
          _tapDownTimer?.cancel();
          _tapDownTimer = null;
          if (isSpecialHoldDragActive) {
            _inputModel.tapUp(_isLeft ? MouseButtons.left : MouseButtons.right);
          }
          isSpecialHoldDragActive = false;
          if (_isDragging) {
            _trySavePosition();
          }
        },
        child: Container(
          width: _kLeftRightButtonWidth,
          height: _kLeftRightButtonHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _kDefaultColor,
            border: Border.all(
                color: _isDown ? _kTapDownColor : _kDefaultBorderColor,
                width: _kBorderWidth),
            borderRadius: _isLeft
                ? BorderRadius.horizontal(
                    left: Radius.circular(_kLeftRightButtonHeight * 0.5))
                : BorderRadius.horizontal(
                    right: Radius.circular(_kLeftRightButtonHeight * 0.5)),
          ),
          child: _buildButtonIcon(),
        ),
      ),
          ),
        ],
      ),
    );
  }
}

class _QuarterCirclePainter extends CustomPainter {
  final Color color;
  final bool isLeft;
  final double radius;
  _QuarterCirclePainter(
      {required this.color, required this.isLeft, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final rect = Rect.fromLTWH(0, 0, radius * 2, radius * 2);
    if (isLeft) {
      canvas.drawArc(rect, -pi, pi / 2, true, paint);
    } else {
      canvas.drawArc(rect, -pi / 2, pi / 2, true, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

// Virtual joystick sends the absolute movement for now.
// Maybe we need to change it to relative movement in the future.
class VirtualJoystick extends StatefulWidget {
  final CursorModel cursorModel;
  final Size stackSize;

  const VirtualJoystick({super.key, required this.cursorModel, required this.stackSize});

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  Offset _position = Offset.zero;
  bool _isInitialized = false;
  Offset _offset = Offset.zero;
  final double _joystickRadius = 50.0;
  final double _thumbRadius = 20.0;
  final double _moveStep = 3.0;
  final double _speed = 1.0;

  // One-shot timer to detect a drag gesture
  Timer? _dragStartTimer;
  // Periodic timer for continuous movement
  Timer? _continuousMoveTimer;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    widget.cursorModel.blockEvents = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resetPosition();
    });
  }

  @override
  void dispose() {
    _stopSendEventTimer();
    widget.cursorModel.blockEvents = false;
    super.dispose();
  }

  @override
  void didUpdateWidget(VirtualJoystick oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stackSize != widget.stackSize) {
      _resetPosition();
    }
  }

  void _resetPosition() {
    final w = widget.stackSize.width;
    final h = widget.stackSize.height;
    final isLandscape = w > h;
    final offset = isLandscape ? _kCenterToWidgetOffset * 2.5 : _kCenterToWidgetOffset;
    setState(() {
      _position = Offset(
        w / 2 - offset,
        h - _kBottomOffset - _wheelHeight / 2,
      );
      _isInitialized = true;
    });
  }

  Offset _offsetToPanDelta(Offset offset) {
    return Offset(
      offset.dx / _joystickRadius,
      offset.dy / _joystickRadius,
    );
  }

  void _stopSendEventTimer() {
    _dragStartTimer?.cancel();
    _continuousMoveTimer?.cancel();
    _dragStartTimer = null;
    _continuousMoveTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Positioned(child: Offstage());
    }
    return Positioned(
      left: _position.dx - _joystickRadius,
      top: _position.dy - _joystickRadius,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _isPressed = true;
          });
          widget.cursorModel.blockEvents = true;
          _updateOffset(details.localPosition);

          // 1. Send a single, small pan event immediately for responsiveness.
          //    The movement is small for a gentle start.
          final initialDelta = _offsetToPanDelta(_offset);
          if (initialDelta.distance > 0) {
            widget.cursorModel.updatePan(initialDelta, Offset.zero, false);
          }

          // 2. Start a one-shot timer to check if the user is holding for a drag.
          _dragStartTimer?.cancel();
          _dragStartTimer = Timer(const Duration(milliseconds: 120), () {
            // 3. If the timer fires, it's a drag. Start the continuous movement timer.
            _continuousMoveTimer?.cancel();
            _continuousMoveTimer =
                periodic_immediate(const Duration(milliseconds: 20), () async {
              if (_offset != Offset.zero) {
                widget.cursorModel.updatePan(
                    _offsetToPanDelta(_offset) * _moveStep * _speed,
                    Offset.zero,
                    false);
              }
            });
          });
        },
        onPanUpdate: (details) {
          _updateOffset(details.localPosition);
        },
        onPanEnd: (details) {
          setState(() {
            _offset = Offset.zero;
            _isPressed = false;
          });
          widget.cursorModel.blockEvents = false;

          // 4. Critical step: On pan end, cancel all timers.
          //    If it was a flick, this cancels the drag detection before it fires.
          //    If it was a drag, this stops the continuous movement.
          _stopSendEventTimer();
        },
        child: SizedBox(
          width: _joystickRadius * 2,
          height: _joystickRadius * 2,
          child: Stack(
            children: [
              // Glass base circle
              ClipOval(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: _joystickRadius * 2,
                    height: _joystickRadius * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFEFEFE).withOpacity(0.3),
                      border: Border.all(
                        color: _isPressed
                            ? _kTapDownColor
                            : const Color(0xFFFFFFFF).withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
              // Thumb
              Positioned(
                left: _joystickRadius + _offset.dx - _thumbRadius,
                top: _joystickRadius + _offset.dy - _thumbRadius,
                child: Container(
                  width: _thumbRadius * 2,
                  height: _thumbRadius * 2,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFFEFEFE),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateOffset(Offset localPosition) {
    final center = Offset(_joystickRadius, _joystickRadius);
    final offset = localPosition - center;
    final distance = offset.distance;

    if (distance <= _joystickRadius) {
      setState(() {
        _offset = offset;
      });
    } else {
      final clampedOffset = offset / distance * _joystickRadius;
      setState(() {
        _offset = clampedOffset;
      });
    }
  }
}

