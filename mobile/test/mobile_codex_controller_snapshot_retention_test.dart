import 'dart:async';

import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void main() {
  test(
    'mobile keeps paginated history while bounding live snapshots',
    () async {
      final historyCells = <Object?>[
        for (var index = 0; index < 481; index++)
          <String, Object?>{
            'id': 'history-$index',
            'kind': 'assistantMessage',
            'status': 'completed',
            'markdownText': 'History $index',
          },
      ];
      final client = FakeMobileCodexClient(
        initialThreadId: 'thread-history',
        initialSnapshot: const <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'live-before-history',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Recent answer',
            },
          ],
        },
        responses: <String, Map<String, Object?>>{
          'codex.thread.history': <String, Object?>{
            'snapshot': <String, Object?>{'timelineCells': historyCells},
          },
        },
      );
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider('host-paginated-history')
              .overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider(
        'host-paginated-history',
        'tab-paginated-history',
      );
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      await container.read(provider.future);

      await container.read(provider.notifier).loadHistory(cursor: 'older');
      client.emit(
        const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
          'tabId': 'tab-paginated-history',
          'threadId': 'thread-history',
          'snapshot': <String, Object?>{
            'timelineCells': <Object?>[
              <String, Object?>{
                'id': 'live-after-history',
                'kind': 'assistantMessage',
                'status': 'inProgress',
                'markdownText': 'Streaming answer',
              },
            ],
          },
          'snapshotDelta': <String, Object?>{
            'timelineUpserts': <Object?>[
              <String, Object?>{
                'id': 'live-after-history',
                'kind': 'assistantMessage',
                'status': 'inProgress',
                'markdownText': 'Streaming answer',
              },
            ],
          },
        }),
      );
      await Future<void>.delayed(.zero);

      final cells = container.read(provider).value!.timelineCells;
      expect(cells, hasLength(483));
      expect(cells.first.id, 'history-0');
      expect(cells[480].id, 'history-480');
      expect(cells.last.id, 'live-after-history');
    },
  );

  test('mobile retains older cells from deferred bounded snapshots', () async {
    final models = Completer<Map<String, Object?>>();
    final client = FakeMobileCodexClient(
      initialThreadId: 'thread-current',
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'older-live',
            'kind': 'userMessage',
            'status': 'completed',
            'markdownText': 'Older prompt',
          },
          <String, Object?>{
            'id': 'recent-live',
            'kind': 'assistantMessage',
            'status': 'completed',
            'markdownText': 'Recent answer',
          },
        ],
      },
      requestHandler: (type, payload) =>
          type == 'codex.model.list' ? models.future : null,
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider('host-bounded-snapshot')
            .overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider(
      'host-bounded-snapshot',
      'tab-bounded-snapshot',
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
        'tabId': 'tab-bounded-snapshot',
        'threadId': 'thread-current',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'deferred-live',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Deferred answer',
            },
          ],
        },
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': <Object?>[
            <String, Object?>{
              'id': 'deferred-live',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Deferred answer',
            },
          ],
        },
      }),
    );
    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-bounded-snapshot',
        'threadId': 'thread-current',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'recent-live',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Updated recent answer',
            },
            <String, Object?>{
              'id': 'new-live',
              'kind': 'assistantMessage',
              'status': 'inProgress',
              'markdownText': 'New answer',
            },
          ],
        },
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': <Object?>[
            <String, Object?>{
              'id': 'recent-live',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Updated recent answer',
            },
            <String, Object?>{
              'id': 'new-live',
              'kind': 'assistantMessage',
              'status': 'inProgress',
              'markdownText': 'New answer',
            },
          ],
        },
      }),
    );
    models.complete(const <String, Object?>{'data': <Object?>[]});

    await container.read(provider.future);
    await Future<void>.delayed(.zero);
    await Future<void>.delayed(.zero);

    final cells = container.read(provider).value!.timelineCells;
    expect(cells.map((cell) => cell.id), <String>[
      'older-live',
      'deferred-live',
      'recent-live',
      'new-live',
    ]);
    expect(cells[2].markdownText, 'Updated recent answer');
  });

  test('mobile deferred snapshots replace the previous thread', () async {
    final models = Completer<Map<String, Object?>>();
    final client = FakeMobileCodexClient(
      initialThreadId: 'thread-old',
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'old-thread-cell',
            'kind': 'assistantMessage',
            'status': 'completed',
            'markdownText': 'Old thread answer',
          },
        ],
      },
      requestHandler: (type, payload) =>
          type == 'codex.model.list' ? models.future : null,
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider('host-replacement-snapshot')
            .overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = mobileCodexControllerProvider(
      'host-replacement-snapshot',
      'tab-replacement-snapshot',
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
        'tabId': 'tab-replacement-snapshot',
        'threadId': 'thread-new',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'first-new-thread-cell',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'First new answer',
            },
          ],
        },
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': <Object?>[
            <String, Object?>{
              'id': 'first-new-thread-cell',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'First new answer',
            },
          ],
        },
      }),
    );
    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-replacement-snapshot',
        'threadId': 'thread-new',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'latest-new-thread-cell',
              'kind': 'assistantMessage',
              'status': 'inProgress',
              'markdownText': 'Latest new answer',
            },
          ],
        },
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': <Object?>[
            <String, Object?>{
              'id': 'latest-new-thread-cell',
              'kind': 'assistantMessage',
              'status': 'inProgress',
              'markdownText': 'Latest new answer',
            },
          ],
        },
      }),
    );
    models.complete(const <String, Object?>{'data': <Object?>[]});

    await container.read(provider.future);
    await Future<void>.delayed(.zero);
    await Future<void>.delayed(.zero);

    expect(
      container.read(provider).value!.timelineCells.map((cell) => cell.id),
      <String>['first-new-thread-cell', 'latest-new-thread-cell'],
    );
  });
}
