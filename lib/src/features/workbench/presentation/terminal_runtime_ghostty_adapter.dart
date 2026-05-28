part of 'terminal_runtime.dart';

class _GhosttyTerminalPtySessionAdapter implements TerminalPtySession {
  final StreamController<TerminalPtySessionEvent> _events =
      StreamController<TerminalPtySessionEvent>.broadcast();
  GhosttyTerminalPtySession? _session;
  StreamSubscription<GhosttyTerminalPtySessionEvent>? _sessionSub;
  bool _disposed = false;
  bool _startedNewProcess = false;

  @override
  Stream<TerminalPtySessionEvent> get events => _events.stream;

  @override
  bool get startedNewProcess => _startedNewProcess;

  @override
  Future<void> start({
    required GhosttyTerminalShellLaunch launch,
    required String workingDirectory,
    required int cols,
    required int rows,
  }) async {
    if (_disposed) {
      throw StateError('PTY session is disposed.');
    }
    final session = GhosttyTerminalPtySession(
      config: GhosttyTerminalPtySessionConfig(rows: rows, cols: cols),
    );
    _session = session;
    _sessionSub = session.events.listen(_handleGhosttyEvent);
    try {
      session.spawn(
        launch.shell,
        args: launch.arguments,
        environment: launch.environment,
      );
      _startedNewProcess = true;
    } catch (_) {
      unawaited(_sessionSub?.cancel());
      _sessionSub = null;
      _session = null;
      session.close();
      rethrow;
    }
  }

  void _handleGhosttyEvent(GhosttyTerminalPtySessionEvent event) {
    if (_disposed) {
      return;
    }
    switch (event) {
      case GhosttyTerminalPtyOutputEvent(:final data):
        _events.add(TerminalPtyOutputEvent(data));
      case GhosttyTerminalPtyExitEvent(:final exitCode):
        _events.add(TerminalPtyExitEvent(exitCode));
      case GhosttyTerminalPtyErrorEvent(:final error):
        _events.add(TerminalPtyErrorEvent(error));
      case GhosttyTerminalPtyStateChangeEvent():
        break;
    }
  }

  @override
  bool writeBytes(List<int> bytes) {
    final session = _session;
    if (_disposed || session == null || bytes.isEmpty) {
      return false;
    }
    return session.writeBytes(Uint8List.fromList(bytes)) > 0;
  }

  @override
  void resize(int cols, int rows, int cellWidthPx, int cellHeightPx) {
    if (_disposed) {
      return;
    }
    _session?.resize(rows: rows, cols: cols);
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_sessionSub?.cancel());
    _sessionSub = null;
    _session?.close();
    _session = null;
    unawaited(_events.close());
  }

  @override
  void terminate() {
    dispose();
  }
}

@visibleForTesting
TerminalPtySession createPosixPtySessionForTesting() {
  return _PosixPortablePtySessionAdapter();
}

@visibleForTesting
TerminalPtySession createGhosttyPtySessionForTesting() {
  return _GhosttyTerminalPtySessionAdapter();
}

@visibleForTesting
void handlePosixReadMessageForTesting(
  TerminalPtySession session,
  Object? message,
) {
  (session as _PosixPortablePtySessionAdapter)._handleReadMessage(message);
}

@visibleForTesting
void handleGhosttyEventForTesting(
  TerminalPtySession session,
  GhosttyTerminalPtySessionEvent event,
) {
  (session as _GhosttyTerminalPtySessionAdapter)._handleGhosttyEvent(event);
}
