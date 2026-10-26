import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_activity_rows.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_find.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_message_views.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_turn_view.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// One timeline row, dispatched by entry kind. Requests are not rows: they
/// dock above the composer. [preparingAttachmentIds] holds the client message
/// ids whose attachments are still uploading.
class const AgentChatTimelineEntryView({
  super.key,
  required final AgentChatTimelineEntry entry,
  required final AgentChatTimelineActions actions,
  required final AgentChatExpansion expansion,
  required final String workspacePath,
  final Set<String> preparingAttachmentIds = const <String>{},
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
        child: AgentChatFindTarget(
          targetKey: agentChatFindItemTargetKey(item.id),
          child: AgentChatItemRowView(
            item: item,
            expansion: expansion,
            actions: actions,
            workspacePath: workspacePath,
          ),
        ),
      ),
      AgentChatOutgoingEntry(:final message) => AgentChatFindTarget(
        targetKey: agentChatFindOutgoingTargetKey(message.clientMessageId),
        child: AgentChatOutgoingMessageView(
          message: message,
          onRetry: () => actions.onRetrySend(message.clientMessageId),
          onEdit: () => actions.onEditSend(message.clientMessageId),
          uploading: preparingAttachmentIds.contains(message.clientMessageId),
        ),
      ),
    };
  }
}
