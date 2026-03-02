import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../mobile/pages/home_page.dart';

enum ChatPageType {
  mobileMain,
  desktopCM,
}

class ChatPage extends StatelessWidget implements PageShape {
  late final ChatModel chatModel;
  final ChatPageType? type;

  ChatPage({ChatModel? chatModel, this.type}) {
    this.chatModel = chatModel ?? gFFI.chatModel;
  }

  @override
  final title = translate("Chat");

  @override
  final icon = unreadTopRightBuilder(gFFI.chatModel.mobileUnreadSum);

  @override
  final appBarActions = [
    PopupMenuButton<MessageKey>(
        tooltip: "",
        icon: unreadTopRightBuilder(gFFI.chatModel.mobileUnreadSum,
            icon: Icon(Icons.group)),
        itemBuilder: (context) {
          // only mobile need [appBarActions], just bind gFFI.chatModel
          final chatModel = gFFI.chatModel;
          return chatModel.messages.entries.map((entry) {
            final key = entry.key;
            final user = entry.value.chatUser;
            final client = gFFI.serverModel.clients
                .firstWhereOrNull((e) => e.id == key.connId);
            final connected =
                gFFI.serverModel.clients.any((e) => e.id == key.connId);
            return PopupMenuItem<MessageKey>(
              child: Row(
                children: [
                  Icon(
                          key.isOut
                              ? Icons.call_made_rounded
                              : Icons.call_received_rounded,
                          color: MyTheme.accent)
                      .marginOnly(right: 6),
                  Text("${user.firstName}   ${user.id}"),
                  if (connected)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.fromARGB(255, 46, 205, 139)),
                    ).marginSymmetric(horizontal: 2),
                  if (client != null)
                    unreadMessageCountBuilder(client.unreadChatMessageCount)
                        .marginOnly(left: 4)
                ],
              ),
              value: key,
            );
          }).toList();
        },
        onSelected: (key) {
          gFFI.chatModel.changeCurrentKey(key);
        })
  ];

  // 시간 포맷 (오후 02:30 형식)
  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? '오전' : '오후';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$period ${hour12.toString().padLeft(2, '0')}:$minute';
  }

  // 날짜 포맷 (2025.11.04 화요일 형식)
  String _formatDate(DateTime dateTime) {
    final weekdays = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
    final weekday = weekdays[dateTime.weekday - 1];
    return '${dateTime.year}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.day.toString().padLeft(2, '0')} $weekday';
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: chatModel,
      child: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Consumer<ChatModel>(
          builder: (context, chatModel, child) {
            final readOnly = type == ChatPageType.mobileMain &&
                    (chatModel.currentKey.connId == ChatModel.clientModeID ||
                        gFFI.serverModel.clients.every((e) =>
                            e.id != chatModel.currentKey.connId ||
                            chatModel.currentUser == null)) ||
                type == ChatPageType.desktopCM &&
                    gFFI.serverModel.clients
                            .firstWhereOrNull(
                                (e) => e.id == chatModel.currentKey.connId)
                            ?.disconnected ==
                        true;
            return Stack(
              children: [
                LayoutBuilder(builder: (context, constraints) {
                  final chat = DashChat(
                    onSend: chatModel.send,
                    currentUser: chatModel.me,
                    messages: chatModel
                            .messages[chatModel.currentKey]?.chatMessages ??
                        [],
                    readOnly: readOnly,
                    inputOptions: InputOptions(
                      focusNode: chatModel.inputNode,
                      textController: chatModel.textController,
                      inputTextStyle: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFF646368)),
                      inputDecoration: InputDecoration(
                        isDense: true,
                        hintText: translate('Write a message'),
                        hintStyle: const TextStyle(
                          color: Color(0xFFB9B8BF),
                          fontSize: 16,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFFFFFFF),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      inputToolbarStyle: BoxDecoration(
                        color: const Color(0xFFF2F1F6),
                      ),
                      sendButtonBuilder: (onSend) => Container(
                        margin: const EdgeInsets.only(left: 8),
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: Color(0xFF5667E8),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: onSend,
                          icon: SvgPicture.asset(
                            'assets/icons/cm-chat-message-send.svg',
                            width: 18,
                            height: 18,
                            colorFilter: const ColorFilter.mode(
                              Color(0xFFFFFFFF),
                              BlendMode.srcIn,
                            ),
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),
                      ),
                    ),
                    messageOptions: MessageOptions(
                      showOtherUsersAvatar: false,
                      showOtherUsersName: false,
                      showCurrentUserAvatar: false,
                      showTime: false,
                      maxWidth: constraints.maxWidth * 0.7,
                      messageTextBuilder: (message, _, __) {
                        final isOwnMessage = message.user.id == chatModel.me.id;
                        return Text(
                          message.text,
                          style: TextStyle(
                            color: isOwnMessage ? const Color(0xFFFEFEFE) : const Color(0xFF646368),
                            fontSize: 16,
                          ),
                        );
                      },
                      messageDecorationBuilder:
                          (message, previousMessage, nextMessage) {
                        final isOwnMessage = message.user.id == chatModel.me.id;
                        return BoxDecoration(
                          color: isOwnMessage
                              ? const Color(0xFF5F71FF)
                              : const Color(0xFFF2F1F6),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isOwnMessage ? 16 : 4),
                            bottomRight: Radius.circular(isOwnMessage ? 4 : 16),
                          ),
                        );
                      },
                      messageRowBuilder: (message, previousMessage, nextMessage, isAfterDateSeparator, isBeforeDateSeparator) {
                        final isOwnMessage = message.user.id == chatModel.me.id;
                        final timeStr = _formatTime(message.createdAt);

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Row(
                            mainAxisAlignment: isOwnMessage
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: isOwnMessage
                                ? [
                                    // 시간 (왼쪽)
                                    Text(
                                      timeStr,
                                      style: const TextStyle(
                                        color: Color(0xFF8F8E95),
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // 메시지 버블 (오른쪽) - 내 메시지
                                    Flexible(
                                      child: Container(
                                        constraints: BoxConstraints(
                                          maxWidth: constraints.maxWidth * 0.65,
                                        ),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF5F71FF),
                                          borderRadius: BorderRadius.only(
                                            topLeft: Radius.circular(16),
                                            topRight: Radius.circular(16),
                                            bottomLeft: Radius.circular(16),
                                            bottomRight: Radius.circular(4),
                                          ),
                                        ),
                                        child: Text(
                                          message.text,
                                          style: const TextStyle(
                                            color: Color(0xFFFEFEFE),
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ]
                                : [
                                    // 메시지 버블 (왼쪽) - 상대방 메시지
                                    Flexible(
                                      child: Container(
                                        constraints: BoxConstraints(
                                          maxWidth: constraints.maxWidth * 0.65,
                                        ),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFF2F1F6),
                                          borderRadius: BorderRadius.only(
                                            topLeft: Radius.circular(16),
                                            topRight: Radius.circular(16),
                                            bottomLeft: Radius.circular(4),
                                            bottomRight: Radius.circular(16),
                                          ),
                                        ),
                                        child: Text(
                                          message.text,
                                          style: const TextStyle(
                                            color: Color(0xFF646368),
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // 시간 (오른쪽)
                                    Text(
                                      timeStr,
                                      style: const TextStyle(
                                        color: Color(0xFF8F8E95),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                          ),
                        );
                      },
                    ),
                    messageListOptions: MessageListOptions(
                      dateSeparatorBuilder: (date) => Container(
                        margin: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            _formatDate(date),
                            style: const TextStyle(
                              color: Color(0xFF8F8E95),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ).workaroundFreezeLinuxMint();
                  return SelectionArea(child: chat);
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 별도의 전체 화면 채팅 페이지 (모바일 CM용)
class MobileChatPage extends StatelessWidget {
  final String peerId;
  final int connId;
  final ChatPageType? chatPageType;

  static const Color _titleColor = Color(0xFF454447);

  const MobileChatPage({
    Key? key,
    required this.peerId,
    required this.connId,
    this.chatPageType = ChatPageType.mobileMain,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    gFFI.chatModel.changeCurrentKey(MessageKey(peerId, connId));
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: _titleColor, size: 20),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Get.back();
            }
          },
        ),
        title: Text(
          '[$peerId]',
          style: const TextStyle(
            color: _titleColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: ChatPage(type: chatPageType),
    );
  }
}
