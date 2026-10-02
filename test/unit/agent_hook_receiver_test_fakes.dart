part of 'agent_hook_receiver_test.dart';

class _FakeStatusSink implements AgentStatusSink {
  final events = <AgentHookEvent>[];

  @override
  void applyHookEvent(AgentHookEvent event) {
    events.add(event);
  }
}

class _ThrowingStatusSink implements AgentStatusSink {
  @override
  void applyHookEvent(AgentHookEvent event) {
    throw StateError('sink failed');
  }
}

class _FakeAgentHookServer implements AgentHookServer {
  final _batches = StreamController<AgentHookEventBatch>.broadcast();
  final _enabledAgents = <String>{};
  final stopStarted = Completer<void>();

  HttpServer? _server;
  String _token = '';
  Completer<void>? stopGate;
  var startCount = 0;
  var watchCount = 0;

  @override
  Stream<AgentHookEventBatch> watchEventBatches() {
    watchCount++;
    return _batches.stream;
  }

  @override
  Future<int> start({
    required String token,
    required List<String> enabledAgents,
  }) async {
    startCount++;
    _token = token;
    _enabledAgents
      ..clear()
      ..addAll(enabledAgents);
    final existing = _server;
    if (existing != null) {
      return existing.port;
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    unawaited(_serve(server));
    return server.port;
  }

  @override
  Future<void> setEnabledAgents(List<String> enabledAgents) async {
    _enabledAgents
      ..clear()
      ..addAll(enabledAgents);
  }

  @override
  Future<void> stop() async {
    if (!stopStarted.isCompleted) {
      stopStarted.complete();
    }
    await stopGate?.future;
    stopGate = null;
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  void emit(AgentHookEventBatch batch) {
    _batches.add(batch);
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      await _handle(request);
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final agentType = _agentTypeForPath(request.uri.path);
    if (request.method != 'POST' || agentType == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    if (request.headers.value(aleraAgentHookTokenHeader) != _token) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    if (!_enabledAgents.contains(agentType.key)) {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }
    try {
      final bodyBytes = <int>[];
      await for (final chunk in request) {
        bodyBytes.addAll(chunk);
        if (bodyBytes.length > agentHookRequestMaxBytes) {
          throw const FormatException('too large');
        }
      }
      final decoded = decodeAgentHookRequestBody(
        contentType: request.headers.contentType?.toString() ?? '',
        bodyBytes: bodyBytes,
      );
      final event = parseAgentHookRequest(agentType: agentType, body: decoded);
      if (event != null) {
        _batches.add(AgentHookEventBatch(events: <AgentHookEvent>[event]));
      }
    } catch (_) {}
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
  }

  AgentType? _agentTypeForPath(String path) {
    if (!path.startsWith('/hook/')) {
      return null;
    }
    final key = path.substring('/hook/'.length);
    for (final agentType in AgentType.values) {
      if (agentType.key == key) {
        return agentType;
      }
    }
    return null;
  }
}
