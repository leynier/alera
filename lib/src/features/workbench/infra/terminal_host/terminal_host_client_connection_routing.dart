part of 'terminal_host_client.dart';

extension _TerminalHostConnectionRouting on SocketTerminalHostClient {
  Future<_TerminalHostConnection> _connectTerminalImpl() {
    if (_disposed) {
      throw const TerminalHostConnectionClosedException();
    }
    if (_terminalConnection case final connection?) {
      return Future<_TerminalHostConnection>.value(connection);
    }
    if (_runtimeConnection case final connection?
        when connection.supportsRuntime) {
      _terminalConnection = connection;
      return Future<_TerminalHostConnection>.value(connection);
    }
    final future = _terminalConnectionFuture;
    if (future != null) {
      return future;
    }
    late final Future<_TerminalHostConnection> next;
    next = _openTerminalConnection().whenComplete(() {
      if (identical(_terminalConnectionFuture, next)) {
        _terminalConnectionFuture = null;
      }
    });
    _terminalConnectionFuture = next;
    _guardHostFuture(next);
    return next;
  }

  Future<_TerminalHostConnection> _connectRuntimeImpl({
    bool requireOrchestration = false,
    bool launchIfMissing = true,
  }) async {
    if (_disposed) {
      throw const TerminalHostConnectionClosedException();
    }
    if (_runtimeConnection case final connection?
        when _supportsRuntime(connection, requireOrchestration)) {
      return Future<_TerminalHostConnection>.value(connection);
    }
    if (_terminalConnection case final connection?) {
      if (_supportsRuntime(connection, requireOrchestration)) {
        _runtimeConnection = connection;
        return Future<_TerminalHostConnection>.value(connection);
      }
      _throwIfOrchestrationWouldSplitPtyHost(connection, requireOrchestration);
    }
    final future = _runtimeConnectionFuture;
    if (future != null) {
      final connection = await _waitForRuntimeConnectionFuture(
        future,
        requireOrchestration: requireOrchestration,
      );
      if (connection != null &&
          _supportsRuntime(connection, requireOrchestration)) {
        return connection;
      }
    }
    final terminalFuture = _terminalConnectionFuture;
    if (terminalFuture != null) {
      final connection = await terminalFuture;
      if (_supportsRuntime(connection, requireOrchestration)) {
        _runtimeConnection = connection;
        return connection;
      }
      _throwIfOrchestrationWouldSplitPtyHost(connection, requireOrchestration);
    }
    if (_runtimeConnection case final connection?
        when _supportsRuntime(connection, requireOrchestration)) {
      return connection;
    }
    final nextFuture = _runtimeConnectionFuture;
    if (nextFuture != null) {
      final connection = await _waitForRuntimeConnectionFuture(
        nextFuture,
        requireOrchestration: requireOrchestration,
      );
      if (connection != null &&
          _supportsRuntime(connection, requireOrchestration)) {
        return connection;
      }
    }
    late final Future<_TerminalHostConnection> next;
    next =
        _openRuntimeConnection(
          requireOrchestration: requireOrchestration,
          launchIfMissing: launchIfMissing,
        ).whenComplete(() {
          if (identical(_runtimeConnectionFuture, next)) {
            _runtimeConnectionFuture = null;
          }
        });
    _runtimeConnectionFuture = next;
    _guardHostFuture(next);
    return next;
  }

  Future<_TerminalHostConnection?> _waitForRuntimeConnectionFuture(
    Future<_TerminalHostConnection> future, {
    required bool requireOrchestration,
  }) async {
    try {
      return await future;
    } catch (_) {
      if (_disposed) {
        throw const TerminalHostConnectionClosedException();
      }
      if (requireOrchestration) {
        rethrow;
      }
      // A strict orchestration probe can reject a live pre-orchestration host;
      // normal runtime callers should retry without inheriting that error.
      return null;
    }
  }

  void _handleLineImpl(_TerminalHostConnection connection, Object? line) {
    // The reader isolate parses; the fallback path hands over the raw line.
    final decoded = line is String ? jsonDecode(line) : line;
    final message = asTerminalHostMap(decoded, 'Terminal host message');
    if (message['event'] case final String event) {
      if (event == 'checkoutBuffersLock' ||
          event == 'checkoutBuffersSaveRequested') {
        final payload = asTerminalHostMap(message['payload'], 'buffer guard');
        _lockCheckoutBuffers(
          connection,
          payload,
          resolution: event == 'checkoutBuffersSaveRequested'
              ? 'save'
              : payload['resolution'] as String?,
        );
        return;
      }
      if (event == 'checkoutBuffersReleased') {
        final payload = asTerminalHostMap(message['payload'], 'buffer guard');
        if (payload['guardId'] case final String id) {
          _releaseCheckoutBuffers(id, retired: payload['retired'] == true);
        }
        return;
      }
      _handleEvent(event, asTerminalHostMap(message['payload'], 'event'));
      return;
    }
    final id = message['id'];
    if (id is! int) {
      return;
    }
    if (id == 0) {
      if (message['ok'] != true) {
        final error = StateError(
          (message['error'] as String?) ??
              'Terminal host authentication was rejected.',
        );
        connection.completeAuthenticationError(error);
        _handleConnectionClosed(connection, error);
      } else {
        if (message['payload'] is Map) {
          _restoreCheckoutBufferGuards(
            connection,
            asTerminalHostMap(message['payload'], 'hello'),
          );
        }
        connection.completeAuthentication();
      }
      return;
    }
    final pending = _pending.remove(id);
    final completer = pending?.completer;
    if (completer == null || completer.isCompleted) {
      return;
    }
    if (message['ok'] == true) {
      completer.complete(message['payload']);
    } else {
      completer.completeError(_terminalHostRequestError(message));
    }
  }

  void _handleConnectionClosedImpl(
    _TerminalHostConnection connection, [
    Object? error,
  ]) {
    if (connection.isClosed) {
      return;
    }
    final closedError = TerminalHostConnectionClosedException(error);
    _stopHeartbeatFor(connection);
    connection.completeAuthenticationError(closedError);
    final wasTerminalConnection = identical(_terminalConnection, connection);
    if (wasTerminalConnection) {
      _terminalConnection = null;
      _terminalConnectionFuture = null;
      unawaited(_terminalLineSub?.cancel());
      _terminalLineSub = null;
    }
    if (wasTerminalConnection && !_disposed && !_appQuitInProgress) {
      _emitConnectionError(closedError);
    }
    if (identical(_runtimeConnection, connection)) {
      CrashReporting.clearRuntimeContext();
      _runtimeConnection = null;
      _runtimeConnectionFuture = null;
      unawaited(_runtimeLineSub?.cancel());
      _runtimeLineSub = null;
      if (!_runtimeEvents.isClosed) {
        _runtimeEvents.add(
          const RuntimeHostEvent(
            aleraRuntimeHostDisconnectedEvent,
            <String, Object?>{},
          ),
        );
      }
    }
    connection.dispose();
    final pendingIds = <int>[
      for (final entry in _pending.entries)
        if (identical(entry.value.connection, connection)) entry.key,
    ];
    for (final id in pendingIds) {
      final completer = _pending.remove(id)?.completer;
      if (completer != null && !completer.isCompleted) {
        final pendingError = _disposed || _appQuitInProgress
            ? const TerminalHostConnectionClosedException()
            : closedError;
        // Preserve the close site for reporters that receive this error
        // without an await; public callers observe the async wrapper stack.
        completer.completeError(pendingError, .current);
      }
    }
  }

  Future<_TerminalHostPaths> _runtimePathsImpl() async {
    final support = await _applicationSupportDirectory();
    final runtimeDir = Directory(p.join(support.path, 'terminal_host'));
    if (!await runtimeDir.exists()) {
      await runtimeDir.create(recursive: true);
    }
    return _TerminalHostPaths(
      runtimeDir: runtimeDir,
      controlFile: File(p.join(runtimeDir.path, 'host.json')),
      runtimeControlFile: File(p.join(runtimeDir.path, 'runtime-host.json')),
    );
  }

  String _newTokenImpl() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}
