import 'package:alera_agent_chat/alera_agent_chat.dart';

/// What a chat tab's status dot says without opening the chat.
enum AgentChatTabActivity {
  idle,
  working,

  /// The agent waits on the person: an approval, an answer or a form, its
  /// own or one of a task it delegated.
  needsInput,
  failed,

  /// The chat is idle but tasks it delegated are still running.
  waitingOnTasks,
}

/// The dot's state, most urgent first: needs input, failed, working,
/// waiting on tasks, idle. Children report through their parent, so a child
/// waiting on a person raises the parent's dot as well.
AgentChatTabActivity agentChatTabActivity(
  AgentChatSessionStatus status, {
  bool hasPendingRequests = false,
  bool childNeedsInput = false,
  bool waitingOnTasks = false,
}) {
  if (hasPendingRequests ||
      childNeedsInput ||
      status == AgentChatSessionStatus.waiting) {
    return AgentChatTabActivity.needsInput;
  }
  return switch (status) {
    AgentChatSessionStatus.error => AgentChatTabActivity.failed,
    AgentChatSessionStatus.starting ||
    AgentChatSessionStatus.running => AgentChatTabActivity.working,
    _ when waitingOnTasks => AgentChatTabActivity.waitingOnTasks,
    _ => AgentChatTabActivity.idle,
  };
}

/// [activity] with the live state of the tasks the chat delegated folded in.
AgentChatTabActivity agentChatTabActivityWithTasks(
  AgentChatTabActivity activity, {
  required bool childNeedsInput,
  required bool waitingOnTasks,
}) => switch (activity) {
  AgentChatTabActivity.needsInput => activity,
  _ when childNeedsInput => AgentChatTabActivity.needsInput,
  AgentChatTabActivity.idle when waitingOnTasks =>
    AgentChatTabActivity.waitingOnTasks,
  _ => activity,
};

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
