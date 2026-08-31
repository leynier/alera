part of 'codex_chat_controller_test.dart';

void registerCodexSubmissionRecoveryTests() {
  for (final steer in [false, true]) {
    test(
      'lost ${steer ? "Steer" : "send"} acknowledgement survives controller disposal',
      () async {
        var thread = 'thread';
        final ids = <Object?>[];
        final client = _FakeCodexRuntimeClient(
          requestHandler: (type, payload) {
            if (type == 'codex.thread.open') {
              return Future.value({
                'threadId': thread,
                'chatFeatures': ['codexSharedQueueV1'],
                'snapshot': {
                  'activeTurnId': 'turn',
                  'timelineCells': <Object?>[],
                },
              });
            }
            if (type == 'codex.queue.add') {
              ids.add(payload['clientUserMessageId']);
              return Future.error(StateError('Acknowledgement lost'));
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
          container.dispose();
          client.dispose();
        });
        final provider = codexChatControllerProvider('retry');
        for (var attempt = 0; attempt < 3; attempt++) {
          if (attempt == 2) thread = 'different';
          final listener = container.listen(provider, (_, _) {});
          await _settle();
          final controller = container.read(provider.notifier);
          expect(
            await (steer
                ? controller.steer('Correction')
                : controller.send('Correction')),
            isFalse,
          );
          listener.close();
          await container.pump();
          expect(container.exists(provider), isFalse);
        }
        expect(ids, hasLength(3));
        expect(ids[1], ids[0]);
        expect(ids[2], isNot(ids[0]));
      },
    );
  }
  test(
    'reopening a different thread accepts its lower queue revision',
    () async {
      var thread = 'old';
      var revision = 99;
      Map<String, Object?> queue() => {
        'tabId': 'retry',
        'threadId': thread,
        'revision': revision,
        'paused': true,
        'messages': [
          {
            'id': thread,
            'status': 'queued',
            'payload': {
              'draft': {'text': thread},
            },
          },
        ],
      };
      final client = _FakeCodexRuntimeClient(
        requestHandler: (type, payload) {
          if (type == 'codex.thread.open') {
            return Future.value({
              'threadId': thread,
              'chatFeatures': ['codexSharedQueueV1'],
              'snapshot': {'timelineCells': <Object?>[]},
              'queue': queue(),
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
      final provider = codexChatControllerProvider('retry');
      final listener = container.listen(provider, (_, _) {});
      addTearDown(listener.close);
      await _settle();
      expect(container.read(provider).queueState['revision'], 99);
      thread = 'new';
      revision = 1;
      await container.read(provider.notifier).retry();
      expect(container.read(provider).queuedMessages.single.text, 'new');
      expect(container.read(provider).queueState['revision'], 1);
      revision = 2;
      client.emit(RuntimeHostEvent('codexQueueChanged', queue()));
      await _settle();
      expect(container.read(provider).queueState['revision'], 2);
      revision = 1;
      await container.read(provider.notifier).retry();
      expect(container.read(provider).queueState['revision'], 2);
    },
  );
}
