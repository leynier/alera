import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera_mobile/src/features/chat_tasks/application/mobile_chat_task_providers.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_detail_screen.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_dock_view.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_notice_views.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_open.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_request_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The tasks [chatId] delegated, above its composer: a banner when a child
/// waits on a person, then the Tasks dock. The banner yields while the chat
/// has its own pending request. Hidden on a runtime without chat tasks and
/// while nothing was delegated; nothing here navigates on its own.
class const ChatTasksForChat({
  super.key,
  required final String chatId,
  required final String hostId,
  final bool parentHasPendingRequest = false,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<ChatTasksForChat> createState() => _ChatTasksForChatState();
}

class _ChatTasksForChatState extends ConsumerState<ChatTasksForChat> {
  String? _answering;
  final Set<String> _stopping = <String>{};

  String get _hostId => widget.hostId;

  Future<void> _stop(AgentChatTask task) async {
    final messenger = ScaffoldMessenger.of(context);
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
      final actions = await ref.read(
        mobileChatTaskActionsProvider(_hostId).future,
      );
      await actions.cancel(task.id);
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(agentChatOrchestrationErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _stopping.remove(task.id));
    }
  }

  void _openChat(AgentChatTask task) {
    final chatId = task.childChatId;
    final workspaceId = task.workspaceId;
    if (chatId == null || workspaceId == null) return;
    unawaited(
      openMobileChatTaskChat(
        context,
        ref,
        hostId: _hostId,
        chatId: chatId,
        workspaceId: workspaceId,
      ),
    );
  }

  bool _canOpen(AgentChatTask task) =>
      task.childChatId != null && task.workspaceId != null;

  @override
  Widget build(BuildContext context) {
    if (ref.watch(mobileChatTasksSupportedProvider(_hostId)).value != true) {
      return const SizedBox.shrink();
    }
    final chatId = widget.chatId;
    final tasks =
        ref
            .watch(
              mobileChatTaskListProvider(
                _hostId,
                AgentChatTaskQuery(parentChatId: chatId),
              ),
            )
            .value
            ?.tasks ??
        const <AgentChatTask>[];
    if (tasks.isEmpty) return const SizedBox.shrink();
    final waiting = agentChatTaskDockOrder(tasks)
        .where(
          (task) =>
              task.status == AgentChatTaskStatus.needsInput ||
              task.attention == AgentChatTaskAttention.needsInput,
        )
        .toList(growable: false);
    final first = waiting.firstOrNull;
    final expansion = mobileChatTaskDockExpansionProvider(_hostId);
    final expanded = ref.watch(expansion.select((ids) => ids.contains(chatId)));
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      spacing: AleraTokens.spaceSm,
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
                    hostId: _hostId,
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
          onExpandedChanged: (value) =>
              ref.read(expansion.notifier).set(chatId, expanded: value),
          now: DateTime.now,
          // The runtime names the place, so the dock costs no extra reads.
          placeOf: agentChatTaskPlaceLabel,
          stopping: _stopping,
          actions: ChatTaskDockActions(
            onView: (task) =>
                unawaited(openChatTaskDetail(context, _hostId, task.id)),
            onStop: (task) => unawaited(_stop(task)),
            canOpenChat: _canOpen,
            onOpenChat: _openChat,
          ),
        ),
      ],
    );
  }
}

/// The child's open requests, answered in the parent chat.
class const _ChildRequests({
  required final String hostId,
  required final AgentChatTask task,
  final VoidCallback? onAnswerInChat,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests =
        ref.watch(mobileChatTaskRequestsProvider(hostId, task.id)).value ??
        const <AgentChatTaskRequest>[];
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: <Widget>[
        for (final request in requests)
          ChatTaskRequestCard(
            request: request,
            enabled: true,
            onAnswerInChat: onAnswerInChat,
            onDecision: (request, decision) => unawaited(() async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                final actions = await ref.read(
                  mobileChatTaskActionsProvider(hostId).future,
                );
                await actions.approve(request, decision);
                ref.invalidate(mobileChatTaskRequestsProvider(hostId, task.id));
              } on Object catch (error) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(agentChatOrchestrationErrorMessage(error)),
                  ),
                );
              }
            }()),
          ),
      ],
    );
  }
}
