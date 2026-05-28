import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_history_store.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:portable_pty/portable_pty.dart';

part 'terminal_host_session.dart';
part 'terminal_host_buffer.dart';

final class AleraTerminalHostServer {
  factory AleraTerminalHostServer({
    required String runtimeDir,
    required String controlFilePath,
    required String token,
    required TerminalHostConfig config,
  }) {
    return AleraTerminalHostServer._(
      Directory(runtimeDir),
      File(controlFilePath),
      token,
      config,
    );
  }

  AleraTerminalHostServer._(
    this._runtimeDir,
    this._controlFile,
    this._token,
    this._config,
  );

  final Directory _runtimeDir;
  final File _controlFile;
  final String _token;
  final Map<String, _TerminalHostSession> _sessions =
      <String, _TerminalHostSession>{};
  final Set<_TerminalHostClientConnection> _clients =
      <_TerminalHostClientConnection>{};

  ServerSocket? _server;
  TerminalHostHistoryStore? _historyStore;
  TerminalHostConfig _config;
  Timer? _shutdownTimer;
  bool _disposed = false;

  Future<void> run() async {
    if (!await _runtimeDir.exists()) {
      await _runtimeDir.create(recursive: true);
    }
    _historyStore = TerminalHostHistoryStore.open(runtimeDir: _runtimeDir);
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    await _writeControlFile(_server!.port);
    _scheduleShutdownIfIdle();
    await for (final socket in _server!) {
      _accept(socket);
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _shutdownTimer?.cancel();
    _shutdownTimer = null;
    final clients = _clients.toList(growable: false);
    for (final client in clients) {
      client.dispose();
    }
    final sessions = _sessions.values.toList(growable: false);
    _sessions.clear();
    for (final session in sessions) {
      await session.terminate(removeHistory: false);
    }
    _historyStore?.close();
    _historyStore = null;
    await _deleteControlFile();
    await _server?.close();
    _server = null;
  }

  Future<void> _writeControlFile(int port) async {
    final tempFile = File('${_controlFile.path}.tmp');
    await tempFile.writeAsString(
      jsonEncode(<String, Object?>{
        'protocolVersion': aleraTerminalHostProtocolVersion,
        'pid': pid,
        'port': port,
        'token': _token,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    await tempFile.rename(_controlFile.path);
  }

  void _accept(Socket socket) {
    final client = _TerminalHostClientConnection(
      socket,
      onDispose: _clients.remove,
    );
    _clients.add(client);
    client.lines.listen(
      (line) => _handleLine(client, line),
      onError: (_) => _disposeClient(client), // coverage:ignore-line
      onDone: () => _disposeClient(client),
      cancelOnError: true,
    );
  }

  void _disposeClient(_TerminalHostClientConnection client) {
    for (final session in _sessions.values) {
      session.detach(client);
    }
    client.dispose();
    _scheduleShutdownIfIdle();
  }

  Future<void> _handleLine(
    _TerminalHostClientConnection client,
    String line,
  ) async {
    Object? requestId;
    try {
      final decoded = jsonDecode(line);
      final request = asTerminalHostMap(decoded, 'terminal host request');
      requestId = request['id'];
      final type = request['type'];
      final payload = asTerminalHostMap(request['payload'], 'request payload');
      if (requestId is! int || type is! String) {
        throw const FormatException('Terminal host request is malformed.');
      }
      final response = await _handleRequest(client, type, payload);
      client.write(<String, Object?>{
        'id': requestId,
        'ok': true,
        'payload': response,
      });
    } catch (error) {
      if (requestId is int) {
        client.write(<String, Object?>{
          'id': requestId,
          'ok': false,
          'error': _terminalHostErrorMessage(error),
        });
      } else {
        client.dispose();
      }
    }
  }

  String _terminalHostErrorMessage(Object error) {
    if (error is StateError) {
      return error.message;
    }
    return error.toString();
  }

  Future<Map<String, Object?>> _handleRequest(
    _TerminalHostClientConnection client,
    String type,
    Map<String, Object?> payload,
  ) async {
    switch (type) {
      case 'hello':
        final protocolVersion = payload['protocolVersion'];
        final token = payload['token'];
        if (protocolVersion != aleraTerminalHostProtocolVersion ||
            token != _token) {
          throw StateError('Terminal host authentication failed.');
        }
        client.authenticated = true;
        _cancelShutdownTimer();
        return const <String, Object?>{};
      case 'configure':
        client.requireAuthenticated();
        _applyConfig(TerminalHostConfig.fromJson(payload));
        return const <String, Object?>{};
      case 'createOrAttach':
        client.requireAuthenticated();
        return _createOrAttach(client, payload);
      case 'write':
        client.requireAuthenticated();
        _session(payload).write(decodeTerminalHostBytes(payload['dataBase64']));
        return const <String, Object?>{};
      case 'resize':
        client.requireAuthenticated();
        _session(payload).resize(
          cols: (payload['cols'] as int?) ?? 80,
          rows: (payload['rows'] as int?) ?? 24,
        );
        return const <String, Object?>{};
      case 'detach':
        client.requireAuthenticated();
        _session(payload).detach(client);
        return const <String, Object?>{};
      case 'terminate':
        client.requireAuthenticated();
        final session = _session(payload);
        await session.terminate(removeHistory: true);
        _sessions.remove(session.id);
        _scheduleShutdownIfIdle();
        return const <String, Object?>{};
      default:
        throw StateError('Unknown terminal host request: $type');
    }
  }

  Future<Map<String, Object?>> _createOrAttach(
    _TerminalHostClientConnection client,
    Map<String, Object?> payload,
  ) async {
    final sessionId = payload['sessionId'];
    final workspaceId = payload['workspaceId'];
    final tabId = payload['tabId'];
    final workingDirectory = payload['workingDirectory'];
    if (sessionId is! String ||
        workspaceId is! String ||
        tabId is! String ||
        workingDirectory is! String) {
      throw const FormatException('createOrAttach requires session metadata.');
    }
    if (_sessions[sessionId] case final existing?) {
      existing.attach(client);
      return existing.attachmentPayload(created: false);
    }

    final restored = await _TerminalHostSession.restoreExited(
      sessionId: sessionId,
      workspaceId: workspaceId,
      tabId: tabId,
      historyStore: _requireHistoryStore(),
      maxBufferBytes: _config.scrollbackBytes,
      onLifecycleChanged: _scheduleShutdownIfIdle,
    );
    if (restored != null) {
      _sessions[sessionId] = restored;
      restored.updateConfig(maxBufferBytes: _config.scrollbackBytes);
      restored.attach(client);
      return restored.attachmentPayload(created: false);
    }

    final launch = TerminalHostLaunch.fromJson(
      asTerminalHostMap(payload['launch'], 'launch'),
    );
    final session = await _TerminalHostSession.start(
      id: sessionId,
      workspaceId: workspaceId,
      tabId: tabId,
      workingDirectory: workingDirectory,
      launch: launch,
      cols: (payload['cols'] as int?) ?? 80,
      rows: (payload['rows'] as int?) ?? 24,
      historyStore: _requireHistoryStore(),
      maxBufferBytes: _config.scrollbackBytes,
      onLifecycleChanged: _scheduleShutdownIfIdle,
    );
    _sessions[sessionId] = session;
    session.attach(client);
    return session.attachmentPayload(created: true);
  }

  _TerminalHostSession _session(Map<String, Object?> payload) {
    final sessionId = payload['sessionId'];
    if (sessionId is! String) {
      throw const FormatException('Terminal session id is required.');
    }
    final session = _sessions[sessionId];
    if (session == null) {
      throw StateError('Terminal session is not attached: $sessionId');
    }
    return session;
  }

  TerminalHostHistoryStore _requireHistoryStore() {
    final store = _historyStore;
    // coverage:ignore-start
    // The store is opened before the socket accepts requests; this guard keeps
    // the invariant explicit for future lifecycle changes.
    if (store == null) {
      throw StateError('Terminal host history store is not open.');
    }
    // coverage:ignore-end
    return store;
  }

  void _applyConfig(TerminalHostConfig config) {
    _config = config;
    for (final session in _sessions.values) {
      session.updateConfig(maxBufferBytes: config.scrollbackBytes);
    }
    _scheduleShutdownIfIdle();
  }

  void _cancelShutdownTimer() {
    _shutdownTimer?.cancel();
    _shutdownTimer = null;
  }

  void _scheduleShutdownIfIdle() {
    if (_disposed || _hasAuthenticatedClients) {
      _cancelShutdownTimer();
      return;
    }
    final duration = _hasRunningSessions
        ? Duration(seconds: _config.detachedSessionShutdownDelaySeconds)
        : Duration(seconds: _config.emptyShutdownDelaySeconds);
    _shutdownTimer?.cancel();
    _shutdownTimer = Timer(duration, () {
      unawaited(dispose());
    });
  }

  bool get _hasAuthenticatedClients {
    return _clients.any((client) => client.authenticated);
  }

  bool get _hasRunningSessions {
    return _sessions.values.any((session) => session.running);
  }

  Future<void> _deleteControlFile() async {
    try {
      if (await _controlFile.exists()) {
        await _controlFile.delete();
      }
    } catch (_) {}
  }
}
