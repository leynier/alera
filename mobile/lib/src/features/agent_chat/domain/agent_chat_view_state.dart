import 'package:alera_agent_chat/alera_agent_chat.dart';

/// One chat as the phone shows it: the runtime's thread, its timeline, and
/// what only this phone knows, such as prompts still on their way.
class AgentChatViewState {
  AgentChatViewState({
    required this.thread,
    this.outbox = const <AgentChatOutgoingMessage>[],
    this.stale = false,
    this.loadingHistory = false,
    this.interrupting = false,
    this.respondingRequestIds = const <String>{},
    AgentChatTimelineProjection? previous,
  }) : timeline = AgentChatTimelineProjection.build(
         thread,
         outgoing: outbox,
         previous: previous,
       );

  final AgentChatThread thread;

  /// Sends the runtime has not stamped into the thread, or refused.
  final List<AgentChatOutgoingMessage> outbox;

  /// The connection dropped or a reload failed: what is shown may be behind.
  final bool stale;
  final bool loadingHistory;

  /// Stop was asked for and the turn has not ended yet.
  final bool interrupting;
  final Set<String> respondingRequestIds;

  /// Shared with the desktop, so both surfaces group a turn the same way.
  final AgentChatTimelineProjection timeline;

  AgentChatSession get session => thread.session;

  AgentChatRef get ref =>
      AgentChatRef(chatId: thread.chatId, workspaceId: thread.workspaceId);

  bool get turnActive =>
      session.activeTurnId != null ||
      session.status == AgentChatSessionStatus.running;

  AgentChatViewState copyWith({
    AgentChatThread? thread,
    List<AgentChatOutgoingMessage>? outbox,
    bool? stale,
    bool? loadingHistory,
    bool? interrupting,
    Set<String>? respondingRequestIds,
  }) {
    final nextThread = thread ?? this.thread;
    final nextOutbox = outbox ?? this.outbox;
    return AgentChatViewState(
      thread: nextThread,
      // A send that reached the runtime shows up in the thread or its queue,
      // even one whose answer was lost with the connection.
      outbox: nextOutbox
          .where(
            (message) =>
                !nextThread.containsClientMessage(message.clientMessageId),
          )
          .toList(growable: false),
      stale: stale ?? this.stale,
      loadingHistory: loadingHistory ?? this.loadingHistory,
      interrupting:
          (interrupting ?? this.interrupting) &&
          (nextThread.session.activeTurnId != null ||
              nextThread.session.status == AgentChatSessionStatus.running),
      respondingRequestIds: respondingRequestIds ?? this.respondingRequestIds,
      previous: timeline,
    );
  }
}
