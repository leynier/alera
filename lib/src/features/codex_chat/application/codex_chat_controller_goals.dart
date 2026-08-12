part of 'codex_chat_controller.dart';

// These extensions are split from the notifier only to keep the source files small.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

extension CodexChatControllerGoals on CodexChatController {
  Future<void> _refreshGoal({bool retryUnavailable = false}) async {
    final expectedThreadId = _threadId;
    final generation = _threadGeneration;
    if (!_goalCapabilityAdvertised ||
        (!state.supportsGoals && !retryUnavailable) ||
        expectedThreadId == null) {
      return;
    }
    try {
      final response = await _host.getGoal(tabId);
      if (!ref.mounted ||
          generation != _threadGeneration ||
          expectedThreadId != _threadId) {
        return;
      }
      _goalsAvailable = true;
      state = state.copyWith(
        supportsGoals: true,
        snapshot: state.snapshot.applyDelta(<String, Object?>{
          'goal': response['goal'],
        }),
      );
    } on Object catch (error) {
      if (!_goalOperationIsCurrent(expectedThreadId, generation) ||
          !_isUnsupportedGoalApiError(error)) {
        return;
      }
      _goalsAvailable = false;
      state = state.copyWith(supportsGoals: false);
    }
  }

  Future<bool> replaceGoal(
    String objective, {
    bool recordUserMessage = false,
  }) async {
    final trimmed = objective.trim();
    if (!state.supportsGoals || trimmed.isEmpty || trimmed.length > 4000) {
      return false;
    }
    return setGoal(trimmed, recordUserMessage: recordUserMessage);
  }

  Future<bool> setGoal(
    String objective, {
    bool recordUserMessage = false,
  }) async {
    final trimmed = objective.trim();
    if (!state.supportsGoals || trimmed.isEmpty || trimmed.length > 4000) {
      return false;
    }
    final expectedThreadId = _threadId;
    final generation = _threadGeneration;
    try {
      final response = await _host.setGoal(
        tabId,
        expectedThreadId: expectedThreadId,
        objective: trimmed,
        status: CodexThreadGoalStatus.active.wireName,
        recordUserMessage: recordUserMessage,
        clientUserMessageId: recordUserMessage ? _newClientMessageId() : null,
        configuration: _configurationPayload(state),
      );
      final goal = response['goal'];
      if (goal is Map) {
        final parsed = CodexThreadGoal.fromJson(goal);
        if (!_goalSetResponseIsCurrent(
          expectedThreadId,
          generation,
          parsed.threadId,
        )) {
          return false;
        }
        if (parsed.threadId.isNotEmpty && parsed.threadId != _threadId) {
          _threadId = parsed.threadId;
          _threadGeneration += 1;
        }
        state = state.copyWith(
          snapshot: state.snapshot.applyDelta(<String, Object?>{'goal': goal}),
          error: null,
        );
      }
      return true;
    } catch (error) {
      if (_goalOperationIsCurrent(expectedThreadId, generation)) {
        _applyGoalOperationError(error);
      }
      return false;
    }
  }

  Future<void> updateGoalStatus(CodexThreadGoalStatus status) async {
    final expectedThreadId = _threadId;
    final generation = _threadGeneration;
    if (!state.supportsGoals || state.snapshot.goal == null) return;
    try {
      final response = await _host.setGoal(
        tabId,
        expectedThreadId: expectedThreadId,
        status: status.wireName,
      );
      if (!_goalOperationIsCurrent(expectedThreadId, generation) ||
          response['goal'] is! Map) {
        return;
      }
      state = state.copyWith(
        snapshot: state.snapshot.applyDelta(<String, Object?>{
          'goal': response['goal'],
        }),
        error: null,
      );
    } catch (error) {
      if (_goalOperationIsCurrent(expectedThreadId, generation)) {
        _applyGoalOperationError(error);
      }
    }
  }

  Future<bool> editGoal(String objective) async {
    final goal = state.snapshot.goal;
    final expectedThreadId = _threadId;
    final generation = _threadGeneration;
    final trimmed = objective.trim();
    if (goal == null || trimmed.isEmpty || trimmed.length > 4000) return false;
    final preservedStatus = switch (goal.status) {
      CodexThreadGoalStatus.budgetLimited ||
      CodexThreadGoalStatus.complete => CodexThreadGoalStatus.active,
      final status => status,
    };
    try {
      final response = await _host.setGoal(
        tabId,
        expectedThreadId: expectedThreadId,
        objective: trimmed,
        status: preservedStatus.wireName,
      );
      if (!_goalOperationIsCurrent(expectedThreadId, generation) ||
          response['goal'] is! Map) {
        return false;
      }
      state = state.copyWith(
        snapshot: state.snapshot.applyDelta(<String, Object?>{
          'goal': response['goal'],
        }),
        error: null,
      );
      return true;
    } catch (error) {
      if (_goalOperationIsCurrent(expectedThreadId, generation)) {
        _applyGoalOperationError(error);
      }
      return false;
    }
  }

  Future<bool> clearGoal() async {
    final expectedThreadId = _threadId;
    final generation = _threadGeneration;
    if (!state.supportsGoals || state.snapshot.goal == null) return false;
    try {
      final response = await _host.clearGoal(
        tabId,
        expectedThreadId: expectedThreadId,
      );
      if (!_goalOperationIsCurrent(expectedThreadId, generation) ||
          response['cleared'] != true) {
        return false;
      }
      state = state.copyWith(
        snapshot: state.snapshot.applyDelta(const <String, Object?>{
          'goal': null,
        }),
        error: null,
      );
      return true;
    } catch (error) {
      if (_goalOperationIsCurrent(expectedThreadId, generation)) {
        _applyGoalOperationError(error);
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

  bool _isUnsupportedGoalApiError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('method not found') ||
        message.contains('unknown method') ||
        message.contains('goals feature is disabled') ||
        message.contains('-32601');
  }

  void _applyGoalOperationError(Object error) {
    final unsupported = _isUnsupportedGoalApiError(error);
    if (unsupported) _goalsAvailable = false;
    state = state.copyWith(
      supportsGoals: unsupported ? false : state.supportsGoals,
      error: _safeError(error),
    );
  }
}
