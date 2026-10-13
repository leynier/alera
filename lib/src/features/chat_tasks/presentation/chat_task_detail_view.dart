import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_key_value_row.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_controls.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_requests_view.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_status.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// What a person can do with the selected task. A null callback hides or
/// disables its action; every action runs only on a press.
class const ChatTaskDetailActions({
  final VoidCallback? onOpenChat,
  final VoidCallback? onOpenWorkspace,
  final VoidCallback? onOpenParentChat,
  final VoidCallback? onWait,
  final VoidCallback? onFollowUp,
  final VoidCallback? onCancel,
  final ValueChanged<String>? onSelectTask,
  final void Function(
    AgentChatTaskRequest request,
    AgentChatApprovalDecision decision,
  )?
  onDecision,
});

/// One task: where it runs, its lineage, what it was asked, what it returned
/// and what it waits for. Presentational, so it previews without a runtime.
class const ChatTaskDetailView({
  super.key,
  required final AgentChatTask task,
  required final DateTime now,
  required final String place,
  required final ChatTaskDetailActions actions,
  final List<AgentChatTaskRequest> requests = const <AgentChatTaskRequest>[],
  final bool busy = false,
  final bool waiting = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attention = agentChatTaskAttentionLabel(task);
    final result = task.result;
    final failure = task.failure;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: .start,
            children: <Widget>[
              Expanded(
                child: SelectableText(
                  task.displayTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              ChatTaskStatusBadge(status: task.status),
            ],
          ),
          const SizedBox(height: AleraTokens.space4),
          Text(
            <String>[
              agentChatTaskKindLabel(task.kind),
              ?task.role,
              agentChatTaskAgeLabel(task.updatedAt, now),
            ].join(' · '),
            style: theme.textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          if (attention != null) ...<Widget>[
            const SizedBox(height: AleraTokens.space12),
            AleraInlineNotice(message: attention, tone: .warning),
          ],
          const SizedBox(height: AleraTokens.space12),
          _ActionRow(
            task: task,
            actions: actions,
            busy: busy,
            waiting: waiting,
          ),
          const SizedBox(height: AleraTokens.space16),
          const AleraSectionHeader(label: 'Details'),
          ..._facts(task, place, now, actions),
          if (task.brief case final brief?) ...<Widget>[
            const SizedBox(height: AleraTokens.space16),
            const AleraSectionHeader(label: 'Task'),
            SelectableText(brief, style: theme.textTheme.bodyMedium),
          ],
          if (requests.isNotEmpty) ...<Widget>[
            const SizedBox(height: AleraTokens.space16),
            const AleraSectionHeader(label: 'Waiting For Input'),
            ChatTaskRequestsView(
              requests: requests,
              enabled: !busy,
              onDecision: actions.onDecision,
              onAnswerInChat: actions.onOpenChat,
            ),
          ],
          if (failure != null) ...<Widget>[
            const SizedBox(height: AleraTokens.space16),
            AleraInlineNotice(
              message: failure.message.trim().isEmpty
                  ? 'The task failed without a message.'
                  : failure.message,
              tone: .error,
            ),
          ],
          if (result != null) ...<Widget>[
            const SizedBox(height: AleraTokens.space16),
            const AleraSectionHeader(label: 'Result'),
            SelectableText(
              result.text.trim().isEmpty
                  ? 'The agent finished without a final message.'
                  : result.text,
              key: const ValueKey<String>('chatTaskResult'),
              style: theme.textTheme.bodyMedium,
            ),
            if (result.truncated) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              Text(
                'The result was shortened. Open the chat for the full answer.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  static List<Widget> _facts(
    AgentChatTask task,
    String place,
    DateTime now,
    ChatTaskDetailActions actions,
  ) {
    final agent = chatTaskAgentLabel(task);
    final parentTask = task.parentTaskId;
    final completedAt = task.completedAt;
    return <Widget>[
      AleraKeyValueRow(
        label: 'Target',
        value: agentChatTaskTargetLabel(task.target),
      ),
      AleraKeyValueRow(label: 'Where', value: place),
      AleraKeyValueRow(
        label: 'Agent',
        value: agent.isEmpty ? 'The target chat keeps its agent' : agent,
      ),
      if (task.runtimeMode case final mode?)
        AleraKeyValueRow(
          label: 'Runtime Mode',
          value: agentChatRuntimeModeLabel(mode),
        ),
      if (task.parentChatId != null)
        AleraKeyValueRow(
          label: 'Parent Chat',
          value: task.labels.parentChatTitle ?? task.parentChatId!,
          trailing: actions.onOpenParentChat == null
              ? null
              : TextButton(
                  onPressed: actions.onOpenParentChat,
                  child: const Text('Open'),
                ),
        ),
      if (parentTask != null)
        AleraKeyValueRow(
          label: 'Parent Task',
          value: parentTask,
          monospace: true,
          trailing: actions.onSelectTask == null
              ? null
              : TextButton(
                  onPressed: () => actions.onSelectTask!(parentTask),
                  child: const Text('Show'),
                ),
        ),
      AleraKeyValueRow(
        label: 'Started By',
        value: agentChatTaskActorLabel(task.actor),
      ),
      AleraKeyValueRow(
        label: 'Created',
        value: agentChatTaskAgeLabel(task.createdAt, now),
      ),
      if (completedAt != null)
        AleraKeyValueRow(
          label: 'Finished',
          value: agentChatTaskAgeLabel(completedAt, now),
        ),
      if (task.status.settled && !task.ownedByPerson)
        AleraKeyValueRow(
          label: 'Result Delivery',
          value: agentChatTaskDeliveryLabel(task.delivery),
        ),
      AleraKeyValueRow(label: 'Task ID', value: task.id, monospace: true),
    ];
  }
}

class const _ActionRow({
  required final AgentChatTask task,
  required final ChatTaskDetailActions actions,
  required final bool busy,
  required final bool waiting,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const iconSize = AleraTokens.iconMd;
    return Wrap(
      spacing: AleraTokens.space8,
      runSpacing: AleraTokens.space8,
      children: <Widget>[
        FilledButton.icon(
          key: const ValueKey<String>('chatTaskOpenChat'),
          onPressed: actions.onOpenChat,
          icon: const Icon(AleraIcons.agent, size: iconSize),
          label: const Text('Open Chat'),
        ),
        OutlinedButton.icon(
          key: const ValueKey<String>('chatTaskOpenWorkspace'),
          onPressed: actions.onOpenWorkspace,
          icon: const Icon(AleraIcons.workspaceMain, size: iconSize),
          label: const Text('Open Workspace'),
        ),
        if (!task.status.settled)
          OutlinedButton.icon(
            key: const ValueKey<String>('chatTaskWait'),
            onPressed: busy || waiting ? null : actions.onWait,
            icon: waiting
                ? const SizedBox.square(
                    dimension: iconSize,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AleraIcons.time, size: iconSize),
            label: Text(waiting ? 'Waiting…' : 'Wait For Result'),
          ),
        if (task.status.settled && actions.onFollowUp != null)
          OutlinedButton.icon(
            key: const ValueKey<String>('chatTaskFollowUp'),
            onPressed: busy ? null : actions.onFollowUp,
            icon: const Icon(AleraIcons.send, size: iconSize),
            label: const Text('Send Follow-Up'),
          ),
        if (task.status.cancellable)
          TextButton.icon(
            key: const ValueKey<String>('chatTaskCancel'),
            onPressed: busy ? null : actions.onCancel,
            style: TextButton.styleFrom(foregroundColor: AleraTokens.error),
            icon: const Icon(AleraIcons.stop, size: iconSize),
            label: const Text('Cancel Task'),
          ),
      ],
    );
  }
}
