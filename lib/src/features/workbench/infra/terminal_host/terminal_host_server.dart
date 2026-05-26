// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:portable_pty/portable_pty.dart';

final class AleraTerminalHostServer {
  AleraTerminalHostServer({
    required String runtimeDir,
    required String controlFilePath,
    required String token,
  }) : _runtimeDir = Directory(runtimeDir),
       _controlFile = File(controlFilePath),
       _token = token,
       _historyDir = Directory(p.join(runtimeDir, 'sessions'));

  final Directory _runtimeDir;
  final Directory _historyDir;
  final File _controlFile;
  final String _token;
  final Map<String, _TerminalHostSession> _sessions =
      <String, _TerminalHostSession>{};
  final Set<_TerminalHostClientConnection> _clients =
      <_TerminalHostClientConnection>{};

  ServerSocket? _server;

  Future<void> run() async {
    if (!await _runtimeDir.exists()) {
      await _runtimeDir.create(recursive: true);
    }
    if (!await _historyDir.exists()) {
      await _historyDir.create(recursive: true);
    }
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    await _writeControlFile(_server!.port);
    await for (final socket in _server!) {
      _accept(socket);
    }
  }

  Future<void> dispose() async {
    final clients = _clients.toList(growable: false);
    for (final client in clients) {
      client.dispose();
    }
    final sessions = _sessions.values.toList(growable: false);
    _sessions.clear();
    for (final session in sessions) {
      await session.terminate(removeHistory: false);
    }
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
          'error': error.toString(),
        });
      } else {
        client.dispose();
      }
    }
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
      historyFile: _historyFile(sessionId),
    );
    if (restored != null) {
      _sessions[sessionId] = restored;
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
      historyFile: _historyFile(sessionId),
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

  File _historyFile(String sessionId) {
    return File(
      p.join(_historyDir.path, '${Uri.encodeComponent(sessionId)}.json'),
    );
  }
}

final class _TerminalHostSession {
  _TerminalHostSession._({
    required this.id,
    required this.workspaceId,
    required this.tabId,
    required this.workingDirectory,
    required File historyFile,
    required PortablePty? pty,
    required bool running,
    required List<int> buffer,
    required int? exitCode,
    required DateTime? endedAt,
  }) : _historyFile = historyFile,
       _pty = pty,
       _running = running,
       _buffer = <int>[...buffer],
       _exitCode = exitCode,
       _endedAt = endedAt;

  static Future<_TerminalHostSession> start({
    required String id,
    required String workspaceId,
    required String tabId,
    required String workingDirectory,
    required TerminalHostLaunch launch,
    required int cols,
    required int rows,
    required File historyFile,
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
      id: id,
      workspaceId: workspaceId,
      tabId: tabId,
      workingDirectory: workingDirectory,
      historyFile: historyFile,
      pty: pty,
      running: true,
      buffer: const <int>[],
      exitCode: null,
      endedAt: null,
    );
    await session._writeCheckpoint();
    await session._startReader(pty);
    return session;
  }

  static Future<_TerminalHostSession?> restoreExited({
    required String sessionId,
    required String workspaceId,
    required String tabId,
    required File historyFile,
  }) async {
    try {
      if (!await historyFile.exists()) {
        return null;
      }
      final decoded = jsonDecode(await historyFile.readAsString());
      final map = asTerminalHostMap(decoded, 'terminal host history');
      if (map['endedAt'] == null) {
        return _TerminalHostSession._(
          id: sessionId,
          workspaceId: workspaceId,
          tabId: tabId,
          workingDirectory: (map['workingDirectory'] as String?) ?? '',
          historyFile: historyFile,
          pty: null,
          running: false,
          buffer: decodeTerminalHostBytes(map['bufferBase64']),
          exitCode: -1,
          endedAt: null,
        );
      }
      final endedAt = DateTime.tryParse(map['endedAt'] as String? ?? '');
      return _TerminalHostSession._(
        id: sessionId,
        workspaceId: workspaceId,
        tabId: tabId,
        workingDirectory: (map['workingDirectory'] as String?) ?? '',
        historyFile: historyFile,
        pty: null,
        running: false,
        buffer: decodeTerminalHostBytes(map['bufferBase64']),
        exitCode: (map['exitCode'] as int?) ?? 0,
        endedAt: endedAt,
      );
    } catch (_) {
      return null;
    }
  }

  final String id;
  final String workspaceId;
  final String tabId;
  final String workingDirectory;
  final File _historyFile;
  final Set<_TerminalHostClientConnection> _clients =
      <_TerminalHostClientConnection>{};

  PortablePty? _pty;
  Isolate? _reader;
  ReceivePort? _readerPort;
  StreamSubscription<Object?>? _readerSub;
  Timer? _checkpointTimer;
  List<int> _buffer;
  bool _running;
  int? _exitCode;
  DateTime? _endedAt;
  bool _terminated = false;
  int _checkpointSerial = 0;

  Map<String, Object?> attachmentPayload({required bool created}) {
    return <String, Object?>{
      'sessionId': id,
      'created': created,
      'running': _running,
      'exitCode': _exitCode,
      'snapshotBase64': encodeTerminalHostBytes(_buffer),
    };
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
      try {
        if (await _historyFile.exists()) {
          await _historyFile.delete();
        }
      } catch (_) {}
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
    _buffer.addAll(data);
    if (_buffer.length > _maxTerminalHostBufferBytes) {
      _buffer = _buffer.sublist(_buffer.length - _maxTerminalHostBufferBytes);
    }
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
    final parent = _historyFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final temp = File('${_historyFile.path}.tmp.${_checkpointSerial++}');
    await temp.writeAsString(
      jsonEncode(<String, Object?>{
        'protocolVersion': aleraTerminalHostProtocolVersion,
        'sessionId': id,
        'workspaceId': workspaceId,
        'tabId': tabId,
        'workingDirectory': workingDirectory,
        'running': _running,
        'exitCode': _exitCode,
        'endedAt': _endedAt?.toIso8601String(),
        'bufferBase64': encodeTerminalHostBytes(_buffer),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    await temp.rename(_historyFile.path);
  }
}

final class _TerminalHostClientConnection {
  _TerminalHostClientConnection(this._socket, {required this.onDispose})
    : lines = _socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();

  final Socket _socket;
  final void Function(_TerminalHostClientConnection client) onDispose;
  final Stream<String> lines;
  bool authenticated = false;
  bool _disposed = false;

  void requireAuthenticated() {
    if (!authenticated) {
      throw StateError('Terminal host client is not authenticated.');
    }
  }

  void write(Map<String, Object?> message) {
    if (_disposed) {
      return;
    }
    _socket.writeln(jsonEncode(message));
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    onDispose(this);
    _socket.destroy();
  }
}

void _terminalHostPtyReader(List<Object?> args) {
  final pty = args[0] as PortablePty;
  final sendPort = args[1] as SendPort;
  try {
    while (true) {
      final data = pty.readSync(_terminalHostReadChunkBytes);
      if (data.isEmpty) {
        break;
      }
      sendPort.send(data);
    }
    sendPort.send(<Object?, Object?>{'type': 'exit', 'exitCode': pty.wait()});
  } catch (error) {
    // coverage:ignore-start
    int exitCode = -1;
    try {
      exitCode = pty.tryWait() ?? -1;
    } catch (_) {}
    sendPort.send(<Object?, Object?>{
      'type': 'error',
      'error': error.toString(),
      'exitCode': exitCode,
    });
    // coverage:ignore-end
  }
}

const int _terminalHostReadChunkBytes = 8192;
const int _maxTerminalHostBufferBytes = 1024 * 1024;
const Duration _terminalHostCheckpointDelay = Duration(seconds: 1);
