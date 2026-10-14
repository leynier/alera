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
    this.pendingModel,
    this.removed = false,
    this.discarded = false,
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

  /// A model picked while a turn ran, sent with the next message. Provider
  /// switches are refused while busy, so only the model is ever held.
  final AgentChatPendingModel? pendingModel;

  /// The runtime no longer has this chat: another device discarded it while
  /// it was empty, or deleted it from the archive.
  final bool removed;
  final bool discarded;

  /// Shared with the desktop, so both surfaces group a turn the same way.
  final AgentChatTimelineProjection timeline;

  AgentChatSession get session => thread.session;

  AgentChatRef get ref =>
      AgentChatRef(chatId: thread.chatId, workspaceId: thread.workspaceId);

  bool get turnActive =>
      session.activeTurnId != null ||
      session.status == AgentChatSessionStatus.running;

  /// Nothing was ever sent, so the agent and model change freely and the
  /// chat shows its ready state rather than a stopped session.
  bool get neverSent => thread.snapshot.neverSent && outbox.isEmpty;

  /// A native history change has not finished or its outcome is uncertain.
  /// Sending waits so the draft is not sent into a half-changed history; the
  /// operation's own recovery decides what happens next.
  bool get nativeOperationPending => thread.pendingNativeOperation != null;

  /// The chat has no agent yet; Send waits for one.
  bool get unselected => !thread.snapshot.hasSelection;

  /// A provider switch needs the chat to be idle: no turn, no pending
  /// request, nothing queued.
  bool get canSwitchProvider =>
      !turnActive &&
      thread.pendingRequests.isEmpty &&
      thread.queue.isEmpty &&
      !nativeOperationPending;

  /// The selection the composer shows, including a model held for later.
  AgentChatSelection? get selection => unselected
      ? null
      : AgentChatSelection(
          providerInstanceId: thread.providerInstanceId.isEmpty
              ? thread.provider
              : thread.providerInstanceId,
          model: switch (pendingModel) {
            final pending? => pending.model,
            null => session.model,
          },
          runtimeMode: session.runtimeMode,
          interactionMode: session.interactionMode,
        );

  AgentChatViewState copyWith({
    AgentChatThread? thread,
    List<AgentChatOutgoingMessage>? outbox,
    bool? stale,
    bool? loadingHistory,
    bool? interrupting,
    Set<String>? respondingRequestIds,
    AgentChatPendingModel? pendingModel,
    bool clearPendingModel = false,
    bool? removed,
    bool? discarded,
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
      pendingModel: clearPendingModel
          ? null
          : pendingModel ?? this.pendingModel,
      removed: removed ?? this.removed,
      discarded: discarded ?? this.discarded,
      previous: timeline,
    );
  }
}

/// A model choice waiting for the next message; [model] null means the
/// provider default.
class const AgentChatPendingModel({final String? model});
