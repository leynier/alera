part of 'codex_chat_controller.dart';

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

extension CodexChatControllerSharedQueue on CodexChatController {
  Future<bool> removeQueuedMessageById(String id, {int? revision}) async {
    if (!await _awaitRuntimeCapabilities()) return false;
    if (state.supportsSharedQueue) {
      return queueAction('remove', messageId: id, revision: revision);
    }
    final remaining = state.queuedMessages
        .where((message) => message.id != id)
        .toList();
    if (remaining.length == state.queuedMessages.length) return false;
    state = state.copyWith(queuedMessages: remaining);
    return true;
  }

  void _applyQueueSnapshot(Map<String, Object?> queue) {
    if (_transferringLegacyQueue || !state.supportsSharedQueue) return;
    final threadId = _string(queue['threadId']);
    if (_threadId != null && threadId != _threadId) return;
    if ((queue['revision'] as int? ?? 0) <
        (state.queueState['revision'] as int? ?? 0)) {
      return;
    }
    _threadId ??= threadId;
    final entries = queue['messages'];
    state = state.copyWith(
      queueState: queue,
      queuedMessages: entries is List
          ? [
              for (final entry in entries.whereType<Map>())
                codexQueuedMessageFromWire(Map<String, Object?>.from(entry)),
            ]
          : const [],
    );
    if (state.historyOutdated && !state.loading && !_opening) {
      unawaited(retry());
    }
  }

  Future<void> retryHistoryEdit(String operationId) async {
    try {
      final response = await _host.request('codex.thread.edit', {
        'tabId': tabId,
        'expectedThreadId': _threadId,
        'operationId': operationId,
      });
      if (ref.mounted) {
        _applyQueueSnapshot(
          Map<String, Object?>.from(response['queue'] as Map? ?? response),
        );
      }
    } catch (error) {
      if (ref.mounted) state = state.copyWith(error: _safeError(error));
    }
  }

  Future<void> refreshQueue() async {
    if (!state.supportsSharedQueue) return;
    final generation = _threadGeneration;
    try {
      final queue = await _host.request('codex.queue.get', {
        'tabId': tabId,
        'expectedThreadId': _threadId,
      });
      if (ref.mounted && generation == _threadGeneration) {
        _applyQueueSnapshot(queue);
      }
    } catch (error) {
      if (ref.mounted && generation == _threadGeneration) {
        state = state.copyWith(error: _safeError(error));
      }
    }
  }

  Future<bool> queueAction(
    String action, {
    String? messageId,
    Map<String, Object?>? message,
    String? turnId,
    int? revision,
  }) async {
    if (!await _awaitRuntimeCapabilities()) return false;
    if (!state.supportsSharedQueue &&
        (action == 'pause' || action == 'resume')) {
      state = state.copyWith(
        queueState: {...state.queueState, 'paused': action == 'pause'},
      );
      if (action == 'resume') _drainQueuedMessageIfIdle();
      return true;
    }
    final generation = _threadGeneration;
    try {
      final response = await _host.request('codex.queue.$action', {
        'tabId': tabId,
        'expectedThreadId': _threadId,
        'operationId': _newClientMessageId(),
        'expectedRevision': revision ?? state.queueState['revision'],
        'messageId': ?messageId,
        'message': ?message,
        'turnId': ?turnId,
      });
      if (!ref.mounted || generation != _threadGeneration) return false;
      _applyQueueSnapshot(response);
      return true;
    } catch (error) {
      if (!ref.mounted || generation != _threadGeneration) return false;
      await refreshQueue();
      if (ref.mounted) state = state.copyWith(error: _safeError(error));
      return false;
    }
  }

  Future<bool> saveQueuedMessage(
    CodexQueuedMessage original,
    String text, {
    int? revision,
  }) async {
    if (!await _awaitRuntimeCapabilities()) return false;
    if (!state.supportsSharedQueue) {
      final index = state.queuedMessages.indexWhere(
        (item) => item.id == original.id,
      );
      if (index < 0) return false;
      editQueuedMessage(
        index,
        text: text,
        attachments: original.attachments,
        draftItems: original.draftItems,
      );
      return true;
    }
    final replacement = CodexQueuedMessage(
      id: original.id,
      text: text,
      attachments: original.attachments,
      draftItems: original.draftItems,
    );
    return queueAction(
      'edit',
      messageId: original.id,
      revision: revision,
      message: {
        'input': _buildInput(replacement, state),
        'userMessage': _userMessagePresentation(replacement),
        'draft': codexQueueDraft(replacement),
      },
    );
  }

  Future<bool> steerQueuedMessage(
    CodexQueuedMessage message, {
    int? revision,
  }) async {
    final turnId = state.snapshot.activeTurnId;
    if (!canSteer || turnId == null) return false;
    if (state.supportsSharedQueue) {
      return queueAction(
        'steer',
        messageId: message.id,
        turnId: turnId,
        revision: revision,
      );
    }
    final accepted = await steer(
      message.text,
      attachments: message.attachments,
      draftItems: message.draftItems,
    );
    if (accepted && ref.mounted) {
      state = state.copyWith(
        queuedMessages: state.queuedMessages
            .where((item) => item.id != message.id)
            .toList(),
      );
    }
    return accepted;
  }

  Future<Map<String, Object?>> forkThread({String? lastTurnId}) async {
    final submissionIds = _pendingSubmissionIds;
    final key = jsonEncode(['fork', _threadId, lastTurnId]);
    final operationId = submissionIds.putIfAbsent(key, _newClientMessageId);
    final result = await _host.request('codex.thread.fork', {
      'tabId': tabId,
      'expectedThreadId': _threadId,
      'lastTurnId': ?lastTurnId,
      'operationId': operationId,
    });
    submissionIds.remove(key);
    return result;
  }

  Future<bool> editUserMessage(
    CodexTimelineCell cell,
    String text, {
    required String? expectedThreadId,
    String? operationId,
    int? expectedHistoryRevision,
  }) async {
    final generation = _threadGeneration;
    try {
      if (expectedThreadId == null || expectedThreadId != _threadId) {
        throw StateError(
          'The conversation changed. Reopen the message editor.',
        );
      }
      final response = await _host.request('codex.thread.edit', {
        'tabId': tabId,
        'expectedThreadId': expectedThreadId,
        'turnId': cell.turnId,
        'itemId': ?cell.itemId,
        'text': text,
        'operationId': operationId ?? _newClientMessageId(),
        'expectedHistoryRevision':
            expectedHistoryRevision ?? state.historyRevision,
      });
      if (ref.mounted &&
          generation == _threadGeneration &&
          response['queue'] is Map) {
        _applyQueueSnapshot(
          Map<String, Object?>.from(response['queue']! as Map),
        );
      }
      return true;
    } catch (error) {
      if (ref.mounted) state = state.copyWith(error: _safeError(error));
      return false;
    }
  }
}
