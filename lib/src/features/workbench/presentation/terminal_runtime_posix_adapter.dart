part of 'terminal_runtime.dart';

class _PosixPortablePtySessionAdapter implements TerminalPtySession {
  final StreamController<TerminalPtySessionEvent> _events =
      StreamController<TerminalPtySessionEvent>.broadcast();
  PortablePty? _pty;
  ReceivePort? _readPort;
  StreamSubscription<Object?>? _readSub;
  Isolate? _readIsolate;
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
    Future<void> Function()? onProcessCreated,
  }) async {
    if (_disposed) {
      throw StateError('PTY session is disposed.');
    }
    final pty = PortablePty.open(rows: rows, cols: cols);
    _pty = pty;
    try {
      pty.spawn(
        launch.shell,
        args: launch.arguments,
        environment: launch.environment,
      );
      _startedNewProcess = true;
      _readPort = ReceivePort();
      _readSub = _readPort!.listen(_handleReadMessage);
      _readIsolate = await Isolate.spawn<List<Object?>>(
        _posixPtyReadIsolate,
        <Object?>[pty.masterFd, _readPort!.sendPort],
        debugName: 'alera-posix-pty-reader',
      );
      await onProcessCreated?.call();
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  @override
  bool writeBytes(List<int> bytes) {
    final pty = _pty;
    if (_disposed || pty == null || bytes.isEmpty) {
      return false;
    }
    return _writePtyBytes(bytes: bytes, write: pty.writeBytes, events: _events);
  }

  @override
  Future<bool> writeBytesAndWait(List<int> bytes) async => writeBytes(bytes);

  @override
  void resize(int cols, int rows, int cellWidthPx, int cellHeightPx) {
    final pty = _pty;
    if (_disposed || pty == null) {
      return;
    }
    _resizePty(
      rows: rows,
      cols: cols,
      resize: ({required rows, required cols}) =>
          pty.resize(rows: rows, cols: cols),
      events: _events,
    );
  }

  @override
  Future<void> setOutputPaused(bool paused) async {}

  void _handleReadMessage(Object? message) {
    if (_disposed) {
      return;
    }
    if (message is Uint8List) {
      _events.add(TerminalPtyOutputEvent(message));
      return;
    }
    if (message is Map<Object?, Object?>) {
      final type = message['type'];
      if (type == 'error') {
        _events.add(
          TerminalPtyErrorEvent(message['error'] ?? 'Unknown PTY read error'),
        );
      }
      if (type == 'done' || type == 'error') {
        _handleExit(_pty?.tryWait() ?? 0);
      }
    }
  }

  void _handleExit(int exitCode) {
    if (_disposed) {
      return;
    }
    _events.add(TerminalPtyExitEvent(exitCode));
    dispose();
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_readSub?.cancel());
    _readSub = null;
    _readPort?.close();
    _readPort = null;
    _readIsolate?.kill(priority: Isolate.immediate);
    _readIsolate = null;
    final pty = _pty;
    _pty = null;
    if (pty != null) {
      try {
        if (pty.tryWait() == null) {
          try {
            pty.kill();
          } catch (_) {
            // The child can exit between tryWait and kill.
          }
        }
      } finally {
        pty.close();
      }
    }
    unawaited(_events.close());
  }

  @override
  void terminate() {
    dispose();
  }
}
