import 'dart:async';

import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_state.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void main() {
  test('mobile session changes replace conversation-owned state', () async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'activeTurnId': 'old-turn',
        'title': 'Old Thread',
        'contextUsed': 900,
        'contextLimit': 1000,
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'old-user',
            'kind': 'userMessage',
            'status': 'completed',
            'markdownText': 'Old prompt',
          },
        ],
      },
      responses: const <String, Map<String, Object?>>{
        'codex.thread.resume': <String, Object?>{
          'cwd': '/workspace/new',
          'historyNextCursor': 'history-next',
          'snapshot': <String, Object?>{
            'title': 'New Thread',
            'contextUsed': 4,
            'contextLimit': 128000,
            'timelineCells': <Object?>[
              <String, Object?>{
                'id': 'new-user',
                'kind': 'userMessage',
                'status': 'completed',
                'markdownText': 'New prompt',
              },
            ],
          },
        },
        'codex.thread.new': <String, Object?>{
          'cwd': '/workspace/new',
          'snapshot': <String, Object?>{
            'timelineCells': <Object?>[
              <String, Object?>{
                'id': 'boundary',
                'kind': 'systemNotice',
                'status': 'completed',
              },
            ],
          },
        },
      },
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider(
          'host-session',
        ).overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider(
      'host-session',
      'tab-session',
    );
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await container.read(provider.future);
    final controller = container.read(provider.notifier);

    await controller.resumeThread(
      const MobileCodexThreadSummary(
        id: 'new-thread',
        title: 'New Thread',
        cwd: '/workspace/new',
      ),
    );
    final resumeCall = client.calls.lastWhere(
      (call) => call.type == 'codex.thread.resume',
    );
    expect(resumeCall.payload.containsKey('cwd'), isFalse);
    var current = container.read(provider).value!;
    expect(current.activeTurnId, isNull);
    expect(current.title, 'New Thread');
    expect(current.contextUsed, 4);
    expect(current.contextLimit, 128000);
    expect(current.promptHistory, <String>['New prompt']);
    expect(current.historyNextCursor, 'history-next');
    expect(current.models, isNotEmpty);
    expect(current.selectedModel, 'gpt-current');

    await controller.newThread();
    current = container.read(provider).value!;
    expect(current.activeTurnId, isNull);
    expect(current.title, isNull);
    expect(current.contextUsed, isNull);
    expect(current.contextLimit, isNull);
    expect(current.promptHistory, isEmpty);
    expect(current.historyNextCursor, isNull);
    expect(current.models, isNotEmpty);
    expect(current.selectedModel, 'gpt-current');
  });

  test('mobile does not drain queued prompts into a new thread', () async {
    late FakeMobileCodexClient client;
    client = FakeMobileCodexClient(
      requestHandler: (type, payload) {
        if (type != 'codex.thread.new') return null;
        return () async {
          client.emit(
            const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
              'tabId': 'tab-session-queue',
              'snapshot': <String, Object?>{
                'timelineCells': <Object?>[],
                'pendingRequests': <Object?>[],
              },
            }),
          );
          await Future<void>.delayed(Duration.zero);
          return <String, Object?>{
            'snapshot': <String, Object?>{
              'timelineCells': <Object?>[],
              'pendingRequests': <Object?>[],
            },
          };
        }();
      },
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider(
          'host-session-queue',
        ).overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider(
      'host-session-queue',
      'tab-session-queue',
    );
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await container.read(provider.future);
    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-session-queue',
        'snapshot': <String, Object?>{'activeTurnId': 'turn-old'},
      }),
    );
    await Future<void>.delayed(Duration.zero);
    final controller = container.read(provider.notifier);
    await controller.send('queued for the old thread');

    await controller.newThread();
    await Future<void>.delayed(Duration.zero);

    expect(container.read(provider).value!.queuedMessages, isEmpty);
    expect(
      client.calls.where((call) => call.type == 'codex.turn.start'),
      isEmpty,
    );
  });
  test('mobile drains prompts queued during a session transition', () async {
    final transitionResponse = Completer<Map<String, Object?>>();
    final client = FakeMobileCodexClient(
      initialThreadId: 'thread-old',
      requestHandler: (type, payload) =>
          type == 'codex.thread.new' ? transitionResponse.future : null,
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider(
          'host-transition-queue',
        ).overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider(
      'host-transition-queue',
      'tab-transition-queue',
    );
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await container.read(provider.future);
    final controller = container.read(provider.notifier);

    final transition = controller.newThread();
    await Future<void>.delayed(Duration.zero);
    await controller.send('queued during transition');
    transitionResponse.complete(<String, Object?>{
      'threadId': 'thread-new',
      'snapshot': <String, Object?>{
        'timelineCells': const <Object?>[],
        'pendingRequests': const <Object?>[],
      },
    });
    expect(await transition, isTrue);
    await Future<void>.delayed(Duration.zero);

    final turnStarts = client.calls
        .where((call) => call.type == 'codex.turn.start')
        .toList();
    expect(turnStarts, hasLength(1));
    expect(turnStarts.single.payload['expectedThreadId'], 'thread-new');
    expect(container.read(provider).value!.queuedMessages, isEmpty);
  });
  test('mobile ignores a session reply after controller disposal', () async {
    final transitionResponse = Completer<Map<String, Object?>>();
    final client = FakeMobileCodexClient(
      requestHandler: (type, payload) =>
          type == 'codex.thread.new' ? transitionResponse.future : null,
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider(
          'host-disposed-transition',
        ).overrideWith((ref) async => client),
      ],
    );
    addTearDown(client.dispose);
    final provider = mobileCodexControllerProvider(
      'host-disposed-transition',
      'tab-disposed-transition',
    );
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    await container.read(provider.future);
    final transition = container.read(provider.notifier).newThread();
    await Future<void>.delayed(Duration.zero);

    listener.close();
    container.dispose();
    transitionResponse.complete(<String, Object?>{
      'threadId': 'thread-after-dispose',
      'snapshot': <String, Object?>{'timelineCells': const <Object?>[]},
    });

    expect(await transition, isFalse);
  });
  test(
    'mobile waits for every overlapping session transition before draining',
    () async {
      final firstResponse = Completer<Map<String, Object?>>();
      final secondResponse = Completer<Map<String, Object?>>();
      final client = FakeMobileCodexClient(
        initialThreadId: 'thread-old',
        requestHandler: (type, payload) => switch (type) {
          'codex.thread.new' => firstResponse.future,
          'codex.thread.clear' => secondResponse.future,
          _ => null,
        },
      );
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider(
            'host-overlapping-transition',
          ).overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider(
        'host-overlapping-transition',
        'tab-overlapping-transition',
      );
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      await container.read(provider.future);
      final controller = container.read(provider.notifier);

      final first = controller.newThread();
      await Future<void>.delayed(Duration.zero);
      final second = controller.clearThread();
      await Future<void>.delayed(Duration.zero);
      await controller.send('queued until both transitions finish');
      firstResponse.complete(<String, Object?>{
        'threadId': 'thread-first',
        'snapshot': <String, Object?>{'timelineCells': const <Object?>[]},
      });
      expect(await first, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(
        client.calls.where((call) => call.type == 'codex.turn.start'),
        isEmpty,
      );

      secondResponse.complete(<String, Object?>{
        'threadId': 'thread-second',
        'snapshot': <String, Object?>{'timelineCells': const <Object?>[]},
      });
      expect(await second, isTrue);
      await Future<void>.delayed(Duration.zero);

      final turnStarts = client.calls
          .where((call) => call.type == 'codex.turn.start')
          .toList();
      expect(turnStarts, hasLength(1));
      expect(turnStarts.single.payload['expectedThreadId'], 'thread-second');
    },
  );
  test(
    'mobile drops an old queue when an overlapping transition succeeds',
    () async {
      final firstResponse = Completer<Map<String, Object?>>();
      final secondResponse = Completer<Map<String, Object?>>();
      final client = FakeMobileCodexClient(
        initialThreadId: 'thread-old',
        initialSnapshot: const <String, Object?>{
          'activeTurnId': 'turn-old',
          'timelineCells': <Object?>[],
          'pendingRequests': <Object?>[],
        },
        requestHandler: (type, payload) => switch (type) {
          'codex.thread.new' => firstResponse.future,
          'codex.thread.clear' => secondResponse.future,
          _ => null,
        },
      );
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider(
            'host-overlapping-failed-transition',
          ).overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider(
        'host-overlapping-failed-transition',
        'tab-overlapping-failed-transition',
      );
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      await container.read(provider.future);
      final controller = container.read(provider.notifier);
      await controller.send('queued for the old thread');

      final first = controller.newThread();
      await Future<void>.delayed(Duration.zero);
      final second = controller.clearThread();
      await Future<void>.delayed(Duration.zero);
      await controller.send('queued during transition');
      firstResponse.completeError(StateError('first transition failed'));
      expect(await first, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(
        client.calls.where((call) => call.type == 'codex.turn.start'),
        isEmpty,
      );

      secondResponse.complete(<String, Object?>{
        'threadId': 'thread-second',
        'snapshot': <String, Object?>{'timelineCells': const <Object?>[]},
      });
      expect(await second, isTrue);
      await Future<void>.delayed(Duration.zero);

      final turnStarts = client.calls
          .where((call) => call.type == 'codex.turn.start')
          .toList();
      expect(turnStarts, hasLength(1));
      expect(turnStarts.single.payload['expectedThreadId'], 'thread-second');
      expect(turnStarts.single.payload['input'], <Object?>[
        <String, Object?>{'type': 'text', 'text': 'queued during transition'},
      ]);
    },
  );

  test('mobile discards history returned after a thread change', () async {
    final historyResponse = Completer<Map<String, Object?>>();
    final client = FakeMobileCodexClient(
      initialThreadId: 'thread-old',
      requestHandler: (type, payload) {
        if (type == 'codex.thread.history') return historyResponse.future;
        if (type == 'codex.thread.new') {
          return Future<Map<String, Object?>>.value(<String, Object?>{
            'threadId': 'thread-new',
            'snapshot': <String, Object?>{'timelineCells': const <Object?>[]},
          });
        }
        return null;
      },
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider(
          'host-history-race',
        ).overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider(
      'host-history-race',
      'tab-history-race',
    );
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await container.read(provider.future);
    final controller = container.read(provider.notifier);

    final history = controller.loadHistory(cursor: 'older');
    await Future<void>.delayed(Duration.zero);
    expect(await controller.newThread(), isTrue);
    historyResponse.complete(<String, Object?>{
      'snapshot': <String, Object?>{
        'timelineCells': const <Object?>[
          <String, Object?>{
            'id': 'stale-message',
            'kind': 'userMessage',
            'status': 'completed',
            'markdownText': 'Old thread',
          },
        ],
      },
    });
    await history;

    expect(container.read(provider).value!.timelineCells, isEmpty);
  });
}
