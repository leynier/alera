part of 'codex_chat_controller_test.dart';

void registerCodexChatControllerHistorySessionTests() {
  test('same-thread bounded updates retain older live cells', () async {
    final client = _FakeCodexRuntimeClient()
      ..openThreadId = 'thread-current'
      ..openSnapshot = <String, Object?>{
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'older-live',
            'kind': 'userMessage',
            'status': 'completed',
            'markdownText': 'Older prompt',
          },
          <String, Object?>{
            'id': 'recent-live',
            'kind': 'assistantMessage',
            'status': 'completed',
            'markdownText': 'Recent answer',
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
    final provider = codexChatControllerProvider('tab-bounded-live');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await _settle();

    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-bounded-live',
        'threadId': 'thread-current',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'missed-live',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Missed answer recovered from the snapshot',
            },
            <String, Object?>{
              'id': 'recent-live',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Updated recent answer',
            },
            <String, Object?>{
              'id': 'new-live',
              'kind': 'assistantMessage',
              'status': 'inProgress',
              'markdownText': 'New answer',
            },
          ],
        },
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': <Object?>[
            <String, Object?>{
              'id': 'recent-live',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Updated recent answer',
            },
            <String, Object?>{
              'id': 'new-live',
              'kind': 'assistantMessage',
              'status': 'inProgress',
              'markdownText': 'New answer',
            },
          ],
        },
      }),
    );
    await _settle();

    final cells = container.read(provider).snapshot.timelineCells;
    expect(cells.map((cell) => cell.id), <String>[
      'older-live',
      'missed-live',
      'recent-live',
      'new-live',
    ]);
    expect(cells[2].markdownText, 'Updated recent answer');
  });

  test(
    'identity-only thread events do not complete or drain an active send',
    () async {
      final turnStart = Completer<Object?>();
      final client = _FakeCodexRuntimeClient(
        requestHandler: (type, payload) =>
            type == 'codex.turn.start' ? turnStart.future : null,
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
      final provider = codexChatControllerProvider('tab-identity-only');
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      await _settle();
      final controller = container.read(provider.notifier);

      final firstSend = controller.send('First message');
      await _settle();
      await controller.send('Second message');
      client.emit(
        const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
          'tabId': 'tab-identity-only',
          'threadId': 'thread-created',
          'cwd': '/workspace/created',
        }),
      );
      await _settle();

      final duringSend = container.read(provider);
      expect(duringSend.sending, isTrue);
      expect(duringSend.activeCwd, '/workspace/created');
      expect(duringSend.queuedMessages, hasLength(1));
      expect(
        client.requests.where((request) => request.type == 'codex.turn.start'),
        hasLength(1),
      );

      turnStart.complete(<String, Object?>{
        'turn': <String, Object?>{'id': 'turn-1'},
      });
      await firstSend;
    },
  );

  test('reloads session catalogues after resuming a thread', () async {
    final client = _FakeCodexRuntimeClient(
      requestHandler: (type, payload) => type == 'codex.thread.resume'
          ? Future<Object?>.value(<String, Object?>{
              'threadId': 'thread-resumed',
              'cwd': '/workspace/resumed',
              'snapshot': <String, Object?>{'timelineCells': const <Object?>[]},
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
    final provider = codexChatControllerProvider('tab-catalogue-resume');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await _settle();
    expect(container.read(provider).skills.single['name'], 'review');
    client.skills = <String, Object?>{
      'data': <Object?>[
        <String, Object?>{'name': 'resumed', 'path': '/skills/resumed'},
      ],
    };

    await container
        .read(provider.notifier)
        .resumeThread(
          const CodexThreadSummary(id: 'thread-resumed', title: 'Resumed'),
        );

    expect(container.read(provider).skills.single['name'], 'resumed');
    expect(container.read(provider).activeCwd, '/workspace/resumed');
  });

  test('reloads session catalogues after an external thread switch', () async {
    final client = _FakeCodexRuntimeClient()..openThreadId = 'thread-original';
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
    final provider = codexChatControllerProvider('tab-external-catalogue');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    await _settle();
    expect(container.read(provider).skills.single['name'], 'review');
    client.skills = <String, Object?>{
      'data': <Object?>[
        <String, Object?>{'name': 'external', 'path': '/skills/external'},
      ],
    };

    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-external-catalogue',
        'threadId': 'thread-external',
        'cwd': '/workspace/external',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[],
          'pendingRequests': <Object?>[],
        },
      }),
    );
    await _settle();

    expect(container.read(provider).skills.single['name'], 'external');
    expect(container.read(provider).activeCwd, '/workspace/external');
  });

  test(
    'same-thread broadcasts preserve loaded history and switch cursors',
    () async {
      final client = _FakeCodexRuntimeClient()
        ..openThreadId = 'thread-current'
        ..openSnapshot = <String, Object?>{
          'events': <Object?>[
            <String, Object?>{'method': 'evicted-from-host-window'},
          ],
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'recent',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Recent answer',
            },
          ],
        }
        ..historyResponse = <String, Object?>{
          'snapshot': <String, Object?>{
            'events': <Object?>[
              <String, Object?>{'method': 'older-history-page'},
            ],
            'timelineCells': <Object?>[
              <String, Object?>{
                'id': 'older',
                'kind': 'userMessage',
                'status': 'completed',
                'markdownText': 'Older prompt',
              },
            ],
          },
          'nextCursor': 'older-next',
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
      final provider = codexChatControllerProvider('tab-history-broadcast');
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      await _settle();
      await container.read(provider.notifier).loadHistory(cursor: 'older');
      final loadedTimeline =
          container.read(provider).snapshot.timelineCells as CodexTimelineCells;
      final loadedHistory = loadedTimeline.history;

      client.emit(
        const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
          'tabId': 'tab-history-broadcast',
          'threadId': 'thread-current',
          'snapshot': <String, Object?>{
            'events': <Object?>[
              <String, Object?>{'method': 'current-host-window'},
            ],
            'timelineCells': <Object?>[
              <String, Object?>{
                'id': 'recent',
                'kind': 'assistantMessage',
                'status': 'completed',
                'markdownText': 'Updated answer',
              },
            ],
          },
        }),
      );
      await _settle();
      var current = container.read(provider);
      expect(current.snapshot.timelineCells.map((cell) => cell.id), <String>[
        'older',
        'recent',
      ]);
      expect(
        current.snapshot.timelineCells.last.markdownText,
        'Updated answer',
      );
      expect(current.historyNextCursor, 'older-next');
      expect(current.snapshot.events.map((event) => event.method), <String>[
        'current-host-window',
      ]);
      expect(
        identical(
          (current.snapshot.timelineCells as CodexTimelineCells).history,
          loadedHistory,
        ),
        isTrue,
      );
      final loadedPromptHistory =
          (current.snapshot.promptHistory as CodexPromptHistory).history;

      client.emit(
        const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
          'tabId': 'tab-history-broadcast',
          'threadId': 'thread-current',
          'snapshot': <String, Object?>{
            'events': <Object?>[
              <String, Object?>{'method': 'bounded-host-window'},
            ],
            'timelineCells': <Object?>[
              <String, Object?>{
                'id': 'bounded-live',
                'kind': 'assistantMessage',
                'status': 'inProgress',
                'markdownText': 'Bounded update',
              },
            ],
          },
          'snapshotDelta': <String, Object?>{
            'timelineUpserts': <Object?>[
              <String, Object?>{
                'id': 'bounded-live',
                'kind': 'assistantMessage',
                'status': 'inProgress',
                'markdownText': 'Bounded update',
              },
            ],
            'timelineRemovedIds': <Object?>[],
            'eventsReplace': <Object?>[
              <String, Object?>{'method': 'bounded-host-window'},
            ],
          },
        }),
      );
      await _settle();
      current = container.read(provider);
      expect(current.snapshot.timelineCells.map((cell) => cell.id), <String>[
        'older',
        'recent',
        'bounded-live',
      ]);
      expect(current.historyNextCursor, 'older-next');
      expect(
        identical(
          (current.snapshot.timelineCells as CodexTimelineCells).history,
          loadedHistory,
        ),
        isTrue,
      );
      expect(
        identical(
          (current.snapshot.promptHistory as CodexPromptHistory).history,
          loadedPromptHistory,
        ),
        isTrue,
      );

      client.emit(
        const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
          'tabId': 'tab-history-broadcast',
          'threadId': 'thread-replacement',
          'snapshot': <String, Object?>{'timelineCells': <Object?>[]},
        }),
      );
      await _settle();
      current = container.read(provider);
      expect(current.snapshot.timelineCells, isEmpty);
      expect(current.historyNextCursor, isNull);
    },
  );
}
