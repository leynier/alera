part of 'mobile_codex_controller.dart';

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

extension _MobileCodexDelivery on MobileCodexController {
  Future<void> _stopCapturedTurn() async {
    final client = _client;
    final current = state.value;
    final generation = _threadGeneration;
    final threadId = _threadId;
    if (client == null || current == null || current.interrupting) {
      return;
    }
    final turnId = current.activeTurnId;
    if ((!current.supportsSharedQueue || turnId == null) &&
        !await queueAction('pause')) {
      return;
    }
    if (!ref.mounted ||
        generation != _threadGeneration ||
        turnId == null ||
        state.value?.interrupting == true) {
      return;
    }
    _update((value) => value.copyWith(interrupting: true, error: null));
    _interruptSafetyTimer?.cancel();
    _interruptSafetyTimer = Timer(const Duration(seconds: 2), () {
      if (ref.mounted) {
        _update((value) => value.copyWith(interrupting: false, sending: false));
      }
    });
    try {
      await client.codexRequest('codex.turn.interrupt', <String, Object?>{
        'tabId': tabId,
        'turnId': turnId,
        if (current.supportsSharedQueue) 'expectedThreadId': threadId,
      });
    } catch (error, stackTrace) {
      _interruptSafetyTimer?.cancel();
      _setError(error, stackTrace);
    }
  }

  Future<bool> _deliverMessage(Map<String, Object?> message) async {
    final client = _client;
    if (client == null) return false;
    final current = state.value ?? const MobileCodexState();
    if (state.isLoading || state.hasError || current.historyOutdated) {
      return false;
    }
    final generation = _threadGeneration;
    final supportsTurnPolicy = client.supportsCodexTurnPolicy;
    final wirePermissionMode =
        !supportsTurnPolicy && current.permissionMode == 'auto-review'
        ? 'on-request'
        : current.permissionMode;
    state = AsyncData(current.copyWith(sending: true, error: null));
    try {
      final response = await client.codexRequest(
        current.supportsSharedQueue ? 'codex.queue.add' : 'codex.turn.start',
        <String, Object?>{
          'draft': message,
          'expectedHistoryRevision': current.historyRevision,
          'tabId': tabId,
          'expectedThreadId': _threadId,
          'clientUserMessageId':
              message['id']?.toString() ?? _newClientMessageId(),
          'input': _input(message, current),
          'userMessage': _userMessagePresentation(
            message,
            cwd: current.activeCwd,
          ),
          'model': current.selectedModel,
          'reasoning': <String, Object?>{'effort': current.reasoningEffort},
          'effort': current.reasoningEffort,
          'serviceTier': current.speedMode == 'fast' ? 'fast' : null,
          'approvalPolicy': supportsTurnPolicy
              ? switch (current.permissionMode) {
                  'never' => 'never',
                  'untrusted' => 'untrusted',
                  _ => 'on-request',
                }
              : wirePermissionMode,
          if (supportsTurnPolicy)
            'approvalsReviewer': current.permissionMode == 'auto-review'
                ? 'auto_review'
                : 'user',
          if (supportsTurnPolicy)
            'sandboxPolicy': current.permissionMode == 'never'
                ? <String, Object?>{'type': 'dangerFullAccess'}
                : <String, Object?>{
                    'type': 'workspaceWrite',
                    'writableRoots': const <String>[],
                    'networkAccess': false,
                  },
          'collaborationMode': <String, Object?>{
            'mode':
                current.collaborationMode ??
                (current.planMode ? 'plan' : 'default'),
            'settings': <String, Object?>{
              'model': current.selectedModel,
              'reasoning_effort': current.reasoningEffort,
            },
          },
          'configuration': <String, Object?>{
            ..._mobileConfigurationPayload(current),
            'permissionMode': wirePermissionMode,
          },
        },
      );
      if (ref.mounted && generation == _threadGeneration) {
        state = AsyncData((state.value ?? current).copyWith(sending: false));
        if (current.supportsSharedQueue) {
          _threadId ??= _string(response['threadId']);
          _update((value) => _withSharedQueue(value, response));
        }
      }
      return true;
    } catch (error, stackTrace) {
      if (ref.mounted && generation == _threadGeneration) {
        _setError(error, stackTrace);
      }
      return false;
    }
  }
}
