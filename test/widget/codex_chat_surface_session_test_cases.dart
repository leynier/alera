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

  testWidgets('resume and earlier history are reachable from the surface', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      supportsSessions: true,
      historyNextCursor: 'older',
      pendingRequests: const <Object?>[],
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

    await tester.tap(find.text('Load Earlier Messages'));
    await tester.pump();
    expect(client.requestTypes, contains('codex.thread.history'));

    final composer = find.byType(TextField).last;
    await _selectSlashCommand(tester, composer, '/resume');
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

  testWidgets('switching Codex tabs restores each composer draft', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      supportsSessions: true,
      pendingRequests: const <Object?>[],
    );
    final drafts = CodexComposerDraftStore();
    drafts.write(
      'codex-tab-2',
      const CodexComposerDraft(
        value: TextEditingValue(
          text: 'Second draft',
          selection: TextSelection.collapsed(offset: 12),
        ),
        attachments: <CodexInputAttachment>[
          CodexInputAttachment(
            id: 'second-attachment',
            path: '/repo/workspace/second.md',
            displayName: 'second.md',
            isImage: false,
          ),
        ],
      ),
    );
    addTearDown(client.dispose);

    Future<void> pumpTab(String tabId) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            codexChatRuntimeClientProvider.overrideWithValue(client),
            codexComposerDraftStoreProvider.overrideWithValue(drafts),
            settingsControllerProvider.overrideWith(_SurfaceSettings.new),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 1000,
                height: 800,
                child: CodexChatSurface(
                  workspace: _workspace(),
                  tab: _tab(id: tabId),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    }

    await pumpTab('codex-tab-1');
    await tester.enterText(find.byType(TextField).last, 'First draft');
    await tester.pump();

    await pumpTab('codex-tab-2');
    expect(find.byType(TextField).last, findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller?.text,
      'Second draft',
    );
    expect(find.text('second.md'), findsOneWidget);

    await pumpTab('codex-tab-1');
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller?.text,
      'First draft',
    );
    expect(find.text('second.md'), findsNothing);
  });

  testWidgets('switching away does not recreate a purged Codex draft', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      supportsSessions: true,
      pendingRequests: const <Object?>[],
    );
    final drafts = CodexComposerDraftStore();
    addTearDown(client.dispose);

    Future<void> pumpTab(String tabId) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            codexChatRuntimeClientProvider.overrideWithValue(client),
            codexComposerDraftStoreProvider.overrideWithValue(drafts),
            settingsControllerProvider.overrideWith(_SurfaceSettings.new),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 1000,
                height: 800,
                child: CodexChatSurface(
                  workspace: _workspace(),
                  tab: _tab(id: tabId),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    }

    await pumpTab('codex-tab-closed');
    await tester.enterText(find.byType(TextField).last, 'Discarded draft');
    await tester.pump();
    expect(drafts.read('codex-tab-closed').isEmpty, isFalse);

    drafts.remove('codex-tab-closed');
    await pumpTab('codex-tab-next');

    expect(drafts.read('codex-tab-closed').isEmpty, isTrue);
  });

  testWidgets('switching Codex tabs reloads saved prompts for the next tab', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(pendingRequests: const <Object?>[]);
    final workspaceFiles = _RecordingWorkspaceFileService();
    addTearDown(client.dispose);

    Future<void> pumpTab(String tabId) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            codexChatRuntimeClientProvider.overrideWithValue(client),
            settingsControllerProvider.overrideWith(_SurfaceSettings.new),
            workspaceFileServiceProvider.overrideWithValue(workspaceFiles),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 1000,
                height: 800,
                child: CodexChatSurface(
                  workspace: _workspace(),
                  tab: _tab(id: tabId),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    }

    await pumpTab('codex-prompts-1');
    final firstLoadCount = workspaceFiles.savedPromptWorkspacePaths.length;
    await pumpTab('codex-prompts-2');

    expect(
      workspaceFiles.savedPromptWorkspacePaths.length,
      greaterThan(firstLoadCount),
    );
    expect(workspaceFiles.savedPromptWorkspacePaths.last, _workspace().path);
  });

  testWidgets('question interaction snoozes non-blocking auto-resolution', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[
        <String, Object?>{
          'id': 9,
          'method': 'item/tool/requestUserInput',
          'params': <String, Object?>{
            'autoResolutionMs': 5000,
            'questions': <Object?>[
              <String, Object?>{
                'id': 'scope',
                'question': 'Choose a scope',
                'options': <Object?>[
                  <String, Object?>{'label': 'Complete'},
                ],
              },
            ],
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpSessionSurface(tester, client);
    await tester.scrollUntilVisible(
      find.text('Complete'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.text('Complete'));
    await tester.pump();
    await tester.tap(find.text('Complete'));
    await tester.pump();

    expect(
      client.requestTypes.where((type) => type == 'codex.request.snooze'),
      hasLength(1),
    );
  });

  testWidgets('replacement questions report their own interaction', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[
        <String, Object?>{
          'id': 9,
          'method': 'item/tool/requestUserInput',
          'params': <String, Object?>{
            'autoResolutionMs': 5000,
            'questions': <Object?>[
              <String, Object?>{
                'id': 'scope',
                'question': 'Choose a scope',
                'options': <Object?>[
                  <String, Object?>{'label': 'Complete'},
                ],
              },
            ],
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpSessionSurface(tester, client);
    final timeline = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Complete'),
      200,
      scrollable: timeline,
    );
    await tester.tap(find.text('Complete'));
    await tester.pump();

    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'codex-tab',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[],
          'pendingRequests': <Object?>[
            <String, Object?>{
              'id': 10,
              'method': 'item/tool/requestUserInput',
              'params': <String, Object?>{
                'autoResolutionMs': 5000,
                'questions': <Object?>[
                  <String, Object?>{
                    'id': 'priority',
                    'question': 'Choose a priority',
                    'options': <Object?>[
                      <String, Object?>{'label': 'Focused'},
                    ],
                  },
                ],
              },
            },
          ],
        },
      }),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Focused'),
      200,
      scrollable: timeline,
    );
    await tester.tap(find.text('Focused'));
    await tester.pump();

    expect(
      client.requestTypes.where((type) => type == 'codex.request.snooze'),
      hasLength(2),
    );
  });
}

Future<void> _pumpSessionSurface(
  WidgetTester tester,
  _SurfaceRuntimeClient client,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        codexChatRuntimeClientProvider.overrideWithValue(client),
        settingsControllerProvider.overrideWith(_SurfaceSettings.new),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 800,
            child: CodexChatSurface(workspace: _workspace(), tab: _tab()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _selectSlashCommand(
  WidgetTester tester,
  Finder composer,
  String command,
) async {
  await tester.enterText(composer, command);
  await tester.pump(const Duration(milliseconds: 250));
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}
