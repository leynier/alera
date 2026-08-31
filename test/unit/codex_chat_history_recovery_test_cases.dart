part of 'codex_chat_controller_test.dart';

void registerCodexHistoryRecoveryTests() {
  Map<String, Object?> queue(int historyRevision) => {
    'tabId': 'tab',
    'threadId': 'thread',
    'revision': historyRevision + 1,
    'historyRevision': historyRevision,
    'paused': true,
    'messages': <Object?>[],
  };
  Map<String, Object?> snapshot(String text) => {
    'timelineCells': [
      {'id': text, 'kind': 'agentMessage', 'text': text, 'turnId': text},
    ],
  };
  for (final failReload in [false, true]) {
    test(
      'queue revision refreshes offline history with goals disabled (failure: $failReload)',
      () async {
        final reopened = Completer<Object?>();
        final oldPage = Completer<Object?>();
        var opens = 0;
        final client = _FakeCodexRuntimeClient(
          runtimeCapabilities: const ['codexSharedQueueV1'],
          requestHandler: (type, payload) {
            if (type == 'codex.thread.open') {
              if (++opens > 1) return reopened.future;
              return Future.value({
                'threadId': 'thread',
                'chatFeatures': ['codexSharedQueueV1'],
                'historyRevision': 0,
                'snapshot': snapshot('discarded'),
                'queue': queue(0),
                'historyNextCursor': 'old-page',
              });
            }
            if (type == 'codex.queue.get') return Future.value(queue(1));
            if (type == 'codex.thread.history') return oldPage.future;
            return null;
          },
        );
        final container = ProviderContainer(
          overrides: [
            codexChatRuntimeClientProvider.overrideWithValue(client),
            settingsControllerProvider.overrideWith(
              _TestSettingsController.new,
            ),
          ],
        );
        addTearDown(() {
          container.dispose();
          client.dispose();
        });
        final provider = codexChatControllerProvider('tab');
        final listener = container.listen(provider, (_, _) {});
        addTearDown(listener.close);
        await _settle();
        final controller = container.read(provider.notifier);
        final history = controller.loadHistory(cursor: 'old-page');
        client.emit(const RuntimeHostEvent(aleraRuntimeHostConnectedEvent, {}));
        await _settle();
        expect(opens, 2);
        expect(container.read(provider).loading, isTrue);
        final send = controller.send('New prompt');
        expect(
          client.requests.where((r) => r.type == 'codex.queue.add'),
          isEmpty,
        );
        if (failReload) {
          reopened.completeError(StateError('History unavailable'));
        } else {
          reopened.complete({
            'threadId': 'thread',
            'chatFeatures': ['codexSharedQueueV1'],
            'historyRevision': 1,
            'snapshot': snapshot('corrected'),
            'queue': queue(1),
            'historyNextCursor': 'new-page',
          });
        }
        expect(await send, !failReload);
        await _settle();
        oldPage.complete({
          'snapshot': snapshot('discarded-page'),
          'nextCursor': 'stale',
        });
        await history;
        if (failReload) {
          expect(container.read(provider).historyOutdated, isTrue);
          expect(await controller.send('Still stale'), isFalse);
          expect(
            client.requests.where((r) => r.type == 'codex.queue.add'),
            isEmpty,
          );
        } else {
          final current = container.read(provider);
          expect(current.historyRevision, 1);
          expect(current.snapshot.timelineCells.map((c) => c.id), [
            'corrected',
          ]);
          expect(current.historyNextCursor, 'new-page');
          final submitted = client.requests.singleWhere(
            (r) => r.type == 'codex.queue.add',
          );
          expect(submitted.payload['expectedHistoryRevision'], 1);
          client.emit(RuntimeHostEvent('codexQueueChanged', queue(1)));
          await _settle();
          expect(opens, 2);
        }
      },
    );
  }
  test('missing rollout recovery replaces shared queue metadata', () async {
    final client = _FakeCodexRuntimeClient(
      requestHandler: (type, payload) {
        if (type == 'codex.thread.open') {
          return Future.value({
            'threadId': 'old',
            'chatFeatures': [
              'codexSharedQueueV1',
              'codexForkV1',
              'codexHistoryEditV1',
            ],
            'historyRevision': 5,
            'snapshot': snapshot('old'),
            'recovery': {'kind': 'missingRollout'},
            'queue': {...queue(5), 'threadId': 'old'},
          });
        }
        if (type == 'codex.thread.recover') {
          return Future.value({
            'threadId': 'recovered',
            'chatFeatures': [
              'codexSharedQueueV1',
              'codexForkV1',
              'codexHistoryEditV1',
            ],
            'historyRevision': 0,
            'snapshot': snapshot('new'),
            'cwd': '/repo/new',
            'queue': {...queue(0), 'threadId': 'recovered'},
          });
        }
        return null;
      },
    );
    final container = ProviderContainer(
      overrides: [
        codexChatRuntimeClientProvider.overrideWithValue(client),
        settingsControllerProvider.overrideWith(_TestSettingsController.new),
      ],
    );
    addTearDown(() {
      container.dispose();
      client.dispose();
    });
    final provider = codexChatControllerProvider('tab');
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    await _settle();
    final controller = container.read(provider.notifier);
    await controller.recoverThread();
    final current = container.read(provider);
    expect(current.supportsSharedQueue, isTrue);
    expect(current.supportsFork, isTrue);
    expect(current.supportsHistoryEdit, isTrue);
    expect(current.queueState['threadId'], 'recovered');
    expect(current.historyRevision, 0);
    expect(current.activeCwd, '/repo/new');
    expect(current.queuePaused, isTrue);
    expect(await controller.send('Continue'), isTrue);
    final submitted = client.requests.singleWhere(
      (r) => r.type == 'codex.queue.add',
    );
    expect(submitted.payload['expectedHistoryRevision'], 0);
    expect(submitted.payload['expectedThreadId'], 'recovered');
  });
}
