part of 'codex_chat_controller_test.dart';

void registerCodexChatControllerLifecycleTests() {
  test('events received during open are applied after its response', () async {
    final opening = Completer<Object?>();
    final client = _FakeCodexRuntimeClient(
      requestHandler: (type, payload) =>
          type == 'codex.thread.open' ? opening.future : null,
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
    final provider = codexChatControllerProvider('tab-opening-race');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await Future.pause(.zero);

    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-opening-race',
        'threadId': 'thread-current',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'latest',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Latest event',
            },
          ],
        },
      }),
    );
    await Future.pause(.zero);
    opening.complete(<String, Object?>{
      'threadId': 'thread-current',
      'snapshot': <String, Object?>{
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'older',
            'kind': 'assistantMessage',
            'status': 'completed',
            'markdownText': 'Older open response',
          },
        ],
      },
    });
    await _settle();

    expect(container.read(provider).snapshot.timelineCells.single.id, 'latest');
  });

  test('coalesced opening snapshots retain earlier thread context', () async {
    final opening = Completer<Object?>();
    final client = _FakeCodexRuntimeClient(
      requestHandler: (type, payload) =>
          type == 'codex.thread.open' ? opening.future : null,
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
    final provider = codexChatControllerProvider('tab-opening-context');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await Future.pause(.zero);

    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-opening-context',
        'threadId': 'thread-current',
        'cwd': '/workspace/current',
        'historyNextCursor': 'older-page',
        'recovery': <String, Object?>{
          'kind': 'missingRollout',
          'message': 'Recovered context',
        },
        'snapshot': <String, Object?>{'timelineCells': <Object?>[]},
      }),
    );
    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-opening-context',
        'threadId': 'thread-current',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'latest',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Latest event',
            },
          ],
        },
      }),
    );
    opening.complete(<String, Object?>{
      'threadId': 'thread-current',
      'snapshot': <String, Object?>{'timelineCells': <Object?>[]},
    });
    await _settle();

    final state = container.read(provider);
    expect(state.snapshot.timelineCells.single.id, 'latest');
    expect(state.activeCwd, '/workspace/current');
    expect(state.historyNextCursor, 'older-page');
    expect(state.recovery?.message, 'Recovered context');
  });

  test('coalesced opening snapshots do not cross thread boundaries', () async {
    final opening = Completer<Object?>();
    final client = _FakeCodexRuntimeClient(
      requestHandler: (type, payload) =>
          type == 'codex.thread.open' ? opening.future : null,
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
    final provider = codexChatControllerProvider('tab-opening-thread-change');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await Future.pause(.zero);

    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-opening-thread-change',
        'threadId': 'thread-old',
        'cwd': '/workspace/old',
        'historyNextCursor': 'old-page',
        'snapshot': <String, Object?>{'timelineCells': <Object?>[]},
      }),
    );
    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-opening-thread-change',
        'threadId': 'thread-new',
        'snapshot': <String, Object?>{'timelineCells': <Object?>[]},
      }),
    );
    await Future.pause(.zero);
    opening.complete(<String, Object?>{
      'threadId': 'thread-old',
      'cwd': '/workspace/open',
      'historyNextCursor': 'open-page',
      'snapshot': <String, Object?>{'timelineCells': <Object?>[]},
    });
    await _settle();

    final state = container.read(provider);
    expect(state.activeCwd, '/workspace/open');
    expect(state.historyNextCursor, isNull);
  });

  test('remapped progress cells reconcile by semantic identity', () async {
    final client = _FakeCodexRuntimeClient()
      ..openThreadId = 'thread-current'
      ..openSnapshot = <String, Object?>{
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'item-live-progress',
            'turnId': 'turn-1',
            'kind': 'progressText',
            'status': 'inProgress',
            'isStreaming': true,
            'markdownText': 'Inspecting',
            'metadata': <String, Object?>{'streamPhase': 'commentary'},
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
    final provider = codexChatControllerProvider('tab-progress-identity');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await _settle();

    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-progress-identity',
        'threadId': 'thread-current',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'item-rollout-progress',
              'turnId': 'turn-1',
              'kind': 'progressText',
              'status': 'completed',
              'markdownText': 'Inspecting files',
              'metadata': <String, Object?>{'streamPhase': 'commentary'},
            },
          ],
        },
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': <Object?>[
            <String, Object?>{
              'id': 'item-rollout-progress',
              'turnId': 'turn-1',
              'kind': 'progressText',
              'status': 'completed',
              'markdownText': 'Inspecting files',
              'metadata': <String, Object?>{'streamPhase': 'commentary'},
            },
          ],
        },
      }),
    );
    await _settle();

    final progress = container
        .read(provider)
        .snapshot
        .timelineCells
        .where((cell) => cell.kind == CodexTimelineKind.progressText)
        .toList();
    expect(progress, hasLength(1));
    expect(progress.single.id, 'item-rollout-progress');
    expect(progress.single.markdownText, 'Inspecting files');
  });

  test('repeated same-text user messages keep distinct identities', () async {
    final client = _FakeCodexRuntimeClient()
      ..openThreadId = 'thread-current'
      ..openSnapshot = <String, Object?>{
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'user-client-1',
            'turnId': 'turn-1',
            'kind': 'userMessage',
            'status': 'completed',
            'markdownText': 'Continue',
            'metadata': <String, Object?>{
              'clientUserMessageId': 'client-1',
              'isSteering': true,
            },
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
    final provider = codexChatControllerProvider('tab-repeated-user-message');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await _settle();

    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-repeated-user-message',
        'threadId': 'thread-current',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'user-client-2',
              'turnId': 'turn-1',
              'kind': 'userMessage',
              'status': 'completed',
              'markdownText': 'Continue',
              'metadata': <String, Object?>{
                'clientUserMessageId': 'client-2',
                'isSteering': true,
              },
            },
          ],
        },
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': <Object?>[
            <String, Object?>{
              'id': 'user-client-2',
              'turnId': 'turn-1',
              'kind': 'userMessage',
              'status': 'completed',
              'markdownText': 'Continue',
              'metadata': <String, Object?>{
                'clientUserMessageId': 'client-2',
                'isSteering': true,
              },
            },
          ],
        },
      }),
    );
    await _settle();

    final userIds = container
        .read(provider)
        .snapshot
        .timelineCells
        .where((cell) => cell.kind == CodexTimelineKind.userMessage)
        .map((cell) => cell.id)
        .toSet();
    expect(userIds, <String>{'user-client-1', 'user-client-2'});
  });

  test('one remapped agent cell preserves a repeated agent cell', () async {
    final client = _FakeCodexRuntimeClient()
      ..openThreadId = 'thread-current'
      ..openSnapshot = <String, Object?>{
        'timelineCells': <Object?>[
          for (final id in <String>['item-agent-1', 'item-agent-2'])
            <String, Object?>{
              'id': id,
              'turnId': 'turn-1',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Done',
              'metadata': <String, Object?>{'streamPhase': 'final_answer'},
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
    final provider = codexChatControllerProvider('tab-repeated-agent');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await _settle();

    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-repeated-agent',
        'threadId': 'thread-current',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'item-agent-remapped',
              'turnId': 'turn-1',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Done',
              'metadata': <String, Object?>{'streamPhase': 'final_answer'},
            },
          ],
        },
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': <Object?>[
            <String, Object?>{
              'id': 'item-agent-remapped',
              'turnId': 'turn-1',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Done',
              'metadata': <String, Object?>{'streamPhase': 'final_answer'},
            },
          ],
        },
      }),
    );
    await _settle();

    final agentIds = container
        .read(provider)
        .snapshot
        .timelineCells
        .where((cell) => cell.kind == CodexTimelineKind.assistantMessage)
        .map((cell) => cell.id)
        .toSet();
    expect(agentIds, <String>{'item-agent-2', 'item-agent-remapped'});
  });

  test('Codex controller is disposed after its tab listener closes', () async {
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
    final provider = codexChatControllerProvider('tab-auto-dispose');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    await _settle();
    expect(container.exists(provider), isTrue);

    listener.close();
    await _settle();

    expect(container.exists(provider), isFalse);
  });
}
