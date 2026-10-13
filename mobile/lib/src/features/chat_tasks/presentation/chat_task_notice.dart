import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/chat_tasks/application/mobile_chat_task_providers.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_detail_screen.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_open.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// What a chat on the phone embeds for chat orchestration. Both widgets hide
// on a runtime without chat tasks and when a read fails, and lead nowhere
// until a tap: View Task opens the task, Open Chat pushes that chat.

/// Details under a message another chat or the runtime put into [chatId]:
/// the tasks a wake names, or the chat a message came from.
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
    return switch (origin.kind) {
      AgentChatItemOriginKind.orchestrationWake => Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        children: <Widget>[
          for (final taskId in origin.taskIds.take(maxTasks))
            _WakeTask(
              key: ValueKey<String>(taskId),
              hostId: hostId,
              taskId: taskId,
            ),
        ],
      ),
      AgentChatItemOriginKind.chatMessage when sender != null => _Sender(
        hostId: hostId,
        senderChatId: sender,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// The tasks [chatId] delegated that still run or need someone.
class const ChatTasksForChat({
  super.key,
  required final String chatId,
  required final String hostId,
}) extends ConsumerWidget {
  static const int maxRows = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(mobileChatTasksSupportedProvider(hostId)).value != true) {
      return const SizedBox.shrink();
    }
    final page = ref.watch(
      mobileChatTaskListProvider(
        hostId,
        AgentChatTaskQuery(parentChatId: chatId),
      ),
    );
    final open = <AgentChatTask>[
      for (final task in page.value?.tasks ?? const <AgentChatTask>[])
        if (!task.status.settled || task.needsAttention) task,
    ];
    return ChatTaskDockView(
      tasks: open.take(maxRows).toList(),
      total: open.length,
      onView: (task) => unawaited(openChatTaskDetail(context, hostId, task.id)),
    );
  }
}

class const _WakeTask({
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
    return ChatTaskNoticeRow(
      task: task,
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
