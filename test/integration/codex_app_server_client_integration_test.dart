import 'dart:async';

import 'package:alera/src/features/agents/infrastructure/codex_app_server_client.dart';
import 'package:alera/src/shared/infra/process/io_process_runner.dart';
import 'package:alera/src/shared/models/contracts.dart';
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
  await client.completeHandshake().timeout(const Duration(seconds: 5));
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

Future<Map<String, dynamic>> _waitForNotification(
  List<Map<String, dynamic>> notifications,
  bool Function(Map<String, dynamic> notification) matches,
  String description,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (DateTime.now().isBefore(deadline)) {
    for (final message in notifications) {
      if (matches(message)) {
        return message;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TimeoutException('notification not observed: $description');
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
            reasoningEffort: 'high',
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
            reasoningEffort: 'high',
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

    test(
      'commentary and final_answer phases are emitted with distinct item ids',
      () async {
        final client = await _startFakeClient();
        final notifications = <Map<String, dynamic>>[];
        final sub = client.events.listen(notifications.add);

        await client
            .startThread(cwd: '/tmp/project')
            .timeout(const Duration(seconds: 5));

        await client
            .startTurn(
              threadId: 'thr_fake',
              input: const <Map<String, dynamic>>[
                <String, dynamic>{
                  'type': 'text',
                  'text': 'trigger_commentary_final',
                },
              ],
              model: 'gpt-5.2-codex',
              reasoningEffort: 'high',
              cwd: '/tmp/project',
            )
            .timeout(const Duration(seconds: 5));

        await _waitForMethod(notifications, 'turn/completed');

        final legacyStarts = notifications
            .where((message) => message['method'] == 'codex/event/item_started')
            .map(
              (message) =>
                  (message['params'] as Map<String, dynamic>)['msg']
                      as Map<String, dynamic>,
            )
            .toList(growable: false);

        expect(legacyStarts, hasLength(2));
        final firstItem = legacyStarts.first['item'] as Map<String, dynamic>;
        final secondItem = legacyStarts.last['item'] as Map<String, dynamic>;
        expect(firstItem['phase'], 'commentary');
        expect(secondItem['phase'], 'final_answer');
        expect(firstItem['id'], isNot(secondItem['id']));

        await sub.cancel();
        await client.close();
      },
    );

    test('turn/start forwards selected reasoning effort', () async {
      final client = await _startFakeClient();
      final notifications = <Map<String, dynamic>>[];
      final sub = client.events.listen(notifications.add);

      await client
          .startThread(cwd: '/tmp/project')
          .timeout(const Duration(seconds: 5));

      await client
          .startTurn(
            threadId: 'thr_fake',
            input: const <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'text',
                'text': 'trigger_reasoning_medium',
              },
            ],
            model: 'gpt-5.2-codex',
            reasoningEffort: 'medium',
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

    test('turn/start forwards fast service tier', () async {
      final client = await _startFakeClient();
      final notifications = <Map<String, dynamic>>[];
      final sub = client.events.listen(notifications.add);

      await client
          .startThread(cwd: '/tmp/project')
          .timeout(const Duration(seconds: 5));

      await client
          .startTurn(
            threadId: 'thr_fake',
            input: const <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'text',
                'text': 'trigger_service_tier_fast',
              },
            ],
            model: 'gpt-5.5',
            reasoningEffort: 'high',
            serviceTier: 'fast',
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

    test('turn/start forwards explicit normal service tier', () async {
      final client = await _startFakeClient();
      final notifications = <Map<String, dynamic>>[];
      final sub = client.events.listen(notifications.add);

      await client
          .startThread(cwd: '/tmp/project')
          .timeout(const Duration(seconds: 5));

      await client
          .startTurn(
            threadId: 'thr_fake',
            input: const <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'text',
                'text': 'trigger_service_tier_normal',
              },
            ],
            model: 'gpt-5.5',
            reasoningEffort: 'high',
            serviceTier: null,
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

    test('thread/name/set emits thread/name/updated', () async {
      final client = await _startFakeClient();
      final notifications = <Map<String, dynamic>>[];
      final sub = client.events.listen(notifications.add);

      await client
          .startThread(cwd: '/tmp/project')
          .timeout(const Duration(seconds: 5));

      await client
          .setThreadName(threadId: 'thr_fake', name: 'Review session')
          .timeout(const Duration(seconds: 5));

      final updated = await _waitForMethod(
        notifications,
        'thread/name/updated',
      );
      expect(updated['params'], <String, dynamic>{
        'threadId': 'thr_fake',
        'threadName': 'Review session',
      });

      await sub.cancel();
      await client.close();
    });

    test('review/start detached returns typed review metadata', () async {
      final client = await _startFakeClient();
      final notifications = <Map<String, dynamic>>[];
      final sub = client.events.listen(notifications.add);

      await client
          .startThread(cwd: '/tmp/project')
          .timeout(const Duration(seconds: 5));

      final result = await client
          .startReview(
            threadId: 'thr_fake',
            target: const CodexReviewCommitTarget(
              sha: '1234567deadbeef',
              title: 'Polish tui colors',
            ),
            delivery: CodexReviewDelivery.detached,
          )
          .timeout(const Duration(seconds: 5));

      expect(result.turn.id, isNotEmpty);
      expect(result.turn.status, 'inProgress');
      expect(result.reviewThreadId, startsWith('thr_review_'));

      final threadStarted = await _waitForNotification(
        notifications,
        (message) =>
            message['method'] == 'thread/started' &&
            ((message['params'] as Map<String, dynamic>)['thread']
                    as Map<String, dynamic>)['id'] ==
                result.reviewThreadId,
        'thread/started for detached review thread',
      );
      final detachedThread =
          (threadStarted['params'] as Map<String, dynamic>)['thread']
              as Map<String, dynamic>;
      expect(detachedThread['id'], result.reviewThreadId);

      final completed = await _waitForMethod(notifications, 'turn/completed');
      final turn =
          (completed['params'] as Map<String, dynamic>)['turn']
              as Map<String, dynamic>;
      expect(turn['threadId'], result.reviewThreadId);
      expect(turn['status'], 'completed');

      await sub.cancel();
      await client.close();
    });

    test(
      'list wrappers return typed collaboration modes, skills, and apps',
      () async {
        final client = await _startFakeClient();
        final notifications = <Map<String, dynamic>>[];
        final sub = client.events.listen(notifications.add);

        final collaborationModes = await client
            .listCollaborationModes()
            .timeout(const Duration(seconds: 5));
        expect(collaborationModes, hasLength(2));
        expect(collaborationModes.first.name, 'default');
        expect(collaborationModes.last.kind, CodexCollaborationModeKind.plan);

        final skills = await client
            .listSkills(
              cwds: const <String>['/tmp/project'],
              forceReload: true,
              perCwdExtraUserRoots: const <CodexSkillsListExtraRootsForCwd>[
                CodexSkillsListExtraRootsForCwd(
                  cwd: '/tmp/project',
                  extraUserRoots: <String>['/tmp/shared-skills'],
                ),
              ],
            )
            .timeout(const Duration(seconds: 5));
        expect(skills, hasLength(1));
        expect(skills.first.cwd, '/tmp/project');
        expect(skills.first.skills, hasLength(2));
        expect(skills.first.skills.first.path, contains('/tmp/project'));

        final apps = await client
            .listApps(limit: 1, threadId: 'thr_fake')
            .timeout(const Duration(seconds: 5));
        expect(apps.data, hasLength(1));
        expect(apps.data.first.id, 'demo-app');
        expect(apps.data.first.labels?['threadId'], 'thr_fake');
        expect(apps.nextCursor, '1');

        final updated = await _waitForMethod(notifications, 'app/list/updated');
        final updatedParams = updated['params'] as Map<String, dynamic>;
        expect(updatedParams['nextCursor'], '1');

        await sub.cancel();
        await client.close();
      },
    );
  });
}
