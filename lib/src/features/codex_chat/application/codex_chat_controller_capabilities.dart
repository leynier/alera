part of 'codex_chat_controller.dart';

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

extension CodexChatControllerCapabilities on CodexChatController {
  Future<bool> _awaitRuntimeCapabilities() async {
    while (_reconnectRefresh != null) {
      await _reconnectRefresh;
    }
    return ref.mounted &&
        !_capabilityRefreshBlocked &&
        !state.sharedQueueUnavailable;
  }

  Future<void> _refreshCapabilitiesAndGoal() async {
    final previous = _reconnectRefresh;
    final refresh = () async {
      await previous;
      if (!ref.mounted) return;
      try {
        final features = await _host.refreshChatFeatures();
        if (!ref.mounted) return;
        if (!state.supportsSharedQueue &&
            !state.sharedQueueUnavailable &&
            features.contains('codexSharedQueueV1')) {
          await _transferLegacyQueue();
        }
        if (!ref.mounted) return;
        final downgrade =
            state.supportsSharedQueue &&
            !features.contains('codexSharedQueueV1');
        state = state.copyWith(
          chatFeatures: features,
          queueState:
              downgrade && state.queuedMessages.isEmpty && !state.historyLocked
              ? const {}
              : state.queueState,
          error: null,
        );
        _capabilityRefreshBlocked = false;
        if (state.sharedQueueUnavailable) {
          state = state.copyWith(
            error: 'This runtime cannot manage the saved shared queue. Its messages remain stored and will not be sent locally. Reconnect to a compatible runtime or open a new chat.',
          );
        }
        await _refreshCapabilities();
        if (!ref.mounted) return;
        await refreshQueue();
        await _refreshGoal(retryUnavailable: true);
      } catch (error) {
        if (ref.mounted) {
          _capabilityRefreshBlocked = true;
          state = state.copyWith(
            error:
                'Could not finish reconnecting. Pending messages are preserved. Retry before sending: ${_safeError(error)}',
          );
        }
      }
    }();
    _reconnectRefresh = refresh;
    await refresh;
    if (identical(_reconnectRefresh, refresh)) {
      _reconnectRefresh = null;
      _drainQueuedMessageIfIdle();
    }
  }

  Future<void> _transferLegacyQueue() async {
    // Keep local entries until each stable identity is acknowledged. A lost
    // acknowledgement retries insertion with the same ID, never a new send.
    final generation = _threadGeneration;
    final captured = state;
    _transferringLegacyQueue = true;
    try {
      if (state.queuedMessages.isNotEmpty && captured.queuePaused) {
        final queue = await _host.request('codex.queue.get', {
          'tabId': tabId,
          'expectedThreadId': _threadId,
        });
        await _host.request('codex.queue.pause', {
          'tabId': tabId,
          'expectedThreadId': _threadId,
          'expectedRevision': queue['revision'],
          'operationId': _newClientMessageId(),
        });
      }
      while (state.queuedMessages.isNotEmpty) {
        final message = state.queuedMessages.first;
        await _host.startTurn(
          tabId,
          _buildInput(message, captured),
          expectedThreadId: _threadId,
          userMessage: _userMessagePresentation(message),
          model: captured.selectedModel,
          reasoningEffort: captured.reasoningEffort,
          speedMode: captured.speedMode,
          permissionMode: captured.permissionMode,
          planMode: captured.planMode,
          collaborationMode: captured.collaborationMode,
          clientUserMessageId: message.id,
          sharedQueue: true,
          draft: codexQueueDraft(message),
          expectedHistoryRevision: captured.historyRevision,
        );
        if (!ref.mounted || generation != _threadGeneration) {
          throw StateError('The conversation changed during queue transfer.');
        }
        state = state.copyWith(
          queuedMessages: state.queuedMessages
              .where((entry) => entry.id != message.id)
              .toList(),
        );
      }
    } finally {
      _transferringLegacyQueue = false;
    }
  }

  Future<void> _refreshCapabilities() async {
    final generation = ++_capabilityGeneration;
    var supportsSessions = await _host.supportsSessions();
    if (!supportsSessions) {
      supportsSessions = await _host.supportsSessions();
    }
    final supportsAutoReview = await _host.supportsTurnPolicy();
    final supportsGoals = await _host.supportsGoals();
    if (!ref.mounted || generation != _capabilityGeneration) return;
    _goalCapabilityAdvertised = supportsGoals;
    final permissionMode =
        !supportsAutoReview && state.permissionMode == 'auto-review'
        ? 'on-request'
        : state.permissionMode;
    final permissionChanged = permissionMode != state.permissionMode;
    state = state.copyWith(
      supportsSessions: supportsSessions,
      supportsAutoReview: supportsAutoReview,
      supportsGoals: supportsGoals && _goalsAvailable,
      permissionMode: permissionMode,
    );
    if (permissionChanged) {
      _persistTabConfiguration();
    }
  }
}
