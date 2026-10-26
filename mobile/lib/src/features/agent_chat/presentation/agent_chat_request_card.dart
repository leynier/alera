import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_decline_feedback_dialog.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_elicitation_form.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera_mobile/src/features/updater/infra/mobile_external_browser.dart';
import 'package:flutter/material.dart';

typedef AgentChatRespond = Future<void> Function(
  AgentChatRequest request,
  AgentChatResponse response,
);

/// An approval or MCP form the agent is blocked on, shown in the request
/// dock above the composer. Only the decisions the runtime lists are offered,
/// because a provider may not honor the others.
class const AgentChatRequestCard({
  super.key,
  required final AgentChatRequest request,
  required final bool enabled,
  required final AgentChatRespond onRespond,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = request.detail?.trim() ?? '';
    final elicitation = request.elicitation;
    return Container(
      padding: const EdgeInsets.all(AleraTokens.space12),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.warning),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: AleraTokens.space8,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                AleraIcons.notifications,
                size: AleraTokens.space16,
                color: AleraTokens.warning,
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  agentChatRequestTitle(request),
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          if (request.command case final String command)
            _Mono(text: '\$ $command'),
          if (request.cwd case final String cwd)
            Text(cwd, style: AleraTokens.monoStyle),
          if (request.path case final String path)
            Text(
              path,
              style: AleraTokens.monoStyle.copyWith(
                color: AleraTokens.foreground,
              ),
            ),
          if (request.fullAccessOverride case final override?)
            Text(
              agentChatFullAccessOverrideMessage(override),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.warning,
              ),
            ),
          if (detail.isNotEmpty) AgentChatMarkdown(text: detail),
          if (request.isApproval)
            _ApprovalActions(
              request: request,
              enabled: enabled,
              onRespond: onRespond,
            )
          else if (elicitation != null)
            _ElicitationActions(
              request: request,
              elicitation: elicitation,
              enabled: enabled,
              onRespond: onRespond,
            )
          else
            Text(
              'The agent is waiting for an answer this app cannot give. '
              'Stop the turn to continue.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
        ],
      ),
    );
  }
}

class const _ApprovalActions({
  required final AgentChatRequest request,
  required final bool enabled,
  required final AgentChatRespond onRespond,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Exactly the runtime's decisions in its order: the first two as
    // buttons, the rest one tap further, so no choice is ever invented.
    final decisions = request.offeredDecisions;
    final primary = decisions.take(2).toList(growable: false);
    final more = decisions.skip(2).toList(growable: false);
    return Wrap(
      spacing: AleraTokens.space8,
      runSpacing: AleraTokens.space4,
      crossAxisAlignment: .center,
      children: <Widget>[
        for (final (index, decision) in primary.indexed)
          if (index == 0 && decision.accepts)
            FilledButton(
              onPressed: enabled ? () => _answer(decision) : null,
              child: Text(agentChatDecisionLabel(decision)),
            )
          else
            OutlinedButton(
              onPressed: enabled ? () => _answer(decision) : null,
              child: Text(agentChatDecisionLabel(decision)),
            ),
        if (more.isNotEmpty)
          PopupMenuButton<AgentChatApprovalDecision>(
            tooltip: 'More Decisions',
            enabled: enabled,
            icon: const Icon(AleraIcons.more),
            onSelected: _answer,
            itemBuilder: (context) =>
                <PopupMenuEntry<AgentChatApprovalDecision>>[
                  for (final decision in more)
                    PopupMenuItem<AgentChatApprovalDecision>(
                      value: decision,
                      height: AleraTokens.minTapTarget,
                      child: Text(agentChatDecisionLabel(decision)),
                    ),
                ],
          ),
        if (agentChatOffersDeclineFeedback(request))
          TextButton(
            key: const ValueKey<String>('agent-chat-decline-feedback'),
            onPressed: enabled ? () => _declineWithFeedback(context) : null,
            child: const Text('$agentChatDeclineWithFeedbackLabel…'),
          ),
      ],
    );
  }

  void _answer(AgentChatApprovalDecision decision) =>
      unawaited(onRespond(request, AgentChatApprovalResponse(decision)));

  Future<void> _declineWithFeedback(BuildContext context) async {
    final feedback = await showAgentChatDeclineFeedbackDialog(context);
    if (feedback == null) return;
    await onRespond(
      request,
      AgentChatApprovalResponse(.decline, feedback: feedback),
    );
  }
}

class const _ElicitationActions({
  required final AgentChatRequest request,
  required final AgentChatElicitation elicitation,
  required final bool enabled,
  required final AgentChatRespond onRespond,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final url = Uri.tryParse(elicitation.url ?? '');
    return Column(
      crossAxisAlignment: .stretch,
      spacing: AleraTokens.space8,
      children: <Widget>[
        if (elicitation.message.trim().isNotEmpty)
          AgentChatMarkdown(text: elicitation.message),
        if (elicitation.hasSupportedForm)
          AgentChatElicitationForm(
            elicitation: elicitation,
            enabled: enabled,
            onSubmit: (content) => _answer(.accept, content),
          ),
        Wrap(
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space4,
          children: <Widget>[
            if (url != null && url.hasScheme)
              FilledButton.icon(
                onPressed: enabled
                    ? () {
                        unawaited(openMobileExternalBrowser(url));
                        _answer(.accept);
                      }
                    : null,
                icon: const Icon(
                  AleraIcons.external,
                  size: AleraTokens.space16,
                ),
                label: const Text('Open Link'),
              )
            else if (!elicitation.hasSupportedForm)
              FilledButton(
                onPressed: enabled ? () => _answer(.accept) : null,
                child: const Text('Accept'),
              ),
            TextButton(
              onPressed: enabled ? () => _answer(.decline) : null,
              child: const Text('Decline'),
            ),
            TextButton(
              onPressed: enabled ? () => _answer(.cancel) : null,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }

  void _answer(
    AgentChatElicitationAction action, [
    Map<String, Object?>? content,
  ]) => unawaited(
    onRespond(request, AgentChatElicitationResponse(action, content)),
  );
}

class const _Mono({required final String text}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AleraTokens.bg,
      border: Border.all(color: AleraTokens.borderSubtle),
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
    ),
    child: SingleChildScrollView(
      scrollDirection: .horizontal,
      padding: const EdgeInsets.all(AleraTokens.space8),
      child: SelectableText(
        text,
        style: AleraTokens.monoStyle.copyWith(color: AleraTokens.foreground),
      ),
    ),
  );
}
