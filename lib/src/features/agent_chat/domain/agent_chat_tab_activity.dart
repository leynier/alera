import 'package:alera_agent_chat/alera_agent_chat.dart';

/// What a chat tab's status dot says without opening the chat.
enum AgentChatTabActivity {
  idle,
  working,

  /// The agent waits on the person: an approval, an answer or a form.
  needsInput,
  failed,
}

AgentChatTabActivity agentChatTabActivity(
  AgentChatSessionStatus status, {
  bool hasPendingRequests = false,
}) {
  if (hasPendingRequests || status == AgentChatSessionStatus.waiting) {
    return AgentChatTabActivity.needsInput;
  }
  return switch (status) {
    AgentChatSessionStatus.starting ||
    AgentChatSessionStatus.running => AgentChatTabActivity.working,
    AgentChatSessionStatus.error => AgentChatTabActivity.failed,
    _ => AgentChatTabActivity.idle,
  };
}

/// Folds one change into the last known state of its chat: a session change
/// sets the status, a request list sets whether anything is pending.
({AgentChatSessionStatus status, bool hasPendingRequests}) agentChatFoldChange(
  ({AgentChatSessionStatus status, bool hasPendingRequests}) current,
  AgentChatChange change,
) => (
  status: change.session?.status ?? current.status,
  hasPendingRequests: change.requests == null
      ? current.hasPendingRequests
      : change.requests!.isNotEmpty,
);
