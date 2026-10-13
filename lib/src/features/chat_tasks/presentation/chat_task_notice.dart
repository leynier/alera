import 'dart:async';

import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_notice_views.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_open_actions.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// What a chat timeline embeds for chat orchestration. Both widgets hide on a
// runtime without chat tasks and when a read fails, and change nothing until
// a press: View Task opens Activity, Open Chat selects that chat's tab.

/// Details under a message another chat or the runtime put into [chatId]:
/// the tasks a wake names, or the chat a message came from.
class const ChatTaskOriginNotice({
  super.key,
  required final AgentChatItemOrigin origin,
  required final String chatId,
}) extends ConsumerWidget {
  /// A wake names its whole cohort; the notice lists the first few.
  static const int maxTasks = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(chatTasksSupportedProvider).value != true) {
      return const SizedBox.shrink();
    }
    final sender = origin.senderChatId;
    return switch (origin.kind) {
      AgentChatItemOriginKind.orchestrationWake => Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        children: <Widget>[
          for (final taskId in origin.taskIds.take(maxTasks))
            _WakeTask(key: ValueKey<String>(taskId), taskId: taskId),
        ],
      ),
      AgentChatItemOriginKind.chatMessage when sender != null => _Sender(
        senderChatId: sender,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// The tasks [chatId] delegated that still run or need someone, for the dock
/// above its composer.
class const ChatTasksForChat({super.key, required final String chatId})
    extends ConsumerWidget {
  static const int maxRows = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(chatTasksSupportedProvider).value != true) {
      return const SizedBox.shrink();
    }
    final page = ref.watch(
      chatTaskListProvider(AgentChatTaskQuery(parentChatId: chatId)),
    );
    final open = <AgentChatTask>[
      for (final task in page.value?.tasks ?? const <AgentChatTask>[])
        if (!task.status.settled || task.needsAttention) task,
    ];
    return ChatTaskDockView(
      tasks: open.take(maxRows).toList(),
      total: open.length,
      onView: (task) =>
          ref.read(activityNavigationProvider.notifier).openChatTask(task.id),
    );
  }
}

class const _WakeTask({super.key, required final String taskId})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(chatTaskDetailProvider(taskId)).value;
    if (task == null) return const SizedBox.shrink();
    final childChatId = task.childChatId;
    final workspaceId = task.workspaceId;
    return ChatTaskNoticeRow(
      task: task,
      onView: () =>
          ref.read(activityNavigationProvider.notifier).openChatTask(task.id),
      onOpenChat:
          childChatId != null &&
              workspaceId != null &&
              chatTaskWorkspaceKnown(ref, workspaceId)
          ? () => unawaited(
              openChatTaskChat(
                context,
                ref,
                chatId: childChatId,
                workspaceId: workspaceId,
              ),
            )
          : null,
    );
  }
}

class const _Sender({required final String senderChatId})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatTaskChatProvider(senderChatId)).value;
    if (chat == null) {
      return const ChatMessageSenderRow(senderTitle: 'another chat');
    }
    final place = <String>[?chat.projectName, ?chat.workspaceName].join(' / ');
    return ChatMessageSenderRow(
      senderTitle: chat.title,
      senderPlace: place.isEmpty ? null : place,
      onOpenChat: chatTaskWorkspaceKnown(ref, chat.workspaceId)
          ? () => unawaited(
              openChatTaskChat(
                context,
                ref,
                chatId: chat.chatId,
                workspaceId: chat.workspaceId,
              ),
            )
          : null,
    );
  }
}
