import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../common.dart' hide Dialog;
import '../../common/widgets/styled_form_widgets.dart';
import '../../models/server_model.dart';

/// 카메라 공유 요청 다이얼로그
class CameraRequestDialog extends StatelessWidget {
  final Client client;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const CameraRequestDialog({
    Key? key,
    required this.client,
    required this.onAccept,
    required this.onReject,
  }) : super(key: key);

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
              translate('Camera Share Request'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            // 카메라 아이콘
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFBBC4FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: SvgPicture.asset(
                  'assets/icons/camera.svg',
                  width: 40,
                  height: 40,
                  colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 유저 이름
            Text(
              client.name.isNotEmpty ? client.name : translate('Unknown'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            // 유저 ID
            Text(
              '[${client.peerId}]',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            // 버튼들
            Row(
              children: [
                Expanded(
                  child: StyledOutlinedButton(
                    label: translate('Reject'),
                    onPressed: onReject,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onAccept,
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
      ),
    );
  }
}

/// 음성 채팅 요청 다이얼로그
class VoiceRequestDialog extends StatelessWidget {
  final Client client;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const VoiceRequestDialog({
    Key? key,
    required this.client,
    required this.onAccept,
    required this.onReject,
  }) : super(key: key);

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
              translate('Voice Chat Request'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            // 마이크 아이콘
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
              client.name.isNotEmpty ? client.name : translate('Unknown'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            // 유저 ID
            Text(
              '[${client.peerId}]',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            // 버튼들
            Row(
              children: [
                Expanded(
                  child: StyledOutlinedButton(
                    label: translate('Reject'),
                    onPressed: onReject,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onAccept,
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
      ),
    );
  }
}

/// 요청 다이얼로그 표시 함수
Future<bool?> showAccessRequestDialog(BuildContext context, Client client) {
  if (client.type_() == ClientType.camera) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CameraRequestDialog(
        client: client,
        onAccept: () => Navigator.of(context).pop(true),
        onReject: () => Navigator.of(context).pop(false),
      ),
    );
  } else {
    // 음성 채팅이나 기타 타입
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => VoiceRequestDialog(
        client: client,
        onAccept: () => Navigator.of(context).pop(true),
        onReject: () => Navigator.of(context).pop(false),
      ),
    );
  }
}
