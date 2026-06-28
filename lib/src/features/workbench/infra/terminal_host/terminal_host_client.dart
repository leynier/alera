import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_process_launcher.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

export 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
export 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_process_launcher.dart';

const Set<String> _runtimeHostEventNames = <String>{
  'projectsChanged',
  'workspacesChanged',
  'workspaceTabsChanged',
  'workspaceTagsChanged',
  'workspaceRelationsChanged',
  'sshTargetsChanged',
};

final class SocketTerminalHostClient
    implements TerminalHostClient, RuntimeHostClient {
  factory SocketTerminalHostClient({
    TerminalHostProcessLauncher? launcher,
    Future<Directory> Function()? applicationSupportDirectory,
    Duration startupTimeout = const Duration(seconds: 8),
    TerminalHostConfig initialConfig = TerminalHostConfig.defaults,
  }) {
    return SocketTerminalHostClient._(
      launcher ?? DefaultTerminalHostProcessLauncher(),
      applicationSupportDirectory ?? getApplicationSupportDirectory,
      startupTimeout,
      initialConfig,
    );
  }

  SocketTerminalHostClient._(
    this._launcher,
    this._applicationSupportDirectory,
    this._startupTimeout,
    this._config,
  );

  final TerminalHostProcessLauncher _launcher;
  final Future<Directory> Function() _applicationSupportDirectory;
  final Duration _startupTimeout;
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
  Future<Uint8List> setOutputPaused({
    required String sessionId,
    required bool paused,
  }) async {
    final payload = await _terminalRequestMap(
      'setOutputPaused',
      <String, Object?>{'sessionId': sessionId, 'paused': paused},
    );
    return TerminalHostSnapshot.fromJson(payload).data;
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
  ) async {
    if (_disposed) {
      throw StateError('Terminal host client is disposed.');
    }
    final connection = await _connectRuntime();
    return _requestOnConnection(connection, type, payload);
  }

  Future<Object?> _requestOnConnection(
    _TerminalHostConnection connection,
    String type,
    Map<String, Object?> payload,
  ) {
    final id = _nextRequestId++;
    final completer = Completer<Object?>();
    _pending[id] = _PendingHostRequest(connection, completer);
    connection.write(<String, Object?>{
      'id': id,
      'type': type,
      'payload': payload,
    });
    return completer.future.timeout(_terminalHostRequestTimeout);
  }

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) {
    return _runtimeRequest(type, payload);
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
    final next = _openTerminalConnection();
    _terminalConnectionFuture = next;
    return next;
  }

  Future<_TerminalHostConnection> _connectRuntime() async {
    if (_runtimeConnection case final connection?) {
      return Future<_TerminalHostConnection>.value(connection);
    }
    if (_terminalConnection case final connection?
        when connection.supportsRuntime) {
      _runtimeConnection = connection;
      return Future<_TerminalHostConnection>.value(connection);
    }
    final future = _runtimeConnectionFuture;
    if (future != null) {
      return future;
    }
    final terminalFuture = _terminalConnectionFuture;
    if (terminalFuture != null) {
      final connection = await terminalFuture;
      if (connection.supportsRuntime) {
        _runtimeConnection = connection;
        return connection;
      }
    }
    if (_runtimeConnection case final connection?) {
      return connection;
    }
    final nextFuture = _runtimeConnectionFuture;
    if (nextFuture != null) {
      return nextFuture;
    }
    final next = _openRuntimeConnection();
    _runtimeConnectionFuture = next;
    return next;
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
    return _launchAndConnect(runtime, runtime.controlFile);
  }

  Future<_TerminalHostConnection> _openRuntimeConnection() async {
    final runtime = await _runtimePaths();
    final control = await _readControl(runtime.controlFile);
    if (control?.supportsRuntime == true) {
      try {
        return await _connectToControl(control!, _HostConnectionRole.runtime);
      } catch (_) {
        await _deleteControlFile(runtime.controlFile);
      }
    }
    final runtimeControl = await _readControl(runtime.runtimeControlFile);
    if (runtimeControl?.supportsRuntime == true) {
      try {
        return await _connectToControl(
          runtimeControl!,
          _HostConnectionRole.runtime,
        );
      } catch (_) {
        await _deleteControlFile(runtime.runtimeControlFile);
      }
    }
    return _launchAndConnect(
      runtime,
      control == null ? runtime.controlFile : runtime.runtimeControlFile,
    );
  }

  Future<_TerminalHostConnection> _launchAndConnect(
    _TerminalHostPaths runtime,
    File controlFile,
  ) async {
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
          !nextControl.supportsRuntime) {
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
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      control.port,
      timeout: _terminalHostConnectTimeout,
    );
    final connection = _TerminalHostConnection(
      socket,
      supportsRuntime: control.supportsRuntime,
    );
    final lineSub = connection.lines.listen(
      (line) => _handleLine(connection, line),
      onError: (error) => _handleConnectionClosed(connection, error),
      onDone: () => _handleConnectionClosed(connection),
      cancelOnError: true,
    );
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
    connection.write(<String, Object?>{
      'id': 0,
      'type': 'hello',
      'payload': <String, Object?>{
        'protocolVersion': aleraTerminalHostProtocolVersion,
        'token': control.token,
      },
    });
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
        _handleConnectionClosed(connection); // coverage:ignore-line
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

  void _handleEvent(String event, Map<String, Object?> payload) {
    if (_runtimeHostEventNames.contains(event) && !_runtimeEvents.isClosed) {
      _runtimeEvents.add(RuntimeHostEvent(event, payload));
    }
    final sessionId = payload['sessionId'];
    if (sessionId is! String || _events.isClosed) {
      return;
    }
    switch (event) {
      case 'output':
        _events.add(
          TerminalHostOutputEvent(
            sessionId,
            decodeTerminalHostBytes(payload['dataBase64']),
          ),
        );
      case 'exit':
        _events.add(
          TerminalHostExitEvent(sessionId, (payload['exitCode'] as int?) ?? -1),
        );
      case 'error':
        _events.add(
          TerminalHostErrorEvent(
            sessionId,
            payload['error'] ?? 'Unknown terminal host error.',
          ),
        );
    }
  }

  void _handleConnectionClosed(
    _TerminalHostConnection connection, [
    Object? error,
  ]) {
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
        completer.completeError(
          StateError('Terminal host connection closed: $error'),
        );
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

  Future<_TerminalHostControl?> _readControl(File file) async {
    try {
      if (!await file.exists()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      final map = asTerminalHostMap(decoded, 'terminal host control');
      if (map['protocolVersion'] != aleraTerminalHostProtocolVersion) {
        return null;
      }
      final capabilities = asTerminalHostStringList(map['runtimeCapabilities']);
      final port = map['port'];
      final token = map['token'];
      if (port is! int || token is! String || token.isEmpty) {
        return null;
      }
      return _TerminalHostControl(
        port: port,
        token: token,
        supportsRuntime: capabilities.contains(aleraRuntimeHostCapability),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteControlFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
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
}

final class _TerminalHostConnection {
  _TerminalHostConnection(this._socket, {required this.supportsRuntime})
    : lines = _socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();

  final Socket _socket;
  final bool supportsRuntime;
  final Stream<String> lines;

  void write(Map<String, Object?> message) {
    _socket.writeln(jsonEncode(message));
  }

  void dispose() {
    _socket.destroy();
  }
}

final class _TerminalHostPaths {
  const _TerminalHostPaths({
    required this.runtimeDir,
    required this.controlFile,
    required this.runtimeControlFile,
  });

  final Directory runtimeDir;
  final File controlFile;
  final File runtimeControlFile;
}

final class _TerminalHostControl {
  const _TerminalHostControl({
    required this.port,
    required this.token,
    required this.supportsRuntime,
  });

  final int port;
  final String token;
  final bool supportsRuntime;
}

final class _PendingHostRequest {
  const _PendingHostRequest(this.connection, this.completer);

  final _TerminalHostConnection connection;
  final Completer<Object?> completer;
}

enum _HostConnectionRole { terminal, runtime }

const Duration _terminalHostConnectTimeout = Duration(seconds: 2);
const Duration _terminalHostRequestTimeout = Duration(seconds: 10);
