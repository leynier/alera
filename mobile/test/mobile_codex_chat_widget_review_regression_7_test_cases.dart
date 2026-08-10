part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexReviewRegression7Tests() {
  testWidgets('mobile removes a mention token with its attachment chip', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['docs/notes.md'],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-mention-delete');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '@notes');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'docs/notes.md'));
    await tester.pump();

    expect(
      tester.widget<TextField>(composer).controller!.text,
      'docs/notes.md ',
    );
    final chip = tester.widget<InputChip>(
      find.widgetWithText(InputChip, 'notes.md'),
    );
    chip.onDeleted!();
    await tester.pump();

    expect(tester.widget<TextField>(composer).controller!.text, isEmpty);
    expect(find.widgetWithText(InputChip, 'notes.md'), findsNothing);
    final sendButton = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Send',
    );
    expect(tester.widget<IconButton>(sendButton).onPressed, isNull);
  });

  testWidgets('mobile preserves local slash commands during active turns', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'activeTurnId': 'turn-active',
        'timelineCells': <Object?>[],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-active-command');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '/new');
    await tester.pump();
    await tester.tap(find.byTooltip('Steer'));
    await tester.pumpAndSettle();

    expect(
      client.calls.where((call) => call.type == 'codex.turn.steer'),
      isEmpty,
    );
    expect(tester.widget<TextField>(composer).controller?.text, '/new');
  });

  testWidgets('mobile executes local slash commands on older runtimes', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      savedPromptsLoader: (_, _) async =>
          throw UnsupportedError('Saved prompts are unavailable.'),
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-legacy-prompts');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '/rename Legacy Thread');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(
      client.calls.where((call) => call.type == 'codex.thread.rename'),
      hasLength(1),
    );
    expect(
      client.calls.where((call) => call.type == 'codex.turn.start'),
      isEmpty,
    );
  });

  testWidgets('mobile ignores resume navigation after chat disposal', (
    tester,
  ) async {
    final resume = Completer<Map<String, Object?>>();
    final focusedTabs = <({String workspaceId, String tabId})>[];
    final client = FakeMobileCodexClient(
      responses: const <String, Map<String, Object?>>{
        'codex.thread.list': <String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'id': 'bound-thread',
              'name': 'Bound Thread',
              'cwd': '/repo',
              'workspaceId': 'workspace-bound',
              'boundWorkspaceId': 'workspace-bound',
              'boundTabId': 'tab-bound',
            },
          ],
        },
      },
      requestHandler: (type, payload) {
        if (type == 'codex.thread.resume') return resume.future;
        return null;
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(
      tester,
      client: client,
      hostId: 'host-disposed-resume',
      onFocusBoundTab: (workspaceId, tabId) =>
          focusedTabs.add((workspaceId: workspaceId, tabId: tabId)),
    );

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '/resume');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bound Thread'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    resume.complete(const <String, Object?>{
      'alreadyBound': true,
      'boundWorkspaceId': 'workspace-bound',
      'boundTabId': 'tab-bound',
    });
    await tester.pumpAndSettle();

    expect(focusedTabs, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile preserves a saved prompt when lookup fails on submit', (
    tester,
  ) async {
    var loads = 0;
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['workspace-capability-marker'],
      savedPromptsLoader: (_, _) async {
        loads += 1;
        if (loads == 1) {
          return const <MobileCodexSavedPrompt>[
            MobileCodexSavedPrompt(
              name: 'compact',
              description: 'Run the repository compact workflow.',
              body: 'Expanded compact workflow',
              scope: 'repo',
            ),
          ];
        }
        throw StateError('saved prompt lookup failed');
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-prompt-retry');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '/comp');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'compact'));
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(
      client.calls.where((call) => call.type == 'codex.thread.compact'),
      isEmpty,
    );
    expect(
      client.calls.where((call) => call.type == 'codex.turn.start'),
      isEmpty,
    );
    expect(
      tester.widget<TextField>(composer).controller?.text.trim(),
      '/compact',
    );
  });

  testWidgets('mobile keeps the originating cwd for timeline attachments', (
    tester,
  ) async {
    final previewReads = <({String path, String? cwd})>[];
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['docs/notes.md'],
      workspaceFileReader: (workspaceId, relativePath, cwd, offset, length) {
        previewReads.add((path: relativePath, cwd: cwd));
        return Future<MobileWorkspaceFileRange>.value(
          const MobileWorkspaceFileRange(
            relativePath: 'docs/notes.md',
            offset: 0,
            nextOffset: 5,
            totalBytes: 5,
            mimeType: 'text/markdown',
            isText: true,
            bytes: <int>[110, 111, 116, 101, 115],
          ),
        );
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-attachment-cwd');
    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-attachment-cwd',
        'cwd': '/repo/old',
      }),
    );
    await tester.pump();

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '@notes');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('docs/notes.md'));
    await tester.pump();
    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-attachment-cwd',
        'cwd': '/repo/new',
      }),
    );
    await tester.pump();
    await tester.tap(find.text('notes.md'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(previewReads, <({String path, String? cwd})>[
      (path: 'docs/notes.md', cwd: '/repo/old'),
    ]);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    final turn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    final input = (turn.payload['input']! as List).cast<Map>();
    final reference = input.singleWhere(
      (part) =>
          part['type'] == 'text' &&
          part['text'].toString().contains('notes.md'),
    );
    expect(reference['text'], contains('/repo/old/docs/notes.md'));
    expect(reference['text'], isNot(contains('/repo/new/docs/notes.md')));
    final presentation = Map<String, Object?>.from(
      turn.payload['userMessage']! as Map,
    );
    final attachments = (presentation['attachments']! as List).cast<Map>();
    expect(attachments.single['path'], '/repo/old/docs/notes.md');
  });

  test('mobile relativizes paths against filesystem roots', () {
    expect(
      mobileCodexWorkspaceRelativePath(path: '/src/a.dart', cwd: '/'),
      'src/a.dart',
    );
    expect(
      mobileCodexWorkspaceRelativePath(path: r'C:\src\a.dart', cwd: r'C:\'),
      'src/a.dart',
    );
  });

  testWidgets('mobile shows MCP startup failure details', (tester) async {
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'mcp-failure',
          'kind': 'toolCall',
          'status': 'failed',
          'title': 'Docs MCP Server',
          'detailsText': 'Authentication failed for the configured account.',
          'metadata': <String, Object?>{'itemType': 'mcpServerStartup'},
        },
      ],
    );
    addTearDown(client.dispose);

    await _pumpScreen(tester, client: client, hostId: 'host-mcp-failure');

    expect(find.text('Docs MCP Server'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(
      find.text('Authentication failed for the configured account.'),
      findsOneWidget,
    );
  });
}
