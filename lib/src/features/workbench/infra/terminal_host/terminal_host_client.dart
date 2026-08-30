import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:alera/src/features/runtime_host/domain/runtime_host_status.dart';
import 'package:alera/src/features/diagnostics/infra/crash_reporting.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_frame_codec.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_socket_isolate.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_process_launcher.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/logging/app_logger.dart';
import 'package:alera/src/shared/infra/logging/log_redaction.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

export 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
export 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_process_launcher.dart';

part 'terminal_host_client_types.dart';
part 'terminal_host_client_requests.dart';
part 'terminal_host_client_capabilities.dart';
part 'terminal_host_client_connections.dart';
part 'terminal_host_client_guarded_requests.dart';
part 'terminal_host_client_terminal_requests.dart';
part 'terminal_host_client_lifecycle.dart';
part 'terminal_host_client_heartbeat.dart';
part 'terminal_host_client_session_events.dart';
part 'terminal_host_client_terminal_pulse.dart';
part 'terminal_host_client_socket_reader.dart';
part 'terminal_host_control_file.dart';

final class SocketTerminalHostClient._(
  final TerminalHostProcessLauncher _launcher,
  final Future<Directory> Function() _applicationSupportDirectory,
  final Duration _startupTimeout,
  var TerminalHostConfig _config,
  this._heartbeatInterval,
  final Duration _heartbeatTimeout,
) with
        _TerminalHostClientHeartbeat,
        _TerminalHostClientSessionEvents,
        _TerminalPulseHostClientSupport,
        _RuntimeHostCapabilitySupport,
        _GuardedRuntimeHostClientSupport
    implements
        TerminalHostClient,
        TerminalPulseHostClient,
        RuntimeHostClient,
        RuntimeHostCapabilityClient {
  factory({
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

  @override
  final Duration _heartbeatInterval;

  final StreamController<TerminalHostEvent> _events =
      StreamController<TerminalHostEvent>.broadcast();
  final StreamController<RuntimeHostEvent> _runtimeEvents =
      StreamController<RuntimeHostEvent>.broadcast();
  final Map<int, _PendingHostRequest> _pending = <int, _PendingHostRequest>{};

  Future<_TerminalHostConnection>? _terminalConnectionFuture;
  @override
  _TerminalHostConnection? _terminalConnection;
  StreamSubscription<Object?>? _terminalLineSub;
  Future<_TerminalHostConnection>? _runtimeConnectionFuture;
  @override
  _TerminalHostConnection? _runtimeConnection;
  StreamSubscription<Object?>? _runtimeLineSub;
  int _nextRequestId = 1;
  @override
  bool _disposed = false;
  bool _appQuitInProgress = false;

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
    if (_disposed) {
      throw StateError('Terminal host client is disposed.');
    }
    _throwIfAppQuitInProgress();
    _config = config;
    await _terminalRequest('configure', config.toJson());
  }

  /// Stops application traffic while the quit gate probes and shuts down the
  /// runtime. Requests already in flight cannot be allowed to reach their
  /// normal timeout: the host may close the socket as part of shutdown, so
  /// they are completed as an expected connection close instead.
  void beginAppQuit() {
    if (_disposed || _appQuitInProgress) {
      return;
    }
    _appQuitInProgress = true;
    _stopHeartbeat();
    _failPendingRequests(const TerminalHostConnectionClosedException());
  }

  /// Reopens application traffic when the user cancels the quit gate.
  void cancelAppQuit() {
    if (!_disposed) {
      _appQuitInProgress = false;
    }
  }

  @override
  Future<void> configure(TerminalHostConfig config) async {
    if (_disposed) {
      throw StateError('Terminal host client is disposed.');
    }
    _throwIfAppQuitInProgress();
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
  }) => _createOrAttachTerminal(
    this,
    sessionId: sessionId,
    workspaceId: workspaceId,
    tabId: tabId,
    workingDirectory: workingDirectory,
    launch: launch,
    cols: cols,
    rows: rows,
  );

  @override
  Future<TerminalHostAttachment> restart({
    required String sessionId,
    required String workspaceId,
    required String tabId,
    required String workingDirectory,
    required GhosttyTerminalShellLaunch launch,
    required int cols,
    required int rows,
  }) => _restartTerminal(
    this,
    sessionId: sessionId,
    workspaceId: workspaceId,
    tabId: tabId,
    workingDirectory: workingDirectory,
    launch: launch,
    cols: cols,
    rows: rows,
  );

  @override
  Future<void> write({
    required String sessionId,
    required List<int> bytes,
    bool deferredEnter = false,
  }) async {
    if (bytes.isEmpty && !deferredEnter) {
      return;
    }
    await _terminalRequest('write', <String, Object?>{
      'sessionId': sessionId,
      'dataBase64': encodeTerminalHostBytes(bytes),
      if (deferredEnter) 'deferredEnter': true,
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

  @override
  Future<Map<String, Object?>> _terminalRequestMap(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    return asTerminalHostMap(
      await _terminalRequest(type, payload, timeout: timeout),
      'response',
    );
  }

  Future<Object?> _terminalRequest(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    if (_disposed) {
      throw StateError('Terminal host client is disposed.');
    }
    _throwIfAppQuitInProgress();
    final connection = await _connectTerminal();
    _throwIfAppQuitInProgress();
    return _requestOnConnection(connection, type, payload, timeout: timeout);
  }

  Future<Object?> _runtimeRequest(
    String type,
    Map<String, Object?> payload,
    Duration? timeout,
  ) async {
    if (_disposed) {
      throw StateError('Terminal host client is disposed.');
    }
    _throwIfAppQuitInProgress();
    final connection = await _connectRuntime(
      requireOrchestration: type.startsWith('orchestration.'),
    );
    _throwIfAppQuitInProgress();
    return _requestOnConnection(connection, type, payload, timeout: timeout);
  }

  Future<Object?> _requestOnConnection(
    _TerminalHostConnection connection,
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
    bool allowDuringAppQuit = false,
  }) {
    if (_disposed) {
      throw StateError('Terminal host client is disposed.');
    }
    if (_appQuitInProgress && !allowDuringAppQuit) {
      throw const TerminalHostConnectionClosedException();
    }
    return _sendTerminalHostRequestWithMutationRetry(
      this,
      connection,
      type,
      payload,
      timeout: timeout,
      allowDuringAppQuit: allowDuringAppQuit,
    );
  }

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) {
    return _runtimeRequest(type, payload, timeout);
  }

  Future<_TerminalHostConnection> _connectTerminal() {
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

  @override
  Future<_TerminalHostConnection> _connectRuntime({
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

  void _handleLine(_TerminalHostConnection connection, Object? line) {
    // The reader isolate parses; the fallback path hands over the raw line.
    final decoded = line is String ? jsonDecode(line) : line;
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
      completer.completeError(_terminalHostRequestError(message));
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
    _appQuitInProgress = true;
    _stopHeartbeat();
    _closeSessionEvents();
    _failPendingRequests(const TerminalHostConnectionClosedException());
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

  void _failPendingRequests(Object error) {
    final pending = _pending.values.toList(growable: false);
    _pending.clear();
    for (final request in pending) {
      if (!request.completer.isCompleted) {
        request.completer.completeError(error, .current);
      }
    }
  }

  @override
  void _throwIfAppQuitInProgress() {
    if (_appQuitInProgress) {
      throw const TerminalHostConnectionClosedException();
    }
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
