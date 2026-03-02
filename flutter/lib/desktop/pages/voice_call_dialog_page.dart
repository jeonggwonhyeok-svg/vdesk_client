import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/main.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

import '../../common/widgets/window_buttons.dart';
import '../../common/widgets/styled_form_widgets.dart';

// CM 창과 동일한 디자인 색상
const Color _vcBackgroundColor = Color(0xFFF7F7F7);
const Color _vcTextPrimary = Color(0xFF454447);
const Color _vcAccentColor = Color(0xFF5F71FF);
const Color _vcIconBgColor = Color(0xFFEFF1FF);

/// 피어 캐시에서 platform 정보 조회
String _getPeerPlatform(String peerId) {
  try {
    final peer = bind.mainGetPeerSync(id: peerId);
    final config = jsonDecode(peer);
    return config['info']?['platform'] ?? config['platform'] ?? '';
  } catch (e) {
    return '';
  }
}

/// 피어 캐시에서 OS 버전 정보 조회
String _getPeerOsVersion(String peerId) {
  try {
    final peer = bind.mainGetPeerSync(id: peerId);
    final config = jsonDecode(peer);
    return config['info']?['os_version'] ?? '';
  } catch (e) {
    return '';
  }
}

class VoiceCallDialogPage extends StatefulWidget {
  final int clientId;
  final String clientName;
  final String clientPeerId;

  const VoiceCallDialogPage({
    Key? key,
    required this.clientId,
    required this.clientName,
    required this.clientPeerId,
  }) : super(key: key);

  @override
  State<VoiceCallDialogPage> createState() => _VoiceCallDialogPageState();
}

class _VoiceCallDialogPageState extends State<VoiceCallDialogPage> {
  bool _isAccepted = false;
  bool _isMicOn = true;
  bool _isSpeakerOn = true;
  String _savedMicDevice = '';

  @override
  void initState() {
    super.initState();
    // 현재 마이크 장치 저장 (빈 문자열이면 첫 번째 마이크 장치 사용)
    Future.delayed(Duration.zero, () async {
      _savedMicDevice = await bind.getVoiceCallInputDevice(isCm: true);
      if (_savedMicDevice.isEmpty) {
        // 뮤트 상태에서 시작된 경우, 실제 마이크 장치를 찾아서 저장
        final devices = (await bind.mainGetSoundInputs()).toList();
        if (devices.isNotEmpty) {
          _savedMicDevice = devices.first;
        }
      }
    });
  }

  void _closeWindow() {
    if (kWindowId != null) {
      Future.delayed(Duration.zero, () {
        WindowController.fromWindowId(kWindowId!).close();
      });
    }
  }

  void _reject() {
    bind.cmHandleIncomingVoiceCall(id: widget.clientId, accept: false);
    _closeWindow();
  }

  void _accept() async {
    bind.cmHandleIncomingVoiceCall(id: widget.clientId, accept: true);
    setState(() {
      _isAccepted = true;
    });
  }

  void _disconnect() {
    bind.cmCloseVoiceCall(id: widget.clientId);
    _closeWindow();
  }

  void _toggleMic() async {
    setState(() {
      _isMicOn = !_isMicOn;
    });
    if (_isMicOn) {
      // 마이크 켜기 - 저장된 장치로 복원
      await bind.setVoiceCallInputDevice(isCm: true, device: _savedMicDevice);
    } else {
      // 마이크 끄기 - 빈 문자열로 설정
      await bind.setVoiceCallInputDevice(isCm: true, device: '');
    }
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    // 오디오 권한 토글
    bind.cmSwitchPermission(
      connId: widget.clientId,
      name: 'audio',
      enabled: _isSpeakerOn,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          // 타이틀바 (CM창과 동일)
          _buildTitleBar(context),
          // 컨텐츠
          Expanded(
            child: _isAccepted ? _buildInCallContent() : _buildRequestContent(),
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
                color: Theme.of(context).colorScheme.surface,
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
                      _isAccepted ? translate('Voice Chatting') : translate('Voice Chat Request'),
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
              if (_isAccepted) {
                _disconnect();
              } else {
                _reject();
              }
              return false;
            },
          ),
        ],
      ),
    );
  }

  /// 피어 ID를 포맷팅 (123 456 789 형태)
  String _formatPeerId(String peerId) {
    final cleanId = peerId.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanId.length <= 3) return cleanId;

    final buffer = StringBuffer();
    for (int i = 0; i < cleanId.length; i++) {
      if (i > 0 && i % 3 == 0) buffer.write(' ');
      buffer.write(cleanId[i]);
    }
    return buffer.toString();
  }

  /// 수락 전 요청 화면 (CM 창 스타일)
  Widget _buildRequestContent() {
    return Container(
      color: _vcBackgroundColor,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // 타이틀
          Text(
            translate('Voice Chat Request'),
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: _vcTextPrimary,
            ),
          ),
          const SizedBox(height: 20),
          // 시스템 아이콘 (OS에 따라 다름)
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _vcIconBgColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: getPlatformImage(
                _getPeerPlatform(widget.clientPeerId),
                size: 24,
                color: _vcAccentColor,
                version: _getPeerOsVersion(widget.clientPeerId),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 요청 유저 이름
          Text(
            widget.clientName.isNotEmpty ? widget.clientName : translate('Unknown'),
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: _vcTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          // 피어 ID
          Text(
            _formatPeerId(widget.clientPeerId),
            style: const TextStyle(
              fontSize: 16,
              color: _vcTextPrimary,
            ),
          ),
          const Spacer(),
          // 버튼들 (마이페이지 다이얼로그 스타일)
          Row(
            children: [
              Expanded(
                child: StyledOutlinedButton(
                  label: translate('Reject'),
                  onPressed: _reject,
                  height: 52,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StyledPrimaryButton(
                  label: translate('Accept'),
                  onPressed: _accept,
                  height: 52,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 수락 후 통화 중 화면
  Widget _buildInCallContent() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            translate('Voice Chatting'),
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
          const Spacer(),
          // 컨트롤 버튼들
          Row(
            children: [
              // 마이크 버튼
              _buildControlButton(
                iconPath: _isMicOn ? 'assets/icons/voice-mike.svg' : 'assets/icons/voice-mike-off.svg',
                isActive: _isMicOn,
                onPressed: _toggleMic,
              ),
              const SizedBox(width: 12),
              // 스피커 버튼
              _buildControlButton(
                iconPath: _isSpeakerOn ? 'assets/icons/voice-sound.svg' : 'assets/icons/voice-sound-off.svg',
                isActive: _isSpeakerOn,
                onPressed: _toggleSpeaker,
              ),
              const Spacer(),
              // 연결 끊기 버튼
              ElevatedButton.icon(
                onPressed: _disconnect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: SvgPicture.asset(
                  'assets/icons/voice-unconnection.svg',
                  width: 20,
                  height: 20,
                  colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                ),
                label: Text(
                  translate('Disconnect'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
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

  /// 컨트롤 버튼 (마이크/스피커) - hover 효과 포함
  Widget _buildControlButton({
    required String iconPath,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    final RxBool isHovered = false.obs;
    final theme = MyTheme.sidebarIconButton(context);

    return InkWell(
      onTap: onPressed,
      onHover: (value) => isHovered.value = value,
      borderRadius: BorderRadius.circular(8),
      child: Obx(() => Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive
                    ? (isHovered.value ? theme.hoverBorderColor : Colors.grey.shade300)
                    : Colors.red.shade300,
                width: 1,
              ),
            ),
            child: Center(
              child: SvgPicture.asset(
                iconPath,
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(
                  isActive
                      ? (isHovered.value ? theme.hoverIconColor : Colors.grey.shade700)
                      : Colors.red,
                  BlendMode.srcIn,
                ),
              ),
            ),
          )),
    );
  }
}
