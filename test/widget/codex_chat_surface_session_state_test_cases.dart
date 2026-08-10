part of 'codex_chat_surface_test.dart';

void registerCodexChatSurfaceSessionStateTests() {
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
  _SurfaceRuntimeClient client, {
  WorkspaceFileService? workspaceFiles,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        codexChatRuntimeClientProvider.overrideWithValue(client),
        settingsControllerProvider.overrideWith(_SurfaceSettings.new),
        if (workspaceFiles != null)
          workspaceFileServiceProvider.overrideWithValue(workspaceFiles),
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
