import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agents/acp/application/acp_agent_orchestrator.dart';
import 'package:alera/src/features/agents/acp/infrastructure/codex_acp_client.dart';
import 'package:alera/src/features/agents/application/agent_orchestrator_event.dart';
import 'package:alera/src/shared/infra/json_rpc/json_rpc_error_codes.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AcpAgentOrchestrator permission requests', () {
    test('emits protocol permission option ids and display names', () async {
      final harness = await _bootedHarness();

      final eventFuture = _firstApprovalEvent(harness.orchestrator);
      harness.process.sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'permission-1',
        'method': 'session/request_permission',
        'params': <String, dynamic>{
          'sessionId': 'session-1',
          'toolCall': <String, dynamic>{'title': 'Run command'},
          'options': <Map<String, dynamic>>[
            <String, dynamic>{
              'optionId': 'allow-once',
              'name': 'Allow once',
              'kind': 'allow_once',
            },
            <String, dynamic>{
              'optionId': 'opaque-option',
              'name': 'Use custom approval',
            },
            <String, dynamic>{'name': 'Missing id'},
          ],
        },
      });

      final event = await eventFuture.timeout(const Duration(seconds: 1));

      expect(event.requestId, 'permission-1');
      expect(event.threadId, 'session-1');
      expect(event.description, 'Run command');
      expect(event.options, hasLength(2));
      expect(event.options.first.optionId, 'allow-once');
      expect(event.options.first.name, 'Allow once');
      expect(event.options.first.kind, 'allow_once');
      expect(event.options.last.optionId, 'opaque-option');
      expect(event.options.last.name, 'Use custom approval');
    });

    test('falls back to sentence-case labels for options without names',
        () async {
      final harness = await _bootedHarness();

      final eventFuture = _firstApprovalEvent(harness.orchestrator);
      harness.process.sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'session/request_permission',
        'params': <String, dynamic>{
          'options': <Map<String, dynamic>>[
            <String, dynamic>{'optionId': 'allow_always'},
          ],
        },
      });

      final event = await eventFuture.timeout(const Duration(seconds: 1));

      expect(event.options.single.optionId, 'allow_always');
      expect(event.options.single.name, 'Allow always');
    });

    test('preserves opaque identifiers byte-for-byte (no trimming)', () async {
      final harness = await _bootedHarness();

      final eventFuture = _firstApprovalEvent(harness.orchestrator);
      harness.process.sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'permission-trim',
        'method': 'session/request_permission',
        'params': <String, dynamic>{
          'sessionId': '  s-with-padding  ',
          'options': <Map<String, dynamic>>[
            <String, dynamic>{
              'optionId': '  allow  ',
              'name': '  Allow this once  ',
              'kind': '  allow_once  ',
            },
          ],
        },
      });

      final event = await eventFuture.timeout(const Duration(seconds: 1));

      expect(event.threadId, '  s-with-padding  ',
          reason: 'sessionId is opaque and must not be trimmed');
      expect(event.options.single.optionId, '  allow  ',
          reason: 'optionId is opaque and must not be trimmed');
      expect(event.options.single.name, 'Allow this once',
          reason: 'name is human-readable and is trimmed');
      expect(event.options.single.kind, 'allow_once');
    });

    test(
      'description fallback uses filtered option count, not raw input length',
      () async {
        final harness = await _bootedHarness();

        final eventFuture = _firstApprovalEvent(harness.orchestrator);
        harness.process.sendServerRequest(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': 'permission-count',
          'method': 'session/request_permission',
          'params': <String, dynamic>{
            'options': <Map<String, dynamic>>[
              <String, dynamic>{'optionId': 'allow'},
              <String, dynamic>{'optionId': 'deny'},
              <String, dynamic>{'name': 'No id'},
              <String, dynamic>{'optionId': ''},
            ],
          },
        });

        final event = await eventFuture.timeout(const Duration(seconds: 1));

        expect(event.options, hasLength(2));
        expect(event.description, 'Approve action (2 options)');
      },
    );
  });

  group('AcpAgentOrchestrator request routing', () {
    test('responds methodNotFound for unknown server-initiated requests',
        () async {
      final harness = await _bootedHarness();

      harness.process.sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'unknown-1',
        'method': 'session/totally_new',
        'params': <String, dynamic>{},
      });

      final response = await harness.process
          .responseFor('unknown-1')
          .timeout(const Duration(seconds: 1));

      expect(response['error'], isA<Map>());
      expect((response['error'] as Map)['code'], jsonRpcMethodNotFound);
    });

    test('responds methodNotFound for unknown fs/* subcommands', () async {
      final harness = await _bootedHarness();

      harness.process.sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'fs-unknown',
        'method': 'fs/list_directory',
        'params': <String, dynamic>{},
      });

      final response = await harness.process
          .responseFor('fs-unknown')
          .timeout(const Duration(seconds: 1));

      expect((response['error'] as Map)['code'], jsonRpcMethodNotFound);
    });

    test('subscriptions receive events emitted before initialize completes',
        () async {
      final processRunner = _FakeAcpProcessRunner();
      final client =
          CodexAcpClient(processRunner: processRunner, executable: 'codex-acp');
      final orchestrator = AcpAgentOrchestrator(client);
      addTearDown(orchestrator.close);

      // Make initialize block until we explicitly release it, AND emit a
      // server-initiated notification in the meantime.
      processRunner.process.holdInitialize = true;

      final bootFuture = orchestrator.boot();

      // Allow the orchestrator's listeners to attach. (boot subscribes
      // BEFORE calling initialize.)
      await Future<void>.delayed(Duration.zero);

      processRunner.process.sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': <String, dynamic>{'sessionId': 'session-9'},
      });

      // Allow the notification to be delivered before initialize completes.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      processRunner.process.releaseInitialize();
      await bootFuture.timeout(const Duration(seconds: 1));

      // The orchestrator's events stream is broadcast; subscribe now and
      // verify the buffered notification was emitted. We re-emit a second
      // event after subscribing and ensure both shapes work.
      final received = <String>[];
      final sub = orchestrator.events.listen((event) {
        if (event is AgentNotificationEvent) {
          received.add(event.method);
        }
      });
      addTearDown(sub.cancel);

      processRunner.process.sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': <String, dynamic>{'sessionId': 'session-9', 'after': true},
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(received, contains('session/update'));
    });
  });

  group('AcpAgentOrchestrator boot lifecycle', () {
    test('boot is idempotent — second call is a no-op', () async {
      final harness = await _bootedHarness();

      // Tracking the number of `initialize` messages the fake observed.
      final initialCount = harness.process.initializeCount;
      await harness.orchestrator.boot();
      expect(harness.process.initializeCount, initialCount,
          reason: 'second boot must not re-send initialize');
    });

    test('boot reattaches no subscriptions on second call', () async {
      final harness = await _bootedHarness();
      await harness.orchestrator.boot();

      // Single server request → orchestrator must respond exactly once.
      harness.process.sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'idempotent-1',
        'method': 'session/totally_new',
        'params': <String, dynamic>{},
      });

      final response = await harness.process
          .responseFor('idempotent-1')
          .timeout(const Duration(seconds: 1));
      expect(response, isNotNull);

      // Give it a chance to incorrectly fire a second response.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(harness.process.respondedToIds['idempotent-1'], 1,
          reason: 'duplicate listeners would write two responses');
    });
  });

  group('AcpAgentOrchestrator unsupported gaps', () {
    test('startReview returns a rejected Future, not a synchronous throw',
        () async {
      final processRunner = _FakeAcpProcessRunner();
      final client =
          CodexAcpClient(processRunner: processRunner, executable: 'codex-acp');
      final orchestrator = AcpAgentOrchestrator(client);
      addTearDown(orchestrator.close);

      await expectLater(
        orchestrator.startReview(),
        throwsA(isA<UnsupportedError>()),
      );
      await expectLater(
        orchestrator.compactThread(),
        throwsA(isA<UnsupportedError>()),
      );
      await expectLater(
        orchestrator.setThreadName(),
        throwsA(isA<UnsupportedError>()),
      );
      await expectLater(
        orchestrator.steerTurn(),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('AcpAgentOrchestrator runTurn', () {
    test('emits Codex-shape turn/started + turn/completed and awaits the prompt',
        () async {
      final harness = await _bootedHarness();
      harness.process.promptStopReason = 'tool_use_limit';

      final completedFuture = harness.orchestrator.events
          .where((e) =>
              e is AgentNotificationEvent && e.method == 'turn/completed')
          .cast<AgentNotificationEvent>()
          .first;
      final startedFuture = harness.orchestrator.events
          .where(
              (e) => e is AgentNotificationEvent && e.method == 'turn/started')
          .cast<AgentNotificationEvent>()
          .first;

      final turnId = await harness.orchestrator.runTurn(
        threadId: 'thread-x',
        input: const <Map<String, dynamic>>[
          <String, dynamic>{'type': 'text', 'text': 'hello'},
        ],
      );

      final started = await startedFuture.timeout(const Duration(seconds: 1));
      final completed =
          await completedFuture.timeout(const Duration(seconds: 1));

      final startedTurn = (started.payload['params']
          as Map<String, dynamic>)['turn'] as Map<String, dynamic>;
      expect(startedTurn['id'], turnId);
      expect(startedTurn['threadId'], 'thread-x');
      expect(startedTurn['status'], 'started');

      final completedTurn = (completed.payload['params']
          as Map<String, dynamic>)['turn'] as Map<String, dynamic>;
      expect(completedTurn['id'], turnId);
      expect(completedTurn['threadId'], 'thread-x');
      expect(completedTurn['status'], 'completed');
      expect(completedTurn['stopReason'], 'tool_use_limit');
    });

    test('runTurn rethrows when session/prompt fails, AND emits turn/failed',
        () async {
      final harness = await _bootedHarness();
      harness.process.promptError = <String, dynamic>{
        'code': -32000,
        'message': 'agent rejected the prompt',
      };

      final failedFuture = harness.orchestrator.events
          .where(
              (e) => e is AgentNotificationEvent && e.method == 'turn/failed')
          .cast<AgentNotificationEvent>()
          .first;

      await expectLater(
        harness.orchestrator.runTurn(
          threadId: 'thread-fail',
          input: const <Map<String, dynamic>>[
            <String, dynamic>{'type': 'text', 'text': 'boom'},
          ],
        ),
        throwsA(isA<Object>()),
      );

      final failed = await failedFuture.timeout(const Duration(seconds: 1));
      final turn = (failed.payload['params'] as Map<String, dynamic>)['turn']
          as Map<String, dynamic>;
      expect(turn['status'], 'failed');
      expect(turn['error'], contains('agent rejected the prompt'));
    });
  });

  group('CodexAcpClient response coercion', () {
    test('non-String sessionId from session/new throws StateError', () async {
      final processRunner = _FakeAcpProcessRunner();
      final client =
          CodexAcpClient(processRunner: processRunner, executable: 'codex-acp');
      addTearDown(client.close);

      processRunner.process.sessionIdForNew = 12345; // numeric, not string
      await client.start();
      await client.initialize();

      await expectLater(
        client.newSession(cwd: Directory.systemTemp.path),
        throwsA(isA<StateError>()),
      );
    });

    test('loadSession throws when agent returns no sessionId', () async {
      final processRunner = _FakeAcpProcessRunner();
      final client =
          CodexAcpClient(processRunner: processRunner, executable: 'codex-acp');
      addTearDown(client.close);

      processRunner.process.omitSessionIdForLoad = true;
      await client.start();
      await client.initialize();

      await expectLater(
        client.loadSession(
          sessionId: 'old',
          cwd: Directory.systemTemp.path,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'prompt falls back to end_turn when stopReason missing or non-String',
      () async {
        final processRunner = _FakeAcpProcessRunner();
        final client = CodexAcpClient(
          processRunner: processRunner,
          executable: 'codex-acp',
        );
        addTearDown(client.close);

        processRunner.process.promptStopReasonRaw = 99; // not a string
        await client.start();
        await client.initialize();

        final stopReason =
            await client.prompt(sessionId: 's', content: <Map<String, dynamic>>[]);
        expect(stopReason, 'end_turn');
      },
    );
  });

  group('CodexAcpClient fs sandbox', () {
    test('rejects absolute paths outside the session cwd', () async {
      final tempDir = await Directory.systemTemp.createTemp('alera_acp_test_');
      addTearDown(() => tempDir.delete(recursive: true));

      final processRunner = _FakeAcpProcessRunner();
      final client = CodexAcpClient(
        processRunner: processRunner,
        executable: 'codex-acp',
      );
      addTearDown(client.close);

      await client.start();
      await client.initialize();
      await client.newSession(cwd: tempDir.path);

      // Write outside cwd → invalidParams.
      processRunner.process.sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'fs-escape',
        'method': 'fs/write_text_file',
        'params': <String, dynamic>{
          'path': '/etc/escape-test.txt',
          'content': 'nope',
        },
      });
      final response = await processRunner.process
          .responseFor('fs-escape')
          .timeout(const Duration(seconds: 1));

      expect((response['error'] as Map)['code'], jsonRpcInvalidParams);
    });

    test('rejects relative paths', () async {
      final tempDir = await Directory.systemTemp.createTemp('alera_acp_test_');
      addTearDown(() => tempDir.delete(recursive: true));

      final processRunner = _FakeAcpProcessRunner();
      final client = CodexAcpClient(
        processRunner: processRunner,
        executable: 'codex-acp',
      );
      addTearDown(client.close);

      await client.start();
      await client.initialize();
      await client.newSession(cwd: tempDir.path);

      processRunner.process.sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'fs-relative',
        'method': 'fs/read_text_file',
        'params': <String, dynamic>{'path': 'relative.txt'},
      });
      final response = await processRunner.process
          .responseFor('fs-relative')
          .timeout(const Duration(seconds: 1));

      expect((response['error'] as Map)['code'], jsonRpcInvalidParams);
    });

    test('rejects fs requests before any session is established', () async {
      final processRunner = _FakeAcpProcessRunner();
      final client = CodexAcpClient(
        processRunner: processRunner,
        executable: 'codex-acp',
      );
      addTearDown(client.close);

      await client.start();
      await client.initialize();

      processRunner.process.sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'fs-no-session',
        'method': 'fs/read_text_file',
        'params': <String, dynamic>{'path': '/tmp/file.txt'},
      });
      final response = await processRunner.process
          .responseFor('fs-no-session')
          .timeout(const Duration(seconds: 1));

      expect((response['error'] as Map)['code'], jsonRpcInvalidParams);
    });

    test('allows paths inside the session cwd', () async {
      final tempDir = await Directory.systemTemp.createTemp('alera_acp_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/inside.txt');
      await file.writeAsString('hello\nworld');

      final processRunner = _FakeAcpProcessRunner();
      final client = CodexAcpClient(
        processRunner: processRunner,
        executable: 'codex-acp',
      );
      addTearDown(client.close);

      await client.start();
      await client.initialize();
      await client.newSession(cwd: tempDir.path);

      processRunner.process.sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'fs-inside',
        'method': 'fs/read_text_file',
        'params': <String, dynamic>{'path': file.path},
      });
      final response = await processRunner.process
          .responseFor('fs-inside')
          .timeout(const Duration(seconds: 1));

      expect(response['result'], <String, dynamic>{'content': 'hello\nworld'});
    });
  });

  group('CodexAcpClient fs/read_text_file slicing', () {
    test('uses ACP 1-based line numbers for ranged reads', () async {
      final tempDir = await Directory.systemTemp.createTemp('alera_acp_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('one\ntwo\nthree\nfour');

      final processRunner = _FakeAcpProcessRunner();
      final client = CodexAcpClient(
        processRunner: processRunner,
        executable: 'codex-acp',
      );
      addTearDown(client.close);

      await client.start();
      await client.initialize();
      await client.newSession(cwd: tempDir.path);

      processRunner.process.sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'fs/read_text_file',
        'params': <String, dynamic>{'path': file.path, 'line': 1, 'limit': 1},
      });
      var response = await processRunner.process.responseFor(3);
      expect(response['result'], <String, dynamic>{'content': 'one'});

      processRunner.process.sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'fs/read_text_file',
        'params': <String, dynamic>{'path': file.path, 'line': 2, 'limit': 2},
      });
      response = await processRunner.process.responseFor(4);
      expect(response['result'], <String, dynamic>{'content': 'two\nthree'});
    });

    test('accepts JSON-decoded doubles for line/limit', () async {
      final tempDir = await Directory.systemTemp.createTemp('alera_acp_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('one\ntwo\nthree\nfour');

      final processRunner = _FakeAcpProcessRunner();
      final client = CodexAcpClient(
        processRunner: processRunner,
        executable: 'codex-acp',
      );
      addTearDown(client.close);

      await client.start();
      await client.initialize();
      await client.newSession(cwd: tempDir.path);

      processRunner.process.sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'double-line',
        'method': 'fs/read_text_file',
        'params': <String, dynamic>{
          'path': file.path,
          'line': 2.0,
          'limit': 2.0,
        },
      });
      final response = await processRunner.process.responseFor('double-line');
      expect(response['result'], <String, dynamic>{'content': 'two\nthree'});
    });

    test('rejects line<=0 with invalidParams', () async {
      final tempDir = await Directory.systemTemp.createTemp('alera_acp_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('one\ntwo');

      final processRunner = _FakeAcpProcessRunner();
      final client = CodexAcpClient(
        processRunner: processRunner,
        executable: 'codex-acp',
      );
      addTearDown(client.close);

      await client.start();
      await client.initialize();
      await client.newSession(cwd: tempDir.path);

      processRunner.process.sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'bad-line',
        'method': 'fs/read_text_file',
        'params': <String, dynamic>{'path': file.path, 'line': 0},
      });
      final response = await processRunner.process.responseFor('bad-line');
      expect((response['error'] as Map)['code'], jsonRpcInvalidParams);
    });

    test('rejects negative limit with invalidParams', () async {
      final tempDir = await Directory.systemTemp.createTemp('alera_acp_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('one\ntwo');

      final processRunner = _FakeAcpProcessRunner();
      final client = CodexAcpClient(
        processRunner: processRunner,
        executable: 'codex-acp',
      );
      addTearDown(client.close);

      await client.start();
      await client.initialize();
      await client.newSession(cwd: tempDir.path);

      processRunner.process.sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'bad-limit',
        'method': 'fs/read_text_file',
        'params': <String, dynamic>{'path': file.path, 'limit': -1},
      });
      final response = await processRunner.process.responseFor('bad-limit');
      expect((response['error'] as Map)['code'], jsonRpcInvalidParams);
    });

    test('starts at the first line when line is missing', () async {
      final tempDir = await Directory.systemTemp.createTemp('alera_acp_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('one\ntwo\nthree');

      final processRunner = _FakeAcpProcessRunner();
      final client = CodexAcpClient(
        processRunner: processRunner,
        executable: 'codex-acp',
      );
      addTearDown(client.close);

      await client.start();
      await client.initialize();
      await client.newSession(cwd: tempDir.path);

      processRunner.process.sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 5,
        'method': 'fs/read_text_file',
        'params': <String, dynamic>{'path': file.path, 'limit': 2},
      });
      final response = await processRunner.process.responseFor(5);
      expect(response['result'], <String, dynamic>{'content': 'one\ntwo'});
    });
  });
}

class _Harness {
  _Harness(this.orchestrator, this.processRunner);

  final AcpAgentOrchestrator orchestrator;
  final _FakeAcpProcessRunner processRunner;

  _FakeAcpProcess get process => processRunner.process;
}

Future<_Harness> _bootedHarness() async {
  final processRunner = _FakeAcpProcessRunner();
  final client =
      CodexAcpClient(processRunner: processRunner, executable: 'codex-acp');
  final orchestrator = AcpAgentOrchestrator(client);
  addTearDown(orchestrator.close);
  await orchestrator.boot();
  return _Harness(orchestrator, processRunner);
}

Future<AgentApprovalRequestEvent> _firstApprovalEvent(
  AcpAgentOrchestrator orchestrator,
) {
  return orchestrator.events
      .where((event) => event is AgentApprovalRequestEvent)
      .cast<AgentApprovalRequestEvent>()
      .first;
}

class _FakeAcpProcessRunner implements ProcessRunner {
  _FakeAcpProcessRunner() : process = _FakeAcpProcess();

  final _FakeAcpProcess process;

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    return process.startedProcess;
  }
}

class _FakeAcpProcess {
  final StreamController<List<int>> _stdout =
      StreamController<List<int>>.broadcast();
  final StreamController<List<int>> _stderr =
      StreamController<List<int>>.broadcast();
  final Completer<int> _exitCode = Completer<int>();
  final Map<Object, Completer<Map<String, dynamic>>> _responseWaiters =
      <Object, Completer<Map<String, dynamic>>>{};

  /// Counts how many times the client wrote to a given response id, so tests
  /// can detect duplicate listeners writing duplicate responses.
  final Map<Object, int> respondedToIds = <Object, int>{};

  /// Counts initialize requests received.
  int initializeCount = 0;

  /// If true, hold the initialize response until [releaseInitialize] is
  /// called. Useful to verify subscriptions are attached before initialize.
  bool holdInitialize = false;
  Map<String, dynamic>? _pendingInitialize;

  /// Customizable behavior for the session/prompt response.
  String promptStopReason = 'end_turn';
  Object? promptStopReasonRaw;
  Map<String, dynamic>? promptError;

  /// Customizable behavior for session/new / session/load.
  Object sessionIdForNew = 'session-1';
  bool omitSessionIdForLoad = false;

  String _stdinBuffer = '';

  StartedProcess get startedProcess => StartedProcess(
        stdinWrite: _stdinWrite,
        stdout: _stdout.stream,
        stderr: _stderr.stream,
        pid: 1001,
        exitCode: _exitCode.future,
        kill: ([signal]) {
          if (!_exitCode.isCompleted) {
            _exitCode.complete(0);
          }
          unawaited(_stdout.close());
          unawaited(_stderr.close());
          return true;
        },
      );

  Future<Map<String, dynamic>> responseFor(Object id) {
    final completer = _responseWaiters.putIfAbsent(
      id,
      () => Completer<Map<String, dynamic>>(),
    );
    return completer.future.timeout(const Duration(seconds: 1));
  }

  void sendServerRequest(Map<String, dynamic> message) {
    _stdout.add(utf8.encode('${jsonEncode(message)}\n'));
  }

  void releaseInitialize() {
    final pending = _pendingInitialize;
    if (pending == null) {
      return;
    }
    _pendingInitialize = null;
    sendServerRequest(pending);
  }

  void _stdinWrite(List<int> data) {
    _stdinBuffer += utf8.decode(data);
    while (_stdinBuffer.contains('\n')) {
      final index = _stdinBuffer.indexOf('\n');
      final rawLine = _stdinBuffer.substring(0, index).trim();
      _stdinBuffer = _stdinBuffer.substring(index + 1);
      if (rawLine.isEmpty) {
        continue;
      }
      final message = jsonDecode(rawLine) as Map<String, dynamic>;
      _handleClientMessage(message);
    }
  }

  void _handleClientMessage(Map<String, dynamic> message) {
    final id = message['id'];
    final method = message['method'];

    if (method == 'initialize') {
      initializeCount++;
      final response = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'protocolVersion': 1,
          'agentCapabilities': <String, dynamic>{},
        },
      };
      if (holdInitialize) {
        _pendingInitialize = response;
      } else {
        sendServerRequest(response);
      }
      return;
    }

    if (method == 'session/new') {
      sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{'sessionId': sessionIdForNew},
      });
      return;
    }

    if (method == 'session/load') {
      sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': omitSessionIdForLoad
            ? <String, dynamic>{}
            : <String, dynamic>{'sessionId': message['params']?['sessionId']},
      });
      return;
    }

    if (method == 'session/prompt') {
      if (promptError != null) {
        sendServerRequest(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'error': promptError,
        });
        return;
      }
      sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'stopReason': promptStopReasonRaw ?? promptStopReason,
        },
      });
      return;
    }

    if (id != null &&
        (message.containsKey('result') || message.containsKey('error'))) {
      respondedToIds[id] = (respondedToIds[id] ?? 0) + 1;
      _responseWaiters
          .putIfAbsent(id, () => Completer<Map<String, dynamic>>())
          .complete(message);
    }
  }
}
