part of 'codex_chat_controller_test.dart';

void registerCodexChatControllerQueueTests() {
  test(
    'keeps queued prompts while a missing rollout awaits recovery',
    () async {
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
      final provider = codexChatControllerProvider('tab-recovery-queue');
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      final controller = container.read(provider.notifier);

      final sending = controller.send('Keep this prompt');
      client.emit(
        const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
          'tabId': 'tab-recovery-queue',
          'threadId': 'missing-thread',
          'snapshot': <String, Object?>{'timelineCells': <Object?>[]},
          'recovery': <String, Object?>{
            'kind': 'missingRollout',
            'message': 'The rollout is missing.',
          },
        }),
      );
      await _settle();

      expect(container.read(provider).queuedMessages, isEmpty);
      expect(
        client.requests.where((request) => request.type == 'codex.turn.start'),
        isEmpty,
      );

      open.complete(<String, Object?>{
        'threadId': 'missing-thread',
        'snapshot': <String, Object?>{'timelineCells': const <Object?>[]},
        'recovery': <String, Object?>{
          'kind': 'missingRollout',
          'message': 'The rollout is missing.',
        },
      });
      expect(await sending, isTrue);
      await _settle();
      expect(container.read(provider).queuedMessages, hasLength(1));
    },
  );

  test('queues, edits and removes messages while a turn is active', () async {
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

    final provider = codexChatControllerProvider('tab-1');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    container.read(provider);
    await _settle();
    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-1',
        'snapshot': <String, Object?>{'activeTurnId': 'turn-1'},
      }),
    );
    await _settle();
    final controller = container.read(provider.notifier);
    await controller.send('queued prompt');
    expect(
      container.read(provider).queuedMessages.single.text,
      'queued prompt',
    );
    controller.editQueuedMessage(0, text: 'edited prompt');
    expect(
      container.read(provider).queuedMessages.single.text,
      'edited prompt',
    );
    controller.removeQueuedMessage(0);
    expect(container.read(provider).queuedMessages, isEmpty);
    expect(
      await controller.steer(
        'Use this too',
        attachments: const <CodexInputAttachment>[
          CodexInputAttachment(path: '/tmp/steer.csv', isImage: false),
        ],
      ),
      isTrue,
    );
    final steer = client.requests.lastWhere(
      (request) => request.type == 'codex.turn.steer',
    );
    expect(steer.payload['userMessage'], <String, Object?>{
      'text': 'Use this too',
      'attachments': <Map<String, Object?>>[
        <String, Object?>{
          'path': '/tmp/steer.csv',
          'displayName': 'steer.csv',
          'kind': 'file',
          'origin': 'attachment',
          'isImage': false,
          'isDirectory': false,
        },
      ],
    });
  });

  test('keeps queued prompts when no active turn can be steered', () async {
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

    final provider = codexChatControllerProvider('tab-1');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    container.read(provider);
    await _settle();
    final controller = container.read(provider.notifier);

    expect(controller.canSteer, isFalse);
    expect(await controller.steer('Do not lose this prompt'), isFalse);
    expect(
      client.requests.where((request) => request.type == 'codex.turn.steer'),
      isEmpty,
    );
  });

  test('does not steer while an active turn is being interrupted', () async {
    final interrupt = Completer<Object?>();
    final client = _FakeCodexRuntimeClient(
      requestHandler: (type, payload) =>
          type == 'codex.turn.interrupt' ? interrupt.future : null,
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
    final provider = codexChatControllerProvider('tab-interrupting');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await _settle();
    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-interrupting',
        'snapshot': <String, Object?>{'activeTurnId': 'turn-active'},
      }),
    );
    await _settle();
    final controller = container.read(provider.notifier);
    expect(controller.canSteer, isTrue);

    final stopping = controller.stop();
    await _settle();

    expect(controller.canSteer, isFalse);
    expect(await controller.steer('Do not race the interrupt'), isFalse);
    expect(
      client.requests.where((request) => request.type == 'codex.turn.steer'),
      isEmpty,
    );

    interrupt.complete(const <String, Object?>{});
    await stopping;
  });

  test(
    'forwards attachments, collaboration, permission, speed and review target',
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
      final provider = codexChatControllerProvider('tab-1');
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      container.read(provider);
      await _settle();
      final controller = container.read(provider.notifier);
      controller.setModel('gpt-current');
      controller.setReasoning('xhigh');
      controller.setSpeed('fast');
      controller.setPermissionMode('never');
      controller.setCollaborationMode('plan');
      await _settle();
      final persisted = container.read(settingsControllerProvider).codexChat;
      expect(persisted.selectedModel, 'gpt-current');
      expect(persisted.reasoningEffort, 'xhigh');
      expect(persisted.speedMode, 'fast');
      expect(persisted.permissionMode, 'never');
      expect(persisted.planMode, isTrue);
      await controller.send(
        'Inspect @lib/main.dart',
        attachments: const <CodexInputAttachment>[
          CodexInputAttachment(path: '/tmp/screenshot.png', isImage: true),
        ],
      );
      await controller.startReview(target: 'baseBranch', delivery: 'inline');
      final turn = client.requests.singleWhere(
        (request) => request.type == 'codex.turn.start',
      );
      final payload = turn.payload;
      expect(payload['serviceTier'], 'fast');
      expect(payload['approvalPolicy'], 'never');
      expect(payload['approvalsReviewer'], 'user');
      expect(payload['sandboxPolicy'], <String, Object?>{
        'type': 'dangerFullAccess',
      });
      expect(payload['collaborationMode'], isA<Map<String, Object?>>());
      expect(payload['input'], <Object?>[
        <String, Object?>{'type': 'text', 'text': 'Inspect @lib/main.dart'},
        <String, Object?>{'type': 'localImage', 'path': '/tmp/screenshot.png'},
      ]);
      expect(payload['userMessage'], <String, Object?>{
        'text': 'Inspect @lib/main.dart',
        'attachments': <Map<String, Object?>>[
          <String, Object?>{
            'path': '/tmp/screenshot.png',
            'displayName': 'screenshot.png',
            'kind': 'image',
            'origin': 'attachment',
            'isImage': true,
            'isDirectory': false,
          },
        ],
      });
      final review = client.requests.singleWhere(
        (request) => request.type == 'codex.review.start',
      );
      expect(review.payload['target'], <String, Object?>{'type': 'baseBranch'});
      expect(review.payload['delivery'], 'inline');

      await controller.send('/app filesystem Open the selected file');
      final appTurn = client.requests.lastWhere(
        (request) => request.type == 'codex.turn.start',
      );
      expect((appTurn.payload['input'] as List).first, <String, Object?>{
        'type': 'mention',
        'name': 'filesystem',
        'path': 'app://connector-filesystem',
      });
      expect((appTurn.payload['input'] as List)[1], <String, Object?>{
        'type': 'text',
        'text': r'$filesystem Open the selected file',
      });
      expect(appTurn.payload['clientUserMessageId'], isA<String>());
    },
  );
}
