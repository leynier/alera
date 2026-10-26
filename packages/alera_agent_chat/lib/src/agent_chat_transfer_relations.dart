import 'package:alera_agent_chat/src/agent_chat_context_transfer.dart';
import 'package:alera_agent_chat/src/agent_chat_summary.dart';

/// One context transfer in the lineage control, as T3 Code's relationships
/// control lists a `transfer` edge: the chat the context came from, how and
/// whether it arrived. A transfer within one chat (a provider handoff) has no
/// other chat to open, so it stays the divider in the timeline.
final class const AgentChatTransferRelation({
  required final AgentChatContextTransfer transfer,
  required final String title,

  /// The source chat, when it is in the list.
  final AgentChatSummary? source,
}) {
  String get key => 'transfer-${transfer.id}';

  String get chatId => transfer.sourceChatId;

  /// The source chat is not in the list (archived, deleted, or on another
  /// host), so it cannot be opened from here.
  bool get missing => source == null || source!.archived;
}

/// The cross-chat transfers into [chatId], newest first.
List<AgentChatTransferRelation> agentChatTransferRelations({
  required String chatId,
  required List<AgentChatContextTransfer> transfers,
  required List<AgentChatSummary> chats,
}) {
  final byId = <String, AgentChatSummary>{
    for (final chat in chats) chat.chatId: chat,
  };
  final relations = <AgentChatTransferRelation>[
    for (final transfer in transfers)
      if (transfer.crossChat && transfer.targetChatId == chatId)
        AgentChatTransferRelation(
          transfer: transfer,
          source: byId[transfer.sourceChatId],
          title: agentChatTransferSourceTitle(
            transfer,
            byId[transfer.sourceChatId],
          ),
        ),
  ];
  relations.sort(
    (left, right) =>
        right.transfer.createdAt.compareTo(left.transfer.createdAt),
  );
  return List<AgentChatTransferRelation>.unmodifiable(relations);
}

/// The source chat's current title, else the one the record kept.
String agentChatTransferSourceTitle(
  AgentChatContextTransfer transfer,
  AgentChatSummary? source,
) {
  for (final title in <String?>[source?.title, transfer.sourceTitle]) {
    final trimmed = title?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
  }
  return switch (transfer.kind) {
    AgentChatTransferKind.subagentResult => 'Delegated Chat',
    AgentChatTransferKind.subagentSpawn => 'Parent Chat',
    _ => 'Agent Chat',
  };
}
