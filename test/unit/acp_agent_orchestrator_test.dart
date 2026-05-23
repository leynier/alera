import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agents/acp/application/acp_agent_orchestrator.dart';
import 'package:alera/src/features/agents/acp/infrastructure/codex_acp_client.dart';
import 'package:alera/src/features/agents/application/agent_orchestrator_event.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AcpAgentOrchestrator', () {
    test('emits protocol permission option ids and display names', () async {
      final processRunner = _FakeAcpProcessRunner();
      final client = CodexAcpClient(processRunner: processRunner);
      final orchestrator = AcpAgentOrchestrator(client);

      await orchestrator.boot();

      final eventFuture = orchestrator.events
          .where((event) => event is AgentApprovalRequestEvent)
          .cast<AgentApprovalRequestEvent>()
          .first;
      processRunner.process.sendServerRequest(<String, dynamic>{
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

      await orchestrator.close();
    });

    test(
      'falls back to sentence-case labels for options without names',
      () async {
        final processRunner = _FakeAcpProcessRunner();
        final client = CodexAcpClient(processRunner: processRunner);
        final orchestrator = AcpAgentOrchestrator(client);

        await orchestrator.boot();

        final eventFuture = orchestrator.events
            .where((event) => event is AgentApprovalRequestEvent)
            .cast<AgentApprovalRequestEvent>()
            .first;
        processRunner.process.sendServerRequest(<String, dynamic>{
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

        await orchestrator.close();
      },
    );

    test(
      'does not emit turn completion after close cancels pending prompt',
      () async {
        final processRunner = _FakeAcpProcessRunner();
        final client = CodexAcpClient(processRunner: processRunner);
        final orchestrator = AcpAgentOrchestrator(client);
        final events = <AgentOrchestratorEvent>[];

        await orchestrator.boot();

        final subscription = orchestrator.events.listen(events.add);
        await orchestrator.runTurn(
          threadId: 'session-1',
          input: const <Map<String, dynamic>>[
            <String, dynamic>{'type': 'text', 'text': 'hello'},
          ],
        );

        await orchestrator.close();
        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();

        expect(
          events.whereType<AgentNotificationEvent>().map(
            (event) => event.method,
          ),
          isNot(contains('turn/failed')),
        );
      },
    );
  });

  group('CodexAcpClient fs/read_text_file', () {
    test('uses ACP 1-based line numbers for ranged reads', () async {
      final processRunner = _FakeAcpProcessRunner();
      final client = CodexAcpClient(processRunner: processRunner);
      final tempDir = await Directory.systemTemp.createTemp('alera_acp_test_');
      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('one\ntwo\nthree\nfour');

      await client.start();

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

      await client.close();
      await tempDir.delete(recursive: true);
    });

    test(
      'starts at the first line when line is missing and handles overflow',
      () async {
        final processRunner = _FakeAcpProcessRunner();
        final client = CodexAcpClient(processRunner: processRunner);
        final tempDir = await Directory.systemTemp.createTemp(
          'alera_acp_test_',
        );
        final file = File('${tempDir.path}/sample.txt');
        await file.writeAsString('one\ntwo\nthree');

        await client.start();

        processRunner.process.sendServerRequest(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': 5,
          'method': 'fs/read_text_file',
          'params': <String, dynamic>{'path': file.path, 'limit': 2},
        });
        var response = await processRunner.process.responseFor(5);
        expect(response['result'], <String, dynamic>{'content': 'one\ntwo'});

        processRunner.process.sendServerRequest(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': 6,
          'method': 'fs/read_text_file',
          'params': <String, dynamic>{
            'path': file.path,
            'line': 10,
            'limit': 2,
          },
        });
        response = await processRunner.process.responseFor(6);
        expect(response['result'], <String, dynamic>{'content': ''});

        await client.close();
        await tempDir.delete(recursive: true);
      },
    );
  });
}

class _FakeAcpProcessRunner implements ProcessRunner {
  late final _FakeAcpProcess process;

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
    process = _FakeAcpProcess();
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
    if (message['method'] == 'initialize') {
      sendServerRequest(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'protocolVersion': 1,
          'agentCapabilities': <String, dynamic>{},
        },
      });
      return;
    }

    if (id != null &&
        (message.containsKey('result') || message.containsKey('error'))) {
      _responseWaiters
          .putIfAbsent(id, () => Completer<Map<String, dynamic>>())
          .complete(message);
    }
  }
}
