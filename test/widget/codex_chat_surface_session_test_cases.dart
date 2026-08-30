part of 'codex_chat_surface_test.dart';

void registerCodexChatSurfaceSessionTests() {
  testWidgets('shows the auto-review approval mode accurately', (tester) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      permissionMode: 'auto-review',
    );
    addTearDown(client.dispose);

    await _pumpSessionSurface(tester, client);

    expect(find.text('Approve For Me'), findsOneWidget);
    expect(find.text('Ask For Approval'), findsNothing);
  });

  testWidgets('hides auto-review when the sidecar cannot honor it', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      permissionMode: 'auto-review',
      supportsTurnPolicy: false,
    );
    addTearDown(client.dispose);

    await _pumpSessionSurface(tester, client);
    expect(find.text('Ask For Approval'), findsOneWidget);
    await tester.tap(find.text('Ask For Approval'));
    await tester.pumpAndSettle();
    expect(find.text('Approve For Me'), findsNothing);
  });

  testWidgets('slash permissions confirms full access before applying it', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(pendingRequests: const <Object?>[]);
    addTearDown(client.dispose);
    await _pumpSessionSurface(tester, client);

    await _selectSlashCommand(
      tester,
      find.byType(TextField).last,
      '/permissions',
    );
    await tester.tap(find.text('Full Access'));
    await tester.pumpAndSettle();

    expect(find.text('Turn On Full Access?'), findsOneWidget);
  });

  testWidgets('session commands stay in the current Codex tab', (tester) async {
    final client = _SurfaceRuntimeClient(
      supportsSessions: true,
      pendingRequests: const <Object?>[],
    );
    addTearDown(client.dispose);
    await _pumpSessionSurface(tester, client);
    final composer = find.byType(TextField).last;

    await _selectSlashCommand(tester, composer, '/new');
    await _selectSlashCommand(tester, composer, '/clear');

    expect(
      client.requestTypes.where((type) => type == 'codex.thread.new'),
      hasLength(1),
    );
    expect(
      client.requestTypes.where((type) => type == 'codex.thread.clear'),
      hasLength(1),
    );
  });

  testWidgets('typed session commands preserve parsing and result order', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      supportsSessions: true,
      pendingRequests: const <Object?>[],
    );
    addTearDown(client.dispose);
    await _pumpSessionSurface(tester, client);
    final composer = find.byKey(
      const ValueKey<String>('codex-composer-text-field'),
    );

    Future<void> submit(String command) async {
      await tester.enterText(composer, command);
      await tester.pump();
      await tester.sendKeyEvent(.enter);
      await tester.pumpAndSettle();
    }

    await submit('  /NeW   Feature  Thread  ');
    await submit('/clear Reset Thread');
    await submit('/ReNaMe Final Thread');

    final requests = client.requests
        .where(
          (request) =>
              request.type == 'codex.thread.new' ||
              request.type == 'codex.thread.clear' ||
              request.type == 'codex.thread.rename',
        )
        .toList();
    expect(requests.map((request) => request.type), <String>[
      'codex.thread.new',
      'codex.thread.rename',
      'codex.thread.clear',
      'codex.thread.rename',
      'codex.thread.rename',
    ]);
    expect(
      requests
          .where((request) => request.type == 'codex.thread.rename')
          .map((request) => request.payload['name']),
      <String>['Feature  Thread', 'Reset Thread', 'Final Thread'],
    );
    expect(tester.widget<TextField>(composer).controller?.text, isEmpty);
    expect(tester.widget<TextField>(composer).focusNode?.hasFocus, isTrue);
  });

  testWidgets('failed typed reset reports the error without renaming', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      supportsSessions: true,
      pendingRequests: const <Object?>[],
      sessionCommandFailures: const <String>{'codex.thread.new'},
    );
    addTearDown(client.dispose);
    await _pumpSessionSurface(tester, client);
    final composer = find.byKey(
      const ValueKey<String>('codex-composer-text-field'),
    );

    await tester.enterText(composer, '/new Must Not Rename');
    await tester.pump();
    await tester.sendKeyEvent(.enter);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(CodexChatSurface)),
    );
    expect(client.requestTypes, contains('codex.thread.new'));
    expect(client.requestTypes, isNot(contains('codex.thread.rename')));
    expect(
      container.read(codexChatControllerProvider('codex-tab')).error,
      contains('codex.thread.new failed'),
    );
    expect(tester.widget<TextField>(composer).controller?.text, isEmpty);
    expect(tester.widget<TextField>(composer).focusNode?.hasFocus, isTrue);
  });

  testWidgets('legacy hosts keep new and clear commands available', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(pendingRequests: const <Object?>[]);
    addTearDown(client.dispose);
    await _pumpSessionSurface(tester, client);

    await tester.enterText(find.byType(TextField).last, '/');
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('/new'), findsOneWidget);
    expect(find.text('/clear'), findsOneWidget);
    expect(find.text('/resume'), findsNothing);
  });

  testWidgets('saved prompts take precedence over colliding session commands', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      supportsSessions: true,
      pendingRequests: const <Object?>[],
    );
    final workspaceFiles = _RecordingWorkspaceFileService(
      savedPrompts: const <native.CodexSavedPrompt>[
        native.CodexSavedPrompt(
          name: 'new',
          description: 'Draft a feature',
          body: r'Draft $1',
          scope: native.CodexSavedPromptScope.repo,
        ),
      ],
    );
    addTearDown(client.dispose);
    await _pumpSessionSurface(tester, client, workspaceFiles: workspaceFiles);

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '/new feature');
    await tester.pump();
    await tester.sendKeyEvent(.enter);
    await tester.pumpAndSettle();

    expect(client.requestTypes, isNot(contains('codex.thread.new')));
    expect(client.startTurnPayloads, hasLength(1));
    final input = client.startTurnPayloads.single['input']! as List<Object?>;
    expect(input.whereType<Map>().single['text'], 'Draft feature');
  });

  testWidgets('unsupported typed resume falls through as a prompt', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(pendingRequests: const <Object?>[]);
    addTearDown(client.dispose);
    await _pumpSessionSurface(tester, client);

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '/resume old');
    await tester.pump();
    await tester.sendKeyEvent(.enter);
    await tester.pumpAndSettle();

    expect(client.startTurnPayloads, hasLength(1));
    final input = client.startTurnPayloads.single['input']! as List<Object?>;
    expect(input.whereType<Map>().single['text'], '/resume old');
  });

  testWidgets('invalid typed commands fall through as prompts', (tester) async {
    final client = _SurfaceRuntimeClient(
      supportsSessions: true,
      pendingRequests: const <Object?>[],
    );
    addTearDown(client.dispose);
    await _pumpSessionSurface(tester, client);
    final composer = find.byKey(
      const ValueKey<String>('codex-composer-text-field'),
    );

    for (final prompt in <String>['/resume old', '/newish thread']) {
      await tester.enterText(composer, prompt);
      await tester.pump();
      await tester.sendKeyEvent(.enter);
      await tester.pumpAndSettle();
    }

    expect(client.requestTypes, isNot(contains('codex.thread.resume')));
    expect(client.requestTypes, isNot(contains('codex.thread.new')));
    expect(
      client.startTurnPayloads.map((payload) {
        final input = payload['input']! as List<Object?>;
        return input.whereType<Map>().single['text'];
      }),
      <String>['/resume old', '/newish thread'],
    );
  });

  testWidgets('resume and earlier history are reachable from the surface', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      supportsSessions: true,
      historyNextCursor: 'older',
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'current',
          'turnId': 'turn-shared',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': 'Current history',
        },
      ],
      historyTimelineCells: const <Object?>[
        <String, Object?>{
          'id': 'older',
          'turnId': 'turn-shared',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': 'Older history',
        },
      ],
      threadListResponse: const <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'id': 'thread-old',
            'title': 'Old Thread',
            'cwd': '/repo/workspace',
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpSessionSurface(tester, client);

    final historyButton = find.widgetWithText(
      TextButton,
      'Load Earlier Messages',
    );
    final surfaceRect = tester.getRect(find.byType(CodexChatSurface));
    expect(
      find.descendant(
        of: historyButton,
        matching: find.byIcon(AleraIcons.chevronUp),
      ),
      findsOneWidget,
    );
    expect(
      tester.getRect(historyButton).center.dx,
      closeTo(surfaceRect.center.dx, 0.1),
    );
    await tester.tap(find.text('Load Earlier Messages'));
    await tester.pump();
    expect(client.requestTypes, contains('codex.thread.history'));
    expect(find.text('Older history'), findsOneWidget);
    expect(find.text('Current history'), findsOneWidget);

    final composer = find.byType(TextField).last;
    await _selectSlashCommand(tester, composer, ' /ReSuMe ');
    await tester.pumpAndSettle();
    expect(find.text('Old Thread'), findsOneWidget);
    await tester.tap(find.text('Old Thread'));
    await tester.pumpAndSettle();
    expect(client.requestTypes, contains('codex.thread.resume'));
  });

  testWidgets('long timelines build only visible turn widgets', (tester) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: <Object?>[
        for (var index = 0; index < 200; index++)
          <String, Object?>{
            'id': 'message-$index',
            'turnId': 'turn-$index',
            'kind': 'assistantMessage',
            'status': 'completed',
            'markdownText': 'Timeline message $index',
          },
      ],
    );
    addTearDown(client.dispose);
    await _pumpSessionSurface(tester, client);

    expect(find.text('Timeline message 0'), findsOneWidget);
    expect(find.text('Timeline message 199'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Timeline message 199'),
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 200,
    );
    expect(find.text('Timeline message 199'), findsOneWidget);
  });

  registerCodexChatSurfaceSessionStateTests();
}
