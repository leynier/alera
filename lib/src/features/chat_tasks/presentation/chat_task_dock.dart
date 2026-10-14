import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/domain/activity_section.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_actions.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_dock_expansion.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_dock_view.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_input_banner.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_open_actions.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_requests_view.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The tasks [chatId] delegated, above its composer: a banner when a child
/// waits on a person, then the Tasks dock. The banner yields while the chat
/// has its own pending request. Hidden on a runtime without chat tasks and
/// while nothing was delegated; nothing here navigates on its own.
class const ChatTasksForChat({
  super.key,
  required final String chatId,
  final bool parentHasPendingRequest = false,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<ChatTasksForChat> createState() => _ChatTasksForChatState();
}

class _ChatTasksForChatState extends ConsumerState<ChatTasksForChat> {
  String? _answering;
  final Set<String> _stopping = <String>{};

  Future<void> _stop(AgentChatTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const AleraConfirmDialog(
        title: 'Stop Task?',
        message: 'The agent stops, its queued input is dropped and every task it started is stopped too. Workspaces it created stay.',
        confirmLabel: 'Stop Task',
        cancelLabel: 'Keep Running',
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _stopping.add(task.id));
    try {
      await ref.read(chatTaskActionsProvider).cancel(task.id);
    } on Object catch (error) {
      if (mounted) _toast(agentChatOrchestrationErrorMessage(error));
    } finally {
      if (mounted) setState(() => _stopping.remove(task.id));
    }
  }

  void _toast(String message) =>
      AleraToast.show(context, message: message, tone: AleraToastTone.error);

  void _openChat(AgentChatTask task) {
    final chatId = task.childChatId;
    final workspaceId = task.workspaceId;
    if (chatId == null || workspaceId == null) return;
    unawaited(
      openChatTaskChat(context, ref, chatId: chatId, workspaceId: workspaceId),
    );
  }

  String _place(AgentChatTask task) {
    final workbench = ref.read(workbenchControllerProvider);
    final workspace = workbench.workspacesByProject.values
        .expand((items) => items)
        .where((item) => item.id == task.workspaceId)
        .firstOrNull;
    return agentChatTaskPlaceLabel(
      task,
      projectName: workbench.projects
          .where((item) => item.id == task.projectId)
          .firstOrNull
          ?.name,
      workspaceName: workspace?.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(chatTasksSupportedProvider).value != true) {
      return const SizedBox.shrink();
    }
    final chatId = widget.chatId;
    final tasks =
        ref
            .watch(
              chatTaskListProvider(AgentChatTaskQuery(parentChatId: chatId)),
            )
            .value
            ?.tasks ??
        const <AgentChatTask>[];
    if (tasks.isEmpty) return const SizedBox.shrink();
    // Rebuild place labels when workspaces load or are renamed.
    ref.watch(
      workbenchControllerProvider.select((state) => state.workspacesByProject),
    );
    final waiting = agentChatTaskDockOrder(tasks)
        .where(
          (task) =>
              task.status == AgentChatTaskStatus.needsInput ||
              task.attention == AgentChatTaskAttention.needsInput,
        )
        .toList(growable: false);
    final first = waiting.firstOrNull;
    final navigation = ref.read(activityNavigationProvider.notifier);
    final expanded = ref.watch(
      chatTaskDockExpansionProvider.select((ids) => ids.contains(chatId)),
    );
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      spacing: AleraTokens.space8,
      children: <Widget>[
        if (first != null && !widget.parentHasPendingRequest)
          ChatTaskInputBanner(
            task: first,
            otherCount: waiting.length - 1,
            answering: _answering == first.id,
            onAnswerHere: () => setState(
              () => _answering = _answering == first.id ? null : first.id,
            ),
            onOpenChat: _canOpen(first) ? () => _openChat(first) : null,
            requests: _answering == first.id
                ? _ChildRequests(
                    task: first,
                    onAnswerInChat: _canOpen(first)
                        ? () => _openChat(first)
                        : null,
                  )
                : null,
          ),
        ChatTaskDockView(
          tasks: tasks,
          expanded: expanded,
          onExpandedChanged: (value) => ref
              .read(chatTaskDockExpansionProvider.notifier)
              .set(chatId, expanded: value),
          now: ref.watch(agentChatClockProvider),
          placeOf: _place,
          stopping: _stopping,
          actions: ChatTaskDockActions(
            onView: (task) => navigation.openChatTask(task.id),
            onStop: (task) => unawaited(_stop(task)),
            canOpenChat: _canOpen,
            onOpenChat: _openChat,
            onViewAll: () => navigation.open(ActivitySection.chatTasks),
          ),
        ),
      ],
    );
  }

  bool _canOpen(AgentChatTask task) =>
      task.childChatId != null && chatTaskWorkspaceKnown(ref, task.workspaceId);
}

/// The child's open requests, answered in the parent. Approvals resolve here
/// with the decisions the provider offers; questions and forms open the
/// child chat, where their full form lives.
class const _ChildRequests({
  required final AgentChatTask task,
  final VoidCallback? onAnswerInChat,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests =
        ref.watch(chatTaskRequestsProvider(task.id)).value ??
        const <AgentChatTaskRequest>[];
    return ChatTaskRequestsView(
      requests: requests,
      enabled: true,
      onAnswerInChat: onAnswerInChat,
      onDecision: (request, decision) => unawaited(() async {
        try {
          await ref.read(chatTaskActionsProvider).approve(request, decision);
          ref.invalidate(chatTaskRequestsProvider(task.id));
        } on Object catch (error) {
          if (context.mounted) {
            AleraToast.show(
              context,
              message: agentChatOrchestrationErrorMessage(error),
              tone: AleraToastTone.error,
            );
          }
        }
      }()),
    );
  }
}
