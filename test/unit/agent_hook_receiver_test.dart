import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_endpoint_file.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_receiver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentHookReceiver', () {
    late Directory tempDir;
    late _FakeStatusSink sink;
    late AgentHookReceiver receiver;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('alera-hook-receiver-');
      sink = _FakeStatusSink();
      receiver = AgentHookReceiver(
        statusSink: sink,
        applicationSupportDirectory: () async => tempDir,
        token: 'token-1',
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
        contentType: ContentType.json,
      );

      expect(response.statusCode, HttpStatus.forbidden);
      expect(sink.events, isEmpty);
    });

    test('returns 404 outside supported hook routes', () async {
      final response = await _post(
        receiver.endpoint!.port,
        path: '/hook/unknown',
        token: 'token-1',
        body: jsonEncode(<String, Object?>{}),
        contentType: ContentType.json,
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
        contentType: ContentType.json,
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
        contentType: ContentType.json,
      );

      expect(response.statusCode, HttpStatus.noContent);
      expect(sink.events, hasLength(1));
      expect(sink.events.single.agentType, AgentType.agy);
      expect(sink.events.single.payload['prompt'], 'ship it');
    });

    test('accepts Cursor, OpenCode, Pi, and Amp hook routes', () async {
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
        contentType: ContentType.json,
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
        contentType: ContentType.json,
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
        contentType: ContentType.json,
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
        contentType: ContentType.json,
      );

      expect(cursorResponse.statusCode, HttpStatus.noContent);
      expect(openCodeResponse.statusCode, HttpStatus.noContent);
      expect(piResponse.statusCode, HttpStatus.noContent);
      expect(ampResponse.statusCode, HttpStatus.noContent);
      expect(sink.events.map((event) => event.agentType), <AgentType>[
        AgentType.cursor,
        AgentType.opencode,
        AgentType.pi,
        AgentType.amp,
      ]);
    });

    test('ignores disabled agents with 204', () async {
      await receiver.dispose();
      sink = _FakeStatusSink();
      receiver = AgentHookReceiver(
        statusSink: sink,
        applicationSupportDirectory: () async => tempDir,
        token: 'token-1',
        isAgentEnabled: (agentType) => agentType != AgentType.copilot,
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
        contentType: ContentType.json,
      );

      expect(response.statusCode, HttpStatus.noContent);
      expect(sink.events, isEmpty);
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
