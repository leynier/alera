part of 'terminal_host_client_test.dart';

final class _TerminalHostTestServer {
  _TerminalHostTestServer._(
    this._server, {
    this.errorForType,
    this.closeForType,
    this.beforeResponse,
    this.negotiateBinaryFrames = false,
  });

  static Future<_TerminalHostTestServer> start({
    String? errorForType,
    String? closeForType,
    Future<void> Function(String type)? beforeResponse,
    bool negotiateBinaryFrames = false,
  }) async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final server = _TerminalHostTestServer._(
      socket,
      errorForType: errorForType,
      closeForType: closeForType,
      beforeResponse: beforeResponse,
      negotiateBinaryFrames: negotiateBinaryFrames,
    );
    server._sub = socket.listen(server._accept, onError: (_) {});
    return server;
  }

  final ServerSocket _server;
  final String? errorForType;
  final String? closeForType;
  final Future<void> Function(String type)? beforeResponse;
  final bool negotiateBinaryFrames;
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];
  StreamSubscription<Socket>? _sub;
  Socket? _client;
  String token = 'existing-token';
  int acceptedConnections = 0;
  bool _binaryFrames = false;

  bool get usingBinaryFrames => _binaryFrames;

  int get port => _server.port;

  List<String> get requestTypes {
    return <String>[for (final request in requests) request['type']! as String];
  }

  Map<String, Object?> payloadFor(String type) {
    return requests
        .where((request) => request['type'] == type)
        .map((request) => request['payload']! as Map<String, Object?>)
        .last;
  }

  void _accept(Socket socket) {
    acceptedConnections += 1;
    _client = socket;
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => unawaited(_handleLine(socket, line).catchError((_) {})),
          onError: (_) {},
        );
  }

  Future<void> _handleLine(Socket socket, String line) async {
    final request = Map<String, Object?>.from(jsonDecode(line) as Map);
    final payload = Map<String, Object?>.from(request['payload'] as Map);
    request['payload'] = payload;
    requests.add(request);
    final id = request['id'] as int;
    final type = request['type'] as String;
    await beforeResponse?.call(type);
    if (type == 'hello') {
      // Mirrors the host: the response goes out as a line, and only the bytes
      // after it are framed. The client must not switch any earlier.
      final accepted = negotiateBinaryFrames && payload['binaryFrames'] == true;
      socket.writeln(
        jsonEncode(<String, Object?>{
          'id': id,
          'ok': true,
          'payload': const <String, Object?>{},
          if (accepted) 'binaryFrames': true,
        }),
      );
      _binaryFrames = accepted;
      return;
    }
    if (type == closeForType) {
      socket.destroy();
      return;
    }
    if (type == errorForType) {
      _respond(socket, <String, Object?>{
        'id': id,
        'ok': false,
        'error': '$type failed',
      });
      return;
    }
    if (type == 'createOrAttach') {
      _respond(socket, <String, Object?>{
        'id': id,
        'ok': true,
        'payload': <String, Object?>{
          'sessionId': 'session-1',
          'created': true,
          'running': true,
          'snapshotBase64': encodeTerminalHostBytes(<int>[65, 66]),
        },
      });
      return;
    }
    if (type == 'setOutputPaused') {
      _respond(socket, <String, Object?>{
        'id': id,
        'ok': true,
        'payload': <String, Object?>{
          'sessionId': 'session-1',
          'snapshotBase64': encodeTerminalHostBytes(<int>[83, 78, 65, 80]),
        },
      });
      return;
    }
    _respond(socket, <String, Object?>{
      'id': id,
      'ok': true,
      'payload': const <String, Object?>{},
    });
  }

  /// Writes a response in whichever mode this connection negotiated. The hello
  /// response itself never goes through here: it must stay a line.
  void _respond(Socket socket, Map<String, Object?> message) {
    if (_binaryFrames) {
      socket.add(encodeTerminalHostJsonFrame(jsonEncode(message)));
      return;
    }
    socket.writeln(jsonEncode(message));
  }

  void send(Map<String, Object?> message) {
    if (_binaryFrames) {
      _client!.add(encodeTerminalHostJsonFrame(jsonEncode(message)));
      return;
    }
    _client!.writeln(jsonEncode(message));
  }

  /// Sends PTY output the way the host would for this client's negotiated mode.
  void sendOutput(String sessionId, List<int> data) {
    if (_binaryFrames) {
      _client!.add(encodeTerminalHostOutputFrame(sessionId, data));
      return;
    }
    send(<String, Object?>{
      'event': 'output',
      'payload': <String, Object?>{
        'sessionId': sessionId,
        'dataBase64': encodeTerminalHostBytes(data),
      },
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _client?.destroy();
    await _server.close();
  }
}
