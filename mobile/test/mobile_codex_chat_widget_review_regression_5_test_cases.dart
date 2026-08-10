part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexReviewRegression5Tests() {
  testWidgets('mobile scrolls an expanded catalog with the composer', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(820, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = FakeMobileCodexClient(
      responses: <String, Map<String, Object?>>{
        'codex.apps.list': <String, Object?>{
          'data': <Object?>[
            for (var index = 0; index < 8; index++)
              <String, Object?>{
                'name': 'Application $index',
                'connectorId': 'application-$index',
              },
          ],
        },
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-catalog-footer');

    await tester.enterText(find.byType(TextField).last, r'$');
    await tester.pump();

    expect(find.text('Application 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile restores a delayed thread command once a turn starts', (
    tester,
  ) async {
    final prompts = Completer<List<MobileCodexSavedPrompt>>();
    final turnStart = Completer<Map<String, Object?>>();
    var promptLoads = 0;
    var delayedPromptLoad = -1;
    late final FakeMobileCodexClient client;
    client = FakeMobileCodexClient(
      initialThreadId: 'thread-existing',
      workspaceFiles: const <String>['workspace-capability-marker'],
      savedPromptsLoader: (_, _) {
        promptLoads += 1;
        if (promptLoads == delayedPromptLoad) return prompts.future;
        return Future<List<MobileCodexSavedPrompt>>.value(const []);
      },
      requestHandler: (type, payload) async {
        if (type == 'codex.turn.start') {
          return turnStart.future;
        }
        return <String, Object?>{};
      },
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider(
          'host-command-race',
        ).overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    await _pumpScreen(
      tester,
      client: client,
      hostId: 'host-command-race',
      container: container,
    );
    final composer = find.byType(TextField).last;
    final initialPromptLoads = promptLoads;
    delayedPromptLoad = initialPromptLoads + 1;

    await tester.enterText(composer, '/slow');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(promptLoads, initialPromptLoads + 1);
    await tester.enterText(composer, '/new');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    prompts.complete(const <MobileCodexSavedPrompt>[
      MobileCodexSavedPrompt(
        name: 'slow',
        description: 'Delayed prompt',
        body: 'Start the delayed request.',
        scope: 'user',
      ),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-command-race',
        'threadId': 'thread-existing',
        'snapshotDelta': <String, Object?>{'activeTurnId': 'turn-active'},
      }),
    );
    await tester.pump(const Duration(milliseconds: 30));
    expect(
      container
          .read(
            mobileCodexControllerProvider(
              'host-command-race',
              'tab-host-command-race',
            ),
          )
          .value
          ?.activeTurnId,
      'turn-active',
    );
    turnStart.complete(<String, Object?>{'turnId': 'turn-active'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(
      client.calls.where((call) => call.type == 'codex.thread.new'),
      isEmpty,
    );
    expect(tester.widget<TextField>(composer).controller?.text, '/new');
  });

  testWidgets('mobile resets prompt navigation when the thread changes', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      initialThreadId: 'thread-old',
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'old-prompt-1',
          'kind': 'userMessage',
          'status': 'completed',
          'markdownText': 'Old prompt 1',
        },
        <String, Object?>{
          'id': 'old-prompt-2',
          'kind': 'userMessage',
          'status': 'completed',
          'markdownText': 'Old prompt 2',
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-history-reset');
    final composer = find.byType(TextField).last;

    await tester.tap(composer);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tester.widget<TextField>(composer).controller?.text, 'Old prompt 1');
    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-history-reset',
        'threadId': 'thread-new',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'old-prompt-1',
              'kind': 'userMessage',
              'status': 'completed',
              'markdownText': 'Old prompt 1',
            },
            <String, Object?>{
              'id': 'old-prompt-2',
              'kind': 'userMessage',
              'status': 'completed',
              'markdownText': 'Old prompt 2',
            },
          ],
          'pendingRequests': <Object?>[],
        },
      }),
    );
    await tester.pump(const Duration(milliseconds: 30));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tester.widget<TextField>(composer).controller?.text, 'Old prompt 1');
  });

  testWidgets('mobile ignores a completed plan action after route dismissal', (
    tester,
  ) async {
    final turn = Completer<Map<String, Object?>>();
    final client = FakeMobileCodexClient(
      configuration: <String, Object?>{
        'planMode': true,
        'collaborationMode': 'plan',
      },
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'plan-request',
          'kind': 'userMessage',
          'status': 'completed',
          'markdownText': 'Create a plan.',
        },
        <String, Object?>{
          'id': 'actionable-plan',
          'kind': 'plan',
          'status': 'completed',
          'markdownText': '# Plan\n\nImplement this plan.',
        },
      ],
      requestHandler: (type, payload) {
        if (type == 'codex.turn.start') return turn.future;
        return null;
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-plan-dismiss');

    await tester.tap(find.byTooltip('Maximize Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, Implement This Plan'));
    await tester.pump();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    turn.complete(<String, Object?>{'turnId': 'turn-plan'});
    await tester.pump(const Duration(milliseconds: 30));

    expect(tester.takeException(), isNull);
  });

  test('mobile plan sharing preserves the markdown filename', () async {
    ShareParams? captured;
    const origin = Rect.fromLTWH(10, 20, 30, 40);
    final shared = await shareMobileCodexPlanText(
      '# Plan',
      sharePositionOrigin: origin,
      share: (params) async {
        captured = params;
        return ShareResult.unavailable;
      },
    );

    expect(shared, isTrue);
    expect(captured?.fileNameOverrides, const <String>['plan.md']);
    expect(captured?.sharePositionOrigin, origin);
  });

  testWidgets('mobile ignores history completion after the chat unmounts', (
    tester,
  ) async {
    final history = Completer<Map<String, Object?>>();
    final client = FakeMobileCodexClient(
      requestHandler: (type, payload) async {
        if (type == 'codex.thread.open') {
          return <String, Object?>{
            'threadId': 'thread-history-unmount',
            'historyNextCursor': 'older',
            'snapshot': const <String, Object?>{'timelineCells': <Object?>[]},
          };
        }
        if (type == 'codex.thread.history') return history.future;
        return <String, Object?>{};
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-history-unmount');

    await tester.tap(find.text('Load Earlier Messages'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    history.complete(const <String, Object?>{
      'snapshot': <String, Object?>{'timelineCells': <Object?>[]},
    });
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
