part of 'agent_chat_controller.dart';

/// History operations on a chat: fork, rewind, file checkpoints, the native
/// operation recovery, and the read-only approval history and turn changes.
/// Each is offered only where the runtime and the chat's agent support it.
extension AgentChatHistoryOperations on AgentChatController {
  /// Starts a new chat from this one's history up to [turnId]; the runtime
  /// opens it in its own tab and this chat stays as it is.
  Future<AgentChatOpenResult> fork(String turnId) => _ready()
      .repository
      .lifecycle
      .fork(_chat, requestId: _uuid.v4(), turnId: turnId);

  /// Takes the chat back to before [turnId]: its transcript only, or with
  /// [native] the agent's own conversation too. The runtime hands back that
  /// turn's prompt, which returns to the composer for editing.
  Future<AgentChatRewindResult> rewind(
    String turnId, {
    bool native = false,
  }) async {
    final sync = _ready();
    final lifecycle = sync.repository.lifecycle;
    final result = native
        ? await lifecycle.nativeHistory.rewind(
            _chat,
            requestId: _uuid.v4(),
            turnId: turnId,
            mode: AgentChatRewindMode.native,
          )
        : await lifecycle.rewind(_chat, requestId: _uuid.v4(), turnId: turnId);
    sync.adopt(result.snapshot);
    return result;
  }

  /// Restores the files the agent checkpointed before [turnId]; the
  /// transcript stays as it is.
  Future<AgentChatFilesystemRewindResult> rewindFiles(String turnId) async {
    final sync = _ready();
    final result = await sync.repository.lifecycle.nativeHistory.rewindFiles(
      _chat,
      requestId: _uuid.v4(),
      turnId: turnId,
    );
    if (result.snapshot case final snapshot?) sync.adopt(snapshot);
    return result;
  }

  /// Settles a native history change the runtime could not finish on its
  /// own, with an action the person chose from the ones it allows.
  /// [requestId] is one per attempt, so a retry after a lost answer replays
  /// it instead of acting twice.
  Future<void> reconcileNativeOperation(
    AgentChatNativeOperation operation,
    AgentChatNativeHistoryAction action, {
    required String requestId,
  }) async {
    final sync = _ready();
    final result = await sync.repository.lifecycle.nativeHistory.reconcile(
      _chat,
      requestId: requestId,
      operationId: operation.operationId,
      action: action,
    );
    sync.adopt(result.snapshot);
  }

  /// File checkpoints let a later rewind restore files. The change applies
  /// from the next message, which starts a new agent session.
  Future<void> configureFileCheckpoints({required bool enabled}) async {
    final sync = _ready();
    sync.adopt(
      await sync.repository.lifecycle.nativeHistory.configureFileCheckpoints(
        _chat,
        requestId: _uuid.v4(),
        enabled: enabled,
      ),
    );
  }

  Future<AgentChatApprovalHistoryPage> approvalHistory({String? before}) =>
      _ready().repository.lifecycle.approvalHistory(_chat, before: before);

  Future<AgentChatTurnDiff> turnDiff(String turnId) =>
      _ready().repository.lifecycle.turnDiff(_chat, turnId: turnId);
}
