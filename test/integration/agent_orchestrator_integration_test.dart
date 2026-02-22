import 'dart:async';

import 'package:alera/src/features/agents/application/agent_orchestrator.dart';
import 'package:alera/src/features/agents/application/agent_orchestrator_event.dart';
import 'package:alera/src/features/agents/infrastructure/codex_app_server_client.dart';
import 'package:alera/src/shared/infra/process/io_process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<AgentOrchestrator> _startOrchestrator() async {
  final script = p.absolute(
    'test/integration/fixtures/fake_codex_app_server.dart',
  );
  final client = CodexAppServerClient(
    processRunner: const IoProcessRunner(),
    executable: 'dart',
    arguments: <String>[script],
  );
  final orchestrator = AgentOrchestrator(client);
  await orchestrator.boot().timeout(const Duration(seconds: 5));
  return orchestrator;
}

Future<Map<String, dynamic>> _waitForNotification(
  List<AgentNotificationEvent> events,
  String method,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (DateTime.now().isBefore(deadline)) {
    for (final event in events) {
      if (event.method == method) {
        return event.payload;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TimeoutException('notification not observed: $method');
}

void main() {
  group('AgentOrchestrator integration', () {
    test(
      'runTurn sends no collaborationMode and approvalPolicy never',
      () async {
        final orchestrator = await _startOrchestrator();
        final notifications = <AgentNotificationEvent>[];
        final sub = orchestrator.events.listen((event) {
          if (event is AgentNotificationEvent) {
            notifications.add(event);
          }
        });

        final threadId = await orchestrator.ensureThread(cwd: '/tmp/project');
        expect(threadId, 'thr_fake');

        final turnId = await orchestrator.runTurn(
          threadId: threadId,
          prompt: 'run checks',
          model: 'gpt-5.2-codex',
          cwd: '/tmp/project',
        );
        expect(turnId, isNotEmpty);

        final completed = await _waitForNotification(
          notifications,
          'turn/completed',
        );
        final turn =
            (completed['params'] as Map<String, dynamic>)['turn']
                as Map<String, dynamic>;
        expect(turn['status'], 'completed');

        await sub.cancel();
        await orchestrator.close();
      },
    );

    test('unexpected approval request is auto-accepted', () async {
      final orchestrator = await _startOrchestrator();
      final notifications = <AgentNotificationEvent>[];
      final sub = orchestrator.events.listen((event) {
        if (event is AgentNotificationEvent) {
          notifications.add(event);
        }
      });

      final threadId = await orchestrator.ensureThread(cwd: '/tmp/project');
      await orchestrator.runTurn(
        threadId: threadId,
        prompt: 'trigger_approval now',
        model: 'gpt-5.2-codex',
        cwd: '/tmp/project',
      );

      final completed = await _waitForNotification(
        notifications,
        'turn/completed',
      );
      final turn =
          (completed['params'] as Map<String, dynamic>)['turn']
              as Map<String, dynamic>;
      expect(turn['status'], 'completed');

      await sub.cancel();
      await orchestrator.close();
    });
  });
}
