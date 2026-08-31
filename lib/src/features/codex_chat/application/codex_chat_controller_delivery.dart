part of 'codex_chat_controller.dart';

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

extension CodexChatControllerDelivery on CodexChatController {
  Future<bool> _sendNow(CodexQueuedMessage message) async {
    final generation = _threadGeneration;
    state = state.copyWith(sending: true, error: null);
    try {
      final response = await _host.startTurn(
        tabId,
        _buildInput(message, state),
        expectedThreadId: _threadId,
        userMessage: _userMessagePresentation(message),
        model: state.selectedModel,
        reasoningEffort: state.reasoningEffort,
        speedMode: state.speedMode,
        permissionMode: state.permissionMode,
        planMode: state.planMode,
        collaborationMode: state.collaborationMode,
        clientUserMessageId: message.id,
        sharedQueue: state.supportsSharedQueue,
        draft: codexQueueDraft(message),
        expectedHistoryRevision: state.historyRevision,
      );
      if (ref.mounted && generation == _threadGeneration) {
        state = state.copyWith(sending: false);
        if (state.supportsSharedQueue) _applyQueueSnapshot(response);
      }
      return true;
    } catch (error) {
      if (ref.mounted && generation == _threadGeneration) {
        state = state.copyWith(sending: false, error: _safeError(error));
      }
      return false;
    }
  }

  Future<bool> steer(
    String text, {
    List<CodexInputAttachment> attachments = const <CodexInputAttachment>[],
    List<CodexDraftItem> draftItems = const <CodexDraftItem>[],
  }) async {
    final turnId = state.snapshot.activeTurnId;
    if (!canSteer ||
        turnId == null ||
        (text.trim().isEmpty && attachments.isEmpty && draftItems.isEmpty)) {
      return false;
    }
    final generation = _threadGeneration;
    final message = CodexQueuedMessage(
      text: text.trim(),
      attachments: attachments,
      draftItems: draftItems,
    );
    final submissionIds = _pendingSubmissionIds;
    final signature = jsonEncode([
      'steer',
      _threadId,
      turnId,
      codexQueueDraft(message),
    ]);
    final id = submissionIds.putIfAbsent(signature, _newClientMessageId);
    _steering = true;
    try {
      final response = await _host.steer(
        tabId,
        turnId,
        _buildInput(message, state),
        userMessage: _userMessagePresentation(message),
        clientUserMessageId: id,
        expectedThreadId: _threadId,
        expectedHistoryRevision: state.historyRevision,
        sharedQueue: state.supportsSharedQueue,
        draft: codexQueueDraft(message),
      );
      submissionIds.remove(signature);
      if (ref.mounted &&
          generation == _threadGeneration &&
          state.supportsSharedQueue) {
        _applyQueueSnapshot(response);
      }
      return true;
    } catch (error) {
      if (ref.mounted && generation == _threadGeneration) {
        state = state.copyWith(error: _safeError(error));
      }
      return false;
    } finally {
      _steering = false;
    }
  }
}
