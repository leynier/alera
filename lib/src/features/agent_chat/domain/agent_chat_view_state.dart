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

/// A model chosen while the running turn cannot take it yet. [model] `null`
/// is the provider default. It goes out with the next message, or as a
/// configuration once the chat is idle.
final class const AgentChatPendingModel({
  required final String? model,
  required final String label,
});

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
  final Set<String> preparingAttachmentIds = const <String>{},
  final bool interrupting = false,
  final bool loadingHistory = false,
  final bool configuring = false,
  final bool recovering = false,
  final AgentChatPendingModel? pendingModel,

  /// The runtime deleted the chat (another client discarded or deleted it).
  /// The view stays readable; nothing can be sent to it anymore.
  final bool removed = false,

  /// A recovery action for the pending native history operation is on its
  /// way to the runtime.
  final bool reconcilingNativeOperation = false,
  final String? loadError,
  final String? actionError,
}) {
  bool get live => connection == AgentChatConnection.live;

  bool get preparingAttachments => preparingAttachmentIds.isNotEmpty;

  bool get busy => thread?.session.busy ?? false;

  bool get archived => thread?.archived ?? false;

  /// A native history operation (a native rewind) has not settled. Nothing
  /// may be sent until it does or the person resolves it.
  bool get nativeOperationPending => thread?.pendingNativeOperation != null;

  /// No message ever reached the runtime and none is on its way, so a
  /// provider change needs no handoff and New Agent Chat may reuse the chat.
  bool get neverSent =>
      (thread?.snapshot.neverSent ?? false) && outgoing.isEmpty;

  /// Why provider rows are disabled, or `null` when a switch is accepted.
  String? get providerSwitchBlockedReason {
    if (canSwitchProvider) return null;
    if (!canSend) return 'The agent can change once the chat is connected.';
    return agentChatSwitchBusyReason;
  }

  /// Whether the composer may submit right now. A busy session still accepts
  /// a message (the runtime queues it behind the running turn), and so does a
  /// stopped one: the runtime resumes or restarts it on the next send.
  bool get canSend =>
      phase == AgentChatPhase.ready && live && !archived && !removed;

  /// Whether Mod+Enter may steer the message into the running turn.
  bool get canSteer => canSend && busy && thread!.session.capabilities.steer;

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
    Set<String>? preparingAttachmentIds,
    bool? interrupting,
    bool? loadingHistory,
    bool? configuring,
    bool? recovering,
    Object? pendingModel = _unchanged,
    bool? removed,
    bool? reconcilingNativeOperation,
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
    preparingAttachmentIds:
        preparingAttachmentIds ?? this.preparingAttachmentIds,
    interrupting: interrupting ?? this.interrupting,
    loadingHistory: loadingHistory ?? this.loadingHistory,
    configuring: configuring ?? this.configuring,
    recovering: recovering ?? this.recovering,
    pendingModel: identical(pendingModel, _unchanged)
        ? this.pendingModel
        : pendingModel as AgentChatPendingModel?,
    removed: removed ?? this.removed,
    reconcilingNativeOperation:
        reconcilingNativeOperation ?? this.reconcilingNativeOperation,
    loadError: identical(loadError, _unchanged)
        ? this.loadError
        : loadError as String?,
    actionError: identical(actionError, _unchanged)
        ? this.actionError
        : actionError as String?,
  );
}

const Object _unchanged = Object();
