import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// The open requests of a task's child chat. Approvals are answered here
/// with the decisions the provider offers, in its order and with the labels
/// the chat's own request dock uses; questions and forms open the chat, where
/// their full form lives.
class const ChatTaskRequestsView({
  super.key,
  required final List<AgentChatTaskRequest> requests,
  required final bool enabled,
  final void Function(
    AgentChatTaskRequest request,
    AgentChatApprovalDecision decision,
  )?
  onDecision,
  final VoidCallback? onAnswerInChat,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: <Widget>[
      for (final request in requests) ...<Widget>[
        _RequestCard(
          request: request,
          enabled: enabled,
          onDecision: onDecision,
          onAnswerInChat: onAnswerInChat,
        ),
        const SizedBox(height: AleraTokens.space8),
      ],
    ],
  );
}

class const _RequestCard({
  required final AgentChatTaskRequest request,
  required final bool enabled,
  required final void Function(
    AgentChatTaskRequest request,
    AgentChatApprovalDecision decision,
  )?
  onDecision,
  required final VoidCallback? onAnswerInChat,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = request.request;
    final detail = <String>[?value.title, ?value.detail];
    final decide = onDecision;
    return AleraPanel(
      key: ValueKey<String>('chatTaskRequest:${value.id}'),
      borderRadius: AleraTokens.radiusMd,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AleraTokens.space12),
          child: Column(
            crossAxisAlignment: .start,
            children: <Widget>[
              Text(
                agentChatRequestTitle(value),
                style: theme.textTheme.titleSmall,
              ),
              for (final line in detail) ...<Widget>[
                const SizedBox(height: AleraTokens.space4),
                Text(line, style: theme.textTheme.bodySmall),
              ],
              if (value.command ?? value.path case final code?) ...<Widget>[
                const SizedBox(height: AleraTokens.space8),
                SelectableText(code, style: AleraTokens.monoCompactStyle),
              ],
              for (final question in value.questions) ...<Widget>[
                const SizedBox(height: AleraTokens.space4),
                Text(question.question, style: theme.textTheme.bodySmall),
              ],
              const SizedBox(height: AleraTokens.space12),
              Wrap(
                spacing: AleraTokens.space8,
                runSpacing: AleraTokens.space8,
                children: <Widget>[
                  if (value.isApproval && decide != null)
                    for (final decision in value.offeredDecisions)
                      decision.accepts
                          ? FilledButton(
                              key: ValueKey<String>(
                                'chatTaskDecision:${value.id}:${decision.wire}',
                              ),
                              onPressed: enabled
                                  ? () => decide(request, decision)
                                  : null,
                              child: Text(agentChatDecisionLabel(decision)),
                            )
                          : OutlinedButton(
                              key: ValueKey<String>(
                                'chatTaskDecision:${value.id}:${decision.wire}',
                              ),
                              onPressed: enabled
                                  ? () => decide(request, decision)
                                  : null,
                              child: Text(agentChatDecisionLabel(decision)),
                            )
                  else
                    OutlinedButton(
                      onPressed: enabled ? onAnswerInChat : null,
                      child: const Text('Answer In Chat'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
