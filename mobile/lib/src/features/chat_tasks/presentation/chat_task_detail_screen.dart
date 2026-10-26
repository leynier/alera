import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera_mobile/src/features/chat_tasks/application/mobile_chat_task_providers.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_detail_body.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_follow_up_sheet.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_open.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pushes one task. Nothing else changes until the person taps an action.
Future<void> openChatTaskDetail(
  BuildContext context,
  String hostId,
  String taskId,
) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => ChatTaskDetailScreen(hostId: hostId, taskId: taskId),
  ),
);

/// A task on the phone, wired to the paired runtime. Opening it acknowledges
/// a settled result only when a person owns the task; a parent chat still
/// has to read its children's results.
class const ChatTaskDetailScreen({
  super.key,
  required final String hostId,
  required final String taskId,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<ChatTaskDetailScreen> createState() =>
      _ChatTaskDetailScreenState();
}

class _ChatTaskDetailScreenState extends ConsumerState<ChatTaskDetailScreen> {
  bool _busy = false;
  bool _waiting = false;
  bool _acknowledging = false;

  String get _hostId => widget.hostId;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      mobileChatTaskDetailProvider(_hostId, widget.taskId),
      (_, next) => _acknowledge(next.value),
      fireImmediately: true,
    );
  }

  void _acknowledge(AgentChatTask? task) {
    if (task == null ||
        _acknowledging ||
        !AgentChatTaskActions.acknowledges(task)) {
      return;
    }
    _acknowledging = true;
    unawaited(_acknowledgeNow(task));
  }

  Future<void> _acknowledgeNow(AgentChatTask task) async {
    try {
      final actions = await ref.read(
        mobileChatTaskActionsProvider(_hostId).future,
      );
      await actions.acknowledge(task);
    } on Object {
      // The next change or visit tries again.
      _acknowledging = false;
    }
  }

  Future<void> _run(
    Future<void> Function(AgentChatTaskActions actions) action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action(
        await ref.read(mobileChatTaskActionsProvider(_hostId).future),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(agentChatOrchestrationErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(AgentChatTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const AleraConfirmDialog(
        title: 'Cancel Task?',
        message: 'The agent stops, its queued input is dropped and every task it started is cancelled too. Workspaces it created stay.',
        confirmLabel: 'Cancel Task',
        cancelLabel: 'Keep Task',
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run((actions) => actions.cancel(task.id));
  }

  Future<void> _wait(AgentChatTask task) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _waiting = true);
    try {
      final actions = await ref.read(
        mobileChatTaskActionsProvider(_hostId).future,
      );
      final result = await actions.waitFor(task.id);
      if (result.timedOut) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Still running after ${AgentChatOrchestrationWire.maxWaitSeconds} seconds. It keeps running; wait again or come back later.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(agentChatOrchestrationErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _waiting = false);
    }
  }

  Future<void> _followUp(String chatId) async {
    final message = await showChatTaskFollowUpSheet(context);
    if (message == null || !mounted) return;
    final navigator = Navigator.of(context);
    await _run((actions) async {
      final sent = await actions.followUp(chatId, message);
      final taskId = sent.taskId;
      if (taskId != null && mounted) {
        unawaited(
          navigator.pushReplacement<void, void>(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ChatTaskDetailScreen(hostId: _hostId, taskId: taskId),
            ),
          ),
        );
      }
    });
  }

  Future<void> _openParentChat(String chatId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final chat = await ref.read(
        mobileChatTaskChatProvider(_hostId, chatId).future,
      );
      if (!mounted) return;
      await openMobileChatTaskChat(
        context,
        ref,
        hostId: _hostId,
        chatId: chatId,
        workspaceId: chat.workspaceId,
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(agentChatOrchestrationErrorMessage(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final read = ref.watch(
      mobileChatTaskDetailProvider(_hostId, widget.taskId),
    );
    final task = read.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Chat Task')),
      body: SafeArea(
        child: task == null
            ? read.hasError
                  ? AleraEmptyState(
                      title: read.error is AgentChatOrchestrationUpdateRequired
                          ? 'Update Required'
                          : 'Task Unavailable',
                      message: agentChatOrchestrationErrorMessage(read.error!),
                      action: OutlinedButton(
                        onPressed: () => ref.invalidate(
                          mobileChatTaskDetailProvider(_hostId, widget.taskId),
                        ),
                        child: const Text('Retry'),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator())
            : _body(task),
      ),
    );
  }

  Widget _body(AgentChatTask task) {
    final places = ref.watch(mobileChatTaskPlacesProvider(_hostId)).value;
    final childChatId = task.childChatId;
    final workspaceId = task.workspaceId;
    final parentChatId = task.parentChatId;
    return ChatTaskDetailBody(
      task: task,
      now: DateTime.now(),
      place: agentChatTaskPlaceLabel(
        task,
        projectName: places?.projectName(task.projectId),
        workspaceName: places?.workspace(workspaceId)?.name,
      ),
      requests:
          ref
              .watch(mobileChatTaskRequestsProvider(_hostId, widget.taskId))
              .value ??
          const <AgentChatTaskRequest>[],
      busy: _busy,
      waiting: _waiting,
      callbacks: ChatTaskDetailCallbacks(
        onOpenChat: childChatId == null || workspaceId == null
            ? null
            : () => unawaited(
                openMobileChatTaskChat(
                  context,
                  ref,
                  hostId: _hostId,
                  chatId: childChatId,
                  workspaceId: workspaceId,
                ),
              ),
        onOpenWorkspace: workspaceId == null
            ? null
            : () => unawaited(
                openMobileChatTaskWorkspace(
                  context,
                  ref,
                  hostId: _hostId,
                  workspaceId: workspaceId,
                ),
              ),
        onOpenParentChat: parentChatId == null
            ? null
            : () => unawaited(_openParentChat(parentChatId)),
        onWait: () => unawaited(_wait(task)),
        onFollowUp: childChatId == null
            ? null
            : () => unawaited(_followUp(childChatId)),
        onCancel: () => unawaited(_cancel(task)),
        onDecision: (request, decision) => unawaited(
          _run((actions) async {
            await actions.approve(request, decision);
            ref.invalidate(
              mobileChatTaskRequestsProvider(_hostId, widget.taskId),
            );
          }),
        ),
      ),
    );
  }
}
