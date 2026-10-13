import 'package:alera_agent_chat/alera_agent_chat.dart';

enum AgentChatPhase {
  loading,
  ready,

  /// The runtime does not advertise agent chats; an update is required.
  unsupported,

  /// The first snapshot could not be read.
  failed,
}

enum AgentChatConnection {
  live,

  /// The runtime connection dropped; the last copy is shown read-only until
  /// the next snapshot arrives.
  reconnecting,
}

/// Everything one chat tab renders. The thread is the runtime's truth; the
/// rest is this client's transient view of it.
class const AgentChatViewState({
  final AgentChatPhase phase = AgentChatPhase.loading,
  final AgentChatThread? thread,
  final AgentChatTimelineProjection? projection,
  final AgentChatConnection connection = AgentChatConnection.live,
  final List<AgentChatOutgoingMessage> outgoing =
      const <AgentChatOutgoingMessage>[],
  final Set<String> respondingRequestIds = const <String>{},
  final Set<String> cancellingQueueIds = const <String>{},
  final bool interrupting = false,
  final bool loadingHistory = false,
  final bool configuring = false,
  final bool recovering = false,
  final String? loadError,
  final String? actionError,
}) {
  bool get live => connection == AgentChatConnection.live;

  bool get busy => thread?.session.busy ?? false;

  bool get archived => thread?.archived ?? false;

  /// Whether the composer may submit right now. A busy session still accepts
  /// a message (the runtime queues it behind the running turn), and so does a
  /// stopped one: the runtime resumes or restarts it on the next send.
  bool get canSend => phase == AgentChatPhase.ready && live && !archived;

  bool get canInterrupt =>
      live && busy && !interrupting && thread!.session.capabilities.interrupt;

  /// Provider and mode changes wait for an idle session with nothing open,
  /// which is when the runtime accepts them.
  bool get canSwitchProvider =>
      canSend &&
      !busy &&
      !configuring &&
      thread!.pendingRequests.isEmpty &&
      thread!.queue.isEmpty;

  AgentChatViewState copyWith({
    AgentChatPhase? phase,
    AgentChatThread? thread,
    AgentChatTimelineProjection? projection,
    AgentChatConnection? connection,
    List<AgentChatOutgoingMessage>? outgoing,
    Set<String>? respondingRequestIds,
    Set<String>? cancellingQueueIds,
    bool? interrupting,
    bool? loadingHistory,
    bool? configuring,
    bool? recovering,
    Object? loadError = _unchanged,
    Object? actionError = _unchanged,
  }) => AgentChatViewState(
    phase: phase ?? this.phase,
    thread: thread ?? this.thread,
    projection: projection ?? this.projection,
    connection: connection ?? this.connection,
    outgoing: outgoing ?? this.outgoing,
    respondingRequestIds: respondingRequestIds ?? this.respondingRequestIds,
    cancellingQueueIds: cancellingQueueIds ?? this.cancellingQueueIds,
    interrupting: interrupting ?? this.interrupting,
    loadingHistory: loadingHistory ?? this.loadingHistory,
    configuring: configuring ?? this.configuring,
    recovering: recovering ?? this.recovering,
    loadError: identical(loadError, _unchanged)
        ? this.loadError
        : loadError as String?,
    actionError: identical(actionError, _unchanged)
        ? this.actionError
        : actionError as String?,
  );
}

const Object _unchanged = Object();
