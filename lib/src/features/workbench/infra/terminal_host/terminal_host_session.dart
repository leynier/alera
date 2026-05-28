part of 'terminal_host_server.dart';

final class _TerminalHostSession {
  _TerminalHostSession._(
    this.id,
    this.workspaceId,
    this.tabId,
    this.workingDirectory,
    this._historyStore,
    this._pty,
    this._running,
    List<int> buffer,
    this._exitCode,
    this._endedAt,
    int maxBufferBytes,
    this._onLifecycleChanged,
  ) : _buffer = _TerminalHostByteBuffer(maxBufferBytes, buffer);

  static Future<_TerminalHostSession> start({
    required String id,
    required String workspaceId,
    required String tabId,
    required String workingDirectory,
    required TerminalHostLaunch launch,
    required int cols,
    required int rows,
    required TerminalHostHistoryStore historyStore,
    required int maxBufferBytes,
    required void Function() onLifecycleChanged,
  }) async {
    final pty = PortablePty.open(rows: rows, cols: cols);
    try {
      pty.spawn(
        launch.shell,
        args: launch.arguments,
        environment: launch.environment,
      );
    } catch (_) {
      pty.close();
      rethrow;
    }
    final session = _TerminalHostSession._(
      id,
      workspaceId,
      tabId,
      workingDirectory,
      historyStore,
      pty,
      true,
      const <int>[],
      null,
      null,
      maxBufferBytes,
      onLifecycleChanged,
    );
    await session._writeCheckpoint();
    await session._startReader(pty);
    return session;
  }

  static Future<_TerminalHostSession?> restoreExited({
    required String sessionId,
    required String workspaceId,
    required String tabId,
    required TerminalHostHistoryStore historyStore,
    required int maxBufferBytes,
    required void Function() onLifecycleChanged,
  }) async {
    try {
      final checkpoint = historyStore.read(sessionId);
      if (checkpoint == null) {
        return null;
      }
      if (checkpoint.endedAt == null) {
        return _TerminalHostSession._(
          sessionId,
          workspaceId,
          tabId,
          checkpoint.workingDirectory,
          historyStore,
          null,
          false,
          checkpoint.buffer,
          -1,
          null,
          maxBufferBytes,
          onLifecycleChanged,
        );
      }
      return _TerminalHostSession._(
        sessionId,
        workspaceId,
        tabId,
        checkpoint.workingDirectory,
        historyStore,
        null,
        false,
        checkpoint.buffer,
        checkpoint.exitCode ?? 0,
        checkpoint.endedAt,
        maxBufferBytes,
        onLifecycleChanged,
      );
    } catch (_) {
      return null;
    }
  }

  final String id;
  final String workspaceId;
  final String tabId;
  final String workingDirectory;
  final TerminalHostHistoryStore _historyStore;
  final Set<_TerminalHostClientConnection> _clients =
      <_TerminalHostClientConnection>{};

  PortablePty? _pty;
  Isolate? _reader;
  ReceivePort? _readerPort;
  StreamSubscription<Object?>? _readerSub;
  Timer? _checkpointTimer;
  final _TerminalHostByteBuffer _buffer;
  final void Function() _onLifecycleChanged;
  bool _running;
  int? _exitCode;
  DateTime? _endedAt;
  bool _terminated = false;

  bool get running => _running;

  Map<String, Object?> attachmentPayload({required bool created}) {
    return <String, Object?>{
      'sessionId': id,
      'created': created,
      'running': _running,
      'exitCode': _exitCode,
      'snapshotBase64': _buffer.toBase64(),
    };
  }

  void updateConfig({required int maxBufferBytes}) {
    _buffer.maxBytes = maxBufferBytes;
    _scheduleCheckpoint(immediate: true);
  }

  void attach(_TerminalHostClientConnection client) {
    _clients.add(client);
  }

  void detach(_TerminalHostClientConnection client) {
    _clients.remove(client);
    _scheduleCheckpoint(immediate: true);
  }

  void write(Uint8List bytes) {
    if (bytes.isEmpty || !_running) {
      return;
    }
    _pty?.writeBytes(bytes);
  }

  void resize({required int cols, required int rows}) {
    if (!_running) {
      return;
    }
    _pty?.resize(rows: rows, cols: cols);
  }

  Future<void> terminate({required bool removeHistory}) async {
    _terminated = true;
    _running = false;
    final pty = _pty;
    _pty = null;
    try {
      if (pty != null && pty.tryWait() == null) {
        pty.kill();
      }
    } catch (_) {
      // The child can exit between tryWait and kill.
    } finally {
      pty?.close();
    }
    _reader?.kill(priority: Isolate.immediate);
    _reader = null;
    await _readerSub?.cancel();
    _readerSub = null;
    _readerPort?.close();
    _readerPort = null;
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    if (removeHistory) {
      _historyStore.delete(id);
    } else {
      await _writeCheckpoint(endedAt: _endedAt ?? DateTime.now().toUtc());
    }
  }

  Future<void> _startReader(PortablePty pty) async {
    _readerPort = ReceivePort();
    _readerSub = _readerPort!.listen(_handleReaderMessage);
    _reader = await Isolate.spawn<List<Object?>>(
      _terminalHostPtyReader,
      <Object?>[pty, _readerPort!.sendPort],
      debugName: 'alera-terminal-host-pty-reader',
    );
  }

  void _handleReaderMessage(Object? message) {
    if (_terminated) {
      return;
    }
    if (message is Uint8List) {
      _appendOutput(message);
      _broadcast(<String, Object?>{
        'event': 'output',
        'payload': <String, Object?>{
          'sessionId': id,
          'dataBase64': encodeTerminalHostBytes(message),
        },
      });
      return;
    }
    if (message is Map<Object?, Object?>) {
      final type = message['type'];
      if (type == 'error') {
        // coverage:ignore-start
        _broadcast(<String, Object?>{
          'event': 'error',
          'payload': <String, Object?>{
            'sessionId': id,
            'error': message['error']?.toString() ?? 'Unknown PTY error.',
          },
        });
        // coverage:ignore-end
      }
      if (type == 'exit' || type == 'error') {
        _handleExit((message['exitCode'] as int?) ?? -1);
      }
    }
  }

  void _appendOutput(Uint8List data) {
    _buffer.append(data);
    _scheduleCheckpoint();
  }

  void _handleExit(int exitCode) {
    if (!_running) {
      return;
    }
    _running = false;
    _exitCode = exitCode;
    _endedAt = DateTime.now().toUtc();
    _broadcast(<String, Object?>{
      'event': 'exit',
      'payload': <String, Object?>{'sessionId': id, 'exitCode': exitCode},
    });
    _scheduleCheckpoint(immediate: true, endedAt: _endedAt);
    _onLifecycleChanged();
  }

  void _broadcast(Map<String, Object?> message) {
    for (final client in _clients.toList(growable: false)) {
      client.write(message);
    }
  }

  void _scheduleCheckpoint({bool immediate = false, DateTime? endedAt}) {
    if (immediate) {
      _checkpointTimer?.cancel();
      _checkpointTimer = null;
      unawaited(_writeCheckpoint(endedAt: endedAt));
      return;
    }
    _checkpointTimer ??= Timer(_terminalHostCheckpointDelay, () {
      _checkpointTimer = null;
      unawaited(_writeCheckpoint());
    });
  }

  Future<void> _writeCheckpoint({DateTime? endedAt}) async {
    if (endedAt != null) {
      _endedAt = endedAt;
    }
    _historyStore.upsert(
      TerminalHostCheckpoint(
        sessionId: id,
        workspaceId: workspaceId,
        tabId: tabId,
        workingDirectory: workingDirectory,
        running: _running,
        exitCode: _exitCode,
        endedAt: _endedAt,
        updatedAt: DateTime.now().toUtc(),
        buffer: _buffer.toBytes(),
      ),
    );
  }
}
