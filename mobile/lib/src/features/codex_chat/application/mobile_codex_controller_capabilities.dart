part of 'mobile_codex_controller.dart';

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

extension MobileCodexControllerCapabilities on MobileCodexController {
  int get threadGeneration => _threadGeneration;

  bool get supportsSessions => _client?.supportsCodexSessions == true;

  bool get supportsTurnPolicy => _client?.supportsCodexTurnPolicy == true;

  bool get supportsGoals =>
      _goalsAvailable && _client?.supportsCodexGoals == true;

  Future<void> _refreshGoalAvailability() async {
    final client = _client;
    final expectedThreadId = _threadId;
    final generation = _threadGeneration;
    if ((_goalsAvailable && !_goalRefreshPending) ||
        client == null ||
        state.value == null ||
        !client.supportsCodexGoals ||
        expectedThreadId == null) {
      return;
    }
    try {
      final response = await client.codexRequest(
        'codex.goal.get',
        <String, Object?>{'tabId': tabId},
      );
      if (!ref.mounted ||
          generation != _threadGeneration ||
          expectedThreadId != _threadId) {
        return;
      }
      _goalsAvailable = true;
      _goalRefreshPending = false;
      _update(
        (latest) => latest.applySnapshotDelta(<String, Object?>{
          'goal': response['goal'],
        }),
      );
    } on Object catch (error, stackTrace) {
      if (_isUnsupportedMobileGoalApiError(error)) {
        _goalsAvailable = false;
        _goalRefreshPending = false;
        _update((latest) => latest.copyWith());
      } else {
        _goalRefreshPending = true;
      }
      _logger.warning('Codex goals are unavailable.', error, stackTrace);
    }
  }
}

bool _isUnsupportedMobileGoalApiError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('method not found') ||
      message.contains('unknown method') ||
      message.contains('goals feature is disabled') ||
      message.contains('-32601');
}
