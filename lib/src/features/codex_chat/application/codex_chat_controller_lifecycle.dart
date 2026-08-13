part of 'codex_chat_controller.dart';

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

extension CodexChatControllerLifecycle on CodexChatController {
  Future<void> _load() async {
    final generation = ++_loadGeneration;
    _opening = true;
    try {
      final open = await _host.openThread(tabId);
      if (!ref.mounted || generation != _loadGeneration) return;
      _threadId = _string(open['threadId']);
      _threadGeneration += 1;
      final storedConfiguration = open['configuration'];
      state = _applyConfiguration(
        state.copyWith(
          loading: false,
          snapshot: CodexChatSnapshot.fromJson(open['snapshot']),
          activeCwd: _string(open['cwd']),
          historyNextCursor: _string(open['historyNextCursor']),
          recovery: open['recovery'] == null
              ? null
              : CodexThreadRecovery.fromJson(open['recovery']),
          error: null,
        ),
        storedConfiguration,
      );
      _finishOpening(generation);
      _drainQueuedMessageIfIdle();
      await _refreshCapabilities();
      if (!ref.mounted || generation != _loadGeneration) return;
      await _refreshGoal();
      if (!ref.mounted || generation != _loadGeneration) return;
      await _loadCatalogues();
      if (storedConfiguration == null) _persistTabConfiguration();
    } catch (error) {
      if (!ref.mounted || generation != _loadGeneration) return;
      state = state.copyWith(loading: false, error: _safeError(error));
      _finishOpening(generation);
    }
  }

  void _finishOpening(int generation) {
    if (!ref.mounted || generation != _loadGeneration) return;
    _opening = false;
    final deferred = List<RuntimeHostEvent>.of(_deferredThreadEvents);
    _deferredThreadEvents.clear();
    for (final event in deferred) {
      _applyRuntimeThreadEvent(event);
    }
  }
}
