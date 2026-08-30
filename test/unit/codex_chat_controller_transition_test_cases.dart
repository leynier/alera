part of 'codex_chat_controller_test.dart';

void registerCodexChatControllerTransitionTests() {
  test('does not drain queued prompts into a resumed thread', () async {
    late _FakeCodexRuntimeClient client;
    client = _FakeCodexRuntimeClient(
      requestHandler: (type, payload) {
        if (type != 'codex.thread.resume') return null;
        return () async {
          client.emit(
            const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
              'tabId': 'tab-session-queue',
              'snapshot': <String, Object?>{
                'timelineCells': <Object?>[],
                'pendingRequests': <Object?>[],
              },
            }),
          );
          await Future<void>.delayed(.zero);
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
        codexChatRuntimeClientProvider.overrideWithValue(client),
        settingsControllerProvider.overrideWith(_TestSettingsController.new),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = codexChatControllerProvider('tab-session-queue');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await _settle();
    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-session-queue',
        'snapshot': <String, Object?>{'activeTurnId': 'turn-old'},
      }),
    );
    await _settle();
    final controller = container.read(provider.notifier);
    await controller.send('queued for the old thread');

    await controller.resumeThread(
      const CodexThreadSummary(id: 'thread-new', title: 'New Thread'),
    );
    await _settle();

    expect(container.read(provider).queuedMessages, isEmpty);
    expect(
      client.requests.where((request) => request.type == 'codex.turn.start'),
      isEmpty,
    );
  });

  test('drains prompts queued while a session transition is pending', () async {
    final transitionResponse = Completer<Map<String, Object?>>();
    final client = _FakeCodexRuntimeClient(
      requestHandler: (type, payload) =>
          type == 'codex.thread.new' ? transitionResponse.future : null,
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
    final provider = codexChatControllerProvider('tab-transition-queue');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await _settle();
    final controller = container.read(provider.notifier);

    final transition = controller.newThread();
    await _settle();
    await controller.send('queued during transition');
    transitionResponse.complete(<String, Object?>{
      'threadId': 'thread-new',
      'snapshot': <String, Object?>{
        'timelineCells': const <Object?>[],
        'pendingRequests': const <Object?>[],
      },
    });
    expect(await transition, isTrue);
    await _settle();

    final turnStarts = client.requests
        .where((request) => request.type == 'codex.turn.start')
        .toList();
    expect(turnStarts, hasLength(1));
    expect(turnStarts.single.payload['expectedThreadId'], 'thread-new');
    expect(container.read(provider).queuedMessages, isEmpty);
  });

  test(
    'waits for every overlapping session transition before draining',
    () async {
      final firstResponse = Completer<Map<String, Object?>>();
      final secondResponse = Completer<Map<String, Object?>>();
      final client = _FakeCodexRuntimeClient(
        requestHandler: (type, payload) => switch (type) {
          'codex.thread.new' => firstResponse.future,
          'codex.thread.clear' => secondResponse.future,
          _ => null,
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
      final provider = codexChatControllerProvider(
        'tab-overlapping-transition',
      );
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      await _settle();
      final controller = container.read(provider.notifier);

      final first = controller.newThread();
      await _settle();
      final second = controller.clearThread();
      await _settle();
      await controller.send('queued until both transitions finish');
      firstResponse.complete(<String, Object?>{
        'threadId': 'thread-first',
        'snapshot': <String, Object?>{'timelineCells': const <Object?>[]},
      });
      expect(await first, isTrue);
      await _settle();
      expect(
        client.requests.where((request) => request.type == 'codex.turn.start'),
        isEmpty,
      );

      secondResponse.complete(<String, Object?>{
        'threadId': 'thread-second',
        'snapshot': <String, Object?>{'timelineCells': const <Object?>[]},
      });
      expect(await second, isTrue);
      await _settle();

      final turnStarts = client.requests
          .where((request) => request.type == 'codex.turn.start')
          .toList();
      expect(turnStarts, hasLength(1));
      expect(turnStarts.single.payload['expectedThreadId'], 'thread-second');
    },
  );

  test(
    'drops an old queue when an overlapping session transition succeeds',
    () async {
      final firstResponse = Completer<Map<String, Object?>>();
      final secondResponse = Completer<Map<String, Object?>>();
      final client = _FakeCodexRuntimeClient(
        requestHandler: (type, payload) => switch (type) {
          'codex.thread.new' => firstResponse.future,
          'codex.thread.clear' => secondResponse.future,
          _ => null,
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
      final provider = codexChatControllerProvider(
        'tab-overlapping-failed-transition',
      );
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      await _settle();
      client.emit(
        const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
          'tabId': 'tab-overlapping-failed-transition',
          'threadId': 'thread-old',
          'snapshot': <String, Object?>{'activeTurnId': 'turn-old'},
        }),
      );
      await _settle();
      final controller = container.read(provider.notifier);
      await controller.send('queued for the old thread');

      final first = controller.newThread();
      await _settle();
      final second = controller.clearThread();
      await _settle();
      await controller.send('queued during transition');
      firstResponse.completeError(StateError('first transition failed'));
      expect(await first, isFalse);
      await _settle();
      expect(
        client.requests.where((request) => request.type == 'codex.turn.start'),
        isEmpty,
      );

      secondResponse.complete(<String, Object?>{
        'threadId': 'thread-second',
        'snapshot': <String, Object?>{'timelineCells': const <Object?>[]},
      });
      expect(await second, isTrue);
      await _settle();

      final turnStarts = client.requests
          .where((request) => request.type == 'codex.turn.start')
          .toList();
      expect(turnStarts, hasLength(1));
      expect(turnStarts.single.payload['expectedThreadId'], 'thread-second');
      expect(turnStarts.single.payload['input'], <Object?>[
        <String, Object?>{'type': 'text', 'text': 'queued during transition'},
      ]);
    },
  );
}
