part of 'mobile_codex_controller.dart';

mixin _MobileCodexControllerLifecycle on _$MobileCodexController {
  MobileCodexClient? get _client;
  Logger get _logger;
  Timer? get _interruptSafetyTimerValue;
  Future<void> _sendNow(Map<String, Object?> message);

  void _onEvent(MobileRuntimeEvent event) {
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
      }
      return;
    }
    if (event.name != 'codexThreadChanged' || event.payload['tabId'] != tabId) {
      return;
    }
    final next = MobileCodexState.fromSnapshot(event.payload['snapshot']);
    final current = state.value;
    if (current == null) return;
    if (!next.busy) _interruptSafetyTimerValue?.cancel();
    state = AsyncData(
      next.copyWith(
        models: current.models,
        collaborationModes: current.collaborationModes,
        skills: current.skills,
        apps: current.apps,
        selectedModel: current.selectedModel,
        reasoningEffort: current.reasoningEffort,
        speedMode: current.speedMode,
        permissionMode: current.permissionMode,
        planMode: current.planMode,
        collaborationMode: current.collaborationMode,
        queuedMessages: current.queuedMessages,
        sending: next.busy ? current.sending : false,
        interrupting: next.busy ? current.interrupting : false,
        error: null,
      ),
    );
    if (!next.busy && current.queuedMessages.isNotEmpty) {
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
