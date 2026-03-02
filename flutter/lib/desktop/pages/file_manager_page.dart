import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:extended_text/extended_text.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/common/widgets/styled_form_widgets.dart';
import 'package:flutter_hbb/common/widgets/styled_text_field.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_breadcrumb/flutter_breadcrumb.dart';
import 'package:flutter_hbb/desktop/widgets/list_search_action_listener.dart';
import 'package:flutter_hbb/desktop/widgets/menu_button.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/file_model.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_hbb/web/dummy.dart'
    if (dart.library.html) 'package:flutter_hbb/web/web_unique.dart';

import '../../consts.dart';
import '../../desktop/widgets/material_mod_popup_menu.dart' as mod_menu;
import '../../common.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../widgets/popup_menu.dart';

/// status of location bar
enum LocationStatus {
  /// normal bread crumb bar
  bread,

  /// show path text field
  pathLocation,

  /// show file search bar text field
  fileSearchBar
}

/// The status of currently focused scope of the mouse
enum MouseFocusScope {
  /// Mouse is in local field.
  local,

  /// Mouse is in remote field.
  remote,

  /// Mouse is not in local field, remote neither.
  none
}

class FileManagerPage extends StatefulWidget {
  FileManagerPage(
      {Key? key,
      required this.id,
      required this.password,
      required this.isSharedPassword,
      this.tabController,
      this.connToken,
      this.forceRelay})
      : super(key: key);
  final String id;
  final String? password;
  final bool? isSharedPassword;
  final bool? forceRelay;
  final String? connToken;
  final DesktopTabController? tabController;
  final SimpleWrapper<State<FileManagerPage>?> _lastState = SimpleWrapper(null);

  FFI get ffi => (_lastState.value! as _FileManagerPageState)._ffi;

  @override
  State<StatefulWidget> createState() {
    final state = _FileManagerPageState();
    _lastState.value = state;
    return state;
  }
}

class _FileManagerPageState extends State<FileManagerPage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _mouseFocusScope = Rx<MouseFocusScope>(MouseFocusScope.none);

  final _dropMaskVisible = false.obs; // TODO impl drop mask
  final _overlayKeyState = OverlayKeyState();

  late FFI _ffi;

  FileModel get model => _ffi.fileModel;
  JobController get jobController => model.jobController;

  @override
  void initState() {
    super.initState();
    _ffi = FFI(null);
    _ffi.start(widget.id,
        isFileTransfer: true,
        password: widget.password,
        isSharedPassword: widget.isSharedPassword,
        connToken: widget.connToken,
        forceRelay: widget.forceRelay);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ffi.dialogManager
          .showLoading(translate('Connecting...'), onCancel: closeConnection);
    });
    Get.put<FFI>(_ffi, tag: 'ft_${widget.id}');
    if (!isLinux) {
      WakelockPlus.enable();
    }
    if (isWeb) {
      _ffi.ffiModel.updateEventListener(_ffi.sessionId, widget.id);
    }
    debugPrint("File manager page init success with id ${widget.id}");
    _ffi.dialogManager.setOverlayState(_overlayKeyState);
    // Call onSelected in post frame callback, since we cannot guarantee that the callback will not call setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.tabController?.onSelected?.call(widget.id);
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    model.close().whenComplete(() {
      _ffi.close();
      _ffi.dialogManager.dismissAll();
      if (!isLinux) {
        WakelockPlus.disable();
      }
      Get.delete<FFI>(tag: 'ft_${widget.id}');
    });
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      jobController.jobTable.refresh();
    }
  }

  Widget willPopScope(Widget child) {
    if (isWeb) {
      return WillPopScope(
        onWillPop: () async {
          clientClose(_ffi.sessionId, _ffi);
          return false;
        },
        child: child,
      );
    } else {
      return child;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Overlay(key: _overlayKeyState.key, initialEntries: [
      OverlayEntry(builder: (_) {
        return willPopScope(Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Row(
            children: [
              if (!isWeb)
                Flexible(
                    flex: 3,
                    child: dropArea(FileManagerView(
                        model.localController, _ffi, _mouseFocusScope))),
              Flexible(
                  flex: 3,
                  child: dropArea(FileManagerView(
                      model.remoteController, _ffi, _mouseFocusScope))),
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(vertical: 16.0),
                color: const Color(0xFFDEDEE2),
              ),
              Flexible(flex: 2, child: statusList())
            ],
          ),
        ));
      })
    ]);
  }

  Widget dropArea(FileManagerView fileView) {
    return DropTarget(
        onDragDone: (detail) =>
            handleDragDone(detail, fileView.controller.isLocal),
        onDragEntered: (enter) {
          _dropMaskVisible.value = true;
        },
        onDragExited: (exit) {
          _dropMaskVisible.value = false;
        },
        child: fileView);
  }

  Widget generateCard(Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFEFEFE),
        borderRadius: BorderRadius.all(
          Radius.circular(16.0),
        ),
        border: Border.all(color: const Color(0xFFF2F1F6)),
      ),
      child: child,
    );
  }

  /// transfer status list
  /// watch transfer status
  Widget statusList() {
    Widget getIcon(JobProgress job) {
      const iconColor = Color(0xFF94A0FF);
      String iconPath;
      switch (job.type) {
        case JobType.deleteDir:
        case JobType.deleteFile:
          iconPath = "assets/icons/file-sender-delete.svg";
          break;
        default:
          iconPath = "assets/icons/file-sender-file.svg";
      }
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFFEFF1FF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: SvgPicture.asset(
            iconPath,
            width: 24,
            height: 24,
            colorFilter: svgColor(iconColor),
          ),
        ),
      );
    }

    statusListView(List<JobProgress> jobs) => ListView.builder(
          controller: ScrollController(),
          itemBuilder: (BuildContext context, int index) {
            final item = jobs[index];
            final status = item.getStatus();
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: generateCard(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        getIcon(item)
                            .marginSymmetric(horizontal: 10, vertical: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Tooltip(
                                waitDuration: Duration(milliseconds: 500),
                                message: item.state == JobState.done && item.to.isNotEmpty
                                    ? item.to
                                    : item.jobName,
                                child: ExtendedText(
                                  item.state == JobState.done && item.to.isNotEmpty
                                      ? item.to
                                      : item.jobName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  overflowWidget: TextOverflowWidget(
                                      child: Text("..."),
                                      position: TextOverflowPosition.start),
                                ),
                              ),
                              Tooltip(
                                waitDuration: Duration(milliseconds: 500),
                                message: status,
                                child: Text(status,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: MyTheme.darkGray,
                                    )).marginOnly(top: 6),
                              ),
                              Offstage(
                                offstage: item.type != JobType.transfer ||
                                    item.state != JobState.inProgress,
                                child: LinearPercentIndicator(
                                  animateFromLastPercent: true,
                                  center: Text(
                                    '${(item.finishedSize / item.totalSize * 100).toStringAsFixed(0)}%',
                                  ),
                                  barRadius: Radius.circular(15),
                                  percent: item.finishedSize / item.totalSize,
                                  progressColor: MyTheme.accent,
                                  backgroundColor: Theme.of(context).hoverColor,
                                  lineHeight: kDesktopFileTransferRowHeight,
                                ).paddingSymmetric(vertical: 8),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Offstage(
                              offstage: item.state != JobState.paused,
                              child: MenuButton(
                                tooltip: translate("Resume"),
                                onPressed: () {
                                  jobController.resumeJob(item.id);
                                },
                                child: SvgPicture.asset(
                                  "assets/icons/file-sender-refresh.svg",
                                  colorFilter: svgColor(Colors.white),
                                ),
                                color: MyTheme.accent,
                                hoverColor: MyTheme.accent80,
                              ),
                            ),
                            _JobDeleteButton(
                              onPressed: () {
                                jobController.jobTable.removeAt(index);
                                jobController.cancelJob(item.id);
                              },
                            ),
                          ],
                        ).marginAll(12),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
          itemCount: jobController.jobTable.length,
        );

    return PreferredSize(
      preferredSize: const Size(200, double.infinity),
      child: Container(
          padding: const EdgeInsets.all(16.0),
          color: const Color(0xFFF7F7F7),
          child: Obx(
            () => jobController.jobTable.isEmpty
                ? Center(
                    child: Text(
                      translate("No transfers in progress"),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).tabBarTheme.labelColor,
                      ),
                    ),
                  )
                : statusListView(jobController.jobTable),
          )),
    );
  }

  void handleDragDone(DropDoneDetails details, bool isLocal) {
    if (isLocal) {
      // ignore local
      return;
    }
    final items = SelectedItems(isLocal: false);
    for (var file in details.files) {
      final f = File(file.path);
      items.add(Entry()
        ..path = file.path
        ..name = file.name
        ..size = FileSystemEntity.isDirectorySync(f.path) ? 0 : f.lengthSync());
    }
    final otherSideData = model.localController.directoryData();
    model.remoteController.sendFiles(items, otherSideData);
  }
}

class FileManagerView extends StatefulWidget {
  final FileController controller;
  final FFI _ffi;
  final Rx<MouseFocusScope> _mouseFocusScope;

  FileManagerView(this.controller, this._ffi, this._mouseFocusScope);

  @override
  State<StatefulWidget> createState() => _FileManagerViewState();
}

class _FileManagerViewState extends State<FileManagerView> {
  final _locationStatus = LocationStatus.bread.obs;
  final _locationNode = FocusNode();
  final _locationBarKey = GlobalKey();
  final _searchText = "".obs;
  final _breadCrumbScroller = ScrollController();
  final _keyboardNode = FocusNode();
  final _listSearchBuffer = TimeoutStringBuffer();
  final _nameColWidth = 0.0.obs;
  final _modifiedColWidth = 0.0.obs;
  final _sizeColWidth = 0.0.obs;
  final _fileListScrollController = ScrollController();
  final _globalHeaderKey = GlobalKey();
  final _locationTextController = TextEditingController();

  /// [_lastClickTime], [_lastClickEntry] help to handle double click
  var _lastClickTime =
      DateTime.now().millisecondsSinceEpoch - bind.getDoubleClickTime() - 1000;
  Entry? _lastClickEntry;

  double? _windowWidthPrev;

  FileController get controller => widget.controller;
  bool get isLocal => widget.controller.isLocal;
  FFI get _ffi => widget._ffi;
  SelectedItems get selectedItems => controller.selectedItems;

  @override
  void initState() {
    super.initState();
    // register location listener
    _locationNode.addListener(onLocationFocusChanged);
    controller.directory.listen((e) => breadCrumbScrollToEnd());
  }

  @override
  void dispose() {
    _locationNode.removeListener(onLocationFocusChanged);
    _locationNode.dispose();
    _keyboardNode.dispose();
    _breadCrumbScroller.dispose();
    _fileListScrollController.dispose();
    _locationTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _handleColumnPorportions();
    return Container(
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          headTools(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: MouseRegion(
                  onEnter: (evt) {
                    widget._mouseFocusScope.value = isLocal
                        ? MouseFocusScope.local
                        : MouseFocusScope.remote;
                    _keyboardNode.requestFocus();
                  },
                  onExit: (evt) =>
                      widget._mouseFocusScope.value = MouseFocusScope.none,
                  child: _buildFileList(context, _fileListScrollController),
                ))
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleColumnPorportions() {
    final windowWidthNow = MediaQuery.of(context).size.width;
    if (_windowWidthPrev == null) {
      _windowWidthPrev = windowWidthNow;
      final defaultColumnWidth = windowWidthNow * 0.115;
      _nameColWidth.value = defaultColumnWidth;
      _modifiedColWidth.value = defaultColumnWidth;
      _sizeColWidth.value = defaultColumnWidth;
    }

    if (_windowWidthPrev != windowWidthNow) {
      final difference = windowWidthNow / _windowWidthPrev!;
      _windowWidthPrev = windowWidthNow;
      _nameColWidth.value *= difference;
      _modifiedColWidth.value *= difference;
      _sizeColWidth.value *= difference;
    }
  }

  void onLocationFocusChanged() {
    debugPrint("focus changed on local");
    if (_locationNode.hasFocus) {
      // ignore
    } else {
      // lost focus, change to bread
      if (_locationStatus.value != LocationStatus.fileSearchBar) {
        _locationStatus.value = LocationStatus.bread;
      }
    }
  }

  Widget headTools() {
    var uploadButtonTapPosition = RelativeRect.fill;
    RxBool isUploadFolder =
        (bind.mainGetLocalOption(key: 'upload-folder-button') == 'Y').obs;
    return Container(
      child: Column(
        children: [
          // symbols
          PreferredSize(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.all(Radius.circular(16)),
                            color: Color(0xFFEFF1FF),
                          ),
                          child: Center(
                            child: FutureBuilder<String>(
                                future: bind.sessionGetPlatform(
                                    sessionId: _ffi.sessionId,
                                    isRemote: !isLocal),
                                builder: (context, snapshot) {
                                  if (snapshot.hasData &&
                                      snapshot.data!.isNotEmpty) {
                                    return getPlatformImage('${snapshot.data}',
                                        size: 24, color: Color(0xFF5F71FF));
                                  } else {
                                    return CircularProgressIndicator(
                                      color: Color(0xFF5F71FF),
                                    );
                                  }
                                }),
                          )),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isLocal
                                ? translate("Local Computer")
                                : translate("Remote Computer"),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            isLocal
                                ? translate("My Computer")
                                : translate("Partner Computer"),
                            style: TextStyle(
                              fontSize: 13,
                              color: MyTheme.darkGray,
                            ),
                          ),
                        ],
                      ).marginOnly(left: 12.0)
                    ],
                  ),
                  preferredSize: Size(double.infinity, 100))
              .paddingOnly(bottom: 15),
          // buttons - 경로 바
          SizedBox(
            height: 43,
            child: Row(
              children: [
                // Back button (file_arrow 180도 회전)
                _NavIconButton(
                  tooltip: translate('Back'),
                  iconPath: "assets/icons/file_arrow.svg",
                  rotationAngle: 180,
                  onPressed: () {
                    selectedItems.clear();
                    controller.goBack();
                  },
                ),
                // Parent directory button (file_arrow -90도 회전)
                _NavIconButton(
                  tooltip: translate('Parent directory'),
                  iconPath: "assets/icons/file_arrow.svg",
                  rotationAngle: -90,
                  onPressed: () {
                    selectedItems.clear();
                    controller.goToParentDirectory();
                  },
                ),
                // Path bar (보더 적용)
                Expanded(
                  child: Container(
                    height: 43,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFB9B8BF)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: GestureDetector(
                      onTap: () {
                        _locationStatus.value =
                            _locationStatus.value == LocationStatus.bread
                                ? LocationStatus.pathLocation
                                : LocationStatus.bread;
                        Future.delayed(Duration.zero, () {
                          if (_locationStatus.value ==
                              LocationStatus.pathLocation) {
                            _locationNode.requestFocus();
                          }
                        });
                      },
                      child: Obx(
                        () => Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                                child: _locationStatus.value ==
                                        LocationStatus.bread
                                    ? buildBread()
                                    : buildPathLocation()),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Search/Close/Refresh buttons
                Obx(() {
                  switch (_locationStatus.value) {
                    case LocationStatus.bread:
                      return _NavIconButton(
                        tooltip: translate('Search'),
                        iconPath: "assets/icons/file-sender-search.svg",
                        onPressed: () {
                          _locationStatus.value = LocationStatus.fileSearchBar;
                          Future.delayed(Duration.zero,
                              () => _locationNode.requestFocus());
                        },
                      );
                    case LocationStatus.pathLocation:
                      return _NavIconButton(
                        iconPath: "assets/icons/file-sender-close.svg",
                        onPressed: null,
                      );
                    case LocationStatus.fileSearchBar:
                      return _NavIconButton(
                        tooltip: translate('Clear'),
                        iconPath: "assets/icons/file-sender-close.svg",
                        onPressed: () {
                          onSearchText("", isLocal);
                          _locationStatus.value = LocationStatus.bread;
                        },
                      );
                  }
                }),
                _NavIconButton(
                  tooltip: translate('Refresh File'),
                  iconPath: "assets/icons/file-sender-refresh.svg",
                  onPressed: () {
                    controller.refresh();
                  },
                ),
              ],
            ),
          ),
          Row(
            textDirection: isLocal ? TextDirection.ltr : TextDirection.rtl,
            children: [
              Expanded(
                child: Row(
                  mainAxisAlignment:
                      isLocal ? MainAxisAlignment.start : MainAxisAlignment.end,
                  children: [
                    _NavIconButton(
                      tooltip: translate('Home'),
                      iconPath: "assets/icons/file-sender-home.svg",
                      onPressed: () {
                        controller.goToHomeDirectory();
                      },
                    ),
                    _NavIconButton(
                      tooltip: translate('Create Folder'),
                      iconPath: "assets/icons/file-sender-folder-new.svg",
                      onPressed: () {
                        final name = TextEditingController();
                        String? errorText;
                        _ffi.dialogManager.show((setState, close, context) {
                          name.addListener(() {
                            if (errorText != null) {
                              setState(() {
                                errorText = null;
                              });
                            }
                          });
                          submit() {
                            if (name.value.text.isNotEmpty) {
                              if (!PathUtil.validName(name.value.text,
                                  controller.options.value.isWindows)) {
                                setState(() {
                                  errorText = translate("Invalid folder name");
                                });
                                return;
                              }
                              controller.createDir(PathUtil.join(
                                controller.directory.value.path,
                                name.value.text,
                                controller.options.value.isWindows,
                              ));
                              close();
                            }
                          }

                          cancel() => close(false);
                          return CustomAlertDialog(
                            title: Text(
                              translate("Create Folder"),
                              style: MyTheme.dialogTitleStyle,
                            ),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                StyledTextField(
                                  controller: name,
                                  hintText:
                                      translate("Please enter the folder name"),
                                  errorText: errorText,
                                  autofocus: true,
                                ),
                              ],
                            ),
                            actions: [
                              Row(
                                children: [
                                  Expanded(
                                    child: StyledOutlinedButton(
                                      label: translate("Cancel"),
                                      onPressed: cancel,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: StyledPrimaryButton(
                                      label: translate("OK"),
                                      onPressed: submit,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            onSubmit: submit,
                            onCancel: cancel,
                          );
                        });
                      },
                    ),
                    Obx(() => _NavIconButton(
                          tooltip: translate('Delete'),
                          iconPath: "assets/icons/file-sender-delete.svg",
                          onPressed: SelectedItems.valid(selectedItems.items)
                              ? () async {
                                  await (controller
                                      .removeAction(selectedItems));
                                  selectedItems.clear();
                                }
                              : null,
                        )),
                    menu(isLocal: isLocal),
                  ],
                ),
              ),
              if (isWeb)
                Obx(() => ElevatedButton.icon(
                      style: ButtonStyle(
                        padding: WidgetStateProperty.all<EdgeInsetsGeometry>(
                            isLocal
                                ? EdgeInsets.only(left: 10)
                                : EdgeInsets.only(right: 10)),
                        backgroundColor: WidgetStateProperty.all(
                          selectedItems.items.isEmpty
                              ? MyTheme.accent80
                              : MyTheme.accent,
                        ),
                      ),
                      onPressed: () =>
                          {webselectFiles(is_folder: isUploadFolder.value)},
                      label: InkWell(
                        hoverColor: Colors.transparent,
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        focusColor: Colors.transparent,
                        onTapDown: (e) {
                          final x = e.globalPosition.dx;
                          final y = e.globalPosition.dy;
                          uploadButtonTapPosition =
                              RelativeRect.fromLTRB(x, y, x, y);
                        },
                        onTap: () async {
                          final value = await showMenu<bool>(
                              context: context,
                              position: uploadButtonTapPosition,
                              items: [
                                PopupMenuItem<bool>(
                                  value: false,
                                  child: Text(translate('Upload files')),
                                ),
                                PopupMenuItem<bool>(
                                  value: true,
                                  child: Text(translate('Upload folder')),
                                ),
                              ]);
                          if (value != null) {
                            isUploadFolder.value = value;
                            bind.mainSetLocalOption(
                                key: 'upload-folder-button',
                                value: value ? 'Y' : '');
                            webselectFiles(is_folder: value);
                          }
                        },
                        child: Icon(Icons.arrow_drop_down),
                      ),
                      icon: Text(
                        translate(isUploadFolder.isTrue
                            ? 'Upload folder'
                            : 'Upload files'),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Colors.white,
                        ),
                      ).marginOnly(left: 8),
                    )).marginOnly(left: 16),
              Obx(() => StyledCompactButton(
                    label: translate(
                        isLocal ? 'Send' : (isWeb ? 'Download' : 'Receive')),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    onPressed: SelectedItems.valid(selectedItems.items)
                        ? () {
                            final otherSideData =
                                controller.getOtherSideDirectoryData();
                            controller.sendFiles(selectedItems, otherSideData);
                            selectedItems.clear();
                          }
                        : null,
                  )),
            ],
          ).marginOnly(top: 8.0)
        ],
      ),
    );
  }

  Widget menu({bool isLocal = false}) {
    var menuPos = RelativeRect.fill;

    final List<MenuEntryBase<String>> items = [
      MenuEntrySwitch<String>(
        switchType: SwitchType.scheckbox,
        text: translate("Show Hidden Files"),
        getter: () async {
          return controller.options.value.showHidden;
        },
        setter: (bool v) async {
          controller.toggleShowHidden();
        },
        padding: kDesktopMenuPadding,
        dismissOnClicked: true,
      ),
      MenuEntryButton(
          childBuilder: (style) => Text(translate("Select All"), style: style),
          proc: () => setState(() =>
              selectedItems.selectAll(controller.directory.value.entries)),
          padding: kDesktopMenuPadding,
          dismissOnClicked: true),
      MenuEntryButton(
          childBuilder: (style) =>
              Text(translate("Unselect All"), style: style),
          proc: () => selectedItems.clear(),
          padding: kDesktopMenuPadding,
          dismissOnClicked: true)
    ];

    return Listener(
      onPointerDown: (e) {
        final x = e.position.dx;
        final y = e.position.dy;
        menuPos = RelativeRect.fromLTRB(x, y, x, y);
      },
      child: _NavIconButton(
        tooltip: translate('More'),
        iconPath: "assets/icons/file-sender-edit-more.svg",
        onPressed: () => mod_menu.showMenu(
          context: context,
          position: menuPos,
          items: items
              .map(
                (e) => e.build(
                  context,
                  MenuConfig(
                      commonColor: CustomPopupMenuTheme.commonColor,
                      height: CustomPopupMenuTheme.height,
                      dividerHeight: CustomPopupMenuTheme.dividerHeight),
                ),
              )
              .expand((i) => i)
              .toList(),
          elevation: 8,
        ),
      ),
    );
  }

  Widget _buildFileList(
      BuildContext context, ScrollController scrollController) {
    final fd = controller.directory.value;
    final entries = fd.entries;
    Rx<Entry?> rightClickEntry = Rx(null);

    return ListSearchActionListener(
      node: _keyboardNode,
      buffer: _listSearchBuffer,
      onNext: (buffer) {
        debugPrint("searching next for $buffer");
        assert(buffer.length == 1);
        assert(selectedItems.items.length <= 1);
        var skipCount = 0;
        if (selectedItems.items.isNotEmpty) {
          final index = entries.indexOf(selectedItems.items.first);
          if (index < 0) {
            return;
          }
          skipCount = index + 1;
        }
        var searchResult = entries
            .skip(skipCount)
            .where((element) => element.name.toLowerCase().startsWith(buffer));
        if (searchResult.isEmpty) {
          // cannot find next, lets restart search from head
          debugPrint("restart search from head");
          searchResult = entries.where(
              (element) => element.name.toLowerCase().startsWith(buffer));
        }
        if (searchResult.isEmpty) {
          selectedItems.clear();
          return;
        }
        _jumpToEntry(isLocal, searchResult.first, scrollController,
            kDesktopFileTransferRowHeight);
      },
      onSearch: (buffer) {
        debugPrint("searching for $buffer");
        final selectedEntries = selectedItems;
        final searchResult = entries
            .where((element) => element.name.toLowerCase().startsWith(buffer));
        selectedEntries.clear();
        if (searchResult.isEmpty) {
          selectedItems.clear();
          return;
        }
        _jumpToEntry(isLocal, searchResult.first, scrollController,
            kDesktopFileTransferRowHeight);
      },
      child: Obx(() {
        final entries = controller.directory.value.entries;
        final filteredEntries = _searchText.isNotEmpty
            ? entries.where((element) {
                return element.name.contains(_searchText.value);
              }).toList(growable: false)
            : entries;
        final rows = filteredEntries.map((entry) {
          final sizeStr =
              entry.isFile ? readableFileSize(entry.size.toDouble()) : "";
          final lastModifiedStr = entry.isDrive
              ? " "
              : "${entry.lastModified().toString().replaceAll(".000", "")}   ";
          var secondaryPosition = RelativeRect.fromLTRB(0, 0, 0, 0);
          onTap() {
            final items = selectedItems;
            // handle double click
            if (_checkDoubleClick(entry)) {
              controller.openDirectory(entry.path);
              items.clear();
              return;
            }
            _onSelectedChanged(items, filteredEntries, entry, isLocal);
          }

          onSecondaryTap() {
            final items = [
              if (!entry.isDrive &&
                  versionCmp(_ffi.ffiModel.pi.version, "1.3.0") >= 0)
                mod_menu.PopupMenuItem(
                  child: Text(translate("Rename")),
                  height: CustomPopupMenuTheme.height,
                  onTap: () {
                    controller.renameAction(entry, isLocal);
                  },
                )
            ];
            if (items.isNotEmpty) {
              rightClickEntry.value = entry;
              final future = mod_menu.showMenu(
                context: context,
                position: secondaryPosition,
                items: items,
              );
              future.then((value) {
                rightClickEntry.value = null;
              });
              future.onError((error, stackTrace) {
                rightClickEntry.value = null;
              });
            }
          }

          onSecondaryTapDown(details) {
            secondaryPosition = RelativeRect.fromLTRB(
                details.globalPosition.dx,
                details.globalPosition.dy,
                details.globalPosition.dx,
                details.globalPosition.dy);
          }

          final isHovered = false.obs;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
            child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => isHovered.value = true,
                onExit: (_) => isHovered.value = false,
                child: Obx(() => Container(
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.all(
                        Radius.circular(8.0),
                      ),
                      border: selectedItems.items.contains(entry) ||
                              rightClickEntry.value == entry ||
                              isHovered.value
                          ? Border.all(
                              color: const Color(0xFF5F71FF),
                              width: 1.0,
                            )
                          : null,
                    ),
                    key: ValueKey(entry.name),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Expanded(
                          child: InkWell(
                            mouseCursor: SystemMouseCursors.click,
                            child: Row(
                              children: [
                                GestureDetector(
                                  child: Obx(
                                    () => Container(
                                        width: _nameColWidth.value,
                                        child: Tooltip(
                                          waitDuration:
                                              Duration(milliseconds: 500),
                                          message: entry.name,
                                          child: Row(children: [
                                            const SizedBox(width: 8),
                                            entry.isDrive
                                                ? Image(
                                                        image: iconHardDrive,
                                                        fit: BoxFit.scaleDown,
                                                        color: Theme.of(context)
                                                            .iconTheme
                                                            .color
                                                            ?.withOpacity(0.7))
                                                    .paddingAll(4)
                                                : SvgPicture.asset(
                                                    entry.isFile
                                                        ? "assets/icons/file-sender-file.svg"
                                                        : "assets/icons/file-sender-folder.svg",
                                                    width: 16,
                                                    height: 16,
                                                    colorFilter: svgColor(
                                                        const Color(
                                                            0xFF8F8E95)),
                                                  ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                                child: Text(
                                                    entry.name.nonBreaking,
                                                    style: const TextStyle(
                                                        fontSize: 15,
                                                        color:
                                                            Color(0xFF646368)),
                                                    overflow:
                                                        TextOverflow.ellipsis))
                                          ]),
                                        )),
                                  ),
                                  onTap: onTap,
                                  onSecondaryTap: onSecondaryTap,
                                  onSecondaryTapDown: onSecondaryTapDown,
                                ),
                                SizedBox(
                                  width: 2.0,
                                ),
                                GestureDetector(
                                  child: Obx(
                                    () => SizedBox(
                                      width: _modifiedColWidth.value,
                                      child: Tooltip(
                                          waitDuration:
                                              Duration(milliseconds: 500),
                                          message: lastModifiedStr,
                                          child: Text(
                                            lastModifiedStr,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              color: Color(0xFF646368),
                                            ),
                                          )),
                                    ),
                                  ),
                                  onTap: onTap,
                                  onSecondaryTap: onSecondaryTap,
                                  onSecondaryTapDown: onSecondaryTapDown,
                                ),
                                // Divider from header.
                                SizedBox(
                                  width: 2.0,
                                ),
                                Expanded(
                                  // width: 100,
                                  child: GestureDetector(
                                    child: Tooltip(
                                      waitDuration: Duration(milliseconds: 500),
                                      message: sizeStr,
                                      child: Text(
                                        sizeStr,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 15,
                                            color: Color(0xFF646368)),
                                      ),
                                    ),
                                    onTap: onTap,
                                    onSecondaryTap: onSecondaryTap,
                                    onSecondaryTapDown: onSecondaryTapDown,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )))),
          );
        }).toList(growable: false);

        return Column(
          children: [
            // Header
            Row(
              children: [
                Expanded(child: _buildFileBrowserHeader(context)),
              ],
            ),
            // Body
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemExtent: 40,
                itemBuilder: (context, index) {
                  return rows[index];
                },
                itemCount: rows.length,
              ),
            ),
          ],
        );
      }),
    );
  }

  onSearchText(String searchText, bool isLocal) {
    selectedItems.clear();
    _searchText.value = searchText;
  }

  void _jumpToEntry(bool isLocal, Entry entry,
      ScrollController scrollController, double rowHeight) {
    final entries = controller.directory.value.entries;
    final index = entries.indexOf(entry);
    if (index == -1) {
      debugPrint("entry is not valid: ${entry.path}");
    }
    final selectedEntries = selectedItems;
    final searchResult = entries.where((element) => element == entry);
    selectedEntries.clear();
    if (searchResult.isEmpty) {
      return;
    }
    final offset = min(
        max(scrollController.position.minScrollExtent,
            entries.indexOf(searchResult.first) * rowHeight),
        scrollController.position.maxScrollExtent);
    scrollController.jumpTo(offset);
    selectedEntries.add(searchResult.first);
    debugPrint("focused on ${searchResult.first.name}");
  }

  void _onSelectedChanged(SelectedItems selectedItems, List<Entry> entries,
      Entry entry, bool isLocal) {
    final isCtrlDown = RawKeyboard.instance.keysPressed
            .contains(LogicalKeyboardKey.controlLeft) ||
        RawKeyboard.instance.keysPressed
            .contains(LogicalKeyboardKey.controlRight);
    final isShiftDown = RawKeyboard.instance.keysPressed
            .contains(LogicalKeyboardKey.shiftLeft) ||
        RawKeyboard.instance.keysPressed
            .contains(LogicalKeyboardKey.shiftRight);
    if (isCtrlDown) {
      if (selectedItems.items.contains(entry)) {
        selectedItems.remove(entry);
      } else {
        selectedItems.add(entry);
      }
    } else if (isShiftDown) {
      final List<int> indexGroup = [];
      for (var selected in selectedItems.items) {
        indexGroup.add(entries.indexOf(selected));
      }
      indexGroup.add(entries.indexOf(entry));
      indexGroup.removeWhere((e) => e == -1);
      final maxIndex = indexGroup.reduce(max);
      final minIndex = indexGroup.reduce(min);
      selectedItems.clear();
      entries
          .getRange(minIndex, maxIndex + 1)
          .forEach((e) => selectedItems.add(e));
    } else {
      selectedItems.clear();
      selectedItems.add(entry);
    }
    setState(() {});
  }

  bool _checkDoubleClick(Entry entry) {
    final current = DateTime.now().millisecondsSinceEpoch;
    final elapsed = current - _lastClickTime;
    _lastClickTime = current;
    if (_lastClickEntry == entry) {
      if (elapsed < bind.getDoubleClickTime()) {
        return true;
      }
    } else {
      _lastClickEntry = entry;
    }
    return false;
  }

  Widget _buildFileBrowserHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        key: _globalHeaderKey,
        height: kDesktopFileTransferHeaderHeight,
        child: Row(
          children: [
            Obx(
              () => headerItemFunc(
                  _nameColWidth.value, SortBy.name, translate("Name")),
            ),
            Obx(
              () => headerItemFunc(_modifiedColWidth.value, SortBy.modified,
                  translate("Modified")),
            ),
            Expanded(
                child: headerItemFunc(
                    _sizeColWidth.value, SortBy.size, translate("Size")))
          ],
        ),
      ),
    );
  }

  Widget headerItemFunc(double? width, SortBy sortBy, String name) {
    const headerTextStyle = TextStyle(
      color: Color(0xFFB9B8BF),
      fontSize: 14,
    );
    return ObxValue<Rx<bool?>>(
        (ascending) => InkWell(
              onTap: () {
                if (ascending.value == null) {
                  ascending.value = true;
                } else {
                  ascending.value = !ascending.value!;
                }
                controller.changeSortStyle(sortBy,
                    isLocal: isLocal, ascending: ascending.value!);
              },
              child: SizedBox(
                width: width,
                height: kDesktopFileTransferHeaderHeight,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: headerTextStyle,
                        overflow: TextOverflow.ellipsis,
                      ).marginOnly(left: 8),
                    ),
                    ascending.value != null
                        ? Transform.rotate(
                            angle: ascending.value! ? -1.5708 : 1.5708,
                            child: SvgPicture.asset(
                              "assets/icons/file_arrow.svg",
                              width: 16,
                              height: 16,
                              colorFilter: svgColor(const Color(0xFF8F8E95)),
                            ),
                          )
                        : const SizedBox()
                  ],
                ),
              ),
            ), () {
      if (controller.sortBy.value == sortBy) {
        return controller.sortAscending.obs;
      } else {
        return Rx<bool?>(null);
      }
    }());
  }

  Widget buildBread() {
    final items = getPathBreadCrumbItems(isLocal, (list) {
      var path = "";
      for (var item in list) {
        path = PathUtil.join(path, item, controller.options.value.isWindows);
      }
      controller.openDirectory(path);
    });

    return items.isEmpty
        ? Offstage()
        : Row(
            key: _locationBarKey,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
                Expanded(
                  child: Listener(
                    // handle mouse wheel
                    onPointerSignal: (e) {
                      if (e is PointerScrollEvent) {
                        final sc = _breadCrumbScroller;
                        final scale = isWindows ? 2 : 4;
                        sc.jumpTo(sc.offset + e.scrollDelta.dy / scale);
                      }
                    },
                    child: SingleChildScrollView(
                      controller: _breadCrumbScroller,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: items.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (index > 0)
                                const Icon(
                                  Icons.keyboard_arrow_right_rounded,
                                  color: Color(0xFF8F8E95),
                                  size: 20,
                                ),
                              item.content,
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                ActionIcon(
                  message: "",
                  icon: Icons.keyboard_arrow_down_rounded,
                  onTap: () async {
                    final renderBox = _locationBarKey.currentContext
                        ?.findRenderObject() as RenderBox;
                    _locationBarKey.currentContext?.size;

                    final size = renderBox.size;
                    final offset = renderBox.localToGlobal(Offset.zero);

                    final x = offset.dx;
                    final y = offset.dy + size.height + 1;

                    final isPeerWindows = controller.options.value.isWindows;
                    final List<MenuEntryBase> menuItems = [
                      MenuEntryButton(
                          childBuilder: (TextStyle? style) => isPeerWindows
                              ? buildWindowsThisPC(context, style)
                              : Text(
                                  '/',
                                  style: style,
                                ),
                          proc: () {
                            controller.openDirectory('/');
                          },
                          dismissOnClicked: true),
                      MenuEntryDivider()
                    ];
                    if (isPeerWindows) {
                      var loadingTag = "";
                      if (!isLocal) {
                        loadingTag = _ffi.dialogManager.showLoading("Waiting");
                      }
                      try {
                        final showHidden = controller.options.value.showHidden;
                        final fd = await controller.fileFetcher
                            .fetchDirectory("/", isLocal, showHidden);
                        for (var entry in fd.entries) {
                          menuItems.add(MenuEntryButton(
                              childBuilder: (TextStyle? style) =>
                                  Row(children: [
                                    Image(
                                        image: iconHardDrive,
                                        fit: BoxFit.scaleDown,
                                        color: Theme.of(context)
                                            .iconTheme
                                            .color
                                            ?.withOpacity(0.7)),
                                    SizedBox(width: 10),
                                    Text(
                                      entry.name,
                                      style: style,
                                    )
                                  ]),
                              proc: () {
                                controller.openDirectory('${entry.name}\\');
                              },
                              dismissOnClicked: true));
                        }
                        menuItems.add(MenuEntryDivider());
                      } catch (e) {
                        debugPrint("buildBread fetchDirectory err=$e");
                      } finally {
                        if (!isLocal) {
                          _ffi.dialogManager.dismissByTag(loadingTag);
                        }
                      }
                    }
                    mod_menu.showMenu(
                        context: context,
                        position: RelativeRect.fromLTRB(x, y, x, y),
                        elevation: 4,
                        items: menuItems
                            .map((e) => e.build(
                                context,
                                MenuConfig(
                                    commonColor:
                                        CustomPopupMenuTheme.commonColor,
                                    height: CustomPopupMenuTheme.height,
                                    dividerHeight:
                                        CustomPopupMenuTheme.dividerHeight,
                                    boxWidth: size.width)))
                            .expand((i) => i)
                            .toList());
                  },
                  iconSize: 20,
                )
              ]);
  }

  List<BreadCrumbItem> getPathBreadCrumbItems(
      bool isLocal, void Function(List<String>) onPressed) {
    final path = controller.directory.value.path;
    final breadCrumbList = List<BreadCrumbItem>.empty(growable: true);
    final isWindows = controller.options.value.isWindows;
    if (isWindows && path == '/') {
      breadCrumbList.add(BreadCrumbItem(
          content: TextButton(
              child: buildWindowsThisPC(context),
              style: ButtonStyle(
                  minimumSize: WidgetStateProperty.all(Size(0, 0)),
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  backgroundColor: WidgetStateProperty.all(Colors.transparent)),
              onPressed: () =>
                  onPressed(['/'])).marginSymmetric(horizontal: 4)));
    } else {
      final list = PathUtil.split(path, isWindows);
      breadCrumbList.addAll(
        list.asMap().entries.map(
              (e) => BreadCrumbItem(
                content: TextButton(
                  child: Text(
                    e.value,
                    style: const TextStyle(color: Color(0xFF646368)),
                  ),
                  style: ButtonStyle(
                    minimumSize: WidgetStateProperty.all(
                      Size(0, 0),
                    ),
                    foregroundColor: WidgetStateProperty.all(
                      const Color(0xFF646368),
                    ),
                    overlayColor: WidgetStateProperty.all(
                      Colors.transparent,
                    ),
                    backgroundColor: WidgetStateProperty.all(
                      Colors.transparent,
                    ),
                  ),
                  onPressed: () => onPressed(
                    list.sublist(0, e.key + 1),
                  ),
                ).marginSymmetric(horizontal: 4),
              ),
            ),
      );
    }
    return breadCrumbList;
  }

  breadCrumbScrollToEnd() {
    Future.delayed(Duration(milliseconds: 200), () {
      if (_breadCrumbScroller.hasClients) {
        _breadCrumbScroller.animateTo(
            _breadCrumbScroller.position.maxScrollExtent,
            duration: Duration(milliseconds: 200),
            curve: Curves.fastLinearToSlowEaseIn);
      }
    });
  }

  Widget buildPathLocation() {
    final text = _locationStatus.value == LocationStatus.pathLocation
        ? controller.directory.value.path
        : _searchText.value;
    // 컨트롤러 텍스트가 다를 때만 업데이트 (커서 위치 유지)
    if (_locationTextController.text != text) {
      _locationTextController.text = text;
      _locationTextController.selection = TextSelection.collapsed(offset: text.length);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: SvgPicture.asset(
            _locationStatus.value == LocationStatus.pathLocation
                ? "assets/icons/file-folder.svg"
                : "assets/icons/file-sender-search.svg",
            width: 18,
            height: 18,
            colorFilter: svgColor(const Color(0xFF8F8E95)),
          ),
        ),
        Expanded(
          child: TextField(
            focusNode: _locationNode,
            style: const TextStyle(color: Color(0xFF646368)),
            decoration: InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hoverColor: Colors.transparent,
              fillColor: Colors.transparent,
              filled: false,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
            ),
            controller: _locationTextController,
            onSubmitted: (path) {
              controller.openDirectory(path);
            },
            onChanged: _locationStatus.value == LocationStatus.fileSearchBar
                ? (searchText) => onSearchText(searchText, isLocal)
                : null,
          ).workaroundFreezeLinuxMint(),
        )
      ],
    );
  }

  // openDirectory(String path, {bool isLocal = false}) {
  //   model.openDirectory(path, isLocal: isLocal);
  // }
}

Widget buildWindowsThisPC(BuildContext context, [TextStyle? textStyle]) {
  const color = Color(0xFF8F8E95);
  final style = textStyle ?? const TextStyle(color: Color(0xFF646368));
  return Row(children: [
    Icon(Icons.computer, size: 20, color: color),
    SizedBox(width: 10),
    Text(translate('This PC'), style: style)
  ]);
}

/// 경로 바 네비게이션 아이콘 버튼
/// 40x40 크기, 투명 배경, 호버시 아이콘 색상 변경
class _NavIconButton extends StatefulWidget {
  final String iconPath;
  final String? tooltip;
  final VoidCallback? onPressed;
  final double rotationAngle;

  const _NavIconButton({
    required this.iconPath,
    this.tooltip,
    this.onPressed,
    this.rotationAngle = 0,
  });

  @override
  State<_NavIconButton> createState() => _NavIconButtonState();
}

class _NavIconButtonState extends State<_NavIconButton> {
  bool _isHovered = false;

  static const _normalColor = Color(0xFF8F8E95);
  static const _hoverColor = Color(0xFF5F71FF);

  @override
  Widget build(BuildContext context) {
    final iconColor = _isHovered ? _hoverColor : _normalColor;

    Widget icon = SvgPicture.asset(
      widget.iconPath,
      width: 20,
      height: 20,
      colorFilter: svgColor(iconColor),
    );

    if (widget.rotationAngle != 0) {
      icon = Transform.rotate(
        angle: widget.rotationAngle * pi / 180,
        child: icon,
      );
    }

    Widget button = MouseRegion(
      cursor: widget.onPressed != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 40,
          height: 40,
          color: Colors.transparent,
          child: Center(child: icon),
        ),
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      button = Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 300),
        child: button,
      );
    }

    return button;
  }
}

/// 파일 전송 카드의 삭제 버튼 (X 아이콘, 배경 없음, 호버 시 색상 변경)
class _JobDeleteButton extends StatefulWidget {
  final VoidCallback? onPressed;

  const _JobDeleteButton({
    Key? key,
    this.onPressed,
  }) : super(key: key);

  @override
  State<_JobDeleteButton> createState() => _JobDeleteButtonState();
}

class _JobDeleteButtonState extends State<_JobDeleteButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final iconColor = _isHovered ? const Color(0xFF5F71FF) : const Color(0xFF8F8E95);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Tooltip(
          message: translate("Delete"),
          waitDuration: const Duration(milliseconds: 300),
          child: Container(
            width: 32,
            height: 32,
            color: Colors.transparent,
            child: Center(
              child: SvgPicture.asset(
                "assets/icons/file-sender-close.svg",
                width: 20,
                height: 20,
                colorFilter: svgColor(iconColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
