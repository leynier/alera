import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/chat_tasks/application/mobile_chat_task_providers.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_detail_screen.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/delegate_chat_task_screen.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/send_to_chat_sheet.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Delegate Task and Send To Chat from inside a chat on the phone. Both default
// to this chat as the parent when the runtime lets a person name one, and to
// a new chat in this chat's workspace. Neither navigates on its own; a
// SnackBar offers View Task.

/// Delegate Task with [chatId] as the parent and a new chat in [workspaceId]
/// as the target, both changeable in the form.
Future<void> showDelegateChatTaskFromChat(
  BuildContext context, {
  required String hostId,
  required String chatId,
  required String workspaceId,
}) async {
  final container = ProviderScope.containerOf(context);
  final parent = await _personParent(container, hostId, chatId);
  if (!context.mounted) return;
  await openDelegateChatTask(
    context,
    hostId,
    initial: AgentChatDelegateDraft(
      workspaceId: workspaceId,
      parentChatId: parent,
    ),
    openTaskWhenCreated: false,
  );
}

/// Send To Chat from [fromChatId]. A tracked reply belongs to that chat when
/// the runtime lets a person name a parent.
Future<void> showSendToChatSheet(
  BuildContext context, {
  required String hostId,
  required String fromChatId,
  required String workspaceId,
}) async {
  final container = ProviderScope.containerOf(context);
  final parent = await _personParent(container, hostId, fromChatId);
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final result = await showModalBottomSheet<AgentChatTaskMessageResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => SendToChatSheet(
      hostId: hostId,
      fromChatId: fromChatId,
      parentChatId: parent,
    ),
  );
  if (result == null) return;
  final taskId = result.taskId;
  messenger.showSnackBar(
    SnackBar(
      content: const Text('Message sent.'),
      action: taskId == null
          ? null
          : SnackBarAction(
              label: 'View Task',
              onPressed: () => unawaited(
                navigator.push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ChatTaskDetailScreen(hostId: hostId, taskId: taskId),
                  ),
                ),
              ),
            ),
    ),
  );
}

/// Opens Delegate Task to implement [plan] from [chatId] in a new worktree
/// of the chat's project on the chat's host, with the chat as parent when the
/// runtime allows it and the chat's agent when the catalog still offers it.
/// Nothing is created until the person presses Delegate.
Future<void> showImplementPlanInNewWorkspace(
  BuildContext context, {
  required String hostId,
  required String chatId,
  required String workspaceId,
  required AgentChatItem plan,
}) async {
  final container = ProviderScope.containerOf(context);
  final (parent, agent, workspace) = await (
    _personParent(container, hostId, chatId),
    _chatAgent(container, hostId, chatId),
    _workspace(container, hostId, workspaceId),
  ).wait;
  if (!context.mounted) return;
  await openDelegateChatTask(
    context,
    hostId,
    initial: AgentChatDelegateDraft(
      targetKind: AgentChatTaskTargetKind.newWorkspace,
      task: agentChatPlanTaskBrief(plan),
      title: agentChatPlanTaskTitle(plan),
      workspaceId: workspaceId,
      projectId: workspace?.projectId,
      hostId: workspace?.hostId ?? agentChatLocalHostId,
      mode: AgentChatWorkspaceMode.worktree,
      parentChatId: parent,
      providerInstanceId: agent?.providerInstanceId,
      model: agent?.model,
    ),
    openTaskWhenCreated: false,
  );
}

Future<WorkspaceSummary?> _workspace(
  ProviderContainer container,
  String hostId,
  String workspaceId,
) async {
  final places = container.listen(
    mobileChatTaskPlacesProvider(hostId).future,
    (_, _) {},
  );
  try {
    return (await places.read()).workspace(workspaceId);
  } on Object {
    return null;
  } finally {
    places.close();
  }
}

/// The chat's own agent and model, when the host's catalog still offers that
/// agent; otherwise the form keeps its default.
Future<AgentChatSelection?> _chatAgent(
  ProviderContainer container,
  String hostId,
  String chatId,
) async {
  final chat = container.listen(
    mobileChatTaskChatProvider(hostId, chatId).future,
    (_, _) {},
  );
  final repository = container.listen(
    mobileChatTaskRepositoryProvider(hostId).future,
    (_, _) {},
  );
  try {
    final (entry, orchestration) = await (chat.read(), repository.read()).wait;
    final capabilities = await orchestration.capabilities();
    final instanceId = entry.chat.providerInstanceId;
    final offered = capabilities.providers.any(
      (provider) => provider.id == instanceId && provider.available,
    );
    if (!offered) return null;
    return AgentChatSelection(
      providerInstanceId: instanceId,
      model: entry.chat.model,
    );
  } on Object {
    return null;
  } finally {
    chat.close();
    repository.close();
  }
}

Future<String?> _personParent(
  ProviderContainer container,
  String hostId,
  String chatId,
) async {
  // A listener keeps the auto-disposed read alive until it answers.
  final subscription = container.listen(
    mobileChatTaskPersonParentProvider(hostId).future,
    (_, _) {},
  );
  try {
    return await subscription.read() ? chatId : null;
  } on Object {
    return null;
  } finally {
    subscription.close();
  }
}
