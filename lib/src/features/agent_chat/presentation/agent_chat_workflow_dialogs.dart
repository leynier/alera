import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_workflows.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_workflow_phases.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows the script the workflow [callId] started runs.
void showAgentChatWorkflowScript(
  BuildContext context, {
  required String chatId,
  required String workspaceId,
  required String callId,
}) => unawaited(
  showDialog<void>(
    context: context,
    builder: (_) => AgentChatWorkflowScriptDialog(
      chatId: chatId,
      workspaceId: workspaceId,
      callId: callId,
    ),
  ),
);

/// Shows one member of the workflow [callId] started: what it was asked and
/// what it answered. With [readable], the answer comes from its transcript.
void showAgentChatWorkflowMember(
  BuildContext context, {
  required String chatId,
  required String workspaceId,
  required String callId,
  required AgentChatWorkflowMember member,
  required bool readable,
}) => unawaited(
  showDialog<void>(
    context: context,
    builder: (_) => AgentChatWorkflowMemberDialog(
      chatId: chatId,
      workspaceId: workspaceId,
      callId: callId,
      member: member,
      readable: readable,
    ),
  ),
);

class const AgentChatWorkflowScriptDialog({
  super.key,
  required final String chatId,
  required final String workspaceId,
  required final String callId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final script = ref.watch(
      agentChatWorkflowScriptProvider(chatId, workspaceId, callId),
    );
    final value = script.value;
    return AleraDialog(
      maxWidth: AleraTokens.dialogTerminalWidth,
      maxHeight: AleraTokens.dialogMaxHeight,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AleraDialogHeader(
              title: 'Workflow Script',
              onClose: () => Navigator.of(context).pop(),
            ),
            if (value != null) ...<Widget>[
              const SizedBox(height: AleraTokens.space4),
              SelectableText(
                value.scriptPath,
                style: AleraTokens.monoStyle.copyWith(
                  color: AleraTokens.foregroundFaint,
                ),
              ),
            ],
            const SizedBox(height: AleraTokens.space12),
            Flexible(
              child: switch (script) {
                AsyncValue(:final error?) => AleraInlineNotice(
                  tone: AleraInlineNoticeTone.error,
                  message: agentChatErrorMessage(error),
                ),
                AsyncValue(value: final script?) => SingleChildScrollView(
                  key: const ValueKey<String>('agent-chat-workflow-script'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (script.truncated)
                        const Padding(
                          padding: EdgeInsets.only(bottom: AleraTokens.space8),
                          child: AleraInlineNotice(
                            message:
                                'Only the first 256 KiB of the script shows.',
                          ),
                        ),
                      SelectableText(
                        script.contents,
                        style: AleraTokens.monoStyle.copyWith(
                          color: AleraTokens.foreground,
                        ),
                      ),
                    ],
                  ),
                ),
                _ => const AleraEmptyState(
                  message: 'Loading the script…',
                  loading: true,
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class const AgentChatWorkflowMemberDialog({
  super.key,
  required final String chatId,
  required final String workspaceId,
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
              chatId,
              workspaceId,
              callId,
              agent.index,
            ),
          )
        : null;
    final heading = theme.textTheme.labelMedium?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    return AleraDialog(
      maxWidth: AleraTokens.dialogWideWidth,
      maxHeight: AleraTokens.dialogMaxHeight,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AleraDialogHeader(
              title: agent.label,
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AleraTokens.space4),
            Text(
              details.join(' · '),
              style: theme.textTheme.labelSmall?.copyWith(
                color: agentChatWorkflowMemberColor(member.status),
              ),
            ),
            const SizedBox(height: AleraTokens.space12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (agent.prompt case final prompt?) ...<Widget>[
                      Text('Prompt', style: heading),
                      const SizedBox(height: AleraTokens.space4),
                      SelectableText(prompt, style: theme.textTheme.bodySmall),
                      const SizedBox(height: AleraTokens.space12),
                    ],
                    Text('Answer', style: heading),
                    const SizedBox(height: AleraTokens.space4),
                    _Answer(member: member, answers: answers),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class const _Answer({
  required final AgentChatWorkflowMember member,
  required final AsyncValue<List<String>>? answers,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final full = answers?.value;
    if (full != null && full.isNotEmpty) {
      return AgentChatMarkdown(
        key: const ValueKey<String>('agent-chat-workflow-answer'),
        data: full.join('\n\n'),
      );
    }
    if (answers?.isLoading ?? false) {
      return const AleraEmptyState(
        message: 'Loading the answer…',
        loading: true,
      );
    }
    final excerpt = member.agent.result;
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    if (excerpt != null) {
      // The progress snapshot only carries the start of the answer.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Partial answer from workflow progress', style: muted),
          const SizedBox(height: AleraTokens.space4),
          SelectableText(excerpt, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
    }
    return Text(
      member.status.active
          ? 'The agent has not answered yet.'
          : 'No answer from this workflow attempt.',
      style: muted,
    );
  }
}
