import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_activity_rows.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_message_views.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_request_cards.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_turn_view.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// One timeline row, dispatched by entry kind.
class const AgentChatTimelineEntryView({
  super.key,
  required final AgentChatTimelineEntry entry,
  required final AgentChatTimelineActions actions,
  required final AgentChatExpansion expansion,
  required final bool responding,
  required final bool enabled,
  required final String workspacePath,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return switch (entry) {
      AgentChatTurnEntry(:final section) => AgentChatTurnView(
        section: section,
        actions: actions,
        expansion: expansion,
        workspacePath: workspacePath,
      ),
      AgentChatStandaloneEntry(:final item) => Padding(
        padding: const EdgeInsets.only(bottom: AleraTokens.space8),
        child: AgentChatItemRowView(
          item: item,
          expansion: expansion,
          actions: actions,
          workspacePath: workspacePath,
        ),
      ),
      AgentChatOutgoingEntry(:final message) => AgentChatOutgoingMessageView(
        message: message,
        onRetry: () => actions.onRetrySend(message.clientMessageId),
        onEdit: () => actions.onEditSend(message.clientMessageId),
      ),
      AgentChatRequestEntry(:final request) => Padding(
        padding: const EdgeInsets.only(bottom: AleraTokens.space12),
        child: _requestCard(request),
      ),
    };
  }

  Widget _requestCard(AgentChatRequest request) {
    if (request.isApproval) {
      return AgentChatApprovalCard(
        request: request,
        responding: responding,
        enabled: enabled,
        onDecision: (decision) =>
            actions.onRespond(request, AgentChatApprovalResponse(decision)),
      );
    }
    if (request.isElicitation) {
      return AgentChatElicitationCard(
        request: request,
        responding: responding,
        enabled: enabled,
        onOpenUrl: actions.onOpenLink,
        onRespond: (action, content) => actions.onRespond(
          request,
          AgentChatElicitationResponse(action, content),
        ),
      );
    }
    return AgentChatUnsupportedRequestCard(
      request: request,
      responding: responding,
      enabled: enabled,
      onDecision: (decision) =>
          actions.onRespond(request, AgentChatApprovalResponse(decision)),
    );
  }
}
