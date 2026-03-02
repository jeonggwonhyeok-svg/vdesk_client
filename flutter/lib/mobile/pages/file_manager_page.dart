import 'dart:async';
import 'dart:io' show Platform, File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_hbb/models/file_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../common.dart';
import '../../common/widgets/dialog.dart';
import '../../common/widgets/styled_form_widgets.dart';

class FileManagerPage extends StatefulWidget {
  FileManagerPage(
      {Key? key,
      required this.id,
      this.password,
      this.isSharedPassword,
      this.forceRelay,
      this.ffi})
      : super(key: key);
  final String id;
  final String? password;
  final bool? isSharedPassword;
  final bool? forceRelay;
  final FFI? ffi;

  @override
  State<StatefulWidget> createState() => _FileManagerPageState();
}

enum SelectMode { local, remote, none }

extension SelectModeEq on SelectMode {
  bool eq(bool? currentIsLocal) {
    if (currentIsLocal == null) {
      return false;
    }
    if (currentIsLocal) {
      return this == SelectMode.local;
    } else {
      return this == SelectMode.remote;
    }
  }
}

extension SelectModeExt on Rx<SelectMode> {
  void toggle(bool currentIsLocal) {
    switch (value) {
      case SelectMode.local:
        value = SelectMode.none;
        break;
      case SelectMode.remote:
        value = SelectMode.none;
        break;
      case SelectMode.none:
        if (currentIsLocal) {
          value = SelectMode.local;
        } else {
          value = SelectMode.remote;
        }
        break;
    }
  }
}

class _FileManagerPageState extends State<FileManagerPage> {
  late final FFI _ffi;
  late final FileModel model;
  final selectMode = SelectMode.none.obs;

  var showLocal = true;

  bool get _isExternalFfi => widget.ffi != null;

  FileController get currentFileController =>
      showLocal ? model.localController : model.remoteController;
  FileDirectory get currentDir => currentFileController.directory.value;
  DirectoryOptions get currentOptions => currentFileController.options.value;

  @override
  void initState() {
    super.initState();
    _ffi = widget.ffi ?? gFFI;
    model = _ffi.fileModel;

    if (_isExternalFfi) {
      // External FFI already started with file transfer session
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ffi.dialogManager
            .showLoading(translate('Connecting...'), onCancel: _closeExternal);
      });
    } else {
      gFFI.start(widget.id,
          isFileTransfer: true,
          password: widget.password,
          isSharedPassword: widget.isSharedPassword,
          forceRelay: widget.forceRelay);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ffi.dialogManager
            .showLoading(translate('Connecting...'), onCancel: closeConnection);
      });
      _ffi.ffiModel.updateEventListener(_ffi.sessionId, widget.id);
    }
    WakelockPlus.enable();
  }

  void _closeExternal() {
    model.close().whenComplete(() {
      _ffi.close();
      _ffi.dialogManager.dismissAll();
    });
    model.jobController.clear();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    model.close().whenComplete(() {
      _ffi.close();
      _ffi.dialogManager.dismissAll();
      if (!_isExternalFfi) {
        WakelockPlus.disable();
      }
    });
    model.jobController.clear();
    super.dispose();
  }

  void _onMoreMenuSelected(String v) {
    if (v == "refresh") {
      currentFileController.refresh();
    } else if (v == "select") {
      model.localController.selectedItems.clear();
      model.remoteController.selectedItems.clear();
      selectMode.toggle(showLocal);
      setState(() {});
    } else if (v == "folder") {
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
        return CustomAlertDialog(
            title: Text(translate("Create Folder")),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  decoration: InputDecoration(
                    hintText: translate("Please enter the folder name"),
                    hintStyle: const TextStyle(color: Color(0xFFB9B8BF), fontSize: 14),
                    errorText: errorText,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFDEDEE2)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFDEDEE2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF5F71FF)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  ),
                  style: const TextStyle(fontSize: 14, color: Color(0xFF454447)),
                  controller: name,
                ).workaroundFreezeLinuxMint(),
              ],
            ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: dialogButton("Cancel",
                        onPressed: () => close(false), isOutline: true),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: dialogButton("OK", onPressed: () {
                      if (name.value.text.isNotEmpty) {
                        if (!PathUtil.validName(name.value.text,
                            currentFileController.options.value.isWindows)) {
                          setState(() {
                            errorText = translate("Invalid folder name");
                          });
                          return;
                        }
                        currentFileController.createDir(PathUtil.join(
                            currentDir.path,
                            name.value.text,
                            currentOptions.isWindows));
                        close();
                      }
                    }),
                  ),
                ],
              )
            ]);
      });
    } else if (v == "hidden") {
      currentFileController.toggleShowHidden();
    }
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFFF2F2F2),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!showLocal) setState(() => showLocal = true);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: showLocal
                      ? const Color(0xFF454447)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    translate('Local Device'),
                    style: TextStyle(
                      color: showLocal
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
                if (showLocal) setState(() => showLocal = false);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: !showLocal
                      ? const Color(0xFF454447)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    translate('Remote Device'),
                    style: TextStyle(
                      color: !showLocal
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

  // iOS 로컬 파일: 선택한 파일 목록 + 파일 피커 버튼
  final RxList<PlatformFile> _iosPickedFiles = <PlatformFile>[].obs;

  Widget _buildiOSLocalFileView() {
    return Obx(() {
      final files = _iosPickedFiles;
      return Column(
        children: [
          // 파일/사진 추가 버튼
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _pickFilesForIOS,
                      icon: const Icon(Icons.insert_drive_file, size: 20),
                      label: Text(
                        translate('Select files'),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5F71FF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _pickPhotosForIOS,
                      icon: const Icon(Icons.photo_library, size: 20),
                      label: Text(
                        translate('Select photos'),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5F71FF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 선택된 파일 목록
          Expanded(
            child: files.isEmpty
                ? Center(
                    child: Text(
                      translate('Select files to send'),
                      style: const TextStyle(
                        color: Color(0xFF999999),
                        fontSize: 15,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: files.length,
                    itemBuilder: (context, index) {
                      final file = files[index];
                      return ListTile(
                        leading: const Icon(Icons.insert_drive_file,
                            color: Color(0xFF5F71FF)),
                        title: Text(
                          file.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(_formatFileSize(file.size)),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => _iosPickedFiles.removeAt(index),
                        ),
                      );
                    },
                  ),
          ),
          // 전송 버튼
          if (files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _sendIOSPickedFiles,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5F71FF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    '${translate("Send")} (${files.length})',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }

  Future<void> _pickFilesForIOS() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      withReadStream: false,
    );
    if (result != null && result.files.isNotEmpty) {
      _iosPickedFiles.addAll(result.files);
    }
  }

  Future<void> _pickPhotosForIOS() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();
    if (images.isNotEmpty) {
      for (final xfile in images) {
        final file = File(xfile.path);
        final stat = await file.stat();
        _iosPickedFiles.add(PlatformFile(
          name: xfile.name,
          path: xfile.path,
          size: stat.size,
        ));
      }
    }
  }

  Future<void> _sendIOSPickedFiles() async {
    final localDir = model.localController.directory.value.path;
    for (final file in _iosPickedFiles) {
      if (file.path == null) continue;
      // 샌드박스로 복사
      final srcFile = File(file.path!);
      final destPath = p.join(localDir, file.name);
      await srcFile.copy(destPath);
    }
    // 로컬 디렉토리 새로고침
    model.localController.refresh();
    await Future.delayed(const Duration(milliseconds: 500));
    // 복사된 파일들을 선택 상태로 설정
    final localController = model.localController;
    final entries = localController.directory.value.entries;
    final pickedNames = _iosPickedFiles.map((f) => f.name).toSet();
    localController.selectedItems.clear();
    for (final entry in entries) {
      if (pickedNames.contains(entry.name)) {
        localController.selectedItems.add(entry);
      }
    }
    _iosPickedFiles.clear();
    // 다중 선택 모드 활성화 후 리모트 탭으로 전환 (기존 흐름)
    selectMode.value = SelectMode.local;
    setState(() => showLocal = false);
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) => WillPopScope(
      onWillPop: () async {
        if (selectMode.value != SelectMode.none) {
          selectMode.value = SelectMode.none;
          setState(() {});
        } else {
          currentFileController.goBack();
        }
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFEFEFE),
        appBar: AppBar(
          backgroundColor: const Color(0xFFFEFEFE),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios,
                color: Color(0xFF454447), size: 20),
            onPressed: () {
              if (_isExternalFfi) {
                _closeExternal();
              } else {
                clientClose(_ffi.sessionId, _ffi);
              }
            },
          ),
          title: Text(
            translate('Transfer file'),
            style: const TextStyle(
              color: Color(0xFF454447),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: false,
          titleSpacing: 0,
          actions: [
            PopupMenuButton<String>(
              tooltip: "",
              icon: SvgPicture.asset(
                'assets/icons/mobile-file-sender-title-more.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(
                  Color(0xFF454447),
                  BlendMode.srcIn,
                ),
              ),
              itemBuilder: (context) {
                return [
                  PopupMenuItem(
                    child: Text(translate("Refresh File")),
                    value: "refresh",
                  ),
                  PopupMenuItem(
                    enabled: currentDir.path != "/",
                    child: Text(translate("Multi Select")),
                    value: "select",
                  ),
                  PopupMenuItem(
                    enabled: currentDir.path != "/",
                    child: Text(translate("Create Folder")),
                    value: "folder",
                  ),
                  PopupMenuItem(
                    enabled: currentDir.path != "/",
                    child: Text(currentOptions.showHidden
                        ? translate("Hide Hidden Files")
                        : translate("Show Hidden Files")),
                    value: "hidden",
                  ),
                ];
              },
              onSelected: _onMoreMenuSelected,
            ),
          ],
        ),
        body: Column(
          children: [
            _buildTabBar(),
            Expanded(
              child: showLocal
                  ? (Platform.isIOS
                      ? _buildiOSLocalFileView()
                      : FileManagerView(
                          controller: model.localController,
                          selectMode: selectMode,
                          ffi: _ffi,
                        ))
                  : FileManagerView(
                      controller: model.remoteController,
                      selectMode: selectMode,
                      ffi: _ffi,
                    ),
            ),
          ],
        ),
        bottomSheet: bottomSheet(),
      ));

  Widget? bottomSheet() {
    return Obx(() {
      final selectedItems = getActiveSelectedItems();
      final jobTable = model.jobController.jobTable;

      // 다중 선택 모드
      if (selectMode.value != SelectMode.none) {
        if (selectedItems == null ||
            selectedItems.items.isEmpty ||
            selectMode.value.eq(showLocal)) {
          // 같은 쪽에서 선택 중: 보내기/받기 버튼
          final hasItems = selectedItems != null && selectedItems.items.isNotEmpty;
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFEFEFE),
              boxShadow: [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 10,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: hasItems
                    ? () {
                        // 탭 전환 후 확인 모드로
                        setState(() => showLocal = !showLocal);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5F71FF),
                  disabledBackgroundColor: const Color(0xFF5F71FF).withOpacity(0.4),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  showLocal ? translate('Send') : translate('Receive'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        } else {
          // 반대편에서 붙여넣기 대기: 저장 경로 + 확인 버튼
          // 현재 디렉토리의 마지막 폴더 이름
          final pathParts = currentDir.path.split(RegExp(r'[/\\]'));
          final currentFolderName = pathParts.isNotEmpty
              ? pathParts.where((p) => p.isNotEmpty).lastOrNull ?? currentDir.path
              : currentDir.path;
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFEFEFE),
              boxShadow: [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 10,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 저장 경로 카드
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF1FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        translate('Files Save Path'),
                        style: const TextStyle(
                          color: Color(0xFF5F71FF),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '[$currentFolderName]',
                        style: const TextStyle(
                          color: Color(0xFF94A0FF),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 확인 버튼
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      final otherSide = showLocal
                          ? model.remoteController
                          : model.localController;
                      final thisSideData =
                          DirectoryData(currentDir, currentOptions);
                      otherSide.sendFiles(selectedItems, thisSideData);
                      selectedItems.items.clear();
                      selectMode.value = SelectMode.none;
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5F71FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      translate('Verify'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
      }

      // 전송 중/완료/에러 상태: 작업 리스트 팝업
      if (jobTable.isEmpty) {
        return const Offstage();
      }

      return Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFEFEFE),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 16,
              offset: Offset(0, -4),
            ),
          ],
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 타이틀
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  translate('File processing')
                      .replaceAll('N', '${jobTable.length}'),
                  style: const TextStyle(
                    color: Color(0xFF454447),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            // 작업 리스트
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: jobTable.length,
                itemBuilder: (context, index) {
                  final job = jobTable[index];
                  final isDone = job.state == JobState.done;
                  final isError = job.state == JobState.error;
                  final isFile = job.fileName.contains('.');

                  // 상태 텍스트 & 색상
                  String statusText;
                  Color statusColor;
                  if (isDone) {
                    statusText = translate('File Sucess');
                    statusColor = const Color(0xFF62A93E);
                  } else if (isError) {
                    statusText = translate('Error');
                    statusColor = const Color(0xFFFE3E3E);
                  } else {
                    statusText = translate('File Sending');
                    statusColor = const Color(0xFF5F71FF);
                  }

                  final sizeText = readableFileSize(job.totalSize.toDouble());

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEFEFE),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF2F1F6)),
                    ),
                    child: Row(
                      children: [
                        // 파일/폴더 아이콘 카드 (삭제 작업일 때 삭제 아이콘)
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF1FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: SvgPicture.asset(
                              (job.type == JobType.deleteFile || job.type == JobType.deleteDir)
                                  ? 'assets/icons/mobile-file-sender-del.svg'
                                  : isFile
                                      ? 'assets/icons/mobile-file-sender-file.svg'
                                      : 'assets/icons/mobile-file-sender-folder.svg',
                              width: 20,
                              height: 20,
                              colorFilter: const ColorFilter.mode(
                                Color(0xFF94A0FF),
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 파일 정보
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '[${job.jobName.isNotEmpty ? job.jobName : job.fileName}]',
                                style: const TextStyle(
                                  color: Color(0xFF8F8E95),
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    statusText,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${job.fileNum}/${job.fileCount} files  $sizeText',
                                    style: const TextStyle(
                                      color: Color(0xFF8F8E95),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // 처리중: 취소 버튼 / 완료: 확인 버튼
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: () {
                  final hasInProgress = jobTable.any(
                      (job) => job.state == JobState.inProgress || job.state == JobState.none);
                  if (hasInProgress) {
                    return ElevatedButton(
                      onPressed: () {
                        _ffi.dialogManager.show((setState, close, context) {
                          return CustomAlertDialog(
                            title: Text(translate('Warning')),
                            content: Text(translate('File Cancel Warning')),
                            actions: [
                              Row(
                                children: [
                                  Expanded(
                                    child: dialogButton(
                                      'Cancel',
                                      onPressed: close,
                                      isOutline: true,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: dialogButton(
                                      'OK',
                                      onPressed: () {
                                        close();
                                        for (final job in jobTable) {
                                          if (job.state == JobState.inProgress || job.state == JobState.none) {
                                            model.jobController.cancelJob(job.id);
                                          }
                                        }
                                        jobTable.clear();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFE3E3E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        translate('Cancel'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  } else {
                    return ElevatedButton(
                      onPressed: () {
                        jobTable.clear();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5F71FF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        translate('Verify'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }
                }(),
              ),
            ),
          ],
        ),
      );
    });
  }

  SelectedItems? getActiveSelectedItems() {
    final localSelectedItems = model.localController.selectedItems;
    final remoteSelectedItems = model.remoteController.selectedItems;

    if (localSelectedItems.items.isNotEmpty &&
        remoteSelectedItems.items.isNotEmpty) {
      // assert unreachable
      debugPrint("Wrong SelectedItems state, reset");
      localSelectedItems.clear();
      remoteSelectedItems.clear();
    }

    if (localSelectedItems.items.isEmpty && remoteSelectedItems.items.isEmpty) {
      return null;
    }

    if (localSelectedItems.items.length > remoteSelectedItems.items.length) {
      return localSelectedItems;
    } else {
      return remoteSelectedItems;
    }
  }
}

class FileManagerView extends StatefulWidget {
  final FileController controller;
  final Rx<SelectMode> selectMode;
  final FFI ffi;

  FileManagerView({required this.controller, required this.selectMode, required this.ffi});

  @override
  State<StatefulWidget> createState() => _FileManagerViewState();
}

class _FileManagerViewState extends State<FileManagerView> {
  final _listScrollController = ScrollController();
  final _breadCrumbScroller = ScrollController();
  late final ascending = Rx<bool>(controller.sortAscending);

  bool get isLocal => widget.controller.isLocal;
  FileController get controller => widget.controller;
  SelectedItems get _selectedItems => widget.controller.selectedItems;

  @override
  void initState() {
    super.initState();
    controller.directory.listen((e) => breadCrumbScrollToEnd());
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      headTools(),
      Expanded(child: Obx(() {
        final entries = controller.directory.value.entries;
        final showCheckBox =
            widget.selectMode.value != SelectMode.none &&
            widget.selectMode.value.eq(controller.selectedItems.isLocal);
        return ListView.builder(
          controller: _listScrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: entries.length + 1,
          itemBuilder: (context, index) {
            if (index >= entries.length) {
              return listTail();
            }
            var selected = false;
            if (widget.selectMode.value != SelectMode.none) {
              selected = _selectedItems.items.contains(entries[index]);
            }

            final sizeStr = entries[index].isFile
                ? readableFileSize(entries[index].size.toDouble())
                : "";

            // 교차 배경: 다중선택 모드일 때만 짝수 #EFF1FF / 홀수 투명
            final hasBackground = widget.selectMode.value != SelectMode.none && index % 2 == 0;

            return GestureDetector(
              onTap: () {
                if (showCheckBox) {
                  if (selected) {
                    _selectedItems.remove(entries[index]);
                  } else {
                    _selectedItems.add(entries[index]);
                  }
                  setState(() {});
                  return;
                }
                if (entries[index].isDirectory || entries[index].isDrive) {
                  controller.openDirectory(entries[index].path);
                }
              },
              onLongPress: entries[index].isDrive
                  ? null
                  : () {
                      _selectedItems.clear();
                      widget.selectMode.toggle(isLocal);
                      if (widget.selectMode.value != SelectMode.none) {
                        _selectedItems.add(entries[index]);
                      }
                      setState(() {});
                    },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: hasBackground
                    ? BoxDecoration(
                        color: const Color(0xFFEFF1FF),
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
                child: Row(
                  children: [
                    // 파일/폴더 아이콘
                    entries[index].isDrive
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: Image(
                                image: iconHardDrive,
                                fit: BoxFit.scaleDown,
                                color: const Color(0xFF94A0FF)))
                        : SvgPicture.asset(
                            entries[index].isFile
                                ? 'assets/icons/mobile-file-sender-file.svg'
                                : 'assets/icons/mobile-file-sender-folder.svg',
                            width: 24,
                            height: 24,
                            colorFilter: const ColorFilter.mode(
                              Color(0xFF94A0FF),
                              BlendMode.srcIn,
                            ),
                          ),
                    const SizedBox(width: 12),
                    // 파일명 + 날짜/용량
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entries[index].name,
                            style: const TextStyle(
                              color: Color(0xFF4350B5),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (!entries[index].isDrive)
                            Text(
                              "${entries[index].lastModified().toString().replaceAll(".000", "")}   $sizeStr",
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFB9B8BF),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // 우측: 체크박스 또는 더보기
                    if (!entries[index].isDrive)
                      showCheckBox
                          ? StyledCheckbox(
                              value: selected,
                              size: 22,
                              borderRadius: 4,
                              accentColor: const Color(0xFF5F71FF),
                              onChanged: (v) {
                                if (v == null) return;
                                if (v && !selected) {
                                  _selectedItems.add(entries[index]);
                                } else if (!v && selected) {
                                  _selectedItems.remove(entries[index]);
                                }
                                setState(() {});
                              },
                            )
                          : PopupMenuButton<String>(
                              tooltip: "",
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: SvgPicture.asset(
                                'assets/icons/mobile-file-sender-list-more.svg',
                                width: 24,
                                height: 24,
                                colorFilter: const ColorFilter.mode(
                                  Color(0xFF8F8E95),
                                  BlendMode.srcIn,
                                ),
                              ),
                              itemBuilder: (context) {
                                return [
                                  PopupMenuItem(
                                    child: Text(translate("Delete")),
                                    value: "delete",
                                  ),
                                  PopupMenuItem(
                                    child: Text(translate("Multi Select")),
                                    value: "multi_select",
                                  ),
                                  PopupMenuItem(
                                    child: Text(translate("Properties")),
                                    value: "properties",
                                    enabled: false,
                                  ),
                                  if (!entries[index].isDrive &&
                                      versionCmp(widget.ffi.ffiModel.pi.version,
                                              "1.3.0") >=
                                          0)
                                    PopupMenuItem(
                                      child: Text(translate("Rename")),
                                      value: "rename",
                                    )
                                ];
                              },
                              onSelected: (v) {
                                if (v == "delete") {
                                  final items = SelectedItems(isLocal: isLocal);
                                  items.add(entries[index]);
                                  controller.removeAction(items);
                                } else if (v == "multi_select") {
                                  _selectedItems.clear();
                                  widget.selectMode.toggle(isLocal);
                                  setState(() {});
                                } else if (v == "rename") {
                                  controller.renameAction(
                                      entries[index], isLocal);
                                }
                              },
                            ),
                  ],
                ),
              ),
            );
          },
        );
      }))
    ]);
  }

  void breadCrumbScrollToEnd() {
    Future.delayed(Duration(milliseconds: 200), () {
      if (_breadCrumbScroller.hasClients) {
        _breadCrumbScroller.animateTo(
            _breadCrumbScroller.position.maxScrollExtent,
            duration: Duration(milliseconds: 200),
            curve: Curves.fastLinearToSlowEaseIn);
      }
    });
  }

  // 네비게이션 바: 좌측 화살표 + 우측 정렬/삭제/취소
  Widget _buildNavBar() {
    return Obx(() {
      final isMultiSelect =
          widget.selectMode.value != SelectMode.none &&
          widget.selectMode.value.eq(controller.selectedItems.isLocal);

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            // 좌측: 뒤로가기 + 상위 폴더
            GestureDetector(
              onTap: controller.goBack,
              child: SvgPicture.asset(
                'assets/icons/mobile-file-sender-left-arrow.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(
                  Color(0xFF8F8E95),
                  BlendMode.srcIn,
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: controller.goToParentDirectory,
              child: SvgPicture.asset(
                'assets/icons/mobile-file-sender-up-arrow.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(
                  Color(0xFF8F8E95),
                  BlendMode.srcIn,
                ),
              ),
            ),
            const Spacer(),
            // 우측: 다중선택시 del + cancel + sort, 보통시 sort만
            if (isMultiSelect) ...[
              GestureDetector(
                onTap: () async {
                  final selectedItems = controller.selectedItems;
                  if (selectedItems.items.isNotEmpty) {
                    await controller.removeAction(selectedItems);
                    selectedItems.items.clear();
                    widget.selectMode.value = SelectMode.none;
                    setState(() {});
                  }
                },
                child: SvgPicture.asset(
                  'assets/icons/mobile-file-sender-del.svg',
                  width: 24,
                  height: 24,
                  colorFilter: const ColorFilter.mode(
                    Color(0xFFFE3E3E),
                    BlendMode.srcIn,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  controller.selectedItems.items.clear();
                  widget.selectMode.value = SelectMode.none;
                  setState(() {});
                },
                child: SvgPicture.asset(
                  'assets/icons/mobile-file-sender-cancel.svg',
                  width: 24,
                  height: 24,
                  colorFilter: const ColorFilter.mode(
                    Color(0xFF8F8E95),
                    BlendMode.srcIn,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            PopupMenuButton<SortBy>(
              tooltip: "",
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: SvgPicture.asset(
                'assets/icons/mobile-file-sender-sort.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(
                  Color(0xFF8F8E95),
                  BlendMode.srcIn,
                ),
              ),
              itemBuilder: (context) {
                return SortBy.values
                    .map((e) => PopupMenuItem(
                          child: Text(translate(e.toString())),
                          value: e,
                        ))
                    .toList();
              },
              onSelected: (sortBy) {
                if (controller.sortBy.value == sortBy) {
                  ascending.value = !controller.sortAscending;
                } else {
                  ascending.value = true;
                }
                controller.changeSortStyle(sortBy,
                    ascending: ascending.value);
              },
            ),
          ],
        ),
      );
    });
  }

  // 경로 브레드크럼 (좌측 정렬)
  Widget _buildBreadcrumb() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      alignment: Alignment.centerLeft,
      child: Obx(() {
        final home = controller.options.value.home;
        final isWindows = controller.options.value.isWindows;
        final list = PathUtil.split(controller.shortPath, isWindows);

        final children = <Widget>[];

        // Home 아이콘
        children.add(GestureDetector(
          onTap: () => controller.goToHomeDirectory(),
          child: SvgPicture.asset(
            'assets/icons/mobile-file-sender-home.svg',
            width: 20,
            height: 20,
            colorFilter: const ColorFilter.mode(
              Color(0xFF8F8E95),
              BlendMode.srcIn,
            ),
          ),
        ));

        // 경로 아이템들
        for (var i = 0; i < list.length; i++) {
          children.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SvgPicture.asset(
              'assets/icons/mobile-file-sender-path-arrow.svg',
              width: 16,
              height: 16,
              colorFilter: const ColorFilter.mode(
                Color(0xFFC2C2C2),
                BlendMode.srcIn,
              ),
            ),
          ));

          final index = i;
          children.add(GestureDetector(
            onTap: () {
              final subList = list.sublist(0, index + 1);
              var path = "";
              if (home.startsWith(subList[0])) {
                for (var item in subList) {
                  path = PathUtil.join(path, item, isWindows);
                }
              } else {
                path += home;
                for (var item in subList) {
                  path = PathUtil.join(path, item, isWindows);
                }
              }
              controller.openDirectory(path);
            },
            child: Text(
              list[i],
              style: const TextStyle(
                color: Color(0xFF646368),
                fontSize: 14,
              ),
            ),
          ));
        }

        return SingleChildScrollView(
          controller: _breadCrumbScroller,
          scrollDirection: Axis.horizontal,
          child: Row(children: children),
        );
      }),
    );
  }

  Widget headTools() => Column(
        children: [
          _buildBreadcrumb(),
          _buildNavBar(),
        ],
      );

  Widget listTail() => Obx(() => Container(
        height: 100,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(30, 5, 30, 0),
              child: Text(
                controller.directory.value.path,
                style: TextStyle(color: MyTheme.darkGray),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(2),
              child: Text(
                "${translate("Total")}: ${controller.directory.value.entries.length} ${translate("items")}",
                style: TextStyle(color: MyTheme.darkGray),
              ),
            )
          ],
        ),
      ));

}

