part of 'codex_chat_controller_test.dart';

void registerCodexSharedQueueTests() {
  for (final initialBinding in [true, false]) {
    test(
      'legacy queue ${initialBinding ? "survives first binding" : "does not move to another chat"}',
      () async {
        final firstTurn = Completer<Object?>();
        final client = _FakeCodexRuntimeClient(
          requestHandler: (type, payload) =>
              type == 'codex.turn.start' ? firstTurn.future : null,
        )..openThreadId = initialBinding ? null : 'old';
        final container = ProviderContainer(
          overrides: [
            codexChatRuntimeClientProvider.overrideWithValue(client),
            settingsControllerProvider.overrideWith(
              _TestSettingsController.new,
            ),
          ],
        );
        addTearDown(() {
          client.dispose();
          container.dispose();
        });
        final provider = codexChatControllerProvider('legacy');
        final listener = container.listen(provider, (_, _) {});
        addTearDown(listener.close);
        await _settle();
        final controller = container.read(provider.notifier);
        final sending = controller.send('First');
        await _settle();
        await controller.send('Second');
        expect(container.read(provider).queuedMessages, hasLength(1));
        client.emit(
          const RuntimeHostEvent('codexThreadChanged', {
            'tabId': 'legacy',
            'threadId': 'created',
            'snapshot': {'activeTurnId': 'turn', 'timelineCells': <Object?>[]},
          }),
        );
        await _settle();
        expect(
          container.read(provider).queuedMessages,
          hasLength(initialBinding ? 1 : 0),
        );
        firstTurn.complete({
          'turn': {'id': 'turn'},
        });
        await sending;
        client.emit(
          const RuntimeHostEvent('codexThreadChanged', {
            'tabId': 'legacy',
            'threadId': 'created',
            'snapshot': {'timelineCells': <Object?>[]},
          }),
        );
        await _settle();
        expect(
          client.requests.where((r) => r.type == 'codex.turn.start'),
          hasLength(initialBinding ? 2 : 1),
        );
      },
    );
  }

  Map<String, Object?> sharedQueue(int revision, String text) => {
    'tabId': 'shared',
    'threadId': 'thread',
    'revision': revision,
    'paused': true,
    'messages': [
      {
        'id': 'queued',
        'status': 'queued',
        'payload': {
          'draft': {'text': text},
        },
      },
    ],
  };

  for (final reconnect in [true, false]) {
    test(
      reconnect
          ? 'reconnect fetches authoritative shared queue after missed events'
          : 'failed session change does not duplicate a shared queue snapshot',
      () async {
        final transition = Completer<Object?>();
        final client = _FakeCodexRuntimeClient(
          runtimeCapabilities: const ['codexSharedQueueV1'],
          requestHandler: (type, payload) {
            if (type == 'codex.thread.open') {
              return Future.value({
                'threadId': 'thread',
                'chatFeatures': ['codexSharedQueueV1'],
                'snapshot': {'timelineCells': <Object?>[]},
                'queue': sharedQueue(1, 'original'),
              });
            }
            if (type == 'codex.queue.get') {
              return Future.value(sharedQueue(2, 'authoritative'));
            }
            if (type == 'codex.thread.new') return transition.future;
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
          client.dispose();
          container.dispose();
        });
        final provider = codexChatControllerProvider('shared');
        final listener = container.listen(provider, (_, _) {});
        addTearDown(listener.close);
        await _settle();
        if (reconnect) {
          client.emit(
            const RuntimeHostEvent(aleraRuntimeHostConnectedEvent, {}),
          );
          await _settle();
          expect(
            client.requests.where((r) => r.type == 'codex.queue.get'),
            hasLength(1),
          );
        } else {
          final changing = container.read(provider.notifier).newThread();
          client.emit(
            RuntimeHostEvent(
              'codexQueueChanged',
              sharedQueue(2, 'authoritative'),
            ),
          );
          await _settle();
          transition.completeError(StateError('New chat rejected'));
          expect(await changing, isFalse);
        }
        expect(container.read(provider).queuedMessages.map((m) => m.text), [
          'authoritative',
        ]);
        expect(container.read(provider).queuePaused, isTrue);
        expect(
          client.requests.where((r) => r.type == 'codex.turn.start'),
          isEmpty,
        );
      },
    );
  }

  test('queue fetch completed after switching chats is discarded', () async {
    final pending = Completer<Object?>();
    final client = _FakeCodexRuntimeClient(
      requestHandler: (type, payload) {
        if (type == 'codex.thread.open') {
          return Future.value({
            'threadId': 'thread',
            'chatFeatures': ['codexSharedQueueV1'],
            'snapshot': {'timelineCells': <Object?>[]},
            'queue': sharedQueue(1, 'old'),
          });
        }
        if (type == 'codex.queue.get') return pending.future;
        if (type == 'codex.thread.new') {
          return Future.value({
            'threadId': null,
            'snapshot': {'timelineCells': <Object?>[]},
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
      client.dispose();
      container.dispose();
    });
    final provider = codexChatControllerProvider('shared');
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    await _settle();
    final controller = container.read(provider.notifier);
    final refresh = controller.refreshQueue();
    expect(await controller.newThread(), isTrue);
    pending.complete(sharedQueue(2, 'stale'));
    await refresh;
    expect(container.read(provider).queuedMessages, isEmpty);
    expect(controller.threadId, isNull);
  });

  test(
    'shared snapshots reject stale revisions and never drain locally',
    () async {
      Map<String, Object?> queue(int revision, String text) => {
        'tabId': 'shared',
        'threadId': 'thread',
        'revision': revision,
        'paused': true,
        'messages': [
          {
            'id': 'queued',
            'status': 'queued',
            'payload': {
              'draft': {'text': text},
            },
          },
        ],
      };
      final client = _FakeCodexRuntimeClient(
        requestHandler: (type, payload) => type == 'codex.thread.open'
            ? Future.value({
                'threadId': 'thread',
                'chatFeatures': ['codexSharedQueueV1'],
                'snapshot': {'timelineCells': <Object?>[]},
                'queue': queue(3, 'original'),
              })
            : null,
      );
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
      final provider = codexChatControllerProvider('shared');
      final listener = container.listen(provider, (_, _) {});
      addTearDown(listener.close);
      await _settle();
      client.emit(RuntimeHostEvent('codexQueueChanged', queue(4, 'newer')));
      client.emit(RuntimeHostEvent('codexQueueChanged', queue(2, 'stale')));
      await _settle();
      expect(container.read(provider).queuedMessages.single.text, 'newer');
      expect(
        client.requests.where((request) => request.type == 'codex.turn.start'),
        isEmpty,
      );
    },
  );

  test(
    'legacy Stop keeps subsequent sends queued until Resume Queue',
    () async {
      final client = _FakeCodexRuntimeClient();
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
      final provider = codexChatControllerProvider('legacy');
      final listener = container.listen(provider, (_, _) {});
      addTearDown(listener.close);
      await _settle();
      final controller = container.read(provider.notifier);
      await controller.stop();
      await controller.send('Wait for resume');
      expect(container.read(provider).queuePaused, isTrue);
      expect(container.read(provider).queuedMessages, hasLength(1));
      expect(
        client.requests.where((r) => r.type == 'codex.turn.start'),
        isEmpty,
      );
      await controller.queueAction('resume');
      await _settle();
      expect(
        client.requests.where((r) => r.type == 'codex.turn.start'),
        hasLength(1),
      );
    },
  );

  for (final steering in [false, true]) {
    test(
      'lost ${steering ? "Steer" : "queue"} acknowledgement reuses the submission identity',
      () async {
        final ids = <String>[];
        final client = _FakeCodexRuntimeClient(
          requestHandler: (type, payload) {
            if (type == 'codex.thread.open') {
              return Future.value({
                'threadId': 'thread',
                'chatFeatures': ['codexSharedQueueV1'],
                'snapshot': {
                  'timelineCells': <Object?>[],
                  if (steering) 'activeTurnId': 'turn',
                },
              });
            }
            if (type == 'codex.queue.add') {
              ids.add(payload['clientUserMessageId']! as String);
              return ids.length == 1
                  ? Future.error(TimeoutException('Response lost'))
                  : Future.value({
                      'threadId': 'thread',
                      'revision': 1,
                      'messages': <Object?>[],
                    });
            }
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
          client.dispose();
          container.dispose();
        });
        final provider = codexChatControllerProvider('shared');
        final listener = container.listen(provider, (_, _) {});
        addTearDown(listener.close);
        await _settle();
        final controller = container.read(provider.notifier);
        expect(
          await (steering
              ? controller.steer('Do this once')
              : controller.send('Do this once')),
          isFalse,
        );
        expect(
          await (steering
              ? controller.steer('Do this once')
              : controller.send('Do this once')),
          isTrue,
        );
        expect(ids[0], ids[1]);
      },
    );
  }
}
