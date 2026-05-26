// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:alera/src/features/workbench/infra/terminal_host/alera_cli_sidecar.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class TerminalHostClient {
  Stream<TerminalHostEvent> get events;

  Future<void> ensureStarted({required TerminalHostConfig config});

  Future<void> configure(TerminalHostConfig config);

  Future<TerminalHostAttachment> createOrAttach({
    required String sessionId,
    required String workspaceId,
    required String tabId,
    required String workingDirectory,
    required GhosttyTerminalShellLaunch launch,
    required int cols,
    required int rows,
  });

  Future<void> write({required String sessionId, required List<int> bytes});

  Future<void> resize({
    required String sessionId,
    required int cols,
    required int rows,
  });

  Future<void> detach(String sessionId);

  Future<void> terminate(String sessionId);

  void dispose();
}

final class TerminalHostAttachment {
  const TerminalHostAttachment({
    required this.sessionId,
    required this.created,
    required this.running,
    required this.snapshot,
    this.exitCode,
  });

  factory TerminalHostAttachment.fromJson(Map<String, Object?> json) {
    return TerminalHostAttachment(
      sessionId: json['sessionId'] as String,
      created: json['created'] == true,
      running: json['running'] == true,
      snapshot: decodeTerminalHostBytes(json['snapshotBase64']),
      exitCode: json['exitCode'] is int ? json['exitCode'] as int : null,
    );
  }

  final String sessionId;
  final bool created;
  final bool running;
  final Uint8List snapshot;
  final int? exitCode;
}

sealed class TerminalHostEvent {
  const TerminalHostEvent(this.sessionId);

  final String sessionId;
}

final class TerminalHostOutputEvent extends TerminalHostEvent {
  const TerminalHostOutputEvent(super.sessionId, this.data);

  final Uint8List data;
}

final class TerminalHostExitEvent extends TerminalHostEvent {
  const TerminalHostExitEvent(super.sessionId, this.exitCode);

  final int exitCode;
}

final class TerminalHostErrorEvent extends TerminalHostEvent {
  const TerminalHostErrorEvent(super.sessionId, this.error);

  final Object error;
}

abstract interface class TerminalHostProcessLauncher {
  Future<void> start({
    required String runtimeDir,
    required String controlFilePath,
    required String token,
    required TerminalHostConfig config,
  });
}

// coverage:ignore-start
final class DefaultTerminalHostProcessLauncher
    implements TerminalHostProcessLauncher {
  const DefaultTerminalHostProcessLauncher({
    AleraCliResolver cliResolver = const DefaultAleraCliResolver(),
  }) : _cliResolver = cliResolver;

  final AleraCliResolver _cliResolver;

  @override
  Future<void> start({
    required String runtimeDir,
    required String controlFilePath,
    required String token,
    required TerminalHostConfig config,
  }) async {
    final command = await _cliResolver.resolve(runtimeDir: runtimeDir);
    await Process.start(
      command.executable,
      <String>[
        ...command.prefixArguments,
        aleraTerminalHostCommand,
        '--runtime-dir',
        runtimeDir,
        '--control-file',
        controlFilePath,
        '--token',
        token,
        '--empty-shutdown-delay-seconds',
        config.emptyShutdownDelaySeconds.toString(),
        '--detached-session-shutdown-delay-seconds',
        config.detachedSessionShutdownDelaySeconds.toString(),
        '--scrollback-bytes',
        config.scrollbackBytes.toString(),
      ],
      workingDirectory: command.workingDirectory,
      mode: ProcessStartMode.detached,
      environment: const <String, String>{'ALERA_TERMINAL_HOST': '1'},
    );
  }
}
// coverage:ignore-end

final class SocketTerminalHostClient implements TerminalHostClient {
  SocketTerminalHostClient({
    TerminalHostProcessLauncher launcher =
        const DefaultTerminalHostProcessLauncher(),
    Future<Directory> Function()? applicationSupportDirectory,
    Duration startupTimeout = const Duration(seconds: 8),
    TerminalHostConfig initialConfig = TerminalHostConfig.defaults,
  }) : _launcher = launcher,
       _applicationSupportDirectory =
           applicationSupportDirectory ?? getApplicationSupportDirectory,
       _startupTimeout = startupTimeout,
       _config = initialConfig;

  final TerminalHostProcessLauncher _launcher;
  final Future<Directory> Function() _applicationSupportDirectory;
  final Duration _startupTimeout;
  final StreamController<TerminalHostEvent> _events =
      StreamController<TerminalHostEvent>.broadcast();
  final Map<int, Completer<Map<String, Object?>>> _pending =
      <int, Completer<Map<String, Object?>>>{};

  Future<_TerminalHostConnection>? _connectionFuture;
  _TerminalHostConnection? _connection;
  StreamSubscription<String>? _lineSub;
  int _nextRequestId = 1;
  bool _disposed = false;
  TerminalHostConfig _config;

  @override
  Stream<TerminalHostEvent> get events => _events.stream;

  @override
  Future<void> ensureStarted({required TerminalHostConfig config}) async {
    _config = config;
    await _request('configure', config.toJson());
  }

  @override
  Future<void> configure(TerminalHostConfig config) async {
    if (_disposed) {
      throw StateError('Terminal host client is disposed.');
    }
    _config = config;
    if (_connection == null && _connectionFuture == null) {
      return;
    }
    await _request('configure', config.toJson());
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
    final payload = await _request('createOrAttach', <String, Object?>{
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
    await _request('write', <String, Object?>{
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
    await _request('resize', <String, Object?>{
      'sessionId': sessionId,
      'cols': cols,
      'rows': rows,
    });
  }

  @override
  Future<void> detach(String sessionId) async {
    await _request('detach', <String, Object?>{'sessionId': sessionId});
  }

  @override
  Future<void> terminate(String sessionId) async {
    await _request('terminate', <String, Object?>{'sessionId': sessionId});
  }

  Future<Map<String, Object?>> _request(
    String type,
    Map<String, Object?> payload,
  ) async {
    if (_disposed) {
      throw StateError('Terminal host client is disposed.');
    }
    final connection = await _connect();
    final id = _nextRequestId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    connection.write(<String, Object?>{
      'id': id,
      'type': type,
      'payload': payload,
    });
    return completer.future.timeout(_terminalHostRequestTimeout);
  }

  Future<_TerminalHostConnection> _connect() {
    if (_connection case final connection?) {
      return Future<_TerminalHostConnection>.value(connection);
    }
    final future = _connectionFuture;
    if (future != null) {
      return future;
    }
    final next = _openConnection();
    _connectionFuture = next;
    return next;
  }

  Future<_TerminalHostConnection> _openConnection() async {
    final runtime = await _runtimePaths();
    final control = await _readUsableControl(runtime.controlFile);
    if (control != null) {
      try {
        return await _connectToControl(control);
      } catch (_) {
        await _deleteControlFile(runtime.controlFile);
      }
    }

    final token = _newToken();
    await _launcher.start(
      runtimeDir: runtime.runtimeDir.path,
      controlFilePath: runtime.controlFile.path,
      token: token,
      config: _config,
    );
    final deadline = DateTime.now().add(_startupTimeout);
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final nextControl = await _readUsableControl(runtime.controlFile);
      if (nextControl == null || nextControl.token != token) {
        continue;
      }
      try {
        return await _connectToControl(nextControl);
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('Terminal host did not start in time: $lastError');
  }

  Future<_TerminalHostConnection> _connectToControl(
    _TerminalHostControl control,
  ) async {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      control.port,
      timeout: _terminalHostConnectTimeout,
    );
    final connection = _TerminalHostConnection(socket);
    _lineSub = connection.lines.listen(
      _handleLine,
      onError: _handleConnectionClosed,
      onDone: _handleConnectionClosed,
      cancelOnError: true,
    );
    connection.write(<String, Object?>{
      'id': 0,
      'type': 'hello',
      'payload': <String, Object?>{
        'protocolVersion': aleraTerminalHostProtocolVersion,
        'token': control.token,
      },
    });
    _connection = connection;
    _connectionFuture = null;
    return connection;
  }

  void _handleLine(String line) {
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
        _handleConnectionClosed(); // coverage:ignore-line
      }
      return;
    }
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) {
      return;
    }
    if (message['ok'] == true) {
      completer.complete(asTerminalHostMap(message['payload'], 'response'));
    } else {
      completer.completeError(
        StateError((message['error'] as String?) ?? 'Terminal host error.'),
      );
    }
  }

  void _handleEvent(String event, Map<String, Object?> payload) {
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

  void _handleConnectionClosed([Object? error]) {
    final connection = _connection;
    _connection = null;
    _connectionFuture = null;
    unawaited(_lineSub?.cancel());
    _lineSub = null;
    connection?.dispose();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Terminal host connection closed: $error'),
        );
      }
    }
    _pending.clear();
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
    );
  }

  Future<_TerminalHostControl?> _readUsableControl(File file) async {
    try {
      if (!await file.exists()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      final map = asTerminalHostMap(decoded, 'terminal host control');
      if (map['protocolVersion'] != aleraTerminalHostProtocolVersion) {
        return null;
      }
      final port = map['port'];
      final token = map['token'];
      if (port is! int || token is! String || token.isEmpty) {
        return null;
      }
      return _TerminalHostControl(port: port, token: token);
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
    _handleConnectionClosed();
    unawaited(_events.close());
  }
}

final class _TerminalHostConnection {
  _TerminalHostConnection(this._socket)
    : lines = _socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();

  final Socket _socket;
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
  });

  final Directory runtimeDir;
  final File controlFile;
}

final class _TerminalHostControl {
  const _TerminalHostControl({required this.port, required this.token});

  final int port;
  final String token;
}

const Duration _terminalHostConnectTimeout = Duration(seconds: 2);
const Duration _terminalHostRequestTimeout = Duration(seconds: 10);
