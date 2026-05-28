part of 'terminal_host_server_test.dart';

final class _TerminalHostServerHarness {
  _TerminalHostServerHarness._({
    required this.tempDir,
    required this.runtimeDir,
    required this.controlFile,
    required this.token,
    required this._server,
    required this._runFuture,
  });

  static Future<_TerminalHostServerHarness> start({
    Directory? tempDir,
    String token = 'token-1',
    TerminalHostConfig config = TerminalHostConfig.defaults,
  }) async {
    final root =
        tempDir ?? await Directory.systemTemp.createTemp('alera-host-server-');
    final runtimeDir = Directory(p.join(root.path, 'terminal_host'));
    final controlFile = File(p.join(runtimeDir.path, 'host.json'));
    if (await controlFile.exists()) {
      await controlFile.delete();
    }
    final server = AleraTerminalHostServer(
      runtimeDir: runtimeDir.path,
      controlFilePath: controlFile.path,
      token: token,
      config: config,
    );
    final runFuture = server.run();
    final harness = _TerminalHostServerHarness._(
      tempDir: root,
      runtimeDir: runtimeDir,
      controlFile: controlFile,
      token: token,
      server: server,
      runFuture: runFuture,
    );
    await harness._waitForControlFile();
    return harness;
  }

  final Directory tempDir;
  final Directory runtimeDir;
  final File controlFile;
  final String token;
  final AleraTerminalHostServer _server;
  final Future<void> _runFuture;
  bool _disposed = false;

  Future<_TerminalHostJsonClient> connect() async {
    final control = Map<String, Object?>.from(
      jsonDecode(await controlFile.readAsString()) as Map,
    );
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      control['port']! as int,
    );
    return _TerminalHostJsonClient(socket);
  }

  Future<void> writeHistory({
    required String sessionId,
    required DateTime? endedAt,
    required List<int> buffer,
  }) async {
    final store = TerminalHostHistoryStore.open(runtimeDir: runtimeDir);
    try {
      store.upsert(
        TerminalHostCheckpoint(
          sessionId: sessionId,
          workspaceId: 'workspace-1',
          tabId: 'tab-1',
          workingDirectory: Directory.current.path,
          running: false,
          exitCode: null,
          endedAt: endedAt,
          updatedAt: DateTime.now().toUtc(),
          buffer: Uint8List.fromList(buffer),
        ),
      );
    } finally {
      store.close();
    }
  }

  Future<void> writeLegacyHistory({
    required String sessionId,
    required String contents,
  }) async {
    final file = File(
      p.join(
        runtimeDir.path,
        'sessions',
        '${Uri.encodeComponent(sessionId)}.json',
      ),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  Future<TerminalHostCheckpoint?> readHistory(String sessionId) async {
    final store = TerminalHostHistoryStore.open(runtimeDir: runtimeDir);
    try {
      return store.read(sessionId);
    } finally {
      store.close();
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _server.dispose();
    await _runFuture.timeout(const Duration(seconds: 2));
  }

  Future<void> waitForStop() async {
    await _runFuture.timeout(const Duration(seconds: 5));
  }

  Future<void> _waitForControlFile() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (await controlFile.exists()) {
        final control = Map<String, Object?>.from(
          jsonDecode(await controlFile.readAsString()) as Map,
        );
        if (control['token'] == token) {
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    throw StateError('terminal host test server did not publish control file');
  }

  File get historyDatabaseFile =>
      File(p.join(runtimeDir.path, terminalHostHistoryDatabaseFileName));
}

final class _TerminalHostJsonClient {
  _TerminalHostJsonClient(this._socket) {
    _sub = _socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine, onDone: _completeDone, onError: _completeDone);
  }

  final Socket _socket;
  final Map<int, Completer<Map<String, Object?>>> _responses =
      <int, Completer<Map<String, Object?>>>{};
  final List<Map<String, Object?>> _queuedEvents = <Map<String, Object?>>[];
  final List<Completer<Map<String, Object?>>> _eventWaiters =
      <Completer<Map<String, Object?>>>[];
  final Completer<void> _done = Completer<void>();
  late final StreamSubscription<String> _sub;
  int _nextId = 1;

  Future<void> get done => _done.future.timeout(const Duration(seconds: 5));

  Future<Map<String, Object?>> hello(String token) {
    return _requestWithId(0, 'hello', <String, Object?>{
      'protocolVersion': aleraTerminalHostProtocolVersion,
      'token': token,
    });
  }

  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload,
  ) {
    return _requestWithId(_nextId++, type, payload);
  }

  Future<Map<String, Object?>> event(String type, {String? sessionId}) async {
    while (true) {
      final event = _queuedEvents.isNotEmpty
          ? _queuedEvents.removeAt(0)
          : await _waitForEvent();
      if (event['event'] != type) {
        continue;
      }
      final payload = event.payload;
      if (sessionId == null || payload['sessionId'] == sessionId) {
        return event;
      }
    }
  }

  Future<String> outputContaining(String sessionId, String expected) async {
    final buffer = StringBuffer();
    while (!buffer.toString().contains(expected)) {
      final event = await this.event('output', sessionId: sessionId);
      buffer.write(
        utf8.decode(decodeTerminalHostBytes(event.payload['dataBase64'])),
      );
    }
    return buffer.toString();
  }

  void writeRaw(Map<String, Object?> message) {
    _socket.writeln(jsonEncode(message));
  }

  Future<void> dispose() async {
    await _sub.cancel();
    _socket.destroy();
    _completeDone();
  }

  Future<Map<String, Object?>> _requestWithId(
    int id,
    String type,
    Map<String, Object?> payload,
  ) {
    final completer = Completer<Map<String, Object?>>();
    _responses[id] = completer;
    writeRaw(<String, Object?>{'id': id, 'type': type, 'payload': payload});
    return completer.future.timeout(const Duration(seconds: 5));
  }

  void _handleLine(String line) {
    final message = Map<String, Object?>.from(jsonDecode(line) as Map);
    if (message.containsKey('event')) {
      if (_eventWaiters.isEmpty) {
        _queuedEvents.add(message);
      } else {
        _eventWaiters.removeAt(0).complete(message);
      }
      return;
    }
    final id = message['id'];
    if (id is int) {
      _responses.remove(id)?.complete(message);
    }
  }

  void _completeDone([Object? error]) {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  Future<Map<String, Object?>> _waitForEvent() {
    final completer = Completer<Map<String, Object?>>();
    _eventWaiters.add(completer);
    return completer.future.timeout(const Duration(seconds: 5));
  }
}
