part of 'codex_chat_controller.dart';

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

extension CodexChatControllerLifecycle on CodexChatController {
  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final previousOpening = _openingResult;
    if (previousOpening != null && !previousOpening.isCompleted) {
      previousOpening.complete(false);
    }
    final openingResult = Completer<bool>();
    _openingResult = openingResult;
    _opening = true;
    try {
      final open = await _host.openThread(tabId);
      if (!ref.mounted || generation != _loadGeneration) return;
      final nextThreadId = _string(open['threadId']);
      final resetQueue = _threadId != null && _threadId != nextThreadId;
      _threadId = nextThreadId;
      _threadGeneration += 1;
      final storedConfiguration = open['configuration'];
      state = _applyConfiguration(
        state.copyWith(
          queueState: resetQueue ? const {} : state.queueState,
          queuedMessages: resetQueue ? const [] : state.queuedMessages,
          chatFeatures:
              (open['chatFeatures'] as List?)?.whereType<String>().toSet() ??
              const {},
          historyRevision: open['historyRevision'] as int? ?? 0,
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
      if (open['queue'] is Map && state.supportsSharedQueue) {
        _applyQueueSnapshot(Map<String, Object?>.from(open['queue']! as Map));
      }
      _finishOpening(generation);
      if (!openingResult.isCompleted) openingResult.complete(true);
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
    } finally {
      if (!openingResult.isCompleted) openingResult.complete(false);
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
