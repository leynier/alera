import 'package:alera_agent_chat/src/agent_chat_item.dart';

enum AgentChatMessageSenderKind { automation, pullRequestWatch, agent, guest }

/// Who sent a message that the person did not write, as both apps label it:
/// "Automation · Nightly report", "Pull request #42", "Agent" (with a link
/// to [chatId], whose title the app fills in) or "Guest · Ana".
class const AgentChatMessageSender({
  required final AgentChatMessageSenderKind kind,
  required final String label,
  final String? detail,

  /// The chat an [AgentChatMessageSenderKind.agent] message came from.
  final String? chatId,
}) {
  /// The label and its detail on one line.
  String get text => detail == null ? label : '$label · $detail';
}

/// The sender of a message with [origin], or null when the person wrote it
/// or the runtime woke the chat itself.
AgentChatMessageSender? agentChatMessageSender(AgentChatItemOrigin? origin) =>
    switch (origin) {
      null => null,
      AgentChatItemOrigin(kind: .automation, :final automationName) =>
        AgentChatMessageSender(
          kind: .automation,
          label: 'Automation',
          detail: _present(automationName),
        ),
      AgentChatItemOrigin(kind: .pullRequestWatch, :final pullRequestNumber) =>
        AgentChatMessageSender(
          kind: .pullRequestWatch,
          label: pullRequestNumber == null
              ? 'Pull request'
              : 'Pull request #$pullRequestNumber',
        ),
      AgentChatItemOrigin(kind: .chatMessage, :final senderChatId) =>
        AgentChatMessageSender(
          kind: .agent,
          label: 'Agent',
          chatId: _present(senderChatId),
        ),
      AgentChatItemOrigin(kind: .guest, :final guestName) =>
        AgentChatMessageSender(
          kind: .guest,
          label: 'Guest',
          detail: _present(guestName),
        ),
      _ => null,
    };

String? _present(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
