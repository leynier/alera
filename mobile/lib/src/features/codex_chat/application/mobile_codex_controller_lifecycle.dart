part of 'mobile_codex_controller.dart';

mixin _MobileCodexControllerLifecycle on _$MobileCodexController {
  MobileCodexClient? get _client;
  Logger get _logger;
  Timer? get _interruptSafetyTimerValue;
  List<MobileRuntimeEvent> get _deferredThreadEvents;
  Timer? get _deferredThreadEventTimer;
  set _deferredThreadEventTimer(Timer? value);
  bool get _sessionTransitionInProgress;
  String? get _threadId;
  set _threadId(String? value);
  int get _threadGeneration;
  set _threadGeneration(int value);
  Future<void> _sendNow(Map<String, Object?> message);
  Future<void> _reloadCatalogue(String catalog);
  Future<void> _retryGoalAvailability();

  MobileCodexState? get _currentState => state.value;

  bool get _isMounted => ref.mounted;

  void _onEvent(MobileRuntimeEvent event) {
    if (event.name == 'codexCatalogChanged') {
      final catalog = event.payload['catalog']?.toString();
      if (catalog != null) unawaited(_reloadCatalogue(catalog));
      return;
    }
    if (event.name == 'codexServerChanged') {
      final current = state.value;
      if (current == null) return;
      final status = event.payload['status']?.toString();
      if (status == 'error') {
        _logger.warning(
          'Codex app-server reported an error.',
          event.payload['error'],
        );
        state = AsyncData(
          current.copyWith(
            error: _safeError(event.payload['error'] ?? 'Codex server failed.'),
          ),
        );
      } else if (status == 'ready') {
        unawaited(_retryGoalAvailability());
      }
      return;
    }
    if (event.name != 'codexThreadChanged' || event.payload['tabId'] != tabId) {
      return;
    }
    final current = state.value;
    if (current == null ||
        _deferredThreadEvents.isNotEmpty ||
        _deferredThreadEventTimer != null) {
      _deferThreadEvent(event);
      return;
    }
    _applyThreadEvent(current, event);
  }

  void _deferThreadEvent(MobileRuntimeEvent event) {
    if (event.payload['snapshot'] is Map) {
      final retained = <MobileRuntimeEvent>[];
      var segmentThreadId = _threadId;
      var segmentHasBaseSnapshot = segmentThreadId != null;
      for (final deferred in _deferredThreadEvents) {
        final deferredThreadId = deferred.payload.containsKey('threadId')
            ? _string(deferred.payload['threadId'])
            : segmentThreadId;
        if (deferredThreadId != segmentThreadId) {
          segmentThreadId = deferredThreadId;
          segmentHasBaseSnapshot = false;
        }
        if (deferred.payload['snapshot'] is Map && segmentHasBaseSnapshot) {
          final payload = Map<String, Object?>.from(deferred.payload)
            ..remove('snapshot');
          if (payload['snapshotDelta'] is Map) {
            retained.add(MobileRuntimeEvent(deferred.name, payload));
          }
          continue;
        }
        retained.add(deferred);
        if (deferred.payload['snapshot'] is Map) {
          segmentHasBaseSnapshot = true;
        }
      }
      _deferredThreadEvents
        ..clear()
        ..addAll(retained);
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

  void _scheduleDeferredThreadEventDrain() {
    if (_deferredThreadEvents.isEmpty || _deferredThreadEventTimer != null) {
      return;
    }
    _deferredThreadEventTimer = Timer(.zero, _drainDeferredThreadEvent);
  }

  void _drainDeferredThreadEvent() {
    _deferredThreadEventTimer = null;
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null) {
      _deferredThreadEventTimer = Timer(
        const Duration(milliseconds: 1),
        _drainDeferredThreadEvent,
      );
      return;
    }
    final events = List<MobileRuntimeEvent>.of(_deferredThreadEvents);
    _deferredThreadEvents.clear();
    var next = current;
    for (final event in events) {
      _applyThreadEvent(
        next,
        event,
        forceSnapshot: event.payload['snapshot'] is Map,
      );
      next = state.value ?? next;
    }
  }

  void _applyThreadEvent(
    MobileCodexState current,
    MobileRuntimeEvent event, {
    bool forceSnapshot = false,
  }) {
    final previousThreadId = _threadId;
    final eventHasThreadId = event.payload.containsKey('threadId');
    final eventThreadId = eventHasThreadId
        ? _string(event.payload['threadId'])
        : previousThreadId;
    final threadChanged = eventHasThreadId && eventThreadId != previousThreadId;
    final sameThread = eventThreadId == previousThreadId;
    final delta = event.payload['snapshotDelta'];
    final snapshot = event.payload['snapshot'];
    final next = !sameThread && snapshot is Map
        ? MobileCodexState.fromSnapshot(snapshot)
        : delta is Map && delta.isNotEmpty && snapshot is Map
        ? _reconcileMobileSameThreadSnapshot(
            current,
            .fromSnapshot(snapshot, deriveTimeline: false),
            delta,
          )
        : delta is Map
        ? current.applySnapshotDelta(delta)
        : snapshot is Map
        ? sameThread && !forceSnapshot
              ? _mergeMobileSameThreadSnapshot(current, .fromSnapshot(snapshot))
              : MobileCodexState.fromSnapshot(snapshot)
        : null;
    var configured = _applyMobileConfiguration(
      current,
      event.payload['configuration'],
    );
    if (event.payload.containsKey('recovery')) {
      configured = configured.copyWith(
        recovery: event.payload['recovery'] == null
            ? null
            : MobileCodexThreadRecovery.fromJson(event.payload['recovery']),
      );
    }
    if (next == null) {
      if (eventHasThreadId) {
        _threadId = eventThreadId;
        if (threadChanged) _threadGeneration += 1;
      }
      state = AsyncData(
        configured.copyWith(
          activeCwd: event.payload['cwd']?.toString() ?? configured.activeCwd,
          historyNextCursor: event.payload.containsKey('historyNextCursor')
              ? _string(event.payload['historyNextCursor'])
              : configured.historyNextCursor,
        ),
      );
      return;
    }
    if (eventHasThreadId) {
      _threadId = eventThreadId;
      if (threadChanged) _threadGeneration += 1;
    }
    if (!next.busy) _interruptSafetyTimerValue?.cancel();
    state = AsyncData(
      next.copyWith(
        models: configured.models,
        collaborationModes: configured.collaborationModes,
        skills: configured.skills,
        apps: configured.apps,
        selectedModel: configured.selectedModel,
        reasoningEffort: configured.reasoningEffort,
        speedMode: configured.speedMode,
        permissionMode: configured.permissionMode,
        planMode: configured.planMode,
        collaborationMode: configured.collaborationMode,
        queuedMessages: configured.queuedMessages,
        activeCwd: event.payload['cwd']?.toString() ?? configured.activeCwd,
        historyNextCursor: event.payload.containsKey('historyNextCursor')
            ? _string(event.payload['historyNextCursor'])
            : configured.historyNextCursor,
        sending: next.busy ? configured.sending : false,
        interrupting: next.busy ? configured.interrupting : false,
        recovery: configured.recovery,
        error: null,
      ),
    );
    if (!next.busy &&
        !_sessionTransitionInProgress &&
        current.queuedMessages.isNotEmpty) {
      final message = current.queuedMessages.first;
      _update(
        (value) => value.copyWith(
          queuedMessages: value.queuedMessages.skip(1).toList(growable: false),
        ),
      );
      unawaited(_sendNow(message));
    }
  }

  Future<void> _simpleRequest(
    String request, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.codexRequest(request, <String, Object?>{
        'tabId': tabId,
        ...payload,
      });
    } catch (error, stackTrace) {
      _setError(error, stackTrace);
    }
  }

  void _update(MobileCodexState Function(MobileCodexState) update) {
    final current = state.value;
    if (current != null) state = AsyncData(update(current));
  }

  void _setError(Object error, StackTrace stackTrace) {
    _logger.warning('Codex request failed.', error, stackTrace);
    if (!ref.mounted) {
      Error.throwWithStackTrace(error, stackTrace);
    }
    _update(
      (current) => current.copyWith(
        sending: false,
        interrupting: false,
        error: _safeError(error),
      ),
    );
  }
}
