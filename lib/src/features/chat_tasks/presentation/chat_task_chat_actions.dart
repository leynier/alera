import 'dart:async';

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/chat_tasks/presentation/delegate_chat_task_dialog.dart';
import 'package:alera/src/features/chat_tasks/presentation/send_to_chat_dialog.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Delegate Task and Send To Chat from inside a chat. Both default to this
// chat as the parent when the runtime lets a person name one, and to a new
// chat in this chat's workspace. Neither opens Activity, a workspace or a
// tab on its own; a toast offers View In Activity instead.

/// Delegate Task with [chatId] as the parent and a new chat in [workspaceId]
/// as the target, both changeable in the form.
Future<void> showDelegateChatTaskFromChat(
  BuildContext context, {
  required String chatId,
  required String workspaceId,
}) async {
  final container = ProviderScope.containerOf(context);
  final parent = await chatTaskPersonParent(container, chatId);
  if (!context.mounted) return;
  final result = await showDelegateChatTaskDialog(
    context,
    initial: AgentChatDelegateDraft(
      workspaceId: workspaceId,
      parentChatId: parent,
    ),
    openInActivity: false,
  );
  if (result == null) return;
  announceChatTaskDelegated(container, result, reportsToChat: parent != null);
}

/// The toast after a delegation started from a chat. It offers View In
/// Activity and opens nothing by itself.
void announceChatTaskDelegated(
  ProviderContainer container,
  AgentChatDelegateResult result, {
  required bool reportsToChat,
}) => AleraToast.publish(
  message: reportsToChat
      ? 'Task delegated. It reports back to this chat.'
      : 'Task delegated. Follow it in Activity.',
  tone: AleraToastTone.success,
  actionLabel: 'View In Activity',
  onAction: () => container
      .read(activityNavigationProvider.notifier)
      .openChatTask(result.taskId),
);

/// Send To Chat from [fromChatId]. A tracked reply belongs to that chat when
/// the runtime lets a person name a parent.
Future<void> showSendToChatDialog(
  BuildContext context, {
  required String fromChatId,
  required String workspaceId,
}) async {
  final container = ProviderScope.containerOf(context);
  final parent = await chatTaskPersonParent(container, fromChatId);
  if (!context.mounted) return;
  final result = await showDialog<AgentChatTaskMessageResult>(
    context: context,
    builder: (_) =>
        SendToChatDialog(fromChatId: fromChatId, parentChatId: parent),
  );
  if (result == null) return;
  final taskId = result.taskId;
  AleraToast.publish(
    message: 'Message sent.',
    tone: AleraToastTone.success,
    actionLabel: taskId == null ? null : 'View In Activity',
    onAction: taskId == null
        ? null
        : () => container
              .read(activityNavigationProvider.notifier)
              .openChatTask(taskId),
  );
}

/// [chatId] when the runtime lets a person name a parent chat, else null.
Future<String?> chatTaskPersonParent(
  ProviderContainer container,
  String chatId,
) async {
  try {
    return await container
            .read(chatTaskRepositoryProvider)
            .supportsPersonParent()
        ? chatId
        : null;
  } on Object {
    return null;
  }
}

enum _ChatTaskChatAction { delegate, send }

/// The chat header's Delegate Task and Send To Chat. Hidden on a runtime
/// without chat tasks.
class const ChatTaskChatMenuButton({
  super.key,
  required final String chatId,
  required final String workspaceId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(chatTasksSupportedProvider).value != true) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<_ChatTaskChatAction>(
      key: const ValueKey<String>('chatTaskChatMenu'),
      tooltip: 'Chat Task Actions',
      icon: const Icon(AleraIcons.more),
      onSelected: (action) => unawaited(switch (action) {
        _ChatTaskChatAction.delegate => showDelegateChatTaskFromChat(
          context,
          chatId: chatId,
          workspaceId: workspaceId,
        ),
        _ChatTaskChatAction.send => showSendToChatDialog(
          context,
          fromChatId: chatId,
          workspaceId: workspaceId,
        ),
      }),
      itemBuilder: (_) => const <PopupMenuEntry<_ChatTaskChatAction>>[
        AleraDropdownEntry(
          value: _ChatTaskChatAction.delegate,
          label: 'Delegate Task',
        ),
        AleraDropdownEntry(
          value: _ChatTaskChatAction.send,
          label: 'Send To Chat',
        ),
      ],
    );
  }
}
