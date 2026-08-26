part of 'terminal_host_client.dart';

extension _SocketTerminalHostClientConnections on SocketTerminalHostClient {
  Future<_TerminalHostConnection> _openTerminalConnection() async {
    if (_disposed) {
      throw const TerminalHostConnectionClosedException();
    }
    final runtime = await _runtimePaths();
    final control = await _readControl(runtime.controlFile);
    if (control != null) {
      try {
        return await _connectToControl(control, _HostConnectionRole.terminal);
      } catch (_) {
        if (_disposed) {
          throw const TerminalHostConnectionClosedException();
        }
        await _deleteControlFile(runtime.controlFile);
      }
    }
    final runtimeControl = await _readControl(runtime.runtimeControlFile);
    if (runtimeControl?.supportsRuntime == true) {
      try {
        return await _connectToControl(
          runtimeControl!,
          _HostConnectionRole.terminal,
        );
      } catch (_) {
        if (_disposed) {
          throw const TerminalHostConnectionClosedException();
        }
        await _deleteControlFile(runtime.runtimeControlFile);
      }
    }
    final runtimeFuture = _runtimeConnectionFuture;
    if (runtimeFuture != null) {
      try {
        final connection = await runtimeFuture;
        if (connection.supportsRuntime) {
          _terminalConnection = connection;
          return connection;
        }
      } catch (_) {
        if (_disposed) {
          throw const TerminalHostConnectionClosedException();
        }
        // A failed runtime connection must not prevent the terminal path from
        // starting its own host connection.
      }
    }
    if (_disposed) {
      throw const TerminalHostConnectionClosedException();
    }
    return _launchAndConnect(
      runtime,
      runtime.controlFile,
      requireOrchestration: false,
    );
  }

  Future<_TerminalHostConnection> _openRuntimeConnection({
    bool requireOrchestration = false,
    bool launchIfMissing = true,
  }) async {
    if (_disposed) {
      throw const TerminalHostConnectionClosedException();
    }
    final runtime = await _runtimePaths();
    final control = await _readControl(runtime.controlFile);
    if (_controlSupportsRuntime(control, requireOrchestration)) {
      try {
        return await _connectToControl(control!, _HostConnectionRole.runtime);
      } catch (_) {
        if (_disposed) {
          throw const TerminalHostConnectionClosedException();
        }
        await _deleteControlFile(runtime.controlFile);
      }
    }
    if (requireOrchestration && control != null) {
      if (await _controlAcceptsHello(control)) {
        throw StateError(_orchestrationHostRestartRequiredMessage);
      }
      await _deleteControlFile(runtime.controlFile);
    }
    final runtimeControl = await _readControl(runtime.runtimeControlFile);
    if (_controlSupportsRuntime(runtimeControl, requireOrchestration)) {
      try {
        return await _connectToControl(
          runtimeControl!,
          _HostConnectionRole.runtime,
        );
      } catch (_) {
        if (_disposed) {
          throw const TerminalHostConnectionClosedException();
        }
        await _deleteControlFile(runtime.runtimeControlFile);
      }
    }
    if (requireOrchestration && runtimeControl != null) {
      if (await _controlAcceptsHello(runtimeControl)) {
        throw StateError(_orchestrationHostRestartRequiredMessage);
      }
      await _deleteControlFile(runtime.runtimeControlFile);
    }
    if (!launchIfMissing) {
      throw StateError('No live Alera runtime host is available.');
    }
    if (_disposed) {
      throw const TerminalHostConnectionClosedException();
    }
    return _launchAndConnect(
      runtime,
      control == null || requireOrchestration
          ? runtime.controlFile
          : runtime.runtimeControlFile,
      requireOrchestration: requireOrchestration,
    );
  }

  Future<_TerminalHostConnection> _launchAndConnect(
    _TerminalHostPaths runtime,
    File controlFile, {
    required bool requireOrchestration,
  }) async {
    if (_disposed || _appQuitInProgress) {
      throw const TerminalHostConnectionClosedException();
    }
    await _failIfIncompatibleHostHoldsRuntime(runtime);
    if (_disposed || _appQuitInProgress) {
      throw const TerminalHostConnectionClosedException();
    }
    final token = _newToken();
    // Masked in logs and crash reports from here on: the token grants full
    // control of the runtime, and a diagnostics bundle is meant to be shared.
    registerLogSecret(token);
    await _launcher.start(
      runtimeDir: runtime.runtimeDir.path,
      controlFilePath: controlFile.path,
      token: token,
      config: _config,
    );
    if (_disposed || _appQuitInProgress) {
      throw const TerminalHostConnectionClosedException();
    }
    final deadline = DateTime.now().add(_startupTimeout);
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      if (_disposed || _appQuitInProgress) {
        throw const TerminalHostConnectionClosedException();
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final nextControl = await _readControl(controlFile);
      if (nextControl == null ||
          nextControl.token != token ||
          !_controlSupportsRuntime(nextControl, requireOrchestration)) {
        continue;
      }
      try {
        return await _connectToControl(
          nextControl,
          _HostConnectionRole.runtime,
        );
      } catch (error) {
        lastError = error;
      }
    }
    // Keep the public message stable for crash grouping, but preserve the
    // concrete startup cause in the local diagnostics log.
    if (lastError case final error?) {
      AppLogger.recordError(
        error,
        StackTrace.current,
        context: 'SocketTerminalHostClient',
      );
    }
    throw TerminalHostStartupException(lastError);
  }

  Future<_TerminalHostConnection> _connectToControl(
    _TerminalHostControl control,
    _HostConnectionRole role,
  ) async {
    final connection = await _openHostConnection(control);
    if (_disposed) {
      connection.dispose();
      throw const TerminalHostConnectionClosedException();
    }
    unawaited(
      connection.done.then(
        (_) => _handleConnectionClosed(connection),
        onError: (Object error, StackTrace _) {
          _handleConnectionClosed(connection, error);
        },
      ),
    );
    // Output frames bypass the JSON path entirely: no line split, no
    // jsonDecode, no base64. That is the whole point of the binary mode.
    connection.outputFrames.listen(
      (frame) => _emitHostEvent(
        frame.sessionId,
        TerminalHostOutputEvent(frame.sessionId, frame.data),
      ),
      onError: (Object _) {},
    );
    connection.decodedOutput.listen(
      (event) => _emitHostEvent(event.sessionId, event),
      onError: (Object _) {},
    );
    final lineSub = connection.lines.listen(
      (line) {
        try {
          _handleLine(connection, line);
        } catch (error) {
          _handleConnectionClosed(connection, error);
        }
      },
      onError: (error) => _handleConnectionClosed(connection, error),
      onDone: () => _handleConnectionClosed(connection),
      cancelOnError: true,
    );
    try {
      connection.write(<String, Object?>{
        'id': 0,
        'type': 'hello',
        'payload': <String, Object?>{
          'protocolVersion': aleraTerminalHostProtocolVersion,
          'token': control.token,
          'clientKind': 'app',
          'supportedTabKinds': const <String>[
            aleraMobileEmulatorTabKind,
            aleraCodexTabKind,
          ],
          if (control.supportsBinaryFrames) 'binaryFrames': true,
        },
      });
      await connection.authenticated.timeout(
        _terminalHostConnectTimeout,
        onTimeout: () => throw TimeoutException(
          'Terminal host authentication timed out.',
          _terminalHostConnectTimeout,
        ),
      );
      if (connection.isClosed) {
        throw StateError(
          'Terminal host connection closed during authentication.',
        );
      }
      if (_disposed) {
        throw const TerminalHostConnectionClosedException();
      }
      switch (role) {
        case _HostConnectionRole.terminal:
          _terminalLineSub = lineSub;
          _terminalConnection = connection;
          _terminalConnectionFuture = null;
          if (connection.supportsRuntime) {
            _runtimeConnection = connection;
            _runtimeConnectionFuture = null;
            _runtimeLineSub = lineSub;
          }
        case _HostConnectionRole.runtime:
          _runtimeLineSub = lineSub;
          _runtimeConnection = connection;
          _runtimeConnectionFuture = null;
          if (_terminalConnection == null && connection.supportsRuntime) {
            _terminalConnection = connection;
            _terminalConnectionFuture = null;
            _terminalLineSub = lineSub;
          }
      }
      if (connection.supportsRuntime && !_runtimeEvents.isClosed) {
        _runtimeEvents.add(
          const RuntimeHostEvent(
            aleraRuntimeHostConnectedEvent,
            <String, Object?>{},
          ),
        );
      }
    } catch (_) {
      await lineSub.cancel();
      connection.dispose();
      rethrow;
    }
    return connection;
  }
}
