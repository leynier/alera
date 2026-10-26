import 'package:alera_agent_chat/src/agent_chat_item.dart';

enum AgentChatOutgoingStatus {
  /// The send request is in flight.
  sending,

  /// The runtime took the message; it shows until its item or queue entry
  /// arrives in the thread.
  accepted,

  /// The send failed; retrying reuses the same id, which the runtime
  /// deduplicates.
  failed,
}

/// A message on its way to the runtime. It renders until the thread holds an
/// item or queue entry with the same [clientMessageId].
class const AgentChatOutgoingMessage({
  required final String clientMessageId,
  required final String text,
  required final DateTime createdAt,
  final List<AgentChatAttachment> attachments = const <AgentChatAttachment>[],
  final AgentChatOutgoingStatus status = AgentChatOutgoingStatus.sending,
  final String? error,
}) {
  AgentChatOutgoingMessage withStatus(
    AgentChatOutgoingStatus status, {
    String? error,
  }) => AgentChatOutgoingMessage(
    clientMessageId: clientMessageId,
    text: text,
    createdAt: createdAt,
    attachments: attachments,
    status: status,
    error: error,
  );
}
