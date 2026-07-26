import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:alera/src/features/runtime_host/domain/runtime_host_status.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_frame_codec.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_socket_isolate.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_process_launcher.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

export 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
export 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_process_launcher.dart';

part 'terminal_host_client_types.dart';
part 'terminal_host_client_requests.dart';
part 'terminal_host_client_lifecycle.dart';
part 'terminal_host_client_heartbeat.dart';
part 'terminal_host_client_session_events.dart';
part 'terminal_host_client_socket_reader.dart';
part 'terminal_host_control_file.dart';

final class SocketTerminalHostClient
    with _TerminalHostClientHeartbeat, _TerminalHostClientSessionEvents
    implements TerminalHostClient, RuntimeHostClient {
  factory SocketTerminalHostClient({
    TerminalHostProcessLauncher? launcher,
    Future<Directory> Function()? applicationSupportDirectory,
    Duration startupTimeout = const Duration(seconds: 8),
    TerminalHostConfig initialConfig = TerminalHostConfig.defaults,
    Duration heartbeatInterval = _terminalHostHeartbeatInterval,
    Duration heartbeatTimeout = _terminalHostHeartbeatTimeout,
  }) {
    return SocketTerminalHostClient._(
      launcher ?? DefaultTerminalHostProcessLauncher(),
      applicationSupportDirectory ?? getApplicationSupportDirectory,
      startupTimeout,
      initialConfig,
      heartbeatInterval,
      heartbeatTimeout,
    );
  }

  SocketTerminalHostClient._(
    this._launcher,
    this._applicationSupportDirectory,
    this._startupTimeout,
    this._config,
    this._heartbeatInterval,
    this._heartbeatTimeout,
  );

  final TerminalHostProcessLauncher _launcher;
  final Future<Directory> Function() _applicationSupportDirectory;
  final Duration _startupTimeout;
  @override
  final Duration _heartbeatInterval;
  final Duration _heartbeatTimeout;
  final StreamController<TerminalHostEvent> _events =
      StreamController<TerminalHostEvent>.broadcast();
  final StreamController<RuntimeHostEvent> _runtimeEvents =
      StreamController<RuntimeHostEvent>.broadcast();
  final Map<int, _PendingHostRequest> _pending = <int, _PendingHostRequest>{};

  Future<_TerminalHostConnection>? _terminalConnectionFuture;
  _TerminalHostConnection? _terminalConnection;
  StreamSubscription<String>? _terminalLineSub;
  Future<_TerminalHostConnection>? _runtimeConnectionFuture;
  _TerminalHostConnection? _runtimeConnection;
  StreamSubscription<String>? _runtimeLineSub;
  int _nextRequestId = 1;
  bool _disposed = false;
  TerminalHostConfig _config;

  @override
  StreamController<TerminalHostEvent> get _globalEvents => _events;

  @override
  StreamController<RuntimeHostEvent> get _runtimeEventSink => _runtimeEvents;

  @override
  Stream<TerminalHostEvent> get events => _events.stream;

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _runtimeEvents.stream;

  @override
  Future<void> ensureStarted({required TerminalHostConfig config}) async {
    _config = config;
    await _terminalRequest('configure', config.toJson());
  }

  @override
  Future<void> configure(TerminalHostConfig config) async {
    if (_disposed) {
      throw StateError('Terminal host client is disposed.');
    }
    _config = config;
    final pendingConnections = <Future<_TerminalHostConnection>>[];
    if (_terminalConnection case final connection?) {
      pendingConnections.add(Future<_TerminalHostConnection>.value(connection));
    } else if (_terminalConnectionFuture case final future?) {
      pendingConnections.add(future);
    }
    if (_runtimeConnection case final connection?) {
      pendingConnections.add(Future<_TerminalHostConnection>.value(connection));
    } else if (_runtimeConnectionFuture case final future?) {
      pendingConnections.add(future);
    }
    if (pendingConnections.isEmpty) {
      return;
    }
    final connections = <_TerminalHostConnection>{};
    for (final future in pendingConnections) {
      connections.add(await future);
    }
    await Future.wait(<Future<Object?>>[
      for (final connection in connections)
        _requestOnConnection(connection, 'configure', config.toJson()),
    ]);
  }

  @override
  Future<TerminalHostAttachment> createOrAttach({
    required String sessionId,
    required String workspaceId,
    required String tabId,
    required String workingDirectory,
    required GhosttyTerminalShellLaunch launch,
    required int cols,
    required int rows,
  }) async {
    final payload =
        await _terminalRequestMap('createOrAttach', <String, Object?>{
          'sessionId': sessionId,
          'workspaceId': workspaceId,
          'tabId': tabId,
          'workingDirectory': workingDirectory,
          'launch': TerminalHostLaunch(
            label: launch.label,
            shell: launch.shell,
            arguments: launch.arguments,
            environment: launch.environment ?? const <String, String>{},
          ).toJson(),
          'cols': cols,
          'rows': rows,
        });
    return TerminalHostAttachment.fromJson(payload);
  }

  @override
  Future<void> write({
    required String sessionId,
    required List<int> bytes,
  }) async {
    if (bytes.isEmpty) {
      return;
    }
    await _terminalRequest('write', <String, Object?>{
      'sessionId': sessionId,
      'dataBase64': encodeTerminalHostBytes(bytes),
    });
  }

  @override
  Future<void> resize({
    required String sessionId,
    required int cols,
    required int rows,
  }) async {
    await _terminalRequest('resize', <String, Object?>{
      'sessionId': sessionId,
      'cols': cols,
      'rows': rows,
    });
  }

  @override
  Future<bool> reclaimTerminal(String sessionId) async {
    final payload = await _terminalRequestMap(
      'terminal.reclaim',
      <String, Object?>{'sessionId': sessionId},
    );
    return payload['restored'] == true;
  }

  @override
  Future<Map<String, TerminalSessionDriver>> listTerminalDrivers() async {
    return TerminalSessionDriver.mapFromListPayload(
      await _terminalRequest('terminal.driver.list', const <String, Object?>{}),
    );
  }

  @override
  Future<TerminalHostResume> setOutputPaused({
    required String sessionId,
    required bool paused,
  }) async {
    final payload = await _terminalRequestMap(
      'setOutputPaused',
      <String, Object?>{'sessionId': sessionId, 'paused': paused},
    );
    return TerminalHostResume.fromJson(payload);
  }

  @override
  Future<void> detach(String sessionId) async {
    await _terminalRequest('detach', <String, Object?>{'sessionId': sessionId});
  }

  @override
  Future<void> terminate(String sessionId) async {
    await _terminalRequest('terminate', <String, Object?>{
      'sessionId': sessionId,
    });
  }

  Future<Map<String, Object?>> _terminalRequestMap(
    String type,
    Map<String, Object?> payload,
  ) async {
    return asTerminalHostMap(await _terminalRequest(type, payload), 'response');
  }

  Future<Object?> _terminalRequest(
    String type,
    Map<String, Object?> payload,
  ) async {
    if (_disposed) {
      throw StateError('Terminal host client is disposed.');
    }
    final connection = await _connectTerminal();
    return _requestOnConnection(connection, type, payload);
  }

  Future<Object?> _runtimeRequest(
    String type,
    Map<String, Object?> payload,
    Duration? timeout,
  ) async {
    if (_disposed) {
      throw StateError('Terminal host client is disposed.');
    }
    final connection = await _connectRuntime(
      requireOrchestration: type.startsWith('orchestration.'),
    );
    return _requestOnConnection(connection, type, payload, timeout: timeout);
  }

  Future<Object?> _requestOnConnection(
    _TerminalHostConnection connection,
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) => _sendTerminalHostRequest(
    this,
    connection,
    type,
    payload,
    timeout: timeout,
  );

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) {
    return _runtimeRequest(type, payload, timeout);
  }

  Future<_TerminalHostConnection> _connectTerminal() {
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
    return next;
  }

  Future<_TerminalHostConnection> _connectRuntime({
    bool requireOrchestration = false,
    bool launchIfMissing = true,
  }) async {
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
    return next;
  }

  Future<_TerminalHostConnection?> _waitForRuntimeConnectionFuture(
    Future<_TerminalHostConnection> future, {
    required bool requireOrchestration,
  }) async {
    try {
      return await future;
    } catch (_) {
      if (requireOrchestration) {
        rethrow;
      }
      // A strict orchestration probe can reject a live pre-orchestration host;
      // normal runtime callers should retry without inheriting that error.
      return null;
    }
  }

  Future<_TerminalHostConnection> _openTerminalConnection() async {
    final runtime = await _runtimePaths();
    final control = await _readControl(runtime.controlFile);
    if (control != null) {
      try {
        return await _connectToControl(control, _HostConnectionRole.terminal);
      } catch (_) {
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
        await _deleteControlFile(runtime.runtimeControlFile);
      }
    }
    final runtimeFuture = _runtimeConnectionFuture;
    if (runtimeFuture != null) {
      final connection = await runtimeFuture;
      if (connection.supportsRuntime) {
        _terminalConnection = connection;
        return connection;
      }
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
    final runtime = await _runtimePaths();
    final control = await _readControl(runtime.controlFile);
    if (_controlSupportsRuntime(control, requireOrchestration)) {
      try {
        return await _connectToControl(control!, _HostConnectionRole.runtime);
      } catch (_) {
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
    await _failIfIncompatibleHostHoldsRuntime(runtime);
    final token = _newToken();
    await _launcher.start(
      runtimeDir: runtime.runtimeDir.path,
      controlFilePath: controlFile.path,
      token: token,
      config: _config,
    );
    final deadline = DateTime.now().add(_startupTimeout);
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
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
    throw StateError('Terminal host did not start in time: $lastError');
  }

  Future<_TerminalHostConnection> _connectToControl(
    _TerminalHostControl control,
    _HostConnectionRole role,
  ) async {
    final connection = await _openHostConnection(control);
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

  void _handleLine(_TerminalHostConnection connection, String line) {
    final decoded = jsonDecode(line);
    final message = asTerminalHostMap(decoded, 'Terminal host message');
    if (message['event'] case final String event) {
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
      completer.completeError(
        StateError((message['error'] as String?) ?? 'Terminal host error.'),
      );
    }
  }

  @override
  Future<void> _sendHeartbeatRequest(_TerminalHostConnection connection) async {
    await _sendTerminalHostRequest(
      this,
      connection,
      'status.get',
      const <String, Object?>{},
      timeout: _heartbeatTimeout,
    );
  }

  @override
  void _handleConnectionClosed(
    _TerminalHostConnection connection, [
    Object? error,
  ]) {
    if (connection.isClosed) {
      return;
    }
    _stopHeartbeatFor(connection);
    connection.completeAuthenticationError(
      StateError('Terminal host connection closed: $error'),
    );
    if (identical(_terminalConnection, connection)) {
      _terminalConnection = null;
      _terminalConnectionFuture = null;
      unawaited(_terminalLineSub?.cancel());
      _terminalLineSub = null;
    }
    if (identical(_runtimeConnection, connection)) {
      _runtimeConnection = null;
      _runtimeConnectionFuture = null;
      unawaited(_runtimeLineSub?.cancel());
      _runtimeLineSub = null;
    }
    connection.dispose();
    final pendingIds = <int>[
      for (final entry in _pending.entries)
        if (identical(entry.value.connection, connection)) entry.key,
    ];
    for (final id in pendingIds) {
      final completer = _pending.remove(id)?.completer;
      if (completer != null && !completer.isCompleted) {
        final closedError = StateError(
          _disposed
              ? 'Terminal host client is disposed.'
              : 'Terminal host connection closed: $error',
        );
        // Attach a sink before completeError so orphaned RPCs do not become
        // unhandled async errors during ProviderScope / test teardown.
        unawaited(completer.future.catchError((Object _) => null));
        completer.completeError(closedError);
      }
    }
  }

  Future<_TerminalHostPaths> _runtimePaths() async {
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

  String _newToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _stopHeartbeat();
    _closeSessionEvents();
    final connections = <_TerminalHostConnection>{};
    if (_terminalConnection case final connection?) {
      connections.add(connection);
    }
    if (_runtimeConnection case final connection?) {
      connections.add(connection);
    }
    for (final connection in connections) {
      _handleConnectionClosed(connection);
    }
    unawaited(_events.close());
    unawaited(_runtimeEvents.close());
  }

  bool _supportsRuntime(
    _TerminalHostConnection connection,
    bool requireOrchestration,
  ) {
    return connection.supportsRuntime &&
        (!requireOrchestration || connection.supportsOrchestration);
  }

  bool _controlSupportsRuntime(
    _TerminalHostControl? control,
    bool requireOrchestration,
  ) {
    return control?.supportsRuntime == true &&
        (!requireOrchestration || control!.supportsOrchestration);
  }

  void _throwIfOrchestrationWouldSplitPtyHost(
    _TerminalHostConnection connection,
    bool requireOrchestration,
  ) {
    if (requireOrchestration && !_supportsRuntime(connection, true)) {
      throw StateError(_orchestrationHostRestartRequiredMessage);
    }
  }
}
