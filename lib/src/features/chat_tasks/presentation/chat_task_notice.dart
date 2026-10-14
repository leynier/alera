import 'dart:async';

import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_notice_views.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_open_actions.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_outcome_card.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'chat_task_dock.dart' show ChatTasksForChat;

// What a chat timeline embeds for chat orchestration. Every widget hides on a
// runtime without chat tasks and when a read fails, and changes nothing until
// a press: View In Activity opens Activity, Open Chat and Open Parent select
// that chat's tab.

/// Details under a message another chat, a person's delegation or the
/// runtime put into [chatId]: one outcome card per task a wake names, where a
/// task brief came from, or the chat a message came from.
class const ChatTaskOriginNotice({
  super.key,
  required final AgentChatItemOrigin origin,
  required final String chatId,
}) extends ConsumerWidget {
  /// A wake names its whole cohort; the notice shows the first few.
  static const int maxTasks = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(chatTasksSupportedProvider).value != true) {
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
            _WakeOutcome(key: ValueKey<String>(taskId), taskId: taskId),
        ],
      ),
      AgentChatItemOriginKind.chatMessage when taskId != null => _TaskOrigin(
        taskId: taskId,
      ),
      AgentChatItemOriginKind.chatMessage when sender != null => _Sender(
        senderChatId: sender,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class const _WakeOutcome({super.key, required final String taskId})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(chatTaskDetailProvider(taskId)).value;
    if (task == null) return const SizedBox.shrink();
    final childChatId = task.childChatId;
    final workspaceId = task.workspaceId;
    return ChatTaskOutcomeCard(
      task: task,
      now: ref.watch(agentChatClockProvider)(),
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

/// `Delegated by Planner` with Open Parent, or `Delegated by you`. The task
/// names its parent even when the parent chat lives on another host.
class const _TaskOrigin({required final String taskId}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(chatTaskDetailProvider(taskId)).value;
    if (task == null) return const SizedBox.shrink();
    final parentChatId = task.parentChatId;
    final parent = parentChatId == null
        ? null
        : ref.watch(chatTaskChatProvider(parentChatId)).value;
    return ChatTaskOriginRow(
      label: agentChatTaskOriginLabel(task, parentTitle: parent?.title),
      onOpenParent:
          parent != null && chatTaskWorkspaceKnown(ref, parent.workspaceId)
          ? () => unawaited(
              openChatTaskChat(
                context,
                ref,
                chatId: parent.chatId,
                workspaceId: parent.workspaceId,
              ),
            )
          : null,
      onView: () =>
          ref.read(activityNavigationProvider.notifier).openChatTask(task.id),
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
