import 'dart:async';

import 'package:alera/src/features/agents/infrastructure/codex_app_server_client.dart';
import 'package:alera/src/shared/infra/process/io_process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<CodexAppServerClient> _startFakeClient() async {
  final script = p.absolute(
    'test/integration/fixtures/fake_codex_app_server.dart',
  );
  final client = CodexAppServerClient(
    processRunner: const IoProcessRunner(),
    executable: 'dart',
    arguments: <String>[script],
  );
  await client.start().timeout(const Duration(seconds: 5));
  return client;
}

Future<Map<String, dynamic>> _waitForMethod(
  List<Map<String, dynamic>> notifications,
  String method,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (DateTime.now().isBefore(deadline)) {
    for (final message in notifications) {
      if (message['method'] == method) {
        return message;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TimeoutException('method not observed: $method');
}

void main() {
  group('CodexAppServerClient integration', () {
    test('handshake + thread start + turn flow without approval', () async {
      final client = await _startFakeClient();
      final notifications = <Map<String, dynamic>>[];
      final sub = client.events.listen(notifications.add);

      final thread = await client
          .startThread(cwd: '/tmp/project')
          .timeout(const Duration(seconds: 5));
      final threadId =
          ((thread['result'] as Map<String, dynamic>)['thread']
              as Map<String, dynamic>)['id'];
      expect(threadId, 'thr_fake');

      await client
          .startTurn(
            threadId: 'thr_fake',
            input: const <Map<String, dynamic>>[
              <String, dynamic>{'type': 'text', 'text': 'run checks'},
            ],
            model: 'gpt-5.2-codex',
            cwd: '/tmp/project',
          )
          .timeout(const Duration(seconds: 5));

      final turnCompleted = await _waitForMethod(
        notifications,
        'turn/completed',
      );
      final turn =
          (turnCompleted['params'] as Map<String, dynamic>)['turn']
              as Map<String, dynamic>;
      expect(turn['status'], 'completed');

      await sub.cancel();
      await client.close();
    });

    test('manual approval response still works when request arrives', () async {
      final client = await _startFakeClient();
      final notifications = <Map<String, dynamic>>[];
      final sub = client.events.listen(notifications.add);

      await client
          .startThread(cwd: '/tmp/project')
          .timeout(const Duration(seconds: 5));

      final approvalFuture = client.requests.firstWhere(
        (request) => request.method == 'item/commandExecution/requestApproval',
      );

      await client
          .startTurn(
            threadId: 'thr_fake',
            input: const <Map<String, dynamic>>[
              <String, dynamic>{'type': 'text', 'text': 'trigger_approval now'},
            ],
            model: 'gpt-5.2-codex',
            cwd: '/tmp/project',
          )
          .timeout(const Duration(seconds: 5));

      final approvalRequest = await approvalFuture.timeout(
        const Duration(seconds: 5),
      );
      await client.respondApproval(
        requestId: approvalRequest.id,
        decision: 'accept',
        forSession: true,
      );

      final turnCompleted = await _waitForMethod(
        notifications,
        'turn/completed',
      );
      final turn =
          (turnCompleted['params'] as Map<String, dynamic>)['turn']
              as Map<String, dynamic>;
      expect(turn['status'], 'completed');

      await sub.cancel();
      await client.close();
    });
  });
}
