import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';

/// 액세스 리스트 페이지 - 카메라 공유, 음성 채팅 등 연결 목록
class AccessListPage extends StatelessWidget {
  const AccessListPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<ServerModel>(
      builder: (context, serverModel, child) {
        // 카메라 공유 중인 클라이언트
        final cameraClients = serverModel.clients
            .where((c) => c.type_() == ClientType.camera && !c.disconnected)
            .toList();

        // 음성 채팅 중인 클라이언트 (voice call 상태 확인)
        final voiceClients = serverModel.clients
            .where((c) => c.inVoiceCall && !c.disconnected)
            .toList();

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 카메라 공유 섹션
                if (cameraClients.isNotEmpty)
                  _buildSection(
                    context,
                    icon: 'assets/icons/camera.svg',
                    title: translate('Camera Sharing'),
                    clients: cameraClients,
                    clientBuilder: (client) => _CameraClientTile(client: client),
                  ),

                if (cameraClients.isNotEmpty && voiceClients.isNotEmpty)
                  const SizedBox(height: 20),

                // 음성 채팅 섹션
                if (voiceClients.isNotEmpty)
                  _buildSection(
                    context,
                    icon: 'assets/icons/voice-mike.svg',
                    title: translate('Voice Chatting'),
                    clients: voiceClients,
                    clientBuilder: (client) => _VoiceClientTile(client: client),
                  ),

                // 연결 없음
                if (cameraClients.isEmpty && voiceClients.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 100),
                      child: Column(
                        children: [
                          Icon(Icons.link_off, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            translate('No active connections'),
                            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String icon,
    required String title,
    required List<Client> clients,
    required Widget Function(Client) clientBuilder,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 헤더
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SvgPicture.asset(
                  icon,
                  width: 20,
                  height: 20,
                  colorFilter: ColorFilter.mode(
                    Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 클라이언트 목록
          ...clients.map(clientBuilder),
        ],
      ),
    );
  }
}

/// 카메라 공유 클라이언트 타일
class _CameraClientTile extends StatelessWidget {
  final Client client;

  const _CameraClientTile({required this.client});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // 유저 아바타
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 12),
          // 유저 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.name.isNotEmpty ? client.name : translate('Unknown'),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  '[${client.peerId}]',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          // 액세스 끊기 버튼
          ElevatedButton(
            onPressed: () {
              bind.cmCloseConnection(connId: client.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5C5C),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              translate('End Access'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// 음성 채팅 클라이언트 타일
class _VoiceClientTile extends StatelessWidget {
  final Client client;

  const _VoiceClientTile({required this.client});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // 유저 아바타
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 12),
          // 유저 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.name.isNotEmpty ? client.name : translate('Unknown'),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  '[${client.peerId}]',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          // 마이크 토글
          _buildIconButton(
            context,
            icon: 'assets/icons/voice-mike.svg',
            isActive: true, // TODO: 실제 상태 연결
            onTap: () {
              // TODO: 마이크 토글
            },
          ),
          const SizedBox(width: 8),
          // 스피커 토글
          _buildIconButton(
            context,
            icon: 'assets/icons/voice-sound.svg',
            isActive: true, // TODO: 실제 상태 연결
            onTap: () {
              // TODO: 스피커 토글
            },
          ),
          const SizedBox(width: 12),
          // 연결 끊기 버튼
          ElevatedButton.icon(
            onPressed: () {
              bind.cmCloseConnection(connId: client.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5C5C),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: SvgPicture.asset(
              'assets/icons/voice-unconnection.svg',
              width: 16,
              height: 16,
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
            label: Text(
              translate('Disconnect'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton(
    BuildContext context, {
    required String icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isActive ? Colors.grey[200] : Colors.grey[400],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Center(
          child: SvgPicture.asset(
            icon,
            width: 20,
            height: 20,
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
