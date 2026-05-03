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
          input: <Map<String, dynamic>>[
            <String, dynamic>{'type': 'text', 'text': 'run checks'},
          ],
          model: 'gpt-5.2-codex',
          reasoningEffort: 'high',
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

    test(
      'approval request emits event and turn completes after approve',
      () async {
        final orchestrator = await _startOrchestrator();
        final notifications = <AgentNotificationEvent>[];
        final approvalRequests = <AgentApprovalRequestEvent>[];
        final sub = orchestrator.events.listen((event) {
          if (event is AgentNotificationEvent) {
            notifications.add(event);
          } else if (event is AgentApprovalRequestEvent) {
            approvalRequests.add(event);
            unawaited(
              orchestrator.approveRequest(event.requestId, forSession: true),
            );
          }
        });

        final threadId = await orchestrator.ensureThread(cwd: '/tmp/project');
        await orchestrator.runTurn(
          threadId: threadId,
          input: <Map<String, dynamic>>[
            <String, dynamic>{'type': 'text', 'text': 'trigger_approval now'},
          ],
          model: 'gpt-5.2-codex',
          reasoningEffort: 'high',
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
        expect(approvalRequests, isNotEmpty);

        await sub.cancel();
        await orchestrator.close();
      },
    );

    test('runTurn forwards fast service tier', () async {
      final orchestrator = await _startOrchestrator();
      final notifications = <AgentNotificationEvent>[];
      final sub = orchestrator.events.listen((event) {
        if (event is AgentNotificationEvent) {
          notifications.add(event);
        }
      });

      final threadId = await orchestrator.ensureThread(cwd: '/tmp/project');
      final turnId = await orchestrator.runTurn(
        threadId: threadId,
        input: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'text',
            'text': 'trigger_service_tier_fast',
          },
        ],
        model: 'gpt-5.5',
        reasoningEffort: 'high',
        serviceTier: 'fast',
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
    });

    test('interrupt stops an in-flight turn', () async {
      final orchestrator = await _startOrchestrator();
      final notifications = <AgentNotificationEvent>[];
      final sub = orchestrator.events.listen((event) {
        if (event is AgentNotificationEvent) {
          notifications.add(event);
        }
      });

      final threadId = await orchestrator.ensureThread(cwd: '/tmp/project');
      final turnId = await orchestrator.runTurn(
        threadId: threadId,
        input: <Map<String, dynamic>>[
          <String, dynamic>{'type': 'text', 'text': 'trigger_interrupt now'},
        ],
        model: 'gpt-5.2-codex',
        reasoningEffort: 'high',
        cwd: '/tmp/project',
      );

      await orchestrator.interrupt(threadId: threadId, turnId: turnId);

      final completed = await _waitForNotification(
        notifications,
        'turn/completed',
      );
      final turn =
          (completed['params'] as Map<String, dynamic>)['turn']
              as Map<String, dynamic>;
      expect(turn['status'], 'interrupted');

      await sub.cancel();
      await orchestrator.close();
    });

    test(
      'user input request supports snake_case method and missing threadId',
      () async {
        final orchestrator = await _startOrchestrator();
        final notifications = <AgentNotificationEvent>[];
        final userInputRequests = <AgentUserInputRequestEvent>[];
        final sub = orchestrator.events.listen((event) {
          if (event is AgentNotificationEvent) {
            notifications.add(event);
          } else if (event is AgentUserInputRequestEvent) {
            userInputRequests.add(event);
            unawaited(
              orchestrator.respondUserInput(
                event.requestId,
                const <String, dynamic>{},
              ),
            );
          }
        });

        final threadId = await orchestrator.ensureThread(cwd: '/tmp/project');
        await orchestrator.runTurn(
          threadId: threadId,
          input: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'text',
              'text': 'trigger_user_input_no_thread now',
            },
          ],
          model: 'gpt-5.2-codex',
          reasoningEffort: 'high',
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
        expect(userInputRequests, isNotEmpty);
        expect(userInputRequests.first.threadId, isNull);
        expect(userInputRequests.first.turnId, isNotEmpty);
        expect(userInputRequests.first.itemId, isNotEmpty);
        expect(userInputRequests.first.questions, isNotEmpty);

        await sub.cancel();
        await orchestrator.close();
      },
    );

    test('user input request normalizes blank threadId to null', () async {
      final orchestrator = await _startOrchestrator();
      final notifications = <AgentNotificationEvent>[];
      final userInputRequests = <AgentUserInputRequestEvent>[];
      final sub = orchestrator.events.listen((event) {
        if (event is AgentNotificationEvent) {
          notifications.add(event);
        } else if (event is AgentUserInputRequestEvent) {
          userInputRequests.add(event);
          unawaited(
            orchestrator.respondUserInput(
              event.requestId,
              const <String, dynamic>{},
            ),
          );
        }
      });

      final threadId = await orchestrator.ensureThread(cwd: '/tmp/project');
      await orchestrator.runTurn(
        threadId: threadId,
        input: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'text',
            'text': 'trigger_user_input_empty_thread now',
          },
        ],
        model: 'gpt-5.2-codex',
        reasoningEffort: 'high',
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
      expect(userInputRequests, isNotEmpty);
      expect(userInputRequests.first.threadId, isNull);

      await sub.cancel();
      await orchestrator.close();
    });
  });
}
