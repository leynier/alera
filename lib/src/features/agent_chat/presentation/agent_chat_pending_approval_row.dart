import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_decline_feedback_dialog.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_request_cards.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The chat's pending approvals as rows at the end of the timeline, where the
/// agent stopped, each with its decisions inline. Questions, forms and
/// secrets stay in the request dock above the composer.
class const AgentChatPendingApprovalRows({
  super.key,
  required final String chatId,
  required final String workspaceId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = agentChatControllerProvider(chatId, workspaceId);
    final view = ref.watch(
      provider.select(
        (state) => (
          requests: state.projection?.requests ?? const <AgentChatRequest>[],
          responding: state.respondingRequestIds,
          live: state.live,
        ),
      ),
    );
    final approvals = <AgentChatRequest>[
      for (final request in view.requests)
        if (request.isApproval) request,
    ];
    if (approvals.isEmpty) return const SizedBox.shrink();
    final controller = ref.read(provider.notifier);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        for (final request in approvals)
          AgentChatPendingApprovalRow(
            key: ValueKey<String>('agent-chat-approval-row-${request.id}'),
            request: request,
            responding: view.responding.contains(request.id),
            enabled: view.live,
            onRespond: (response) => controller.respond(request, response),
          ),
      ],
    );
  }
}

/// One approval the agent waits on, drawn like a tool row: what it wants to
/// run, change or read, then "Waiting for approval" and the decisions the
/// runtime offers, in its order.
class const AgentChatPendingApprovalRow({
  super.key,
  required final AgentChatRequest request,
  required final bool responding,
  required final bool enabled,
  required final ValueChanged<AgentChatResponse> onRespond,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final title = agentChatRequestTitle(request);
    final command = agentChatJsonString(request.command);
    final path = agentChatJsonString(request.path);
    final cwd = agentChatJsonString(request.cwd);
    final detail = agentChatJsonString(request.detail);
    final subject = command ?? path ?? detail ?? title;
    final reason = subject == detail ? null : detail;
    final override = request.fullAccessOverride;
    final expiresAt = request.expiresAt;
    final canAct = enabled && !responding;
    return Semantics(
      container: true,
      label: title,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
        child: Row(
          crossAxisAlignment: .start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: AleraTokens.space2),
              child: Icon(
                _iconFor(request.kind),
                size: AleraTokens.iconSm,
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                mainAxisSize: .min,
                spacing: AleraTokens.space4,
                children: <Widget>[
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: AleraTokens.agentChatRequestMaxHeight,
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        subject,
                        style: command != null || path != null
                            ? AleraTokens.monoStyle.copyWith(
                                color: AleraTokens.foreground,
                              )
                            : theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                  if (cwd != null) Text('in $cwd', style: muted),
                  if (reason != null) Text(reason, style: muted),
                  if (override != null)
                    AleraInlineNotice(
                      tone: .warning,
                      message: agentChatFullAccessOverrideMessage(override),
                    ),
                  Wrap(
                    crossAxisAlignment: .center,
                    spacing: AleraTokens.space4,
                    runSpacing: AleraTokens.space4,
                    children: <Widget>[
                      const Icon(
                        AleraIcons.insecure,
                        size: AleraTokens.iconSm,
                        color: AleraTokens.warning,
                      ),
                      Text(
                        'Waiting for approval',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AleraTokens.warning,
                        ),
                      ),
                      if (expiresAt != null)
                        Text(
                          '· expires at ${_clockTime(context, expiresAt)}',
                          style: muted,
                        ),
                      ...agentChatDecisionButtons(
                        request.offeredDecisions,
                        enabled: canAct,
                        inline: true,
                        onDecision: (decision) =>
                            onRespond(AgentChatApprovalResponse(decision)),
                      ),
                      if (agentChatOffersDeclineFeedback(request))
                        TextButton(
                          key: const ValueKey<String>(
                            'agent-chat-decline-feedback',
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AleraTokens.foregroundMuted,
                          ),
                          onPressed: canAct
                              ? () async {
                                  final feedback =
                                      await showAgentChatDeclineFeedbackDialog(
                                        context,
                                      );
                                  if (feedback == null) return;
                                  onRespond(
                                    AgentChatApprovalResponse(
                                      .decline,
                                      feedback: feedback,
                                    ),
                                  );
                                }
                              : null,
                          child: const Text(
                            '$agentChatDeclineWithFeedbackLabel…',
                          ),
                        ),
                      if (responding)
                        const SizedBox.square(
                          dimension: AleraTokens.iconSm,
                          child: CircularProgressIndicator(
                            strokeWidth: AleraTokens.strokeSm,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _iconFor(AgentChatRequestKind kind) => switch (kind) {
  .commandExecutionApproval || .execCommandApproval => AleraIcons.terminal,
  .fileChangeApproval || .applyPatchApproval => AleraIcons.edit,
  .fileReadApproval => AleraIcons.visible,
  _ => AleraIcons.devTools,
};

String _clockTime(BuildContext context, DateTime value) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(value.toLocal()),
      alwaysUse24HourFormat: true,
    );
