import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// An open request of a task's child chat. Approvals are answered here with
/// the decisions the provider offers, in its order; questions and forms open
/// the child chat, where their full form lives. Presentational, shared by
/// the task detail and the parent chat's Answer Here.
class const ChatTaskRequestCard({
  super.key,
  required final AgentChatTaskRequest request,
  required final bool enabled,
  final void Function(
    AgentChatTaskRequest request,
    AgentChatApprovalDecision decision,
  )?
  onDecision,
  final VoidCallback? onAnswerInChat,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final value = request.request;
    final decide = onDecision;
    final lines = <String>[
      agentChatRequestTitle(value),
      ?value.detail,
      ?value.command,
    ];
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
                    onPressed: enabled ? onAnswerInChat : null,
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
