part of 'mobile_codex_controller.dart';

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

MobileCodexState _withSharedQueue(
  MobileCodexState current,
  Map<String, Object?> queue,
) {
  if ((queue['revision'] as int? ?? 0) <
      (current.queueState['revision'] as int? ?? 0)) {
    return current;
  }
  final messages = queue['messages'];
  return current.copyWith(
    queueState: queue,
    queuedMessages: messages is List
        ? [
            for (final entry in messages.whereType<Map>())
              {
                ...Map<String, Object?>.from(
                  (entry['payload'] as Map?)?['draft'] as Map? ??
                      (entry['payload'] as Map?)?['userMessage'] as Map? ??
                      const {},
                ),
                'id': entry['id'],
                'status': entry['status'],
                'error': entry['error'],
                'payload': entry['payload'],
              },
          ]
        : const [],
  );
}

extension MobileCodexControllerSharedQueue on MobileCodexController {
  Future<bool> removeQueuedMessageById(String id, {int? revision}) async {
    final current = state.value;
    if (current == null) return false;
    if (current.supportsSharedQueue) {
      return queueAction('remove', messageId: id, revision: revision);
    }
    final remaining = current.queuedMessages
        .where((message) => message['id'] != id)
        .toList();
    if (remaining.length == current.queuedMessages.length) return false;
    _update((value) => value.copyWith(queuedMessages: remaining));
    return true;
  }

  String newHistoryOperationId() => _newClientMessageId();

  String? get threadId => _threadId;

  Future<void> retryHistoryEdit(String operationId) async {
    try {
      final response = await _client!.codexRequest('codex.thread.edit', {
        'tabId': tabId,
        'expectedThreadId': _threadId,
        'operationId': operationId,
      });
      if (ref.mounted) {
        _update(
          (current) => _withSharedQueue(
            current,
            Map<String, Object?>.from(response['queue'] as Map? ?? response),
          ),
        );
      }
    } catch (error, stackTrace) {
      _setError(error, stackTrace);
    }
  }

  Future<void> refreshQueue() async {
    if (state.value?.supportsSharedQueue != true) return;
    final generation = _threadGeneration;
    try {
      final response = await _client!.codexRequest('codex.queue.get', {
        'tabId': tabId,
        'expectedThreadId': _threadId,
      });
      if (ref.mounted && generation == _threadGeneration) {
        _update((current) => _withSharedQueue(current, response));
      }
    } catch (error, stackTrace) {
      if (ref.mounted && generation == _threadGeneration) {
        _setError(error, stackTrace);
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
    final current = state.value;
    if (current != null &&
        !current.supportsSharedQueue &&
        (action == 'pause' || action == 'resume')) {
      _update(
        (value) => value.copyWith(
          queueState: {...value.queueState, 'paused': action == 'pause'},
        ),
      );
      if (action == 'resume' &&
          !current.busy &&
          current.queuedMessages.isNotEmpty) {
        final message = current.queuedMessages.first;
        _update(
          (value) => value.copyWith(
            queuedMessages: value.queuedMessages.skip(1).toList(),
          ),
        );
        unawaited(_sendNow(message));
      }
      return true;
    }
    final generation = _threadGeneration;
    try {
      final response = await _client!.codexRequest('codex.queue.$action', {
        'tabId': tabId,
        'expectedThreadId': _threadId,
        'operationId': _newClientMessageId(),
        'expectedRevision': revision ?? state.value?.queueState['revision'],
        'messageId': ?messageId,
        'message': ?message,
        'turnId': ?turnId,
      });
      if (!ref.mounted || generation != _threadGeneration) return false;
      _update((current) => _withSharedQueue(current, response));
      return true;
    } catch (error, stackTrace) {
      await refreshQueue();
      _setError(error, stackTrace);
      return false;
    }
  }

  Future<bool> saveQueuedMessage(
    Map<String, Object?> original,
    String text, {
    int? revision,
  }) async {
    final current = state.value;
    if (current == null) return false;
    if (!current.supportsSharedQueue) {
      final index = current.queuedMessages.indexWhere(
        (entry) => entry['id'] == original['id'],
      );
      if (index < 0) return false;
      final editedText = text.trim();
      editQueuedMessage(
        index,
        editedText,
        catalogSelections: mobileCodexRebaseCatalogSelections(
          TextEditingValue(text: original['text']?.toString() ?? ''),
          TextEditingValue(text: editedText),
          [
            for (final selection
                in (original['catalogSelections'] as List? ?? const [])
                    .whereType<Map>())
              Map<String, Object?>.from(selection),
          ],
        ),
      );
      return true;
    }
    final draft = {...original, 'text': text};
    return queueAction(
      'edit',
      messageId: original['id']?.toString(),
      revision: revision,
      message: {
        'input': _input(draft, current),
        'userMessage': _userMessagePresentation(draft, cwd: current.activeCwd),
        'draft': {
          'text': text,
          'attachments': original['attachments'],
          'catalogSelections': original['catalogSelections'],
        },
      },
    );
  }

  Future<bool> steerQueuedMessage(
    Map<String, Object?> message, {
    int? revision,
  }) async {
    final current = state.value;
    if (current == null ||
        current.activeTurnId == null ||
        current.interrupting ||
        current.historyLocked) {
      return false;
    }
    if (current.supportsSharedQueue) {
      return queueAction(
        'steer',
        messageId: message['id']?.toString(),
        turnId: current.activeTurnId,
        revision: revision,
      );
    }
    final accepted = await steer(
      message['text']?.toString() ?? '',
      attachments: [
        for (final a
            in (message['attachments'] as List? ?? const []).whereType<Map>())
          Map<String, Object?>.from(a),
      ],
      catalogSelections: [
        for (final a
            in (message['catalogSelections'] as List? ?? const [])
                .whereType<Map>())
          Map<String, Object?>.from(a),
      ],
    );
    if (accepted) {
      _update(
        (value) => value.copyWith(
          queuedMessages: value.queuedMessages
              .where((entry) => entry['id'] != message['id'])
              .toList(),
        ),
      );
    }
    return accepted;
  }

  Future<Map<String, Object?>> forkThread({String? lastTurnId}) async {
    final submissionIds = _pendingSubmissionIds;
    final key = jsonEncode(['fork', _threadId, lastTurnId]);
    final operationId = submissionIds.putIfAbsent(key, _newClientMessageId);
    final result = await _client!.codexRequest('codex.thread.fork', {
      'tabId': tabId,
      'expectedThreadId': _threadId,
      'lastTurnId': ?lastTurnId,
      'operationId': operationId,
    });
    submissionIds.remove(key);
    return result;
  }

  Future<bool> editUserMessage(
    MobileCodexTimelineCell cell,
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
      final response = await _client!.codexRequest('codex.thread.edit', {
        'tabId': tabId,
        'expectedThreadId': expectedThreadId,
        'turnId': cell.turnId,
        'itemId': ?cell.itemId,
        'text': text,
        'operationId': operationId ?? _newClientMessageId(),
        'expectedHistoryRevision':
            expectedHistoryRevision ?? state.value?.historyRevision ?? 0,
      });
      if (ref.mounted &&
          generation == _threadGeneration &&
          response['queue'] is Map) {
        _update(
          (current) => _withSharedQueue(
            current,
            Map<String, Object?>.from(response['queue']! as Map),
          ),
        );
      }
      return true;
    } catch (error, stackTrace) {
      _setError(error, stackTrace);
      return false;
    }
  }
}
