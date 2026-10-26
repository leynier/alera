import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_workflows.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_subagent_actions.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_workflow_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The script the workflow [callId] started runs, as a sheet.
Future<void> showAgentChatWorkflowScriptSheet(
  BuildContext context, {
  required AgentChatSubagentChat chat,
  required String callId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => AgentChatWorkflowScriptSheet(chat: chat, callId: callId),
);

/// One member of the workflow [callId] started: what it was asked and what
/// it answered. With [readable], the answer comes from its transcript.
Future<void> showAgentChatWorkflowMemberSheet(
  BuildContext context, {
  required AgentChatSubagentChat chat,
  required String callId,
  required AgentChatWorkflowMember member,
  required bool readable,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => AgentChatWorkflowMemberSheet(
    chat: chat,
    callId: callId,
    member: member,
    readable: readable,
  ),
);

class const AgentChatWorkflowScriptSheet({
  super.key,
  required final AgentChatSubagentChat chat,
  required final String callId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final script = ref.watch(
      agentChatWorkflowScriptProvider(
        chat.hostId,
        chat.workspaceId,
        chat.chatId,
        callId,
      ),
    );
    return _Sheet(
      title: 'Workflow Script',
      child: switch (script) {
        AsyncValue(:final error?) => AleraEmptyState(
          icon: AleraIcons.loadFailed,
          title: 'Could not read the script',
          message: agentChatErrorMessage(error),
        ),
        AsyncValue(value: final script?) => Column(
          key: const ValueKey<String>('agent-chat-workflow-script'),
          crossAxisAlignment: .stretch,
          children: <Widget>[
            SelectableText(
              script.scriptPath,
              style: AleraTokens.monoStyle.copyWith(
                color: AleraTokens.foregroundFaint,
              ),
            ),
            if (script.truncated)
              Padding(
                padding: const EdgeInsets.only(top: AleraTokens.space8),
                child: Text(
                  'Only the first 256 KiB of the script shows.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ),
            const SizedBox(height: AleraTokens.space12),
            SelectableText(script.contents, style: AleraTokens.monoStyle),
          ],
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class const AgentChatWorkflowMemberSheet({
  super.key,
  required final AgentChatSubagentChat chat,
  required final String callId,
  required final AgentChatWorkflowMember member,
  required final bool readable,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final agent = member.agent;
    final details = <String>[
      member.statusLabel(DateTime.now().toUtc()),
      ?agent.model,
      if ((agent.attempt ?? 1) > 1) 'Attempt ${agent.attempt}',
      ?agentChatWorkflowUsageLabel(
        totalTokens: agent.totalTokens,
        toolCalls: agent.toolCalls,
        durationMs: agent.durationMs,
      ),
    ];
    final answers = readable && agent.agentId != null
        ? ref.watch(
            agentChatWorkflowAnswersProvider(
              chat.hostId,
              chat.workspaceId,
              chat.chatId,
              callId,
              agent.index,
            ),
          )
        : null;
    final heading = theme.textTheme.labelMedium?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final full = answers?.value;
    final excerpt = agent.result;
    return _Sheet(
      title: agent.label,
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Text(
            details.join(' · '),
            style: theme.textTheme.labelSmall?.copyWith(
              color: agentChatWorkflowMemberColor(member.status),
            ),
          ),
          if (agent.prompt case final prompt?) ...<Widget>[
            const SizedBox(height: AleraTokens.space12),
            Text('Prompt', style: heading),
            const SizedBox(height: AleraTokens.space4),
            SelectableText(prompt, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: AleraTokens.space12),
          Text('Answer', style: heading),
          const SizedBox(height: AleraTokens.space4),
          if (full != null && full.isNotEmpty)
            AgentChatMarkdown(
              key: const ValueKey<String>('agent-chat-workflow-answer'),
              text: full.join('\n\n'),
            )
          else if (answers?.isLoading ?? false)
            const Center(child: CircularProgressIndicator())
          else if (excerpt != null) ...<Widget>[
            // The progress snapshot only carries the start of the answer.
            Text('Partial answer from workflow progress', style: muted),
            const SizedBox(height: AleraTokens.space4),
            SelectableText(excerpt, style: theme.textTheme.bodySmall),
          ] else
            Text(
              member.status.active
                  ? 'The agent has not answered yet.'
                  : 'No answer from this workflow attempt.',
              style: muted,
            ),
        ],
      ),
    );
  }
}

class const _Sheet({required final String title, required final Widget child})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.7,
    maxChildSize: 0.95,
    builder: (context, controller) => ListView(
      controller: controller,
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AleraTokens.space8),
        child,
      ],
    ),
  );
}
