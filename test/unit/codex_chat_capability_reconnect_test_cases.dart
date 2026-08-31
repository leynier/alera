part of 'codex_chat_controller_test.dart';

void registerCodexCapabilityReconnectTests() {
  const features = ['codexSharedQueueV1', 'codexForkV1', 'codexHistoryEditV1'];
  Map<String, Object?> queue(List<Map<String, Object?>> entries) => {
    'tabId': 'reconnect',
    'threadId': 'thread',
    'revision': 2,
    'paused': true,
    'messages': entries,
  };
  ProviderContainer containerFor(_FakeCodexRuntimeClient client) =>
      ProviderContainer(
        overrides: [
          codexChatHostClientProvider.overrideWithValue(
            CodexChatHostClient(client),
          ),
          settingsControllerProvider.overrideWith(_TestSettingsController.new),
        ],
      );
  final provider = codexChatControllerProvider('reconnect');

  test('reconnect migrates paused local entries once after a lost insertion acknowledgement', () async {
    var upgraded = false;
    var loseAcknowledgement = true;
    final accepted = <String, Map<String, Object?>>{};
    final client = _FakeCodexRuntimeClient(
      requestHandler: (type, payload) {
        if (type == 'status.get') {
          return Future.value({
            'runtimeCapabilities': upgraded ? features : <String>[],
          });
        }
        if (type == 'codex.thread.open') {
          return Future.value({
            'threadId': 'thread',
            'snapshot': {
              'activeTurnId': 'active',
              'timelineCells': <Object?>[],
            },
          });
        }
        if (type == 'codex.queue.get' || type == 'codex.queue.pause') {
          return Future.value(queue(accepted.values.toList()));
        }
        if (type == 'codex.queue.add') {
          final id = payload['clientUserMessageId']! as String;
          accepted.putIfAbsent(
            id,
            () => {'id': id, 'status': 'queued', 'payload': payload},
          );
          if (loseAcknowledgement) {
            loseAcknowledgement = false;
            return Future.error(StateError('Acknowledgement lost'));
          }
          return Future.value(queue(accepted.values.toList()));
        }
        return null;
      },
    );
    final container = containerFor(client);
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    addTearDown(() {
      container.dispose();
      client.dispose();
    });
    container.read(provider);
    await _settle();
    final controller = container.read(provider.notifier);
    await controller.queueAction('pause');
    await controller.send(
      'First',
      attachments: const [
        CodexInputAttachment(path: '/tmp/image.png', isImage: true),
      ],
    );
    await controller.send('Second');
    final ids = container
        .read(provider)
        .queuedMessages
        .map((entry) => entry.id)
        .toList();
    upgraded = true;
    client.emit(const RuntimeHostEvent(aleraRuntimeHostConnectedEvent, {}));
    await _settle();
    expect(
      container.read(provider).queuedMessages.map((entry) => entry.id),
      ids,
    );
    expect(
      container.read(provider).error,
      contains('Pending messages are preserved'),
    );
    expect(await controller.send('Do not send yet'), isFalse);
    await controller.retry();
    final state = container.read(provider);
    expect(state.chatFeatures, features.toSet());
    expect(state.queuedMessages.map((entry) => entry.text), [
      'First',
      'Second',
    ]);
    expect(state.queuePaused, isTrue);
    final insertions = client.requests
        .where((call) => call.type == 'codex.queue.add')
        .toList();
    expect(insertions.map((call) => call.payload['clientUserMessageId']), [
      ids[0],
      ids[0],
      ids[1],
    ]);
    expect(
      insertions.first.payload['input'],
      contains(equals({'type': 'localImage', 'path': '/tmp/image.png'})),
    );
    expect(
      client.requests.where((call) => call.type == 'codex.turn.start'),
      isEmpty,
    );
    expect(
      client.requests.indexWhere((call) => call.type == 'codex.queue.pause'),
      lessThan(
        client.requests.indexWhere((call) => call.type == 'codex.queue.add'),
      ),
    );
  });

  for (final upgrading in [true, false]) {
    test(
      'submission waits for authoritative reconnect capabilities: $upgrading',
      () async {
        Completer<Object?>? status;
        final client = _FakeCodexRuntimeClient(
          requestHandler: (type, payload) {
            if (type == 'status.get') {
              return status?.future ??
                  Future.value({
                    'runtimeCapabilities': upgrading ? <String>[] : features,
                  });
            }
            if (type == 'codex.thread.open') {
              return Future.value({
                'threadId': 'thread',
                'chatFeatures': upgrading ? <String>[] : features,
                'snapshot': {'timelineCells': <Object?>[]},
                if (!upgrading) 'queue': queue([]),
              });
            }
            if (type == 'codex.queue.get' || type == 'codex.queue.add') {
              return Future.value(queue([]));
            }
            return null;
          },
        );
        final container = containerFor(client);
        final listener = container.listen(provider, (_, _) {});
        addTearDown(listener.close);
        addTearDown(() {
          container.dispose();
          client.dispose();
        });
        container.read(provider);
        await _settle();
        status = Completer<Object?>();
        client.emit(const RuntimeHostEvent(aleraRuntimeHostConnectedEvent, {}));
        await _settle();
        final sending = container.read(provider.notifier).send('New message');
        await _settle();
        expect(
          client.requests.where(
            (call) =>
                call.type == 'codex.queue.add' ||
                call.type == 'codex.turn.start',
          ),
          isEmpty,
        );
        status.complete({
          'runtimeCapabilities': upgrading ? features : <String>[],
        });
        expect(await sending, isTrue);
        expect(container.read(provider).supportsSharedQueue, upgrading);
        expect(
          client.requests.where(
            (call) =>
                call.type ==
                (upgrading ? 'codex.queue.add' : 'codex.turn.start'),
          ),
          hasLength(1),
        );
      },
    );
  }

  for (final statusFails in [false, true]) {
    test(
      'reconnect retains shared rows without local dispatch: failure=$statusFails',
      () async {
        var reconnecting = false;
        var restored = false;
        final entries = <Map<String, Object?>>[
          {
            'id': 'remote',
            'status': 'queued',
            'payload': {
              'draft': {'text': 'Remote pending'},
            },
          },
        ];
        final client = _FakeCodexRuntimeClient(
          requestHandler: (type, payload) {
            if (type == 'status.get') {
              if (reconnecting && !restored && statusFails) {
                return Future.error(StateError('Status unavailable'));
              }
              return Future.value({
                'runtimeCapabilities': reconnecting && !restored
                    ? <String>[]
                    : features,
              });
            }
            if (type == 'codex.thread.open') {
              return Future.value({
                'threadId': 'thread',
                'chatFeatures': features,
                'snapshot': {'timelineCells': <Object?>[]},
                'queue': queue(entries),
              });
            }
            if (type == 'codex.queue.get') return Future.value(queue(entries));
            return null;
          },
        );
        final container = containerFor(client);
        final listener = container.listen(provider, (_, _) {});
        addTearDown(listener.close);
        addTearDown(() {
          container.dispose();
          client.dispose();
        });
        container.read(provider);
        await _settle();
        reconnecting = true;
        client.emit(const RuntimeHostEvent(aleraRuntimeHostConnectedEvent, {}));
        await _settle();
        final controller = container.read(provider.notifier);
        expect(container.read(provider).supportsSharedQueue, statusFails);
        expect(
          container.read(provider).queuedMessages.single.text,
          'Remote pending',
        );
        expect(await controller.queueAction('resume'), isFalse);
        expect(await controller.send('Do not route locally'), isFalse);
        expect(
          client.requests.where(
            (call) =>
                call.type == 'codex.turn.start' ||
                call.type == 'codex.queue.add',
          ),
          isEmpty,
        );
        restored = true;
        client.emit(const RuntimeHostEvent(aleraRuntimeHostConnectedEvent, {}));
        await _settle();
        expect(container.read(provider).chatFeatures, features.toSet());
        expect(
          container.read(provider).queuedMessages.single.text,
          'Remote pending',
        );
        expect(
          client.requests.where((call) => call.type == 'codex.queue.add'),
          isEmpty,
        );
      },
    );
  }
}
