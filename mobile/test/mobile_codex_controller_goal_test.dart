import 'dart:async';

import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void main() {
  test('mobile retries a transient initial goal read', () async {
    var goalReads = 0;
    final client = FakeMobileCodexClient(
      supportsCodexGoals: true,
      initialThreadId: 'thread-goal-retry',
      requestHandler: (type, payload) {
        if (type != 'codex.goal.get') return null;
        goalReads += 1;
        if (goalReads == 1) {
          return Future<Map<String, Object?>>.error(
            StateError('temporary app-server startup failure'),
          );
        }
        return Future<Map<String, Object?>>.value(<String, Object?>{
          'goal': _mobileGoal('thread-goal-retry'),
        });
      },
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider(
          'host-goal-retry',
        ).overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });

    final provider = mobileCodexControllerProvider(
      'host-goal-retry',
      'tab-goal-retry',
    );
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    final state = await container.read(provider.future);

    expect(goalReads, 2);
    expect(state.goal?.objective, 'Ship the release');
    expect(container.read(provider.notifier).supportsGoals, isTrue);
  });

  test('mobile preserves goal support after transient initial reads', () async {
    final client = FakeMobileCodexClient(
      supportsCodexGoals: true,
      initialThreadId: 'thread-goal-transient',
      requestHandler: (type, payload) {
        if (type != 'codex.goal.get') return null;
        return Future<Map<String, Object?>>.error(StateError('temporary'));
      },
    );
    final (container, provider) = _goalController(
      client,
      hostId: 'host-goal-transient',
      tabId: 'tab-goal-transient',
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });

    await container.read(provider.future);

    expect(container.read(provider.notifier).supportsGoals, isTrue);
  });

  test('mobile disables goals after an unsupported initial set', () async {
    final client = FakeMobileCodexClient(
      supportsCodexGoals: true,
      requestHandler: (type, payload) {
        if (type != 'codex.goal.set') return null;
        return Future<Map<String, Object?>>.error(
          StateError('Goals feature is disabled'),
        );
      },
    );
    final (container, provider) = _goalController(
      client,
      hostId: 'host-goal-unsupported-set',
      tabId: 'tab-goal-unsupported-set',
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    await container.read(provider.future);

    final set = await container
        .read(provider.notifier)
        .setGoal('Ship the release');

    expect(set, isFalse);
    expect(container.read(provider.notifier).supportsGoals, isFalse);
  });

  test('mobile authoritative snapshots clear stale goals', () async {
    final client = FakeMobileCodexClient(
      supportsCodexGoals: true,
      initialThreadId: 'thread-goal-snapshot',
      initialSnapshot: <String, Object?>{
        'goal': _mobileGoal('thread-goal-snapshot'),
        'timelineCells': const <Object?>[],
      },
      responses: <String, Map<String, Object?>>{
        'codex.goal.get': <String, Object?>{
          'goal': _mobileGoal('thread-goal-snapshot'),
        },
        'codex.thread.history': const <String, Object?>{
          'snapshot': <String, Object?>{
            'timelineCells': <Object?>[
              <String, Object?>{
                'id': 'older',
                'kind': 'userMessage',
                'status': 'completed',
                'markdownText': 'Older prompt',
              },
            ],
          },
        },
      },
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider(
          'host-goal-snapshot',
        ).overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider(
      'host-goal-snapshot',
      'tab-goal-snapshot',
    );
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await container.read(provider.future);
    await container.read(provider.notifier).loadHistory(cursor: 'older');
    expect(container.read(provider).value!.goal, isNotNull);

    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-goal-snapshot',
        'threadId': 'thread-goal-snapshot',
        'snapshot': <String, Object?>{'timelineCells': <Object?>[]},
      }),
    );
    await Future<void>.delayed(Duration.zero);

    expect(container.read(provider).value!.goal, isNull);
  });

  test('mobile goal recovery merges into the latest state', () async {
    var goalReads = 0;
    final recovery = Completer<Map<String, Object?>>();
    final client = FakeMobileCodexClient(
      supportsCodexGoals: true,
      initialThreadId: 'thread-goal-latest',
      requestHandler: (type, payload) {
        if (type != 'codex.goal.get') return null;
        goalReads += 1;
        if (goalReads <= 2) {
          return Future<Map<String, Object?>>.error(StateError('temporary'));
        }
        return recovery.future;
      },
    );
    final (container, provider) = _goalController(
      client,
      hostId: 'host-goal-latest',
      tabId: 'tab-goal-latest',
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    await container.read(provider.future);

    client.emit(
      const MobileRuntimeEvent('codexServerChanged', <String, Object?>{
        'status': 'ready',
      }),
    );
    await Future<void>.delayed(Duration.zero);
    client.emit(
      const MobileRuntimeEvent('codexServerChanged', <String, Object?>{
        'status': 'error',
        'error': 'newer server error',
      }),
    );
    recovery.complete(<String, Object?>{
      'goal': _mobileGoal('thread-goal-latest'),
    });
    await Future<void>.delayed(Duration.zero);

    final state = container.read(provider).value!;
    expect(state.goal?.objective, 'Ship the release');
    expect(state.error, contains('newer server error'));
  });

  test('mobile failed replacement preserves the previous goal', () async {
    var goal = _mobileGoal('thread-goal-rollback');
    final client = FakeMobileCodexClient(
      supportsCodexGoals: true,
      initialThreadId: 'thread-goal-rollback',
      initialSnapshot: <String, Object?>{'goal': goal},
      requestHandler: (type, payload) {
        if (type == 'codex.goal.get') {
          return Future<Map<String, Object?>>.value(<String, Object?>{
            'goal': goal,
          });
        }
        if (type == 'codex.goal.set') {
          return Future<Map<String, Object?>>.error(StateError('temporary'));
        }
        return null;
      },
    );
    final (container, provider) = _goalController(
      client,
      hostId: 'host-goal-rollback',
      tabId: 'tab-goal-rollback',
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    await container.read(provider.future);

    final replaced = await container
        .read(provider.notifier)
        .replaceGoal('Ship the next release');

    expect(replaced, isFalse);
    expect(container.read(provider).value!.goal?.objective, 'Ship the release');
    expect(container.read(provider).value!.goal?.tokensUsed, 10);
    final setCalls = client.calls
        .where((call) => call.type == 'codex.goal.set')
        .toList();
    expect(setCalls, hasLength(1));
    expect(setCalls.single.payload['objective'], 'Ship the next release');
    expect(
      client.calls.where((call) => call.type == 'codex.goal.clear'),
      isEmpty,
    );
  });

  test('mobile replacement does not roll back into a new thread', () async {
    final replacement = Completer<Map<String, Object?>>();
    var setRequests = 0;
    final client = FakeMobileCodexClient(
      supportsCodexGoals: true,
      initialThreadId: 'thread-old',
      initialSnapshot: <String, Object?>{'goal': _mobileGoal('thread-old')},
      requestHandler: (type, payload) {
        if (type == 'codex.goal.get') {
          return Future<Map<String, Object?>>.value(<String, Object?>{
            'goal': _mobileGoal('thread-old'),
          });
        }
        if (type == 'codex.goal.clear') {
          return Future<Map<String, Object?>>.value(const <String, Object?>{
            'cleared': true,
          });
        }
        if (type == 'codex.goal.set') {
          setRequests += 1;
          return replacement.future;
        }
        return null;
      },
    );
    final (container, provider) = _goalController(
      client,
      hostId: 'host-goal-race',
      tabId: 'tab-goal-race',
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    await container.read(provider.future);

    final replacing = container
        .read(provider.notifier)
        .replaceGoal('New objective');
    await Future<void>.delayed(Duration.zero);
    expect(setRequests, 1);
    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-goal-race',
        'threadId': 'thread-new',
        'snapshot': <String, Object?>{'timelineCells': <Object?>[]},
      }),
    );
    await Future<void>.delayed(Duration.zero);
    replacement.completeError(StateError('replacement failed'));

    expect(await replacing, isFalse);
    expect(setRequests, 1);
    expect(container.read(provider).value!.goal, isNull);
  });
}

(ProviderContainer, MobileCodexControllerProvider) _goalController(
  FakeMobileCodexClient client, {
  required String hostId,
  required String tabId,
}) {
  final container = ProviderContainer(
    overrides: [
      mobileCodexClientProvider(hostId).overrideWith((ref) async => client),
    ],
  );
  final provider = mobileCodexControllerProvider(hostId, tabId);
  container.listen(provider, (_, _) {}, fireImmediately: true);
  return (container, provider);
}

Map<String, Object?> _mobileGoal(String threadId) => <String, Object?>{
  'threadId': threadId,
  'objective': 'Ship the release',
  'status': 'active',
  'tokenBudget': null,
  'tokensUsed': 10,
  'timeUsedSeconds': 20,
  'createdAt': 1,
  'updatedAt': 2,
};
