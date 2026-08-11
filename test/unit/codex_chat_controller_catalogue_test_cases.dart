part of 'codex_chat_controller_test.dart';

void registerCodexChatControllerCatalogueTests() {
  test('downgrades auto-review when the sidecar lacks turn policy', () async {
    final client =
        _FakeCodexRuntimeClient(runtimeCapabilities: const <String>[])
          ..configurations['tab-legacy-policy'] = <String, Object?>{
            'permissionMode': 'auto-review',
          };
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
    final provider = codexChatControllerProvider('tab-legacy-policy');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await _settle();

    final state = container.read(provider);
    expect(state.supportsAutoReview, isFalse);
    expect(state.permissionMode, 'on-request');
    await _settle();
    expect(
      client.configurations['tab-legacy-policy']?['permissionMode'],
      'on-request',
    );
    expect(
      container.read(settingsControllerProvider).codexChat.permissionMode,
      'auto-review',
    );
  });

  test('loads dynamic catalogues and uses current model metadata', () async {
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
    final state = container.read(provider);
    expect(state.loading, isFalse);
    expect(state.selectedModel, 'gpt-current');
    expect(state.models.single.reasoningEfforts, <String>['xhigh', 'low']);
    expect(state.models.single.defaultReasoningEffort, 'low');
    expect(state.models.single.supportsFastMode, isTrue);
    expect(state.reasoningEffort, 'low');
    expect(state.collaborationModes.single['mode'], 'plan');
    expect(state.skills.single['name'], 'review');
    expect(state.apps.single['name'], 'filesystem');
  });

  test('an explicit null tab model clears the current selection', () async {
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
    final provider = codexChatControllerProvider('tab-null-model');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await _settle();
    expect(container.read(provider).selectedModel, 'gpt-current');

    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-null-model',
        'configuration': <String, Object?>{'selectedModel': null},
      }),
    );
    await _settle();

    expect(container.read(provider).selectedModel, isNull);
  });

  test(
    'normalizes legacy untrusted permissions to the visible approval mode',
    () async {
      final client = _FakeCodexRuntimeClient()
        ..configurations['tab-untrusted'] = <String, Object?>{
          'selectedModel': 'gpt-current',
          'reasoningEffort': 'low',
          'speedMode': 'normal',
          'permissionMode': 'untrusted',
          'planMode': false,
          'collaborationMode': null,
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
      final provider = codexChatControllerProvider('tab-untrusted');
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);

      await _settle();

      expect(container.read(provider).permissionMode, 'on-request');
    },
  );

  test(
    'restores supported effort per tab instead of the model default',
    () async {
      final client = _FakeCodexRuntimeClient()
        ..configurations['tab-1'] = <String, Object?>{
          'selectedModel': 'gpt-current',
          'reasoningEffort': 'xhigh',
          'speedMode': 'normal',
          'permissionMode': 'on-request',
          'planMode': false,
          'collaborationMode': null,
        }
        ..configurations['tab-2'] = <String, Object?>{
          'selectedModel': 'gpt-current',
          'reasoningEffort': 'xhigh',
          'speedMode': 'normal',
          'permissionMode': 'on-request',
          'planMode': false,
          'collaborationMode': null,
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

      final first = codexChatControllerProvider('tab-1');
      final firstSubscription = container.listen(
        first,
        (_, _) {},
        fireImmediately: true,
      );
      await _settle();
      expect(container.read(first).reasoningEffort, 'xhigh');
      firstSubscription.close();
      container.invalidate(first);

      final second = codexChatControllerProvider('tab-2');
      final secondSubscription = container.listen(
        second,
        (_, _) {},
        fireImmediately: true,
      );
      await _settle();
      container.read(second.notifier).setReasoning('low');
      await _settle();
      expect(client.configurations['tab-2']!['reasoningEffort'], 'low');
      secondSubscription.close();
      container.invalidate(second);

      final reopenedSubscription = container.listen(
        first,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(reopenedSubscription.close);
      await _settle();
      expect(container.read(first).reasoningEffort, 'xhigh');
    },
  );

  test(
    'surfaces missing rollout recovery without replacing the snapshot',
    () async {
      final client = _FakeCodexRuntimeClient()
        ..openThreadId = 'thread-recovery'
        ..recoveries['tab-1'] = <String, Object?>{
          'kind': 'missingRollout',
          'message': 'The saved Codex context is no longer available.',
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
      final provider = codexChatControllerProvider('tab-1');
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await _settle();
      expect(container.read(provider).recovery?.kind, 'missingRollout');
      final openRequest = client.requests.singleWhere(
        (request) => request.type == 'codex.thread.open',
      );
      expect(openRequest.payload['supportsMissingRolloutRecovery'], isTrue);

      await container.read(provider.notifier).recoverThread();

      expect(container.read(provider).recovery, isNull);
      final recoveryRequest = client.requests.singleWhere(
        (request) => request.type == 'codex.thread.recover',
      );
      expect(recoveryRequest.payload['expectedThreadId'], 'thread-recovery');

      await container.read(provider.notifier).send('Start clean');
      final nextTurn = client.requests.lastWhere(
        (request) => request.type == 'codex.turn.start',
      );
      expect(nextTurn.payload, containsPair('expectedThreadId', null));
    },
  );

  test('coalesces concurrent missing-rollout recovery requests', () async {
    final recovery = Completer<Object?>();
    final client =
        _FakeCodexRuntimeClient(
            requestHandler: (type, payload) =>
                type == 'codex.thread.recover' ? recovery.future : null,
          )
          ..openThreadId = 'thread-recovery'
          ..recoveries['tab-recovery-once'] = <String, Object?>{
            'kind': 'missingRollout',
            'message': 'The saved Codex context is no longer available.',
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
    final provider = codexChatControllerProvider('tab-recovery-once');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await _settle();

    final controller = container.read(provider.notifier);
    final first = controller.recoverThread();
    final second = controller.recoverThread();
    await _settle();
    expect(
      client.requests.where(
        (request) => request.type == 'codex.thread.recover',
      ),
      hasLength(1),
    );

    recovery.complete(<String, Object?>{
      'threadId': null,
      'snapshot': <String, Object?>{'timelineCells': const <Object?>[]},
    });
    await Future.wait(<Future<void>>[first, second]);
    expect(container.read(provider).recovery, isNull);
  });

  test(
    'flattens current cwd-grouped skills and ignores disabled skills',
    () async {
      final client = _FakeCodexRuntimeClient()
        ..skills = <String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'cwd': '/repo',
              'skills': <Object?>[
                <String, Object?>{
                  'name': 'enabled-skill',
                  'description': 'Enabled',
                  'path': '/skills/enabled/SKILL.md',
                  'enabled': true,
                },
                <String, Object?>{
                  'name': 'disabled-skill',
                  'description': 'Disabled',
                  'path': '/skills/disabled/SKILL.md',
                  'enabled': false,
                },
              ],
              'errors': const <Object?>[],
            },
          ],
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
      final sub = container.listen(
        codexChatControllerProvider('tab-skills'),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      await _settle();

      final skills = container
          .read(codexChatControllerProvider('tab-skills'))
          .skills;
      expect(skills.map((skill) => skill['name']), <String>['enabled-skill']);
      expect(skills.single['cwd'], '/repo');

      client.skills = <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'cwd': '/repo',
            'skills': <Object?>[
              <String, Object?>{
                'name': 'refreshed-skill',
                'path': '/skills/refreshed/SKILL.md',
                'enabled': true,
              },
            ],
          },
        ],
      };
      client.emit(
        const RuntimeHostEvent('codexCatalogChanged', <String, Object?>{
          'catalog': 'skills',
        }),
      );
      await _settle();
      expect(
        container
            .read(codexChatControllerProvider('tab-skills'))
            .skills
            .single['name'],
        'refreshed-skill',
      );
    },
  );

  test('account refresh revalidates the desktop model safely', () async {
    var catalogueRevision = 0;
    Future<Object?>? requestHandler(String type, Map<String, Object?> payload) {
      if (type != 'codex.model.list' || catalogueRevision == 0) return null;
      if (catalogueRevision == 3) {
        return Future<Object?>.error(StateError('model discovery failed'));
      }
      final models = catalogueRevision == 1
          ? <Object?>[
              <String, Object?>{
                'id': 'gpt-current',
                'displayName': 'Current Codex',
              },
              <String, Object?>{
                'id': 'gpt-next',
                'displayName': 'Next Codex',
                'isDefault': true,
              },
            ]
          : <Object?>[
              <String, Object?>{
                'id': 'gpt-next',
                'displayName': 'Next Codex',
                'isDefault': true,
              },
            ];
      return Future<Object?>.value(<String, Object?>{'data': models});
    }

    final client = _FakeCodexRuntimeClient(requestHandler: requestHandler);
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
    final provider = codexChatControllerProvider('tab-account-model');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await _settle();

    catalogueRevision = 1;
    client.emit(
      const RuntimeHostEvent('codexCatalogChanged', <String, Object?>{
        'catalog': 'account',
      }),
    );
    await _settle();
    expect(container.read(provider).selectedModel, 'gpt-current');

    catalogueRevision = 2;
    client.emit(
      const RuntimeHostEvent('codexCatalogChanged', <String, Object?>{
        'catalog': 'account',
      }),
    );
    await _settle();
    expect(container.read(provider).selectedModel, 'gpt-next');
    await container.read(provider.notifier).send('Use the available model');
    expect(
      client.requests
          .lastWhere((request) => request.type == 'codex.turn.start')
          .payload['model'],
      'gpt-next',
    );

    catalogueRevision = 3;
    client.emit(
      const RuntimeHostEvent('codexCatalogChanged', <String, Object?>{
        'catalog': 'account',
      }),
    );
    await _settle();
    expect(container.read(provider).selectedModel, 'gpt-next');
    expect(container.read(provider).models.single.id, 'gpt-next');
  });
}
