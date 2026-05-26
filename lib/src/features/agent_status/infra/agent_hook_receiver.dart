import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_endpoint_file.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_request_parser.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

typedef ApplicationSupportDirectoryResolver = Future<Directory> Function();

class AgentHookReceiver {
  AgentHookReceiver({
    required AgentStatusSink statusSink,
    ApplicationSupportDirectoryResolver? applicationSupportDirectory,
    String? token,
    // ignore: prefer_initializing_formals
  }) : _statusSink = statusSink,
       _applicationSupportDirectory =
           applicationSupportDirectory ?? getApplicationSupportDirectory,
       _token = token ?? createAgentHookToken();

  final AgentStatusSink _statusSink;
  final ApplicationSupportDirectoryResolver _applicationSupportDirectory;
  final String _token;

  HttpServer? _server;
  Future<void>? _starting;
  AgentHookEndpoint? _endpoint;
  bool _disposed = false;
  late final shelf.Handler _handler = _buildHandler();

  bool get isRunning => _server != null;

  AgentHookEndpoint? get endpoint => _endpoint;

  Future<void> start() {
    if (_disposed) {
      throw StateError('Agent hook receiver is disposed.');
    }
    final server = _server;
    if (server != null) {
      return Future<void>.value();
    }
    return _starting ??= _start();
  }

  Future<void> stop() async {
    final starting = _starting;
    if (starting != null) {
      await starting.catchError((_) {});
    }
    _starting = null;
    final server = _server;
    _server = null;
    _endpoint = null;
    await server?.close(force: true);
  }

  Future<Map<String, String>?> launchEnvironmentFor({
    required String terminalSessionId,
    required String workspaceId,
    required String tabId,
  }) async {
    await start();
    return _endpoint?.launchEnvironment(
      terminalSessionId: terminalSessionId,
      workspaceId: workspaceId,
      tabId: tabId,
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
  }

  Future<void> _start() async {
    HttpServer? startedServer;
    try {
      final server = await shelf_io.serve(
        _handler,
        InternetAddress.loopbackIPv4,
        0,
        poweredByHeader: null,
      );
      startedServer = server;
      _server = server;
      final supportDir = await _applicationSupportDirectory();
      final endpointDir = Directory(p.join(supportDir.path, 'agent-hooks'));
      final kind = currentAgentHookEndpointFileKind();
      final endpointPath = p.join(
        endpointDir.path,
        agentHookEndpointFileName(kind: kind),
      );
      await writeAgentHookEndpointFile(
        directory: endpointDir,
        filePath: endpointPath,
        kind: kind,
        port: server.port,
        token: _token,
      );
      _endpoint = AgentHookEndpoint(
        filePath: endpointPath,
        port: server.port,
        token: _token,
        version: aleraAgentHookProtocolVersion,
      );
    } catch (_) {
      if (identical(_server, startedServer)) {
        _server = null;
      }
      await startedServer?.close(force: true);
      rethrow;
    } finally {
      _starting = null;
    }
  }

  shelf.Handler _buildHandler() {
    final router = Router(notFoundHandler: (_) => shelf.Response.notFound(null))
      ..post(
        '/hook/codex',
        (shelf.Request request) => _handleHookRequest(request, AgentType.codex),
      )
      ..post(
        '/hook/claude',
        (shelf.Request request) =>
            _handleHookRequest(request, AgentType.claude),
      );
    return router.call;
  }

  Future<shelf.Response> _handleHookRequest(
    shelf.Request request,
    AgentType agentType,
  ) async {
    try {
      if (request.headers[aleraAgentHookTokenHeader] != _token) {
        return shelf.Response(HttpStatus.forbidden);
      }

      AgentHookEvent? event;
      try {
        final bodyBytes = await _readRequestBytes(request);
        final decoded = decodeAgentHookRequestBody(
          contentType: request.mimeType ?? '',
          bodyBytes: bodyBytes,
        );
        event = parseAgentHookRequest(agentType: agentType, body: decoded);
      } catch (_) {
        event = null;
      }
      if (event != null) {
        _statusSink.applyHookEvent(event);
      }
      return shelf.Response(HttpStatus.noContent);
    } catch (_) {
      return shelf.Response(HttpStatus.noContent);
    }
  }

  Future<List<int>> _readRequestBytes(shelf.Request request) async {
    final bytes = <int>[];
    await for (final chunk in request.read()) {
      bytes.addAll(chunk);
      if (bytes.length > agentHookRequestMaxBytes) {
        throw const FormatException('Agent hook request body is too large.');
      }
    }
    return bytes;
  }
}
