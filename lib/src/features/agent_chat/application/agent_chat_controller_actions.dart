part of 'agent_chat_controller.dart';

/// What the composer asks of a chat besides sending: settings for the next
/// turn and the runtime's queue.
mixin _AgentChatComposerActions on _$AgentChatController {
  AgentChatRepository get _repository;
  AgentChatLifecycleRepository get _lifecycle;
  String Function() get _nextId;
  Map<String, String> get _reconcileRequestIds;
  AgentChatRef get _chat;
  void _setOutgoing(List<AgentChatOutgoingMessage> outgoing);
  Future<void> _guard(
    Future<void> Function() action, {
    void Function()? onError,
  });

  /// Applies settings to the next turn; the session change arrives as an
  /// event. Returns whether the runtime accepted it.
  Future<bool> configure(AgentChatConfiguration configuration) async {
    if (configuration.isEmpty || state.configuring || !state.canSend) {
      return false;
    }
    state = state.copyWith(configuring: true, actionError: null);
    var accepted = false;
    await _guard(() async {
      await _repository.configure(
        _chat,
        requestId: _nextId(),
        configuration: configuration,
      );
      accepted = true;
    });
    if (ref.mounted) state = state.copyWith(configuring: false);
    return accepted;
  }

  /// One pick from the agent and model picker. Another agent moves the chat
  /// to it (the caller confirms the handoff first when the chat has
  /// history). A model the running turn cannot take yet is held and goes out
  /// with the next message, or as a configuration once the chat is idle.
  Future<bool> choose(AgentChatSelection pick, {required String label}) async {
    final thread = state.thread;
    if (thread == null) return false;
    if (pick.providerInstanceId != thread.providerInstanceId) {
      if (!state.canSwitchProvider) return false;
      state = state.copyWith(pendingModel: null);
      return configure(pick.configuration(switchProvider: true));
    }
    if (pick.model == thread.session.model && state.pendingModel == null) {
      return true;
    }
    if (state.busy && !thread.session.capabilities.modelSwitch) {
      state = state.copyWith(
        pendingModel: pick.model == thread.session.model
            ? null
            : AgentChatPendingModel(model: pick.model, label: label),
      );
      return true;
    }
    state = state.copyWith(pendingModel: null);
    return configure(pick.configuration());
  }

  void _applyPendingModel() {
    final pending = state.pendingModel;
    if (pending == null || !ref.mounted) return;
    state = state.copyWith(pendingModel: null);
    if (pending.model == state.thread?.session.model) return;
    unawaited(
      configure(
        AgentChatConfiguration(
          model: pending.model,
          resetModel: pending.model == null,
        ),
      ),
    );
  }

  /// Keeps this session's stand-in for the runtime's remembered selection,
  /// for runtimes without chat preferences.
  void _rememberSelection() {
    final thread = state.thread;
    if (thread == null || thread.providerInstanceId.isEmpty) return;
    final session = thread.session;
    ref
        .read(agentChatLaunchPreferenceProvider.notifier)
        .remember(
          AgentChatSelection(
            providerInstanceId: thread.providerInstanceId,
            model: session.model,
            runtimeMode: session.runtimeMode,
            interactionMode: session.interactionMode,
          ),
        );
  }

  /// Turns the agent's own file checkpoints on or off for this chat. The
  /// runtime accepts it only between turns, and a change restarts the
  /// agent's session with the next message. Returns whether it was accepted.
  Future<bool> setFileCheckpointing({required bool enabled}) async {
    final session = state.thread?.session;
    if (session == null ||
        session.fileCheckpointing == enabled ||
        state.configuring ||
        !state.canSwitchProvider) {
      return false;
    }
    state = state.copyWith(configuring: true, actionError: null);
    var accepted = false;
    await _guard(() async {
      await _lifecycle.nativeHistory.configureFileCheckpoints(
        _chat,
        requestId: _nextId(),
        enabled: enabled,
      );
      accepted = true;
    });
    if (ref.mounted) state = state.copyWith(configuring: false);
    return accepted;
  }

  /// Resolves the pending native history operation the way the person chose
  /// from the actions the runtime allows. A retry of the same choice for the
  /// same operation reuses its request id, so the runtime never acts twice;
  /// nothing here retries on its own.
  Future<void> reconcileNativeOperation(
    AgentChatNativeHistoryAction action,
  ) async {
    final operation = state.thread?.pendingNativeOperation;
    if (operation == null || state.reconcilingNativeOperation) return;
    state = state.copyWith(reconcilingNativeOperation: true, actionError: null);
    await _guard(
      () => _lifecycle.nativeHistory.reconcile(
        _chat,
        requestId: _reconcileRequestIds.putIfAbsent(
          '${operation.operationId}:${action.wire}',
          _nextId,
        ),
        operationId: operation.operationId,
        action: action,
      ),
    );
    if (ref.mounted) {
      state = state.copyWith(reconcilingNativeOperation: false);
    }
  }

  /// Takes a message back from the runtime's queue. Returns whether it was
  /// still queued, so the caller knows it may hand the text back.
  Future<bool> cancelQueued(String queueId) async {
    if (state.cancellingQueueIds.contains(queueId)) return false;
    state = state.copyWith(
      cancellingQueueIds: <String>{...state.cancellingQueueIds, queueId},
    );
    var withdrawn = false;
    await _guard(
      () async => withdrawn = await _repository.cancelQueued(
        _chat,
        requestId: _nextId(),
        queueId: queueId,
      ),
      onError: () => state = state.copyWith(
        cancellingQueueIds: <String>{
          for (final id in state.cancellingQueueIds)
            if (id != queueId) id,
        },
      ),
    );
    return withdrawn;
  }

  /// Replaces a queued message's text in one runtime step. Returns `null`
  /// when it was saved, else the reason shown in the editor.
  Future<String?> editQueued(String queueId, String text) async {
    try {
      final edited = await _lifecycle.queueEdit(
        _chat,
        requestId: _nextId(),
        queueId: queueId,
        text: text.trim(),
      );
      return edited ? null : 'The message already left the queue.';
    } on Object catch (error) {
      return agentChatErrorMessage(error);
    }
  }

  /// Moves a queued message into the running turn in one runtime step.
  Future<void> steerQueued(String queueId) async {
    final turnId = state.thread?.session.activeTurnId;
    if (turnId == null || !state.canSteer) return;
    await _guard(
      () => _lifecycle.queueSteer(
        AgentChatQueueSteerInput(
          chatId: chatId,
          workspaceId: workspaceId,
          requestId: _nextId(),
          queueId: queueId,
          turnId: turnId,
        ),
      ),
    );
  }

  /// Drops a failed message and returns it so the composer can edit it.
  AgentChatOutgoingMessage? discardSend(String clientMessageId) {
    final message = state.outgoing
        .where((message) => message.clientMessageId == clientMessageId)
        .firstOrNull;
    if (message == null || message.status != AgentChatOutgoingStatus.failed) {
      return null;
    }
    _setOutgoing(<AgentChatOutgoingMessage>[
      for (final other in state.outgoing)
        if (other.clientMessageId != clientMessageId) other,
    ]);
    return message;
  }
}
