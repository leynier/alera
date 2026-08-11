part of 'codex_chat_controller.dart';

// Event handling is split from the notifier to keep the controller focused.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

const _deferredThreadContextKeys = <String>{
  'configuration',
  'cwd',
  'historyNextCursor',
  'recovery',
  'threadId',
};

extension CodexChatControllerEvents on CodexChatController {
  void _onRuntimeEvent(RuntimeHostEvent event) {
    if (event.name == aleraRuntimeHostConnectedEvent) {
      if (!state.loading) unawaited(_refreshCapabilities());
      return;
    }
    if (event.name == 'codexCatalogChanged') {
      unawaited(_loadCatalogues());
      return;
    }
    if (event.name == 'codexServerChanged') {
      if (!ref.mounted) return;
      final status = event.payload['status']?.toString();
      if (status == 'error') {
        state = state.copyWith(
          error: _safeError(event.payload['error'] ?? 'Codex server failed.'),
        );
      }
      return;
    }
    if (event.name != 'codexThreadChanged' || event.payload['tabId'] != tabId) {
      return;
    }
    if (_opening) {
      _deferRuntimeThreadEvent(event);
      return;
    }
    _applyRuntimeThreadEvent(event);
  }

  void _deferRuntimeThreadEvent(RuntimeHostEvent event) {
    if (event.payload['snapshot'] is Map) {
      final payload = Map<String, Object?>.of(event.payload);
      final eventThreadId = payload.containsKey('threadId')
          ? _string(payload['threadId'])
          : _threadId;
      for (final deferred in _deferredThreadEvents.reversed) {
        final deferredThreadId = deferred.payload.containsKey('threadId')
            ? _string(deferred.payload['threadId'])
            : _threadId;
        if (eventThreadId != deferredThreadId) {
          break;
        }
        for (final key in _deferredThreadContextKeys) {
          if (!payload.containsKey(key) && deferred.payload.containsKey(key)) {
            payload[key] = deferred.payload[key];
          }
        }
      }
      _deferredThreadEvents
        ..clear()
        ..add(RuntimeHostEvent(event.name, payload));
      return;
    }
    _deferredThreadEvents.add(event);
    const deferredEventLimit = 64;
    if (_deferredThreadEvents.length > deferredEventLimit) {
      _deferredThreadEvents.removeRange(
        0,
        _deferredThreadEvents.length - deferredEventLimit,
      );
    }
  }

  void _applyRuntimeThreadEvent(RuntimeHostEvent event) {
    var configured = _applyConfiguration(state, event.payload['configuration']);
    if (event.payload.containsKey('recovery')) {
      configured = configured.copyWith(
        recovery: event.payload['recovery'] == null
            ? null
            : CodexThreadRecovery.fromJson(event.payload['recovery']),
      );
    }
    final previousThreadId = _threadId;
    final eventHasThreadId = event.payload.containsKey('threadId');
    final eventThreadId = eventHasThreadId
        ? _string(event.payload['threadId'])
        : previousThreadId;
    final threadChanged = eventHasThreadId && eventThreadId != previousThreadId;
    final previousCwd = state.activeCwd;
    final activeCwd = _string(event.payload['cwd']) ?? previousCwd;
    final catalogueContextChanged = threadChanged || activeCwd != previousCwd;
    final historyNextCursor = event.payload.containsKey('historyNextCursor')
        ? _string(event.payload['historyNextCursor'])
        : threadChanged
        ? null
        : state.historyNextCursor;
    final delta = event.payload['snapshotDelta'];
    final snapshot = event.payload['snapshot'];
    final incoming = snapshot is Map
        ? CodexChatSnapshot.fromJson(snapshot)
        : null;
    final next = eventThreadId != previousThreadId
        ? incoming
        : delta is Map && delta.isNotEmpty && incoming != null
        ? _reconcileSameThreadSnapshot(state.snapshot, incoming, delta)
        : delta is Map
        ? state.snapshot.applyDelta(delta)
        : incoming == null
        ? null
        : _mergeSameThreadSnapshot(state.snapshot, incoming);
    if (next == null) {
      if (!ref.mounted) return;
      if (eventHasThreadId) {
        _threadId = eventThreadId;
        if (threadChanged) _threadGeneration += 1;
      }
      state = configured.copyWith(
        activeCwd: activeCwd,
        historyNextCursor: historyNextCursor,
      );
      if (catalogueContextChanged) unawaited(_loadCatalogues());
      return;
    }
    if (!ref.mounted) return;
    if (eventHasThreadId) {
      _threadId = eventThreadId;
      if (threadChanged) _threadGeneration += 1;
    }
    if (!next.isBusy) _interruptSafetyTimer?.cancel();
    state = configured.copyWith(
      snapshot: next,
      activeCwd: activeCwd,
      historyNextCursor: historyNextCursor,
      sending: next.isBusy ? state.sending : false,
      interrupting: next.isBusy ? state.interrupting : false,
      error: null,
    );
    if (catalogueContextChanged) unawaited(_loadCatalogues());
    _drainQueuedMessageIfIdle();
  }
}
