import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_endpoint_file.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_request_parser.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_receiver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentHookReceiver', () {
    late Directory tempDir;
    late _FakeStatusSink sink;
    late _FakeAgentHookServer hookServer;
    late AgentHookReceiver receiver;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('alera-hook-receiver-');
      sink = _FakeStatusSink();
      hookServer = _FakeAgentHookServer();
      receiver = AgentHookReceiver(
        statusSink: sink,
        applicationSupportDirectory: () async => tempDir,
        token: 'token-1',
        hookServer: hookServer,
      );
      await receiver.start();
    });

    tearDown(() async {
      await receiver.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('writes endpoint file and exposes launch metadata', () async {
      final endpoint = receiver.endpoint!;

      expect(receiver.isRunning, isTrue);
      expect(File(endpoint.filePath).existsSync(), isTrue);
      expect(File(endpoint.filePath).readAsStringSync(), contains('token-1'));
      expect(
        await receiver.launchEnvironmentFor(
          terminalSessionId: 'session-1',
          workspaceId: 'workspace-1',
          tabId: 'tab-1',
        ),
        containsPair('ALERA_TERMINAL_SESSION_ID', 'session-1'),
      );
    });

    test('rejects bad tokens with 403', () async {
      final response = await _post(
        receiver.endpoint!.port,
        path: '/hook/codex',
        token: 'wrong',
        body: jsonEncode(<String, Object?>{}),
        contentType: .json,
      );

      expect(response.statusCode, HttpStatus.forbidden);
      expect(sink.events, isEmpty);
    });

    test(
      'start throws after dispose and stop waits for failed startup',
      () async {
        await receiver.dispose();
        expect(receiver.isRunning, isFalse);
        expect(receiver.start, throwsStateError);

        final failingReceiver = AgentHookReceiver(
          statusSink: sink,
          applicationSupportDirectory: () async =>
              throw StateError('no support'),
          token: 'token-1',
          hookServer: _FakeAgentHookServer(),
        );
        addTearDown(failingReceiver.dispose);

        await expectLater(failingReceiver.start(), throwsStateError);
        await failingReceiver.stop();

        expect(failingReceiver.isRunning, isFalse);

        final supportCompleter = Completer<Directory>();
        final slowFailingReceiver = AgentHookReceiver(
          statusSink: sink,
          applicationSupportDirectory: () => supportCompleter.future,
          token: 'token-1',
          hookServer: _FakeAgentHookServer(),
        );
        addTearDown(slowFailingReceiver.dispose);

        final startFuture = slowFailingReceiver.start();
        final stopFuture = slowFailingReceiver.stop();
        supportCompleter.completeError(StateError('no support'));

        await expectLater(startFuture, throwsStateError);
        await stopFuture;
        expect(slowFailingReceiver.isRunning, isFalse);
      },
    );

    test('returns 404 outside supported hook routes', () async {
      final response = await _post(
        receiver.endpoint!.port,
        path: '/hook/unknown',
        token: 'token-1',
        body: jsonEncode(<String, Object?>{}),
        contentType: .json,
      );

      expect(response.statusCode, HttpStatus.notFound);
      expect(sink.events, isEmpty);
    });

    test('accepts malformed hook bodies without applying status', () async {
      final response = await _post(
        receiver.endpoint!.port,
        path: '/hook/codex',
        token: 'token-1',
        body: '{not json',
        contentType: .json,
      );

      expect(response.statusCode, HttpStatus.noContent);
      expect(sink.events, isEmpty);
    });

    test('applies valid hook events', () async {
      final response = await _post(
        receiver.endpoint!.port,
        path: '/hook/agy',
        token: 'token-1',
        body: jsonEncode(<String, Object?>{
          'terminalSessionId': 'session-1',
          'workspaceId': 'workspace-1',
          'tabId': 'tab-1',
          'hook_event_name': 'PreInvocation',
          'payload': <String, Object?>{'prompt': 'ship it'},
        }),
        contentType: .json,
      );

      expect(response.statusCode, HttpStatus.noContent);
      expect(sink.events, hasLength(1));
      expect(sink.events.single.agentType, AgentType.agy);
      expect(sink.events.single.payload['prompt'], 'ship it');
    });

    test(
      'accepts Cursor, OpenCode, OpenCode 2, Pi, Amp, and Grok hook routes',
      () async {
        final cursorResponse = await _post(
          receiver.endpoint!.port,
          path: '/hook/cursor',
          token: 'token-1',
          body: jsonEncode(<String, Object?>{
            'terminalSessionId': 'session-0',
            'workspaceId': 'workspace-1',
            'tabId': 'tab-0',
            'payload': <String, Object?>{
              'hook_event_name': 'beforeSubmitPrompt',
              'prompt': 'ship cursor',
            },
          }),
          contentType: .json,
        );
        final openCodeResponse = await _post(
          receiver.endpoint!.port,
          path: '/hook/opencode',
          token: 'token-1',
          body: jsonEncode(<String, Object?>{
            'terminalSessionId': 'session-1',
            'workspaceId': 'workspace-1',
            'tabId': 'tab-1',
            'payload': <String, Object?>{'hook_event_name': 'SessionBusy'},
          }),
          contentType: .json,
        );
        final openCode2Response = await _post(
          receiver.endpoint!.port,
          path: '/hook/opencode2',
          token: 'token-1',
          body: jsonEncode(<String, Object?>{
            'terminalSessionId': 'session-1b',
            'workspaceId': 'workspace-1',
            'tabId': 'tab-1b',
            'payload': <String, Object?>{'hook_event_name': 'SessionBusy'},
          }),
          contentType: .json,
        );
        final piResponse = await _post(
          receiver.endpoint!.port,
          path: '/hook/pi',
          token: 'token-1',
          body: jsonEncode(<String, Object?>{
            'terminalSessionId': 'session-2',
            'workspaceId': 'workspace-1',
            'tabId': 'tab-2',
            'payload': <String, Object?>{
              'hook_event_name': 'before_agent_start',
              'prompt': 'run tests',
            },
          }),
          contentType: .json,
        );
        final ampResponse = await _post(
          receiver.endpoint!.port,
          path: '/hook/amp',
          token: 'token-1',
          body: jsonEncode(<String, Object?>{
            'terminalSessionId': 'session-3',
            'workspaceId': 'workspace-1',
            'tabId': 'tab-3',
            'payload': <String, Object?>{
              'hook_event_name': 'agent.start',
              'message': 'ship amp',
            },
          }),
          contentType: .json,
        );
        final grokResponse = await _post(
          receiver.endpoint!.port,
          path: '/hook/grok',
          token: 'token-1',
          body: jsonEncode(<String, Object?>{
            'terminalSessionId': 'session-4',
            'workspaceId': 'workspace-1',
            'tabId': 'tab-4',
            'hookEventName': 'UserPromptSubmit',
            'payload': <String, Object?>{'prompt': 'ship grok'},
          }),
          contentType: .json,
        );

        expect(cursorResponse.statusCode, HttpStatus.noContent);
        expect(openCodeResponse.statusCode, HttpStatus.noContent);
        expect(openCode2Response.statusCode, HttpStatus.noContent);
        expect(piResponse.statusCode, HttpStatus.noContent);
        expect(ampResponse.statusCode, HttpStatus.noContent);
        expect(grokResponse.statusCode, HttpStatus.noContent);
        expect(sink.events.map((event) => event.agentType), <AgentType>[
          AgentType.cursor,
          AgentType.opencode,
          AgentType.opencode2,
          AgentType.pi,
          AgentType.amp,
          AgentType.grok,
        ]);
      },
    );

    test('ignores disabled agents with 204', () async {
      await receiver.dispose();
      sink = _FakeStatusSink();
      receiver = AgentHookReceiver(
        statusSink: sink,
        applicationSupportDirectory: () async => tempDir,
        token: 'token-1',
        isAgentEnabled: (agentType) => agentType != AgentType.copilot,
        hookServer: _FakeAgentHookServer(),
      );
      await receiver.start();

      final response = await _post(
        receiver.endpoint!.port,
        path: '/hook/copilot',
        token: 'token-1',
        body: jsonEncode(<String, Object?>{
          'terminalSessionId': 'session-1',
          'workspaceId': 'workspace-1',
          'tabId': 'tab-1',
          'hookEventName': 'UserPromptSubmit',
          'payload': <String, Object?>{'prompt': 'ship it'},
        }),
        contentType: .json,
      );

      expect(response.statusCode, HttpStatus.noContent);
      expect(sink.events, isEmpty);
    });

    test('swallows status sink failures after parsing a hook', () async {
      await receiver.dispose();
      receiver = AgentHookReceiver(
        statusSink: _ThrowingStatusSink(),
        applicationSupportDirectory: () async => tempDir,
        token: 'token-1',
        hookServer: _FakeAgentHookServer(),
      );
      await receiver.start();

      final response = await _post(
        receiver.endpoint!.port,
        path: '/hook/claude',
        token: 'token-1',
        body: jsonEncode(<String, Object?>{
          'terminalSessionId': 'session-1',
          'workspaceId': 'workspace-1',
          'tabId': 'tab-1',
          'hookEventName': 'UserPromptSubmit',
          'payload': <String, Object?>{'prompt': 'ship it'},
        }),
        contentType: .json,
      );

      expect(response.statusCode, HttpStatus.noContent);
    });
  });
}

Future<HttpClientResponse> _post(
  int port, {
  required String path,
  required String token,
  required String body,
  required ContentType contentType,
}) async {
  final client = HttpClient();
  addTearDown(client.close);
  final request = await client.postUrl(
    Uri.parse('http://127.0.0.1:$port$path'),
  );
  request.headers.set(aleraAgentHookTokenHeader, token);
  request.headers.contentType = contentType;
  request.write(body);
  return request.close();
}

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

  HttpServer? _server;
  String _token = '';

  @override
  Stream<AgentHookEventBatch> watchEventBatches() => _batches.stream;

  @override
  Future<int> start({
    required String token,
    required List<String> enabledAgents,
  }) async {
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
    final server = _server;
    _server = null;
    await server?.close(force: true);
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
