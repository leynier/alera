import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_key_value_row.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_mode_labels.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_request_card.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_tiles.dart';
import 'package:flutter/material.dart';

/// What a person can do with a task. A null callback hides its action.
class const ChatTaskDetailCallbacks({
  final VoidCallback? onOpenChat,
  final VoidCallback? onOpenWorkspace,
  final VoidCallback? onOpenParentChat,
  final VoidCallback? onWait,
  final VoidCallback? onFollowUp,
  final VoidCallback? onCancel,
  final void Function(
    AgentChatTaskRequest request,
    AgentChatApprovalDecision decision,
  )?
  onDecision,
});

/// One task on the phone: the same facts and actions as the desktop detail.
/// Presentational, so it previews without a runtime.
class const ChatTaskDetailBody({
  super.key,
  required final AgentChatTask task,
  required final DateTime now,
  required final String place,
  required final ChatTaskDetailCallbacks callbacks,
  final List<AgentChatTaskRequest> requests = const <AgentChatTaskRequest>[],
  final bool busy = false,
  final bool waiting = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final attention = agentChatTaskAttentionLabel(task);
    final result = task.result;
    final failure = task.failure;
    final agent = chatTaskAgentLabel(task);
    return ListView(
      padding: AleraTokens.contentPadding,
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
            const SizedBox(width: AleraTokens.spaceSm),
            ChatTaskStatusBadge(status: task.status),
          ],
        ),
        const SizedBox(height: AleraTokens.spaceXs),
        Text(
          <String>[
            agentChatTaskKindLabel(task.kind),
            ?task.role,
            agentChatTaskAgeLabel(task.updatedAt, now),
          ].join(' · '),
          style: muted,
        ),
        if (attention != null) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceMd),
          AleraNotice(message: attention, icon: AleraIcons.warning),
        ],
        const SizedBox(height: AleraTokens.spaceMd),
        _Actions(
          task: task,
          callbacks: callbacks,
          busy: busy,
          waiting: waiting,
        ),
        const SizedBox(height: AleraTokens.spaceLg),
        const AleraSectionHeader(label: 'Details'),
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
        if (task.parentChatId case final parent?)
          AleraKeyValueRow(
            label: 'Parent Chat',
            value: task.labels.parentChatTitle ?? parent,
            trailing: callbacks.onOpenParentChat == null
                ? null
                : TextButton(
                    onPressed: callbacks.onOpenParentChat,
                    child: const Text('Open'),
                  ),
          ),
        AleraKeyValueRow(
          label: 'Started By',
          value: agentChatTaskActorLabel(task.actor),
        ),
        if (task.status.settled && !task.ownedByPerson)
          AleraKeyValueRow(
            label: 'Result Delivery',
            value: agentChatTaskDeliveryLabel(task.delivery),
          ),
        AleraKeyValueRow(label: 'Task ID', value: task.id, monospace: true),
        if (task.brief case final brief?) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceLg),
          const AleraSectionHeader(label: 'Task'),
          SelectableText(brief, style: theme.textTheme.bodyMedium),
        ],
        if (requests.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceLg),
          const AleraSectionHeader(label: 'Waiting For Input'),
          for (final request in requests)
            _Request(request: request, enabled: !busy, callbacks: callbacks),
        ],
        if (failure != null) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceLg),
          AleraNotice(
            message: failure.message.trim().isEmpty
                ? 'The task failed without a message.'
                : failure.message,
            icon: AleraIcons.loadFailed,
          ),
        ],
        if (result != null) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceLg),
          const AleraSectionHeader(label: 'Result'),
          SelectableText(
            result.text.trim().isEmpty
                ? 'The agent finished without a final message.'
                : result.text,
            key: const ValueKey<String>('chatTaskResult'),
            style: theme.textTheme.bodyMedium,
          ),
          if (result.truncated) ...<Widget>[
            const SizedBox(height: AleraTokens.spaceSm),
            Text(
              'The result was shortened. Open the chat for the full answer.',
              style: muted,
            ),
          ],
        ],
      ],
    );
  }
}

class const _Actions({
  required final AgentChatTask task,
  required final ChatTaskDetailCallbacks callbacks,
  required final bool busy,
  required final bool waiting,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AleraTokens.spaceSm,
    runSpacing: AleraTokens.spaceSm,
    children: <Widget>[
      FilledButton.icon(
        key: const ValueKey<String>('chatTaskOpenChat'),
        onPressed: callbacks.onOpenChat,
        icon: const Icon(AleraIcons.agent),
        label: const Text('Open Chat'),
      ),
      OutlinedButton.icon(
        key: const ValueKey<String>('chatTaskOpenWorkspace'),
        onPressed: callbacks.onOpenWorkspace,
        icon: const Icon(AleraIcons.workspaceMain),
        label: const Text('Open Workspace'),
      ),
      if (!task.status.settled)
        OutlinedButton.icon(
          key: const ValueKey<String>('chatTaskWait'),
          onPressed: busy || waiting ? null : callbacks.onWait,
          icon: waiting
              ? const SizedBox.square(
                  dimension: AleraTokens.iconSm,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(AleraIcons.time),
          label: Text(waiting ? 'Waiting…' : 'Wait For Result'),
        ),
      if (task.status.settled && callbacks.onFollowUp != null)
        OutlinedButton.icon(
          key: const ValueKey<String>('chatTaskFollowUp'),
          onPressed: busy ? null : callbacks.onFollowUp,
          icon: const Icon(AleraIcons.send),
          label: const Text('Send Follow-Up'),
        ),
      if (task.status.cancellable)
        TextButton.icon(
          key: const ValueKey<String>('chatTaskCancel'),
          onPressed: busy ? null : callbacks.onCancel,
          style: TextButton.styleFrom(foregroundColor: AleraTokens.error),
          icon: const Icon(AleraIcons.stop),
          label: const Text('Cancel Task'),
        ),
    ],
  );
}

class const _Request({
  required final AgentChatTaskRequest request,
  required final bool enabled,
  required final ChatTaskDetailCallbacks callbacks,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final value = request.request;
    final decide = callbacks.onDecision;
    final lines = <String>[?value.title, ?value.detail, ?value.command];
    return Card(
      key: ValueKey<String>('chatTaskRequest:${value.id}'),
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.spaceMd),
        child: Column(
          crossAxisAlignment: .start,
          children: <Widget>[
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: AleraTokens.spaceXs),
                child: SelectableText(line),
              ),
            for (final question in value.questions) Text(question.question),
            const SizedBox(height: AleraTokens.spaceSm),
            Wrap(
              spacing: AleraTokens.spaceSm,
              runSpacing: AleraTokens.spaceSm,
              children: <Widget>[
                if (value.isApproval && decide != null)
                  for (final decision in value.offeredDecisions)
                    _DecisionButton(
                      key: ValueKey<String>(
                        'chatTaskDecision:${value.id}:${decision.wire}',
                      ),
                      decision: decision,
                      onPressed: enabled
                          ? () => decide(request, decision)
                          : null,
                    )
                else
                  OutlinedButton(
                    onPressed: enabled ? callbacks.onOpenChat : null,
                    child: const Text('Answer In Chat'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class const _DecisionButton({
  super.key,
  required final AgentChatApprovalDecision decision,
  required final VoidCallback? onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final label = Text(agentChatDecisionLabel(decision));
    return decision.accepts
        ? FilledButton(onPressed: onPressed, child: label)
        : OutlinedButton(onPressed: onPressed, child: label);
  }
}
