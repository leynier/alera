import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_endpoint_file.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_request_parser.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_receiver.dart';
import 'package:flutter_test/flutter_test.dart';

part 'agent_hook_receiver_test_fakes.dart';

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

    test(
      'serializes a rapid stop and start and restores event delivery',
      () async {
        final stopGate = Completer<void>();
        hookServer.stopGate = stopGate;
        final stopFuture = receiver.stop();
        await hookServer.stopStarted.future;

        final startFuture = receiver.start();
        await Future.pause(Duration.zero);
        expect(hookServer.startCount, 1);

        stopGate.complete();
        await Future.wait(<Future<void>>[stopFuture, startFuture]);

        expect(hookServer.startCount, 2);
        expect(hookServer.watchCount, 2);
        hookServer.emit(
          AgentHookEventBatch(
            events: <AgentHookEvent>[
              AgentHookEvent(
                terminalSessionId: 'session-rapid',
                workspaceId: 'workspace-1',
                tabId: 'tab-rapid',
                agentType: AgentType.codex,
                payload: const <String, Object?>{},
              ),
            ],
          ),
        );
        await Future.pause(Duration.zero);

        expect(
          sink.events.map((event) => event.terminalSessionId),
          contains('session-rapid'),
        );
      },
    );

    test(
      'stops the producer before cancelling its gated event subscription',
      () async {
        final stopGate = Completer<void>();
        hookServer.stopGate = stopGate;
        final stopFuture = receiver.stop();
        try {
          await hookServer.stopStarted.future.timeout(
            const Duration(seconds: 1),
          );
          expect(hookServer.stopCount, 1);

          final startFuture = receiver.start();
          stopGate.complete();
          await Future.wait(<Future<void>>[stopFuture, startFuture]);

          expect(hookServer.startCount, 2);
          expect(hookServer.watchCount, 2);
        } finally {
          if (!stopGate.isCompleted) {
            stopGate.complete();
          }
          hookServer.releaseProducer();
          await stopFuture;
        }
      },
    );

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
        final resolverCalled = Completer<void>();
        final slowFailingReceiver = AgentHookReceiver(
          statusSink: sink,
          applicationSupportDirectory: () {
            resolverCalled.complete();
            return supportCompleter.future;
          },
          token: 'token-1',
          hookServer: _FakeAgentHookServer(),
        );
        addTearDown(slowFailingReceiver.dispose);

        final startFuture = slowFailingReceiver.start();
        final startExpectation = expectLater(startFuture, throwsStateError);
        final stopFuture = slowFailingReceiver.stop();
        await resolverCalled.future;
        supportCompleter.completeError(StateError('no support'));

        await startExpectation;
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
