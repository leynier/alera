part of 'codex_chat_controller_test.dart';

void registerCodexChatControllerSessionTests() {
  test('queues prompts until the initial thread identity is loaded', () async {
    final open = Completer<Object?>();
    final client = _FakeCodexRuntimeClient(
      requestHandler: (type, payload) {
        if (type == 'codex.thread.open') return open.future;
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
    final provider = codexChatControllerProvider('tab-loading-thread');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);

    await container.read(provider.notifier).send('Queued while opening');

    expect(
      client.requests.where((request) => request.type == 'codex.turn.start'),
      isEmpty,
    );
    expect(container.read(provider).queuedMessages, hasLength(1));

    open.complete(<String, Object?>{
      'threadId': 'thread-existing',
      'snapshot': <String, Object?>{
        'events': const <Object?>[],
        'timelineCells': const <Object?>[],
        'pendingRequests': const <Object?>[],
      },
    });
    await _settle();

    final start = client.requests.singleWhere(
      (request) => request.type == 'codex.turn.start',
    );
    expect(start.payload['expectedThreadId'], 'thread-existing');
    expect(container.read(provider).queuedMessages, isEmpty);
  });

  test(
    'keeps an opening prompt queued until rollout recovery succeeds',
    () async {
      final open = Completer<Object?>();
      final client = _FakeCodexRuntimeClient(
        requestHandler: (type, payload) {
          if (type == 'codex.thread.open') return open.future;
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
      final provider = codexChatControllerProvider('tab-recovery-queue');
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);

      await container.read(provider.notifier).send('Queued before recovery');
      open.complete(<String, Object?>{
        'threadId': 'thread-missing-rollout',
        'historyNextCursor': 'old-thread-cursor',
        'recovery': <String, Object?>{
          'kind': 'missingRollout',
          'message': 'The saved Codex context is no longer available.',
        },
        'snapshot': <String, Object?>{
          'events': const <Object?>[],
          'timelineCells': const <Object?>[],
          'pendingRequests': const <Object?>[],
        },
      });
      await _settle();

      expect(container.read(provider).queuedMessages, hasLength(1));
      expect(container.read(provider).historyNextCursor, 'old-thread-cursor');
      expect(
        client.requests.where((request) => request.type == 'codex.turn.start'),
        isEmpty,
      );

      await container.read(provider.notifier).recoverThread();
      await _settle();

      final start = client.requests.singleWhere(
        (request) => request.type == 'codex.turn.start',
      );
      expect(start.payload['expectedThreadId'], isNull);
      expect(container.read(provider).queuedMessages, isEmpty);
      expect(container.read(provider).historyNextCursor, isNull);
    },
  );

  test(
    'does not overwrite thread events while session support loads',
    () async {
      final status = Completer<Object?>();
      final client = _FakeCodexRuntimeClient(
        requestHandler: (type, payload) =>
            type == 'status.get' ? status.future : null,
      )..openSnapshot = <String, Object?>{'activeTurnId': 'turn-stale'};
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
      final provider = codexChatControllerProvider('tab-open-order');
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      while (container.read(provider).loading) {
        await Future<void>.delayed(Duration.zero);
      }

      client.emit(
        const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
          'tabId': 'tab-open-order',
          'snapshot': <String, Object?>{
            'timelineCells': <Object?>[],
            'pendingRequests': <Object?>[],
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);
      status.complete(<String, Object?>{
        'runtimeCapabilities': <String>[
          aleraRuntimeHostCodexSessionsCapability,
        ],
      });
      await _settle();

      expect(container.read(provider).snapshot.activeTurnId, isNull);
      expect(container.read(provider).supportsSessions, isTrue);
    },
  );

  test('does not inherit old thread context across a null boundary', () async {
    final open = Completer<Object?>();
    final client = _FakeCodexRuntimeClient(
      requestHandler: (type, payload) =>
          type == 'codex.thread.open' ? open.future : null,
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
    final provider = codexChatControllerProvider('tab-null-thread-boundary');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    while (!client.requests.any(
      (request) => request.type == 'codex.thread.open',
    )) {
      await Future<void>.delayed(Duration.zero);
    }

    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-null-thread-boundary',
        'threadId': 'thread-old',
        'historyNextCursor': 'old-cursor',
        'recovery': <String, Object?>{
          'kind': 'missingRollout',
          'message': 'Old recovery',
        },
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[],
          'pendingRequests': <Object?>[],
        },
      }),
    );
    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-null-thread-boundary',
        'threadId': null,
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'new-context',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'New context',
            },
          ],
          'pendingRequests': <Object?>[],
        },
      }),
    );
    await Future<void>.delayed(Duration.zero);
    open.complete(<String, Object?>{
      'threadId': 'thread-old',
      'snapshot': <String, Object?>{
        'timelineCells': const <Object?>[],
        'pendingRequests': const <Object?>[],
      },
    });
    await _settle();

    final state = container.read(provider);
    expect(state.snapshot.timelineCells.single.id, 'new-context');
    expect(state.historyNextCursor, isNull);
    expect(state.recovery, isNull);
  });

  test('gates desktop session commands on the live host capability', () async {
    final currentClient = _FakeCodexRuntimeClient();
    final oldClient = _FakeCodexRuntimeClient(runtimeCapabilities: const []);
    final currentContainer = ProviderContainer(
      overrides: [
        codexChatRuntimeClientProvider.overrideWithValue(currentClient),
        settingsControllerProvider.overrideWith(_TestSettingsController.new),
      ],
    );
    final oldContainer = ProviderContainer(
      overrides: [
        codexChatRuntimeClientProvider.overrideWithValue(oldClient),
        settingsControllerProvider.overrideWith(_TestSettingsController.new),
      ],
    );
    addTearDown(() {
      currentClient.dispose();
      oldClient.dispose();
      currentContainer.dispose();
      oldContainer.dispose();
    });
    final currentProvider = codexChatControllerProvider('tab-current');
    final oldProvider = codexChatControllerProvider('tab-old');
    final currentListener = currentContainer.listen(
      currentProvider,
      (_, _) {},
      fireImmediately: true,
    );
    final oldListener = oldContainer.listen(
      oldProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(currentListener.close);
    addTearDown(oldListener.close);
    await _settle();

    expect(currentContainer.read(currentProvider).supportsSessions, isTrue);
    expect(oldContainer.read(oldProvider).supportsSessions, isFalse);
  });

  test('refreshes host capabilities after runtime reconnection', () async {
    var supportsCurrentHost = false;
    final client = _FakeCodexRuntimeClient(
      requestHandler: (type, payload) {
        if (type != 'status.get') return null;
        return Future<Object?>.value(<String, Object?>{
          'runtimeCapabilities': <String>[
            if (supportsCurrentHost) ...<String>[
              aleraRuntimeHostCodexSessionsCapability,
              aleraRuntimeHostCodexTurnPolicyCapability,
            ],
          ],
        });
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
    final provider = codexChatControllerProvider('tab-capability-reconnect');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await _settle();

    expect(container.read(provider).supportsSessions, isFalse);
    expect(container.read(provider).supportsAutoReview, isFalse);

    supportsCurrentHost = true;
    client.emit(
      const RuntimeHostEvent(
        aleraRuntimeHostConnectedEvent,
        <String, Object?>{},
      ),
    );
    await _settle();

    expect(container.read(provider).supportsSessions, isTrue);
    expect(container.read(provider).supportsAutoReview, isTrue);
  });

  test('defers reconnect capability fallback until the tab opens', () async {
    final open = Completer<Object?>();
    final client = _FakeCodexRuntimeClient(
      runtimeCapabilities: const <String>[],
      requestHandler: (type, payload) =>
          type == 'codex.thread.open' ? open.future : null,
    );
    final container = ProviderContainer(
      overrides: [
        codexChatRuntimeClientProvider.overrideWithValue(client),
        settingsControllerProvider.overrideWith(
          _AutoReviewTestSettingsController.new,
        ),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = codexChatControllerProvider('tab-opening-reconnect');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);

    client.emit(
      const RuntimeHostEvent(
        aleraRuntimeHostConnectedEvent,
        <String, Object?>{},
      ),
    );
    await _settle();

    expect(client.configurations, isEmpty);
    open.complete(<String, Object?>{
      'threadId': null,
      'configuration': <String, Object?>{'permissionMode': 'auto-review'},
      'snapshot': <String, Object?>{
        'timelineCells': const <Object?>[],
        'pendingRequests': const <Object?>[],
      },
    });
    await _settle();

    expect(
      client.configurations['tab-opening-reconnect']?['permissionMode'],
      'on-request',
    );
  });

  registerCodexChatControllerTransitionTests();
}
