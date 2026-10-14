import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/chat_tasks/application/mobile_chat_task_providers.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_detail_screen.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_notice_views.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_open.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'chat_task_dock.dart' show ChatTasksForChat;

// What a chat on the phone embeds for chat orchestration. Every widget hides
// on a runtime without chat tasks and when a read fails, and leads nowhere
// until a tap: View Task opens the task, Open Chat and Open Parent push that
// chat.

/// Details under a message another chat, a person's delegation or the
/// runtime put into [chatId]: one outcome card per task a wake names, where a
/// task brief came from, or the chat a message came from.
class const ChatTaskOriginNotice({
  super.key,
  required final AgentChatItemOrigin origin,
  required final String chatId,
  required final String hostId,
}) extends ConsumerWidget {
  static const int maxTasks = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(mobileChatTasksSupportedProvider(hostId)).value != true) {
      return const SizedBox.shrink();
    }
    final sender = origin.senderChatId;
    final taskId = origin.taskIds.firstOrNull;
    return switch (origin.kind) {
      AgentChatItemOriginKind.orchestrationWake => Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        children: <Widget>[
          for (final taskId in origin.taskIds.take(maxTasks))
            _WakeOutcome(
              key: ValueKey<String>(taskId),
              hostId: hostId,
              taskId: taskId,
            ),
        ],
      ),
      AgentChatItemOriginKind.chatMessage when taskId != null => _TaskOrigin(
        hostId: hostId,
        taskId: taskId,
      ),
      AgentChatItemOriginKind.chatMessage when sender != null => _Sender(
        hostId: hostId,
        senderChatId: sender,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class const _WakeOutcome({
  super.key,
  required final String hostId,
  required final String taskId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(mobileChatTaskDetailProvider(hostId, taskId)).value;
    if (task == null) return const SizedBox.shrink();
    final childChatId = task.childChatId;
    final workspaceId = task.workspaceId;
    return ChatTaskOutcomeCard(
      task: task,
      now: DateTime.now(),
      onView: () => unawaited(openChatTaskDetail(context, hostId, task.id)),
      onOpenChat: childChatId == null || workspaceId == null
          ? null
          : () => unawaited(
              openMobileChatTaskChat(
                context,
                ref,
                hostId: hostId,
                chatId: childChatId,
                workspaceId: workspaceId,
              ),
            ),
    );
  }
}

/// `Delegated by Planner` with Open Parent, or `Delegated by you`.
class const _TaskOrigin({
  required final String hostId,
  required final String taskId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(mobileChatTaskDetailProvider(hostId, taskId)).value;
    if (task == null) return const SizedBox.shrink();
    final parentChatId = task.parentChatId;
    final parent = parentChatId == null
        ? null
        : ref.watch(mobileChatTaskChatProvider(hostId, parentChatId)).value;
    return ChatTaskOriginRow(
      label: agentChatTaskOriginLabel(task, parentTitle: parent?.title),
      onOpenParent: parent == null
          ? null
          : () => unawaited(
              openMobileChatTaskChat(
                context,
                ref,
                hostId: hostId,
                chatId: parent.chatId,
                workspaceId: parent.workspaceId,
              ),
            ),
      onView: () => unawaited(openChatTaskDetail(context, hostId, task.id)),
    );
  }
}

class const _Sender({
  required final String hostId,
  required final String senderChatId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref
        .watch(mobileChatTaskChatProvider(hostId, senderChatId))
        .value;
    if (chat == null) {
      return const ChatMessageSenderRow(senderTitle: 'another chat');
    }
    final place = <String>[?chat.projectName, ?chat.workspaceName].join(' / ');
    return ChatMessageSenderRow(
      senderTitle: chat.title,
      senderPlace: place.isEmpty ? null : place,
      onOpenChat: () => unawaited(
        openMobileChatTaskChat(
          context,
          ref,
          hostId: hostId,
          chatId: chat.chatId,
          workspaceId: chat.workspaceId,
        ),
      ),
    );
  }
}
