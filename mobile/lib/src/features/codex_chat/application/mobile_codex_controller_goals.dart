part of 'mobile_codex_controller.dart';

// These extensions are split from the notifier only to keep the source files small.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

extension MobileCodexControllerGoals on MobileCodexController {
  Future<MobileCodexState> _loadInitialGoal(
    MobileCodexClient client,
    MobileCodexState current,
  ) async {
    if (!client.supportsCodexGoals || _threadId == null) return current;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await client.codexRequest(
          'codex.goal.get',
          <String, Object?>{'tabId': tabId},
        );
        _goalsAvailable = true;
        _goalRefreshPending = false;
        return current.applySnapshotDelta(<String, Object?>{
          'goal': response['goal'],
        });
      } on Object catch (error, stackTrace) {
        if (attempt == 0) {
          await Future<void>.delayed(Duration.zero);
          continue;
        }
        if (_isUnsupportedMobileGoalApiError(error)) {
          _goalsAvailable = false;
          _goalRefreshPending = false;
        } else {
          _goalRefreshPending = true;
        }
        _logger.warning('Codex goals are unavailable.', error, stackTrace);
      }
    }
    return current;
  }

  Future<bool> replaceGoal(
    String objective, {
    bool recordUserMessage = false,
  }) async {
    final trimmed = objective.trim();
    if (!supportsGoals || trimmed.isEmpty || trimmed.length > 4000) {
      return false;
    }
    return setGoal(trimmed, recordUserMessage: recordUserMessage);
  }

  Future<bool> setGoal(
    String objective, {
    bool recordUserMessage = false,
  }) async {
    final client = _client;
    final current = state.value;
    final trimmed = objective.trim();
    if (client == null ||
        current == null ||
        !supportsGoals ||
        trimmed.isEmpty ||
        trimmed.length > 4000) {
      return false;
    }
    final expectedThreadId = _threadId;
    final generation = _threadGeneration;
    try {
      final response = await client
          .codexRequest('codex.goal.set', <String, Object?>{
            'tabId': tabId,
            'expectedThreadId': expectedThreadId,
            'objective': trimmed,
            'status': MobileCodexGoalStatus.active.wireName,
            'recordUserMessage': recordUserMessage,
            if (recordUserMessage) 'clientUserMessageId': _newClientMessageId(),
            'configuration': _mobileConfigurationPayload(current),
          });
      if (response['goal'] is! Map) return false;
      final goal = MobileCodexGoal.fromJson(response['goal']);
      if (!_goalSetResponseIsCurrent(
        expectedThreadId,
        generation,
        goal.threadId,
      )) {
        return false;
      }
      if (goal.threadId.isNotEmpty && goal.threadId != _threadId) {
        _threadId = goal.threadId;
        _threadGeneration += 1;
      }
      _goalRefreshPending = false;
      _update(
        (value) => value
            .applySnapshotDelta(<String, Object?>{'goal': response['goal']})
            .copyWith(error: null),
      );
      return true;
    } catch (error, stackTrace) {
      if (_goalOperationIsCurrent(expectedThreadId, generation)) {
        _applyMobileGoalOperationError(error);
        _setError(error, stackTrace);
      }
      return false;
    }
  }

  Future<bool> editGoal(String objective) async {
    final client = _client;
    final current = state.value;
    final goal = current?.goal;
    final expectedThreadId = _threadId;
    final generation = _threadGeneration;
    final trimmed = objective.trim();
    if (client == null || goal == null || trimmed.isEmpty) return false;
    final status = switch (goal.status) {
      MobileCodexGoalStatus.budgetLimited ||
      MobileCodexGoalStatus.complete => MobileCodexGoalStatus.active,
      final status => status,
    };
    try {
      final response = await client
          .codexRequest('codex.goal.set', <String, Object?>{
            'tabId': tabId,
            'expectedThreadId': expectedThreadId,
            'objective': trimmed,
            'status': status.wireName,
          });
      if (!_goalOperationIsCurrent(expectedThreadId, generation) ||
          response['goal'] is! Map) {
        return false;
      }
      _goalRefreshPending = false;
      _update(
        (value) => value
            .applySnapshotDelta(<String, Object?>{'goal': response['goal']})
            .copyWith(error: null),
      );
      return true;
    } catch (error, stackTrace) {
      if (_goalOperationIsCurrent(expectedThreadId, generation)) {
        _applyMobileGoalOperationError(error);
        _setError(error, stackTrace);
      }
      return false;
    }
  }

  Future<void> updateGoalStatus(MobileCodexGoalStatus status) async {
    final client = _client;
    final expectedThreadId = _threadId;
    final generation = _threadGeneration;
    if (client == null || !supportsGoals || state.value?.goal == null) return;
    try {
      final response = await client
          .codexRequest('codex.goal.set', <String, Object?>{
            'tabId': tabId,
            'expectedThreadId': expectedThreadId,
            'status': status.wireName,
          });
      if (!_goalOperationIsCurrent(expectedThreadId, generation) ||
          response['goal'] is! Map) {
        return;
      }
      _goalRefreshPending = false;
      _update(
        (value) => value
            .applySnapshotDelta(<String, Object?>{'goal': response['goal']})
            .copyWith(error: null),
      );
    } catch (error, stackTrace) {
      if (_goalOperationIsCurrent(expectedThreadId, generation)) {
        _applyMobileGoalOperationError(error);
        _setError(error, stackTrace);
      }
    }
  }

  Future<bool> clearGoal() async {
    final client = _client;
    final expectedThreadId = _threadId;
    final generation = _threadGeneration;
    if (client == null || !supportsGoals || state.value?.goal == null) {
      return false;
    }
    try {
      final response = await client.codexRequest(
        'codex.goal.clear',
        <String, Object?>{'tabId': tabId, 'expectedThreadId': expectedThreadId},
      );
      if (!_goalOperationIsCurrent(expectedThreadId, generation) ||
          response['cleared'] != true) {
        return false;
      }
      _goalRefreshPending = false;
      _update(
        (value) => value
            .applySnapshotDelta(const <String, Object?>{'goal': null})
            .copyWith(error: null),
      );
      return true;
    } catch (error, stackTrace) {
      if (_goalOperationIsCurrent(expectedThreadId, generation)) {
        _applyMobileGoalOperationError(error);
        _setError(error, stackTrace);
      }
      return false;
    }
  }

  bool _goalOperationIsCurrent(String? expectedThreadId, int generation) =>
      ref.mounted &&
      generation == _threadGeneration &&
      expectedThreadId == _threadId;

  bool _goalSetResponseIsCurrent(
    String? expectedThreadId,
    int generation,
    String responseThreadId,
  ) {
    if (!ref.mounted) return false;
    if (expectedThreadId != null) {
      return _goalOperationIsCurrent(expectedThreadId, generation);
    }
    return (generation == _threadGeneration && _threadId == null) ||
        (responseThreadId.isNotEmpty && responseThreadId == _threadId);
  }

  void _applyMobileGoalOperationError(Object error) {
    if (!_isUnsupportedMobileGoalApiError(error)) return;
    _goalsAvailable = false;
    _goalRefreshPending = false;
  }
}
