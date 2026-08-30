import 'dart:async';

import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_state.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void main() {
  test('mobile history pagination extends composer prompt history', () async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'recent',
            'kind': 'userMessage',
            'status': 'completed',
            'markdownText': 'Recent prompt',
          },
        ],
      },
      responses: const <String, Map<String, Object?>>{
        'codex.thread.history': <String, Object?>{
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
        mobileCodexClientProvider('host-history')
            .overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider(
      'host-history',
      'tab-history',
    );
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await container.read(provider.future);

    await container.read(provider.notifier).loadHistory(cursor: 'older');

    expect(container.read(provider).value!.promptHistory, <String>[
      'Older prompt',
      'Recent prompt',
    ]);
  });
  test('mobile recovery preserves the host active cwd', () async {
    final client = FakeMobileCodexClient(
      initialThreadId: 'thread-stale',
      recovery: const <String, Object?>{'kind': 'missingRollout'},
      responses: const <String, Map<String, Object?>>{
        'codex.thread.recover': <String, Object?>{
          'threadId': 'thread-recovered',
          'snapshot': <String, Object?>{'timelineCells': <Object?>[]},
          'cwd': '/repo/packages/app',
        },
      },
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider('host-recovery-cwd')
            .overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider(
      'host-recovery-cwd',
      'tab-recovery-cwd',
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
        'tabId': 'tab-recovery-cwd',
        'historyNextCursor': 'stale-history',
      }),
    );
    await Future<void>.delayed(.zero);

    await container.read(provider.notifier).recoverThread();

    final current = container.read(provider).value!;
    expect(current.activeCwd, '/repo/packages/app');
    expect(current.historyNextCursor, isNull);
    final recoveryCall = client.calls.singleWhere(
      (call) => call.type == 'codex.thread.recover',
    );
    expect(recoveryCall.payload['expectedThreadId'], 'thread-stale');
    await container.read(provider.notifier).send('Continue');
    final turnCall = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect(turnCall.payload['expectedThreadId'], 'thread-recovered');
  });
  test('snapshot delta promotion replaces a provisional mobile cell', () async {
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'progressText-turn-1',
          'turnId': 'turn-1',
          'kind': 'progressText',
          'status': 'inProgress',
          'markdownText': 'Inspecting',
        },
      ],
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider('host-delta')
            .overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider('host-delta', 'tab-delta');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await container.read(provider.future);

    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-delta',
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': <Object?>[
            <String, Object?>{
              'id': 'item-commentary',
              'itemId': 'commentary',
              'turnId': 'turn-1',
              'kind': 'progressText',
              'status': 'inProgress',
              'markdownText': 'Inspecting files',
              'isStreaming': true,
            },
          ],
          'timelineRemovedIds': <Object?>['progressText-turn-1'],
          'eventsAppend': <Object?>[],
          'activeTurnId': 'turn-1',
        },
      }),
    );
    await Future<void>.delayed(.zero);

    final state = container.read(provider).value!;
    expect(state.timelineCells.map((cell) => cell.id), <String>[
      'item-commentary',
    ]);
    expect(state.timelineCells.single.markdownText, 'Inspecting files');
    expect(state.activeTurnId, 'turn-1');
  });
  test(
    'mobile identity-only events do not complete or drain an active send',
    () async {
      final turnStart = Completer<Map<String, Object?>>();
      final client = FakeMobileCodexClient(
        requestHandler: (type, payload) =>
            type == 'codex.turn.start' ? turnStart.future : null,
      );
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider('host-identity-only')
              .overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider(
        'host-identity-only',
        'tab-identity-only',
      );
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      await container.read(provider.future);
      final controller = container.read(provider.notifier);

      final firstSend = controller.send('First message');
      await Future<void>.delayed(.zero);
      await controller.send('Second message');
      client.emit(
        const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
          'tabId': 'tab-identity-only',
          'threadId': 'thread-created',
          'cwd': '/workspace/created',
        }),
      );
      await Future<void>.delayed(.zero);

      final duringSend = container.read(provider).value!;
      expect(duringSend.sending, isTrue);
      expect(duringSend.activeCwd, '/workspace/created');
      expect(duringSend.queuedMessages, hasLength(1));
      expect(
        client.calls.where((call) => call.type == 'codex.turn.start'),
        hasLength(1),
      );

      turnStart.complete(<String, Object?>{
        'turn': <String, Object?>{'id': 'turn-1'},
      });
      await firstSend;
    },
  );
  test(
    'mobile preserves concurrent state while reloading resumed catalogues',
    () async {
      var skillLoads = 0;
      final catalogueReloadStarted = Completer<void>();
      final resumedSkills = Completer<Map<String, Object?>>();
      final client = FakeMobileCodexClient(
        requestHandler: (type, payload) {
          if (type == 'codex.skills.list') {
            skillLoads += 1;
            if (skillLoads == 2) {
              catalogueReloadStarted.complete();
              return resumedSkills.future;
            }
            return Future<Map<String, Object?>>.value(<String, Object?>{
              'data': <Object?>[
                <String, Object?>{'name': 'initial', 'path': '/skills/initial'},
              ],
            });
          }
          if (type == 'codex.thread.resume') {
            return Future<Map<String, Object?>>.value(<String, Object?>{
              'threadId': 'thread-resumed',
              'cwd': '/workspace/resumed',
              'snapshot': <String, Object?>{'timelineCells': const <Object?>[]},
            });
          }
          return null;
        },
      );
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider('host-catalogue-resume')
              .overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider(
        'host-catalogue-resume',
        'tab-catalogue-resume',
      );
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      await container.read(provider.future);
      expect(container.read(provider).value!.skills.single['name'], 'initial');

      final resume = container
          .read(provider.notifier)
          .resumeThread(
            const MobileCodexThreadSummary(
              id: 'thread-resumed',
              title: 'Resumed',
            ),
          );
      await catalogueReloadStarted.future;
      await container
          .read(provider.notifier)
          .send('Queued while catalogues reload');
      expect(container.read(provider).value!.queuedMessages, hasLength(1));
      resumedSkills.complete(<String, Object?>{
        'data': <Object?>[
          <String, Object?>{'name': 'resumed', 'path': '/skills/resumed'},
        ],
      });
      await resume;
      await Future<void>.delayed(.zero);

      final current = container.read(provider).value!;
      expect(current.skills.single['name'], 'resumed');
      expect(current.activeCwd, '/workspace/resumed');
      expect(current.queuedMessages, isEmpty);
      final turnStarts = client.calls
          .where((call) => call.type == 'codex.turn.start')
          .toList(growable: false);
      expect(turnStarts, hasLength(1));
      expect(turnStarts.single.payload['expectedThreadId'], 'thread-resumed');
    },
  );
  test(
    'mobile controller resynchronizes events received during build',
    () async {
      final models = Completer<Map<String, Object?>>();
      final client = FakeMobileCodexClient(
        requestHandler: (type, payload) =>
            type == 'codex.model.list' ? models.future : null,
      );
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider('host-initial-event')
              .overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider(
        'host-initial-event',
        'tab-initial-event',
      );
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      while (!client.calls.any((call) => call.type == 'codex.model.list')) {
        await Future<void>.delayed(.zero);
      }

      client.emit(
        const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
          'tabId': 'tab-initial-event',
          'snapshot': <String, Object?>{
            'timelineCells': <Object?>[
              <String, Object?>{
                'id': 'streamed-during-build',
                'kind': 'assistantMessage',
                'status': 'inProgress',
                'markdownText': 'Streaming',
              },
            ],
          },
          'snapshotDelta': <String, Object?>{
            'timelineUpserts': <Object?>[],
            'eventsAppend': <Object?>[],
          },
        }),
      );
      models.complete(const <String, Object?>{'data': <Object?>[]});

      await container.read(provider.future);
      await Future<void>.delayed(.zero);

      expect(
        container.read(provider).value!.timelineCells.map((cell) => cell.id),
        contains('streamed-during-build'),
      );
    },
  );
  test(
    'mobile controller keeps the newest event while initialization drains',
    () async {
      final models = Completer<Map<String, Object?>>();
      final client = FakeMobileCodexClient(
        requestHandler: (type, payload) =>
            type == 'codex.model.list' ? models.future : null,
      );
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider('host-initial-order')
              .overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider(
        'host-initial-order',
        'tab-initial-order',
      );
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      while (!client.calls.any((call) => call.type == 'codex.model.list')) {
        await Future<void>.delayed(.zero);
      }
      client.emit(
        const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
          'tabId': 'tab-initial-order',
          'snapshot': <String, Object?>{
            'activeTurnId': 'turn-1',
            'timelineCells': <Object?>[
              <String, Object?>{
                'id': 'older-busy',
                'kind': 'assistantMessage',
                'status': 'inProgress',
              },
            ],
          },
        }),
      );
      models.complete(const <String, Object?>{'data': <Object?>[]});
      await container.read(provider.future);
      client.emit(
        const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
          'tabId': 'tab-initial-order',
          'snapshot': <String, Object?>{
            'timelineCells': <Object?>[
              <String, Object?>{
                'id': 'newer-complete',
                'kind': 'assistantMessage',
                'status': 'completed',
              },
            ],
          },
        }),
      );
      await Future<void>.delayed(.zero);
      await Future<void>.delayed(.zero);

      final current = container.read(provider).value!;
      expect(current.activeTurnId, isNull);
      expect(current.timelineCells.single.id, 'newer-complete');
    },
  );
}
