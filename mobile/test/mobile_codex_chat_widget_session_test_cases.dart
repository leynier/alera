part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexSessionTests() {
  testWidgets('mobile session slash commands execute locally in one tab', (
    tester,
  ) async {
    final client = FakeMobileCodexClient();
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-session');

    final composer = find.byType(TextField).last;
    final send = find.byTooltip('Send');
    await tester.enterText(composer, '/rename Mobile Work');
    await tester.pump();
    await tester.tap(send);
    await tester.pumpAndSettle();

    final rename = client.calls.lastWhere(
      (call) => call.type == 'codex.thread.rename',
    );
    expect(rename.payload, <String, Object?>{
      'tabId': 'tab-host-session',
      'name': 'Mobile Work',
    });

    await tester.enterText(composer, '/new Fresh Mobile Thread');
    await tester.pump();
    await tester.tap(send);
    await tester.pumpAndSettle();
    await tester.enterText(composer, '/clear');
    await tester.pump();
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(
      client.calls.where((call) => call.type == 'codex.thread.new'),
      hasLength(1),
    );
    expect(
      client.calls.where((call) => call.type == 'codex.thread.clear'),
      hasLength(1),
    );
    expect(
      client.calls.where((call) => call.type == 'codex.turn.start'),
      isEmpty,
    );

    await tester.enterText(composer, '/review');
    await tester.pump();
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.text('Start Review'), findsNWidgets(2));
    await tester.tap(find.widgetWithText(FilledButton, 'Start Review'));
    await tester.pumpAndSettle();

    expect(
      client.calls.where((call) => call.type == 'codex.review.start'),
      hasLength(1),
    );
    expect(
      client.calls.where((call) => call.type == 'codex.turn.start'),
      isEmpty,
    );

    await tester.enterText(composer, '/review inspect staged changes');
    await tester.pump();
    await tester.tap(send);
    await tester.pumpAndSettle();
    final reviewPrompt = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect((reviewPrompt.payload['input'] as List).first, <String, Object?>{
      'type': 'text',
      'text': '/review inspect staged changes',
    });
  });

  testWidgets('mobile resume keeps pagination for an empty filtered page', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      responses: const <String, Map<String, Object?>>{
        'codex.thread.list': <String, Object?>{
          'data': <Object?>[],
          'nextCursor': 'cursor-2',
        },
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-empty-resume');
    final composer = find.byType(TextField).last;

    await tester.enterText(composer, '/resume');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(find.text('Load More'), findsOneWidget);
    expect(find.text('No Codex Threads Found'), findsNothing);
  });

  testWidgets('mobile resume failure stays inside the chat surface', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      responses: const <String, Map<String, Object?>>{
        'codex.thread.list': <String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'id': 'thread-old',
              'name': 'Old Thread',
              'cwd': '/repo',
              'workspaceId': 'workspace-host-resume-error',
            },
          ],
        },
      },
      responseErrors: <String, Object>{
        'codex.thread.resume': StateError('resume failed'),
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-resume-error');
    final composer = find.byType(TextField).last;

    await tester.enterText(composer, '/resume');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Old Thread'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('resume failed'), findsOneWidget);
  });

  testWidgets('mobile expands saved prompts from the active Codex folder', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['workspace-capability-marker'],
      savedPrompts: const <MobileCodexSavedPrompt>[
        MobileCodexSavedPrompt(
          name: 'audit',
          description: 'Audit one target',
          body: r'Inspect $1',
          scope: 'repo',
        ),
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-prompt');
    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-prompt',
        'cwd': '/repo/packages/app',
        'snapshot': <String, Object?>{'timelineCells': <Object?>[]},
      }),
    );
    await tester.pump();

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '/audit src/main.dart');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    final turn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect((turn.payload['input'] as List).last, <String, Object?>{
      'type': 'text',
      'text': 'Inspect src/main.dart',
    });
    expect(client.lastSavedPromptWorkspaceId, 'workspace-host-prompt');
    expect(client.lastSavedPromptCwd, '/repo/packages/app');
  });

  testWidgets('mobile saved prompts override colliding built-in commands', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['workspace-capability-marker'],
      savedPrompts: const <MobileCodexSavedPrompt>[
        MobileCodexSavedPrompt(
          name: 'compact',
          description: 'Custom compact workflow',
          body: r'Expanded $1',
          scope: 'repo',
        ),
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-prompt-collision');

    await tester.enterText(find.byType(TextField).last, '/compact target');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(
      client.calls.where((call) => call.type == 'codex.thread.compact'),
      isEmpty,
    );
    final turn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect((turn.payload['input'] as List).first, <String, Object?>{
      'type': 'text',
      'text': 'Expanded target',
    });
  });

  testWidgets('mobile does not rename when a new thread command fails', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      responseErrors: <String, Object>{
        'codex.thread.new': StateError('new thread failed'),
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-new-failure');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '/new Must Not Rename');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(
      client.calls.where((call) => call.type == 'codex.thread.new'),
      hasLength(1),
    );
    expect(
      client.calls.where((call) => call.type == 'codex.thread.rename'),
      isEmpty,
    );
  });

  testWidgets('mobile preserves a new draft while expanding the sent prompt', (
    tester,
  ) async {
    const prompts = <MobileCodexSavedPrompt>[
      MobileCodexSavedPrompt(
        name: 'audit',
        description: 'Audit one target',
        body: r'Inspect $1',
        scope: 'repo',
      ),
    ];
    final expansion = Completer<List<MobileCodexSavedPrompt>>();
    var promptLoads = 0;
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['docs/notes.md'],
      savedPromptsLoader: (_, _) {
        promptLoads += 1;
        return promptLoads == 1 ? Future.value(prompts) : expansion.future;
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-draft-race');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '/audit old.dart');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.enterText(composer, 'Keep this next draft');
    expansion.complete(prompts);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(composer).controller!.text,
      'Keep this next draft',
    );
    final turn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect((turn.payload['input'] as List).last, <String, Object?>{
      'type': 'text',
      'text': 'Inspect old.dart',
    });
  });

  testWidgets('mobile preserves submission order during prompt expansion', (
    tester,
  ) async {
    const prompts = <MobileCodexSavedPrompt>[
      MobileCodexSavedPrompt(
        name: 'audit',
        description: 'Audit one target',
        body: r'Inspect $1',
        scope: 'repo',
      ),
    ];
    final expansion = Completer<List<MobileCodexSavedPrompt>>();
    var blockPromptExpansion = false;
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['docs/notes.md'],
      savedPromptsLoader: (_, _) => blockPromptExpansion
          ? expansion.future
          : Future.value(const <MobileCodexSavedPrompt>[]),
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-send-order');

    final composer = find.byType(TextField).last;
    blockPromptExpansion = true;
    await tester.enterText(composer, '/audit first.dart');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.enterText(composer, 'Second message');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expansion.complete(prompts);
    await tester.pumpAndSettle();

    final turns = client.calls
        .where((call) => call.type == 'codex.turn.start')
        .toList(growable: false);
    expect(
      <Object?>[for (final turn in turns) (turn.payload['input'] as List).last],
      <Object?>[
        <String, Object?>{'type': 'text', 'text': 'Inspect first.dart'},
        <String, Object?>{'type': 'text', 'text': 'Second message'},
      ],
    );
  });

  testWidgets('mobile starts a turn when a pending steer target completes', (
    tester,
  ) async {
    const prompts = <MobileCodexSavedPrompt>[
      MobileCodexSavedPrompt(
        name: 'audit',
        description: 'Audit one target',
        body: r'Inspect $1',
        scope: 'repo',
      ),
    ];
    final expansion = Completer<List<MobileCodexSavedPrompt>>();
    var promptLoads = 0;
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'activeTurnId': 'turn-active',
        'timelineCells': <Object?>[],
      },
      workspaceFiles: const <String>['docs/notes.md'],
      savedPromptsLoader: (_, _) {
        promptLoads += 1;
        return promptLoads == 1 ? Future.value(prompts) : expansion.future;
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-steer-race');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '/audit current.dart');
    await tester.tap(composer);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-steer-race',
        'snapshot': <String, Object?>{'timelineCells': <Object?>[]},
      }),
    );
    await tester.pump();
    expansion.complete(prompts);
    await tester.pumpAndSettle();

    expect(
      client.calls.where((call) => call.type == 'codex.turn.steer'),
      isEmpty,
    );
    final turn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect((turn.payload['input'] as List).last, <String, Object?>{
      'type': 'text',
      'text': 'Inspect current.dart',
    });
  });

  testWidgets('mobile restores a submitted saved prompt when disposed', (
    tester,
  ) async {
    const prompts = <MobileCodexSavedPrompt>[
      MobileCodexSavedPrompt(
        name: 'audit',
        description: 'Audit one target',
        body: r'Inspect $1',
        scope: 'repo',
      ),
    ];
    final expansion = Completer<List<MobileCodexSavedPrompt>>();
    var promptLoads = 0;
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['docs/notes.md'],
      savedPromptsLoader: (_, _) {
        promptLoads += 1;
        return promptLoads == 1 ? Future.value(prompts) : expansion.future;
      },
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider(
          'host-disposed-prompt',
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
      hostId: 'host-disposed-prompt',
      container: container,
    );

    await tester.enterText(find.byType(TextField).last, '/audit old.dart');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox()),
      ),
    );
    expansion.complete(prompts);
    await tester.pumpAndSettle();

    expect(
      client.calls.where((call) => call.type == 'codex.turn.start'),
      isEmpty,
    );
    expect(
      container
          .read(mobileCodexComposerDraftStoreProvider)
          .read('host-disposed-prompt', 'tab-host-disposed-prompt')
          .value
          .text,
      '/audit old.dart',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile handles saved prompt catalogue load failures', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['docs/notes.md'],
      savedPromptsLoader: (_, _) async => throw StateError('catalog failed'),
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-prompt-failure');
    await tester.pumpAndSettle();

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '/missing');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('missing'), findsNothing);
  });
}
