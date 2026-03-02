import 'package:auto_size_text/auto_size_text.dart';
import 'package:debounce_throttle/debounce_throttle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../consts.dart';
import '../../desktop/widgets/tabbar_widget.dart';
import '../../models/chat_model.dart';
import '../../models/model.dart';
import 'chat_page.dart';

class DraggableChatWindow extends StatelessWidget {
  const DraggableChatWindow(
      {Key? key,
      this.position = Offset.zero,
      required this.width,
      required this.height,
      required this.chatModel})
      : super(key: key);

  final Offset position;
  final double width;
  final double height;
  final ChatModel chatModel;

  @override
  Widget build(BuildContext context) {
    if (draggablePositions.chatWindow.isInvalid()) {
      draggablePositions.chatWindow.update(position);
    }
    return isIOS
        ? IOSDraggable(
            position: draggablePositions.chatWindow,
            chatModel: chatModel,
            width: width,
            height: height,
            builder: (context, onPanUpdate) {
              return Column(
                children: [
                  GestureDetector(
                    onPanUpdate: onPanUpdate,
                    child: _buildDesktopAppBar(context),
                  ),
                  Expanded(
                    child: ChatPage(chatModel: chatModel),
                  ),
                ],
              );
            },
          )
        : Draggable(
            checkKeyboard: true,
            checkScreenSize: true,
            position: draggablePositions.chatWindow,
            width: width,
            height: height,
            chatModel: chatModel,
            sizeStore: draggablePositions.chatWindowSize,
            minWidth: DraggablePositions.kMinChatWidth,
            minHeight: DraggablePositions.kMinChatHeight,
            builder: (context, onPanUpdate) {
              final child = Scaffold(
                resizeToAvoidBottomInset: false,
                appBar: CustomAppBar(
                  onPanUpdate: onPanUpdate,
                  appBar: _buildDesktopAppBar(context),
                ),
                body: ChatPage(chatModel: chatModel),
              );
              return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: MyTheme.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: child));
            });
  }

  Widget _buildMobileAppBar(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.primary,
      height: 50,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Text(
                translate("Chat"),
                style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'WorkSans',
                    fontWeight: FontWeight.bold,
                    fontSize: 20),
              )),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                  onPressed: () {
                    chatModel.hideChatWindowOverlay();
                  },
                  icon: const Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.white,
                  )),
              IconButton(
                  onPressed: () {
                    chatModel.hideChatWindowOverlay();
                    chatModel.hideChatIconOverlay();
                  },
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white,
                  ))
            ],
          )
        ],
      ),
    );
  }

  Widget _buildDesktopAppBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: Theme.of(context).hintColor.withOpacity(0.4)))),
      height: 38,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              child: Obx(() => Opacity(
                  opacity: chatModel.isWindowFocus.value ? 1.0 : 0.4,
                  child: Row(children: [
                    Icon(Icons.chat_bubble_outline,
                        size: 20, color: const Color(0xFF5F71FF)),
                    SizedBox(width: 6),
                    Text(translate("Chat"))
                  ])))),
          Padding(
              padding: EdgeInsets.all(2),
              child: ActionIcon(
                message: 'Close',
                icon: IconFont.close,
                onTap: chatModel.hideChatWindowOverlay,
                isClose: true,
                boxSize: 32,
              ))
        ],
      ),
    );
  }
}

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final GestureDragUpdateCallback onPanUpdate;
  final Widget appBar;

  const CustomAppBar(
      {Key? key, required this.onPanUpdate, required this.appBar})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(onPanUpdate: onPanUpdate, child: appBar);
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

/// floating buttons of back/home/recent actions for android
class DraggableMobileActions extends StatelessWidget {
  DraggableMobileActions(
      {this.onBackPressed,
      this.onRecentPressed,
      this.onHomePressed,
      this.onHidePressed,
      required this.position,
      required this.width,
      required this.height,
      required this.scale});

  final double scale;
  final DraggableKeyPosition position;
  final double width;
  final double height;
  final VoidCallback? onBackPressed;
  final VoidCallback? onHomePressed;
  final VoidCallback? onRecentPressed;
  final VoidCallback? onHidePressed;

  @override
  Widget build(BuildContext context) {
    return Draggable(
        position: position,
        width: scale * width,
        height: scale * height,
        builder: (_, onPanUpdate) {
          return GestureDetector(
              onPanUpdate: onPanUpdate,
              child: Card(
                  color: Colors.transparent,
                  shadowColor: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                        color: MyTheme.accent.withOpacity(0.4),
                        borderRadius:
                            BorderRadius.all(Radius.circular(15 * scale))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        IconButton(
                            color: Colors.white,
                            onPressed: onBackPressed,
                            splashRadius: kDesktopIconButtonSplashRadius,
                            icon: const Icon(Icons.arrow_back),
                            iconSize: 24 * scale),
                        IconButton(
                            color: Colors.white,
                            onPressed: onHomePressed,
                            splashRadius: kDesktopIconButtonSplashRadius,
                            icon: const Icon(Icons.home),
                            iconSize: 24 * scale),
                        IconButton(
                            color: Colors.white,
                            onPressed: onRecentPressed,
                            splashRadius: kDesktopIconButtonSplashRadius,
                            icon: const Icon(Icons.more_horiz),
                            iconSize: 24 * scale),
                        const VerticalDivider(
                          width: 0,
                          thickness: 2,
                          indent: 10,
                          endIndent: 10,
                        ),
                        IconButton(
                            color: Colors.white,
                            onPressed: onHidePressed,
                            splashRadius: kDesktopIconButtonSplashRadius,
                            icon: const Icon(Icons.keyboard_arrow_down),
                            iconSize: 24 * scale),
                      ],
                    ),
                  )));
        });
  }
}

/// 채팅창 크기 저장 클래스
class DraggableKeySize {
  final String key;
  final double defaultWidth;
  final double defaultHeight;
  Size _size;
  late Debouncer<int> _debouncerStore;

  DraggableKeySize(this.key, {required this.defaultWidth, required this.defaultHeight})
      : _size = Size(defaultWidth, defaultHeight);

  Size get size => _size;
  double get width => _size.width;
  double get height => _size.height;

  void load() {
    final value = bind.getLocalFlutterOption(k: key);
    if (value.isNotEmpty) {
      final parts = value.split(',');
      if (parts.length == 2) {
        _size = Size(double.parse(parts[0]), double.parse(parts[1]));
      }
    }
    _debouncerStore = Debouncer<int>(const Duration(milliseconds: 500),
        onChanged: (v) => _store(), initialValue: 0);
  }

  void update(Size size) {
    _size = size;
    _triggerStore();
  }

  void _triggerStore() => _debouncerStore.value = _debouncerStore.value + 1;
  void _store() {
    bind.setLocalFlutterOption(k: key, v: '${_size.width},${_size.height}');
  }
}

class DraggableKeyPosition {
  final String key;
  Offset _pos;
  late Debouncer<int> _debouncerStore;
  DraggableKeyPosition(this.key)
      : _pos = DraggablePositions.kInvalidDraggablePosition;

  get pos => _pos;

  _loadPosition(String k) {
    final value = bind.getLocalFlutterOption(k: k);
    if (value.isNotEmpty) {
      final parts = value.split(',');
      if (parts.length == 2) {
        return Offset(double.parse(parts[0]), double.parse(parts[1]));
      }
    }
    return DraggablePositions.kInvalidDraggablePosition;
  }

  load() {
    _pos = _loadPosition(key);
    _debouncerStore = Debouncer<int>(const Duration(milliseconds: 500),
        onChanged: (v) => _store(), initialValue: 0);
  }

  update(Offset pos) {
    _pos = pos;
    _triggerStore();
  }

  // Adjust position to keep it in the screen
  // Only used for desktop and web desktop
  tryAdjust(double w, double h, double scale) {
    final size = MediaQuery.of(Get.context!).size;
    w = w * scale;
    h = h * scale;
    double x = _pos.dx;
    double y = _pos.dy;
    if (x + w > size.width) {
      x = size.width - w;
    }
    final tabBarHeight = isDesktop ? kDesktopRemoteTabBarHeight : 0;
    if (y + h > (size.height - tabBarHeight)) {
      y = size.height - tabBarHeight - h;
    }
    if (x < 0) {
      x = 0;
    }
    if (y < 0) {
      y = 0;
    }
    if (x != _pos.dx || y != _pos.dy) {
      update(Offset(x, y));
    }
  }

  isInvalid() {
    return _pos == DraggablePositions.kInvalidDraggablePosition;
  }

  _triggerStore() => _debouncerStore.value = _debouncerStore.value + 1;
  _store() {
    bind.setLocalFlutterOption(k: key, v: '${_pos.dx},${_pos.dy}');
  }
}

class DraggablePositions {
  static const kChatWindow = 'draggablePositionChat';
  static const kChatWindowSize = 'draggableSizeChat';
  static const kMobileActions = 'draggablePositionMobile';
  static const kIOSDraggable = 'draggablePositionIOS';

  static const kInvalidDraggablePosition = Offset(-999999, -999999);
  static const kDefaultChatWidth = 300.0;
  static const kDefaultChatHeight = 400.0;
  static const kMinChatWidth = 200.0;
  static const kMinChatHeight = 250.0;

  final chatWindow = DraggableKeyPosition(kChatWindow);
  final chatWindowSize = DraggableKeySize(kChatWindowSize,
      defaultWidth: kDefaultChatWidth, defaultHeight: kDefaultChatHeight);
  final mobileActions = DraggableKeyPosition(kMobileActions);
  final iOSDraggable = DraggableKeyPosition(kIOSDraggable);

  load() {
    chatWindow.load();
    chatWindowSize.load();
    mobileActions.load();
    iOSDraggable.load();
  }
}

DraggablePositions draggablePositions = DraggablePositions();

class Draggable extends StatefulWidget {
  Draggable(
      {Key? key,
      this.checkKeyboard = false,
      this.checkScreenSize = false,
      required this.position,
      required this.width,
      required this.height,
      this.chatModel,
      this.sizeStore,
      this.minWidth,
      this.minHeight,
      required this.builder})
      : super(key: key);

  final bool checkKeyboard;
  final bool checkScreenSize;
  final DraggableKeyPosition position;
  final double width;
  final double height;
  final ChatModel? chatModel;
  final DraggableKeySize? sizeStore;
  final double? minWidth;
  final double? minHeight;
  final Widget Function(BuildContext, GestureDragUpdateCallback) builder;

  @override
  State<StatefulWidget> createState() => _DraggableState(chatModel);
}

class _DraggableState extends State<Draggable> {
  late ChatModel? _chatModel;
  bool _keyboardVisible = false;
  double _saveHeight = 0;
  double _lastBottomHeight = 0;

  _DraggableState(ChatModel? chatModel) {
    _chatModel = chatModel;
  }

  get position => widget.position.pos;

  // 현재 크기 (sizeStore가 있으면 저장된 크기 사용, 없으면 widget 기본 크기)
  double get currentWidth => widget.sizeStore?.width ?? widget.width;
  double get currentHeight => widget.sizeStore?.height ?? widget.height;

  void onPanUpdate(DragUpdateDetails d) {
    final offset = d.delta;
    final size = MediaQuery.of(context).size;
    double x = 0;
    double y = 0;

    if (position.dx + offset.dx + currentWidth > size.width) {
      x = size.width - currentWidth;
    } else if (position.dx + offset.dx < 0) {
      x = 0;
    } else {
      x = position.dx + offset.dx;
    }

    if (position.dy + offset.dy + currentHeight > size.height) {
      y = size.height - currentHeight;
    } else if (position.dy + offset.dy < 0) {
      y = 0;
    } else {
      y = position.dy + offset.dy;
    }
    setState(() {
      widget.position.update(Offset(x, y));
    });
    _chatModel?.setChatWindowPosition(position);
  }

  // 리사이즈 핸들러
  void onResizeUpdate(DragUpdateDetails d) {
    if (widget.sizeStore == null) return;

    final screenSize = MediaQuery.of(context).size;
    final minW = widget.minWidth ?? 100;
    final minH = widget.minHeight ?? 100;

    double newWidth = currentWidth + d.delta.dx;
    double newHeight = currentHeight + d.delta.dy;

    // 최소 크기 제한
    newWidth = newWidth.clamp(minW, screenSize.width - position.dx);
    newHeight = newHeight.clamp(minH, screenSize.height - position.dy);

    setState(() {
      widget.sizeStore!.update(Size(newWidth, newHeight));
    });
  }

  checkScreenSize() {
    // Ensure the draggable always stays within current screen bounds
    widget.position.tryAdjust(currentWidth, currentHeight, 1);
  }

  checkKeyboard() {
    final bottomHeight = MediaQuery.of(context).viewInsets.bottom;
    final currentVisible = bottomHeight != 0;

    // save
    if (!_keyboardVisible && currentVisible) {
      _saveHeight = position.dy;
    }

    // reset
    if (_lastBottomHeight > 0 && bottomHeight == 0) {
      setState(() {
        widget.position.update(Offset(position.dx, _saveHeight));
      });
    }

    // onKeyboardVisible
    if (_keyboardVisible && currentVisible) {
      final sumHeight = bottomHeight + currentHeight;
      final contextHeight = MediaQuery.of(context).size.height;
      if (sumHeight + position.dy > contextHeight) {
        final y = contextHeight - sumHeight;
        setState(() {
          widget.position.update(Offset(position.dx, y));
        });
      }
    }

    _keyboardVisible = currentVisible;
    _lastBottomHeight = bottomHeight;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.checkKeyboard) {
      checkKeyboard();
    }
    if (widget.checkScreenSize) {
      checkScreenSize();
    }
    return Stack(children: [
      Positioned(
          top: position.dy,
          left: position.dx,
          width: currentWidth,
          height: currentHeight,
          child: Stack(
            children: [
              widget.builder(context, onPanUpdate),
              // 리사이즈 핸들 (sizeStore가 있을 때만 표시)
              if (widget.sizeStore != null)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onPanUpdate: onResizeUpdate,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeDownRight,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: Colors.transparent,
                        ),
                        child: CustomPaint(
                          painter: _ResizeHandlePainter(),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ))
    ]);
  }
}

/// 리사이즈 핸들 페인터 (오른쪽 하단 대각선)
class _ResizeHandlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x99888888)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // 대각선 3개 그리기
    for (int i = 0; i < 3; i++) {
      final offset = 4.0 * i;
      canvas.drawLine(
        Offset(size.width - 2 - offset, size.height),
        Offset(size.width, size.height - 2 - offset),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class IOSDraggable extends StatefulWidget {
  const IOSDraggable(
      {Key? key,
      this.chatModel,
      required this.position,
      required this.width,
      required this.height,
      required this.builder})
      : super(key: key);

  final DraggableKeyPosition position;
  final ChatModel? chatModel;
  final double width;
  final double height;
  final Widget Function(BuildContext, GestureDragUpdateCallback) builder;

  @override
  IOSDraggableState createState() =>
      IOSDraggableState(chatModel, width, height);
}

class IOSDraggableState extends State<IOSDraggable> {
  late ChatModel? _chatModel;
  late double _width;
  late double _height;
  bool _keyboardVisible = false;
  double _saveHeight = 0;
  double _lastBottomHeight = 0;

  IOSDraggableState(ChatModel? chatModel, double w, double h) {
    _chatModel = chatModel;
    _width = w;
    _height = h;
  }

  DraggableKeyPosition get position => widget.position;

  checkKeyboard() {
    final bottomHeight = MediaQuery.of(context).viewInsets.bottom;
    final currentVisible = bottomHeight != 0;

    // save
    if (!_keyboardVisible && currentVisible) {
      _saveHeight = position.pos.dy;
    }

    // reset
    if (_lastBottomHeight > 0 && bottomHeight == 0) {
      setState(() {
        position.update(Offset(position.pos.dx, _saveHeight));
      });
    }

    // onKeyboardVisible
    if (_keyboardVisible && currentVisible) {
      final sumHeight = bottomHeight + _height;
      final contextHeight = MediaQuery.of(context).size.height;
      if (sumHeight + position.pos.dy > contextHeight) {
        final y = contextHeight - sumHeight;
        setState(() {
          position.update(Offset(position.pos.dx, y));
        });
      }
    }

    _keyboardVisible = currentVisible;
    _lastBottomHeight = bottomHeight;
  }

  @override
  void initState() {
    super.initState();
    position.tryAdjust(_width, _height, 1);
  }

  @override
  Widget build(BuildContext context) {
    checkKeyboard();
    return Stack(
      children: [
        Positioned(
          left: position.pos.dx,
          top: position.pos.dy,
          child: Material(
            child: Container(
              width: _width,
              height: _height,
              decoration: BoxDecoration(
                border: Border.all(color: MyTheme.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: widget.builder(context, (details) {
                  setState(() {
                    position.update(position.pos + details.delta);
                  });
                  _chatModel?.setChatWindowPosition(position.pos);
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class QualityMonitor extends StatelessWidget {
  final QualityMonitorModel qualityMonitorModel;
  QualityMonitor(this.qualityMonitorModel);

  Widget _row(String info, String? value, {Color? rightColor}) {
    return Row(
      children: [
        Expanded(
            flex: 8,
            child: AutoSizeText(info,
                style: TextStyle(color: Color.fromARGB(255, 210, 210, 210)),
                textAlign: TextAlign.right,
                maxLines: 1)),
        Spacer(flex: 1),
        Expanded(
            flex: 8,
            child: AutoSizeText(value ?? '',
                style: TextStyle(color: rightColor ?? Colors.white),
                maxLines: 1)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
      value: qualityMonitorModel,
      child: Consumer<QualityMonitorModel>(
          builder: (context, qualityMonitorModel, child) => qualityMonitorModel
                  .show
              ? Container(
                  constraints: BoxConstraints(maxWidth: 200),
                  padding: const EdgeInsets.all(8),
                  color: MyTheme.canvasColor.withAlpha(150),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row("Speed", qualityMonitorModel.data.speed ?? '-'),
                      _row("FPS", qualityMonitorModel.data.fps ?? '-'),
                      // let delay be 0 if fps is 0
                      _row(
                          "Delay",
                          "${qualityMonitorModel.data.delay == null ? '-' : (qualityMonitorModel.data.fps ?? "").replaceAll(' ', '').replaceAll('0', '').isEmpty ? 0 : qualityMonitorModel.data.delay}ms",
                          rightColor: Colors.green),
                      _row("Target Bitrate",
                          "${qualityMonitorModel.data.targetBitrate ?? '-'}kb"),
                      _row(
                          "Codec", qualityMonitorModel.data.codecFormat ?? '-'),
                      _row("Chroma", qualityMonitorModel.data.chroma ?? '-'),
                    ],
                  ),
                )
              : const SizedBox.shrink()));
}

class BlockableOverlayState extends OverlayKeyState {
  final _middleBlocked = false.obs;

  VoidCallback? onMiddleBlockedClick; // to-do use listener

  RxBool get middleBlocked => _middleBlocked;

  void addMiddleBlockedListener(void Function(bool) cb) {
    _middleBlocked.listen(cb);
  }

  void setMiddleBlocked(bool blocked) {
    if (blocked != _middleBlocked.value) {
      _middleBlocked.value = blocked;
    }
  }

  void applyFfi(FFI ffi) {
    ffi.dialogManager.setOverlayState(this);
    ffi.chatModel.setOverlayState(this);
    // make remote page penetrable automatically, effective for chat over remote
    onMiddleBlockedClick = () {
      setMiddleBlocked(false);
    };
  }
}

class BlockableOverlay extends StatelessWidget {
  final Widget underlying;
  final List<OverlayEntry>? upperLayer;

  final BlockableOverlayState state;

  BlockableOverlay(
      {required this.underlying, required this.state, this.upperLayer});

  @override
  Widget build(BuildContext context) {
    final initialEntries = [
      OverlayEntry(builder: (_) => underlying),

      /// middle layer
      OverlayEntry(
          builder: (context) => Obx(() => Listener(
              onPointerDown: (_) {
                state.onMiddleBlockedClick?.call();
              },
              child: Container(
                  color:
                      state.middleBlocked.value ? Colors.transparent : null)))),
    ];

    if (upperLayer != null) {
      initialEntries.addAll(upperLayer!);
    }

    /// set key
    return Overlay(key: state.key, initialEntries: initialEntries);
  }
}
