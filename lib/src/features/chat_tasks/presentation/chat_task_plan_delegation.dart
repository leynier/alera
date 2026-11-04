import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_full_data.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_chat_actions.dart';
import 'package:alera/src/features/chat_tasks/presentation/delegate_chat_task_dialog.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The draft Implement In New Workspace starts from: [plan] as the brief, a
/// new worktree of the chat's project on the chat's host, the chat as parent
/// when the runtime allows it, and the chat's agent when the catalog offers
/// it. Every field stays editable in the form.
AgentChatDelegateDraft chatTaskPlanDraft({
  required AgentChatItem plan,
  required String workspaceId,
  String? projectId,
  String hostId = agentChatLocalHostId,
  String? parentChatId,
  AgentChatSelection? agent,
}) => AgentChatDelegateDraft(
  targetKind: AgentChatTaskTargetKind.newWorkspace,
  task: agentChatPlanTaskBrief(plan),
  title: agentChatPlanTaskTitle(plan),
  workspaceId: workspaceId,
  projectId: projectId,
  hostId: hostId,
  mode: AgentChatWorkspaceMode.worktree,
  parentChatId: parentChatId,
  providerInstanceId: agent?.providerInstanceId,
  model: agent?.model,
);

/// Opens Delegate Task to implement [plan] from [chat] in a new workspace.
/// Nothing is created until the person presses Delegate, and nothing opens
/// afterwards; a toast offers View In Activity.
Future<void> showImplementPlanInNewWorkspace(
  BuildContext context, {
  required AgentChatRef chat,
  required AgentChatItem plan,
}) async {
  final container = ProviderScope.containerOf(context);
  final workbench = container.read(workbenchControllerProvider);
  final workspace = workbench.workspacesByProject.values
      .expand((items) => items)
      .where((item) => item.id == chat.workspaceId)
      .firstOrNull;
  final (parent, agent) = await (
    chatTaskPersonParent(container, chat.chatId),
    _chatAgent(container, chat.chatId),
  ).wait;
  if (!context.mounted) return;
  final result = await showDelegateChatTaskDialog(
    context,
    initial: chatTaskPlanDraft(
      plan: plan,
      workspaceId: chat.workspaceId,
      projectId: workspace?.projectId,
      hostId: workspace?.hostId ?? agentChatLocalHostId,
      parentChatId: parent,
      agent: agent,
    ),
    openInActivity: false,
  );
  if (result == null) return;
  announceChatTaskDelegated(container, result, reportsToChat: parent != null);
}

/// The chat's own agent and model, when the runtime's catalog still offers
/// that agent; otherwise the form keeps its default.
Future<AgentChatSelection?> _chatAgent(
  ProviderContainer container,
  String chatId,
) async {
  // Listeners keep the auto-disposed reads alive until they answer.
  final chat = container.listen(chatTaskChatProvider(chatId).future, (_, _) {});
  final catalog = container.listen(
    chatTaskCapabilitiesProvider.future,
    (_, _) {},
  );
  try {
    final (entry, capabilities) = await (chat.read(), catalog.read()).wait;
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
    catalog.close();
  }
}

/// Implement In New Workspace on a proposed plan. Hidden on a runtime
/// without chat tasks, outside a chat, and while the plan is still drafting.
class const ChatTaskImplementPlanButton({
  super.key,
  required final AgentChatItem plan,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = AgentChatFullDataScope.maybeChatOf(context);
    if (chat == null ||
        plan.isInProgress ||
        ref.watch(chatTasksSupportedProvider).value != true ||
        (plan.text.trim().isEmpty && plan.planSteps.isEmpty)) {
      return const SizedBox.shrink();
    }
    return OutlinedButton.icon(
      key: const ValueKey<String>('agent-chat-implement-plan-in-workspace'),
      onPressed: () => unawaited(
        showImplementPlanInNewWorkspace(context, chat: chat, plan: plan),
      ),
      icon: const Icon(AleraIcons.workspaceChildren, size: AleraTokens.iconMd),
      label: const Text('Implement In New Workspace'),
    );
  }
}
