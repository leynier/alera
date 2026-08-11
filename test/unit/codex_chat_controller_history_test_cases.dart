part of 'codex_chat_controller_test.dart';

void registerCodexChatControllerHistoryTests() {
  test('keeps distinct streaming deltas in loaded raw history', () async {
    final client = _FakeCodexRuntimeClient()
      ..historyResponse = <String, Object?>{
        'snapshot': <String, Object?>{
          'events': <Object?>[
            <String, Object?>{
              'method': 'item/agentMessage/delta',
              'params': <String, Object?>{
                'turnId': 'turn-1',
                'itemId': 'message-1',
                'delta': 'First ',
              },
            },
            <String, Object?>{
              'method': 'item/agentMessage/delta',
              'params': <String, Object?>{
                'turnId': 'turn-1',
                'itemId': 'message-1',
                'delta': 'second',
              },
            },
          ],
          'timelineCells': const <Object?>[],
        },
      };
    final container = ProviderContainer(
      overrides: [
        codexChatRuntimeClientProvider.overrideWithValue(client),
        settingsControllerProvider.overrideWith(_TestSettingsController.new),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = codexChatControllerProvider('tab-delta-history');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await _settle();

    await container.read(provider.notifier).loadHistory(cursor: 'older');

    expect(container.read(provider).snapshot.events, hasLength(2));
  });

  test('discards an earlier history page after the thread changes', () async {
    final history = Completer<Object?>();
    final client = _FakeCodexRuntimeClient(
      requestHandler: (type, payload) =>
          type == 'codex.thread.history' ? history.future : null,
    )..openThreadId = 'thread-old';
    final container = ProviderContainer(
      overrides: [
        codexChatRuntimeClientProvider.overrideWithValue(client),
        settingsControllerProvider.overrideWith(_TestSettingsController.new),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = codexChatControllerProvider('tab-stale-history');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await _settle();

    final load = container.read(provider.notifier).loadHistory(cursor: 'old');
    await _settle();
    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-stale-history',
        'threadId': 'thread-new',
        'cwd': '/workspace/new',
        'historyNextCursor': 'new-cursor',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'new-message',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'New thread',
            },
          ],
        },
      }),
    );
    await _settle();
    history.complete(<String, Object?>{
      'cwd': '/workspace/old',
      'nextCursor': 'old-cursor',
      'snapshot': <String, Object?>{
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'old-message',
            'kind': 'assistantMessage',
            'status': 'completed',
            'markdownText': 'Old thread',
          },
        ],
      },
    });
    await load;

    final state = container.read(provider);
    expect(state.snapshot.timelineCells.single.id, 'new-message');
    expect(state.activeCwd, '/workspace/new');
    expect(state.historyNextCursor, 'new-cursor');
  });

  test('loading earlier turns extends composer prompt history', () async {
    final client = _FakeCodexRuntimeClient()
      ..openSnapshot = <String, Object?>{
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'recent',
            'kind': 'userMessage',
            'status': 'completed',
            'markdownText': 'Recent prompt',
          },
        ],
      }
      ..historyResponse = <String, Object?>{
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
      };
    final container = ProviderContainer(
      overrides: [
        codexChatRuntimeClientProvider.overrideWithValue(client),
        settingsControllerProvider.overrideWith(_TestSettingsController.new),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = codexChatControllerProvider('tab-history');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    container.read(provider);
    await _settle();

    await container.read(provider.notifier).loadHistory(cursor: 'older');

    expect(container.read(provider).snapshot.promptHistory, <String>[
      'Older prompt',
      'Recent prompt',
    ]);
  });

  test(
    'history event merging stays bounded and deduplicates stable ids',
    () async {
      Map<String, Object?> event(String id) => <String, Object?>{
        'method': 'item/completed',
        'params': <String, Object?>{
          'turnId': 'turn-$id',
          'itemId': id,
          'item': <String, Object?>{'id': id, 'text': id},
        },
      };

      final client = _FakeCodexRuntimeClient()
        ..openSnapshot = <String, Object?>{
          'events': <Object?>[
            for (var index = 0; index < 120; index++) event('live-$index'),
          ],
          'timelineCells': <Object?>[],
        }
        ..historyResponse = <String, Object?>{
          'snapshot': <String, Object?>{
            'events': <Object?>[
              event('live-0'),
              for (var index = 0; index < 120; index++) event('old-$index'),
            ],
            'timelineCells': <Object?>[],
          },
        };
      final container = ProviderContainer(
        overrides: [
          codexChatRuntimeClientProvider.overrideWithValue(client),
          settingsControllerProvider.overrideWith(_TestSettingsController.new),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = codexChatControllerProvider('tab-bounded-events');
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      await _settle();

      await container.read(provider.notifier).loadHistory(cursor: 'older-1');
      await container.read(provider.notifier).loadHistory(cursor: 'older-2');

      final events = container.read(provider).snapshot.events;
      expect(events, hasLength(160));
      expect(
        events.where((event) => event.deduplicationKey.contains('live-0')),
        hasLength(1),
      );
    },
  );

  test('turns carry the thread observed by the sending client', () async {
    final client = _FakeCodexRuntimeClient()..openThreadId = 'thread-old';
    final container = ProviderContainer(
      overrides: [
        codexChatRuntimeClientProvider.overrideWithValue(client),
        settingsControllerProvider.overrideWith(_TestSettingsController.new),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = codexChatControllerProvider('tab-thread-precondition');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await _settle();

    await container.read(provider.notifier).send('First message');
    expect(
      client.requests
          .lastWhere((request) => request.type == 'codex.turn.start')
          .payload['expectedThreadId'],
      'thread-old',
    );

    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-thread-precondition',
        'threadId': 'thread-new',
        'snapshot': <String, Object?>{'timelineCells': <Object?>[]},
        'historyNextCursor': null,
      }),
    );
    await _settle();
    await container.read(provider.notifier).send('Second message');

    expect(
      client.requests
          .lastWhere((request) => request.type == 'codex.turn.start')
          .payload['expectedThreadId'],
      'thread-new',
    );
  });

  registerCodexChatControllerHistorySessionTests();
}
