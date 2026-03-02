import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../common.dart' hide Dialog;
import '../../models/server_model.dart';

/// 음성 채팅 중 창 (호스트/게스트 공통)
class VoiceChatWindow extends StatefulWidget {
  final Client client;
  final VoidCallback onDisconnect;
  final bool isHost;

  const VoiceChatWindow({
    Key? key,
    required this.client,
    required this.onDisconnect,
    this.isHost = true,
  }) : super(key: key);

  @override
  State<VoiceChatWindow> createState() => _VoiceChatWindowState();
}

class _VoiceChatWindowState extends State<VoiceChatWindow> {
  bool _isMicMuted = false;
  bool _isSpeakerMuted = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              translate('Voice Chatting'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            // 유저 아이콘
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFBBC4FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: SvgPicture.asset(
                  'assets/icons/voice-mike.svg',
                  width: 40,
                  height: 40,
                  colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 유저 이름
            Text(
              widget.client.name.isNotEmpty ? widget.client.name : translate('Unknown'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            // 유저 ID
            Text(
              '[${widget.client.peerId}]',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            // 컨트롤 버튼들
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 마이크 토글
                _buildControlButton(
                  icon: _isMicMuted ? 'assets/icons/voice-mike.svg' : 'assets/icons/voice-mike.svg',
                  isActive: !_isMicMuted,
                  onTap: () {
                    setState(() {
                      _isMicMuted = !_isMicMuted;
                    });
                    // TODO: 실제 마이크 음소거 처리
                  },
                ),
                const SizedBox(width: 12),
                // 스피커 토글
                _buildControlButton(
                  icon: 'assets/icons/voice-sound.svg',
                  isActive: !_isSpeakerMuted,
                  onTap: () {
                    setState(() {
                      _isSpeakerMuted = !_isSpeakerMuted;
                    });
                    // TODO: 실제 스피커 음소거 처리
                  },
                ),
                const SizedBox(width: 24),
                // 연결 끊기 버튼
                ElevatedButton.icon(
                  onPressed: widget.onDisconnect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5C5C),
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
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required String icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isActive ? Colors.grey[200] : Colors.grey[400],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Center(
          child: SvgPicture.asset(
            icon,
            width: 24,
            height: 24,
            colorFilter: ColorFilter.mode(
              isActive ? Colors.grey[700]! : Colors.grey[500]!,
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }
}

/// 음성 채팅 창 표시 함수
void showVoiceChatWindow(BuildContext context, Client client, {bool isHost = true, VoidCallback? onDisconnect}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => VoiceChatWindow(
      client: client,
      isHost: isHost,
      onDisconnect: () {
        Navigator.of(context).pop();
        onDisconnect?.call();
      },
    ),
  );
}
