import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:alera/src/features/command_terminal/domain/command_terminal_request.dart';
import 'package:alera/src/features/runtime_host/domain/runtime_host_status.dart';
import 'package:alera/src/features/diagnostics/infra/crash_reporting.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/runtime_buffer_guard_handler.dart';
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
import 'package:uuid/uuid.dart';

export 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
export 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_process_launcher.dart';

part 'terminal_host_client_types.dart';
part 'terminal_host_client_requests.dart';
part 'terminal_host_client_capabilities.dart';
part 'terminal_host_client_connections.dart';
part 'terminal_host_client_buffer_guards.dart';
part 'terminal_host_client_guarded_requests.dart';
part 'terminal_host_client_terminal_requests.dart';
part 'terminal_host_client_connection_routing.dart';
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
  final RuntimeBufferGuardHandler? _bufferGuardHandler,
) with
        _TerminalHostClientHeartbeat,
        _TerminalHostClientSessionEvents,
        _TerminalPulseHostClientSupport,
        _RuntimeHostCapabilitySupport,
        _ProviderSetupHostClientSupport,
        _GuardedRuntimeHostClientSupport
    implements
        TerminalHostClient,
        TerminalHostProviderSetupClient,
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
    RuntimeBufferGuardHandler? bufferGuardHandler,
  }) {
    return SocketTerminalHostClient._(
      launcher ?? DefaultTerminalHostProcessLauncher(),
      applicationSupportDirectory ?? getApplicationSupportDirectory,
      startupTimeout,
      initialConfig,
      heartbeatInterval,
      heartbeatTimeout,
      bufferGuardHandler,
    );
  }

  @override
  final Duration _heartbeatInterval;

  final StreamController<TerminalHostEvent> _events =
      StreamController<TerminalHostEvent>.broadcast();
  final StreamController<RuntimeHostEvent> _runtimeEvents =
      StreamController<RuntimeHostEvent>.broadcast();
  final Map<String, String> _pendingTerminalRestarts = {};
  final Map<int, _PendingHostRequest> _pending = <int, _PendingHostRequest>{};
  final Map<String, Set<_TerminalHostConnection>> _heldBufferGuards = {};

  /// Guards whose editors are being saved or discarded before they lock. A
  /// release that arrives meanwhile removes the id so the late lock is undone.
  final Set<String> _resolvingBufferGuards = {};

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
  SocketTerminalHostClient get _providerSetupClient => this;

  @override
  Future<TerminalHostAttachment> createOrAttach({
    required String sessionId,
    required String workspaceId,
    required String tabId,
    required String workingDirectory,
    required GhosttyTerminalShellLaunch launch,
    required int cols,
    required int rows,
    bool observe = false,
  }) => _createOrAttachTerminal(
    this,
    observe: observe,
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
    if (requiresSharedCheckoutSupport(type) &&
        !connection.runtimeCapabilities.contains(
          aleraRuntimeHostSharedCheckoutCapability,
        )) {
      throw StateError(
        'Update the Alera runtime before using $type. Existing terminal sessions remain available.',
      );
    }
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

  Future<_TerminalHostConnection> _connectTerminal() => _connectTerminalImpl();

  @override
  Future<_TerminalHostConnection> _connectRuntime({
    bool requireOrchestration = false,
    bool launchIfMissing = true,
  }) => _connectRuntimeImpl(
    requireOrchestration: requireOrchestration,
    launchIfMissing: launchIfMissing,
  );

  void _handleLine(_TerminalHostConnection connection, Object? line) =>
      _handleLineImpl(connection, line);

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
  ]) => _handleConnectionClosedImpl(connection, error);

  Future<_TerminalHostPaths> _runtimePaths() => _runtimePathsImpl();

  String _newToken() => _newTokenImpl();

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _pendingTerminalRestarts.clear();
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
