import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/main.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../common/widgets/window_buttons.dart';
import '../../common/widgets/styled_form_widgets.dart';

class CameraRequestDialogPage extends StatefulWidget {
  final int clientId;
  final String clientName;
  final String clientPeerId;

  const CameraRequestDialogPage({
    Key? key,
    required this.clientId,
    required this.clientName,
    required this.clientPeerId,
  }) : super(key: key);

  @override
  State<CameraRequestDialogPage> createState() => _CameraRequestDialogPageState();
}

class _CameraRequestDialogPageState extends State<CameraRequestDialogPage> {
  void _closeWindow() {
    if (kWindowId != null) {
      WindowController.fromWindowId(kWindowId!).close();
    }
  }

  void _reject() async {
    await bind.cmLoginRes(connId: widget.clientId, res: false);
    _closeWindow();
  }

  void _accept() async {
    await bind.cmLoginRes(connId: widget.clientId, res: true);
    _closeWindow();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Column(
        children: [
          // 타이틀바 (CM창과 동일)
          _buildTitleBar(context),
          // 컨텐츠
          Expanded(
            child: _buildRequestContent(),
          ),
        ],
      ),
    );
  }

  /// 타이틀바 빌드 (CM창과 동일한 스타일)
  Widget _buildTitleBar(BuildContext context) {
    return SizedBox(
      height: kWindowButtonHeight,
      child: Row(
        children: [
          // 드래그 가능한 영역 + 로고
          Expanded(
            child: GestureDetector(
              onPanStart: (_) {
                // 서브 윈도우용 드래그
                startWindowDragging(false);
              },
              child: Container(
                color: Theme.of(context).colorScheme.background,
                child: Row(
                  children: [
                    // 로고
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: SvgPicture.asset(
                        'assets/icons/topbar-logo.svg',
                        width: 20,
                        height: 20,
                        colorFilter: const ColorFilter.mode(
                          Color(0xFF5B7BF8),
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 타이틀
                    Text(
                      translate('Camera Share Request'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 창 컨트롤 버튼
          WindowControlButtons(
            isMainWindow: false,
            theme: WindowButtonTheme.light,
            height: kWindowButtonHeight,
            buttonWidth: kWindowButtonWidth,
            iconSize: kWindowButtonIconSize,
            showMinimize: true,
            showMaximize: false,
            showClose: true,
            onClose: () async {
              _reject();
              return false;
            },
          ),
        ],
      ),
    );
  }

  /// 요청 화면
  Widget _buildRequestContent() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            translate('Camera Share Request'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          // 유저 아바타
          _buildUserAvatar(),
          const SizedBox(height: 16),
          // 유저 이름
          _buildUserName(),
          const SizedBox(height: 4),
          // 유저 ID
          _buildUserId(),
          const SizedBox(height: 32),
          // 버튼들
          Row(
            children: [
              Expanded(
                child: StyledOutlinedButton(
                  label: translate('Reject'),
                  onPressed: _reject,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _accept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyTheme.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    translate('Accept'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 유저 아바타 위젯
  Widget _buildUserAvatar() {
    return Container(
      width: 80,
      height: 80,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: str2color(widget.clientName),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        widget.clientName.isNotEmpty
            ? widget.clientName[0].toUpperCase()
            : '?',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
          fontSize: 40,
        ),
      ),
    );
  }

  /// 유저 이름 위젯
  Widget _buildUserName() {
    return Text(
      '[${widget.clientName.isNotEmpty ? widget.clientName : translate('Unknown')}]',
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    );
  }

  /// 유저 ID 위젯
  Widget _buildUserId() {
    return Text(
      '[${widget.clientPeerId}]',
      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
    );
  }
}
