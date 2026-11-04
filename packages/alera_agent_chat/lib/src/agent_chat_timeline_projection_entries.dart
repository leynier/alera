part of 'agent_chat_timeline_projection.dart';

sealed class AgentChatTimelineEntry {
  const AgentChatTimelineEntry();

  String get key;
}

final class AgentChatTurnEntry extends AgentChatTimelineEntry {
  const AgentChatTurnEntry(this.section);

  final AgentChatTurnSection section;

  @override
  String get key => 'turn-${section.turnId}';
}

/// An item outside any turn: chat-level notices, errors and compaction.
final class AgentChatStandaloneEntry extends AgentChatTimelineEntry {
  const AgentChatStandaloneEntry(this.item);

  final AgentChatItem item;

  @override
  String get key => 'item-${item.id}';
}

/// A message the user sent that the runtime has not stamped into the
/// timeline yet, or that it rejected.
final class AgentChatOutgoingEntry extends AgentChatTimelineEntry {
  const AgentChatOutgoingEntry(this.message);

  final AgentChatOutgoingMessage message;

  @override
  String get key => 'outgoing-${message.clientMessageId}';
}
