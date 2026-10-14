import 'dart:async';

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_actions.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_detail_view.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_follow_up_dialog.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_open_actions.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_read_state.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The selected task in Activity, wired to the runtime. Opening it
/// acknowledges a settled result only when a person owns the task; a parent
/// chat still has to read its children's results.
class const ChatTaskDetailPage({super.key, required final String taskId})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<ChatTaskDetailPage> createState() => _ChatTaskDetailPageState();
}

class _ChatTaskDetailPageState extends ConsumerState<ChatTaskDetailPage> {
  bool _busy = false;
  bool _waiting = false;
  bool _acknowledging = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      chatTaskDetailProvider(widget.taskId),
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
      await ref.read(chatTaskActionsProvider).acknowledge(task);
    } on Object {
      // The next change or visit tries again.
      _acknowledging = false;
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        AleraToast.show(
          context,
          message: agentChatOrchestrationErrorMessage(error),
          tone: AleraToastTone.error,
        );
      }
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
    await _run(() => ref.read(chatTaskActionsProvider).cancel(task.id));
  }

  Future<void> _wait(AgentChatTask task) async {
    setState(() => _waiting = true);
    try {
      final result = await ref.read(chatTaskActionsProvider).waitFor(task.id);
      if (mounted && result.timedOut) {
        AleraToast.show(
          context,
          message:
              'Still running after ${AgentChatOrchestrationWire.maxWaitSeconds} seconds. It keeps running; wait again or come back later.',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        AleraToast.show(
          context,
          message: agentChatOrchestrationErrorMessage(error),
          tone: AleraToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _waiting = false);
    }
  }

  Future<void> _followUp(String chatId) async {
    final message = await showChatTaskFollowUpDialog(context);
    if (message == null || !mounted) return;
    await _run(() async {
      final sent = await ref
          .read(chatTaskActionsProvider)
          .followUp(chatId, message);
      final taskId = sent.taskId;
      if (taskId != null && mounted) {
        ref.read(activityNavigationProvider.notifier).selectChatTask(taskId);
      }
    });
  }

  Future<void> _openParentChat(String chatId) async {
    try {
      final chat = await ref.read(chatTaskChatProvider(chatId).future);
      if (!mounted) return;
      await openChatTaskChat(
        context,
        ref,
        chatId: chatId,
        workspaceId: chat.workspaceId,
      );
    } on Object catch (error) {
      if (mounted) {
        AleraToast.show(
          context,
          message: agentChatOrchestrationErrorMessage(error),
          tone: AleraToastTone.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final read = ref.watch(chatTaskDetailProvider(widget.taskId));
    final task = read.value;
    if (task == null) {
      return ChatTaskReadState(
        error: read.error,
        onRefresh: () => ref.invalidate(chatTaskDetailProvider(widget.taskId)),
      );
    }
    final requests =
        ref.watch(chatTaskRequestsProvider(widget.taskId)).value ??
        const <AgentChatTaskRequest>[];
    final workbench = ref.watch(workbenchControllerProvider);
    final workspaceId = task.workspaceId;
    final childChatId = task.childChatId;
    final parentChatId = task.parentChatId;
    final project = workbench.projects
        .where((item) => item.id == task.projectId)
        .firstOrNull;
    final workspace = workspaceId == null
        ? null
        : workbench.workspacesByProject.values
              .expand((items) => items)
              .where((item) => item.id == workspaceId)
              .firstOrNull;
    final knownWorkspace = chatTaskWorkspaceKnown(ref, workspaceId);
    return ChatTaskDetailView(
      task: task,
      now: ref.watch(agentChatClockProvider)(),
      place: agentChatTaskPlaceLabel(
        task,
        projectName: project?.name,
        workspaceName: workspace?.name,
      ),
      requests: requests,
      busy: _busy,
      waiting: _waiting,
      actions: ChatTaskDetailActions(
        onOpenChat: childChatId != null && workspaceId != null && knownWorkspace
            ? () => unawaited(
                openChatTaskChat(
                  context,
                  ref,
                  chatId: childChatId,
                  workspaceId: workspaceId,
                ),
              )
            : null,
        onOpenWorkspace: knownWorkspace
            ? () => unawaited(openChatTaskWorkspace(context, ref, workspaceId!))
            : null,
        onOpenParentChat: parentChatId == null
            ? null
            : () => unawaited(_openParentChat(parentChatId)),
        onWait: () => unawaited(_wait(task)),
        onFollowUp: childChatId == null
            ? null
            : () => unawaited(_followUp(childChatId)),
        onCancel: () => unawaited(_cancel(task)),
        onSelectTask: ref
            .read(activityNavigationProvider.notifier)
            .selectChatTask,
        onDecision: (request, decision) => unawaited(
          _run(() async {
            await ref.read(chatTaskActionsProvider).approve(request, decision);
            ref.invalidate(chatTaskRequestsProvider(widget.taskId));
          }),
        ),
      ),
    );
  }
}
