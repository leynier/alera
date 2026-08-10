part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexCatalogTests() {
  testWidgets('mobile handles catalog arrows before scroll attachment', (
    tester,
  ) async {
    final client = FakeMobileCodexClient();
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-catalog-key');

    await tester.enterText(find.byType(TextField).last, '/');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);

    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile only offers slash commands at the start of the draft', (
    tester,
  ) async {
    final client = FakeMobileCodexClient();
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-slash-position');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, 'please /ne');
    await tester.pump();

    expect(find.text('New'), findsNothing);

    await tester.enterText(composer, '/ne');
    await tester.pump();

    expect(find.text('New'), findsOneWidget);
  });

  testWidgets('mobile invalidates file suggestions when the token changes', (
    tester,
  ) async {
    final start = Completer<MobileWorkspaceQuickOpenSession>();
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['docs/notes.md'],
      workspaceQuickOpenStart: start.future,
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-stale-search');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '@notes');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(composer, '/new');
    await tester.pump();
    start.complete(
      const MobileWorkspaceQuickOpenSession(
        id: 'stale-query-session',
        indexedFileCount: 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('docs/notes.md'), findsNothing);
  });

  testWidgets('mobile clears stale catalog rows before workspace search', (
    tester,
  ) async {
    final client = FakeMobileCodexClient();
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-stale-catalog');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '/new');
    await tester.pump();
    expect(find.text('New'), findsOneWidget);

    await tester.enterText(composer, '@notes');
    await tester.pump();

    expect(find.text('New'), findsNothing);
  });

  testWidgets('mobile preserves app identity when a skill has the same name', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      responses: const <String, Map<String, Object?>>{
        'codex.skills.list': <String, Object?>{
          'data': <Object?>[
            <String, Object?>{'name': 'shared', 'path': '/skills/shared'},
          ],
        },
        'codex.apps.list': <String, Object?>{
          'data': <Object?>[
            <String, Object?>{'name': 'shared', 'connectorId': 'app-shared'},
          ],
        },
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-catalog-identity');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, r'$sha');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'shared').last);
    await tester.pump();
    expect(tester.widget<TextField>(composer).controller!.text, r'$shared ');
    await tester.enterText(composer, r'$shared continue');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    final turn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect(turn.payload['input'], <Map<String, Object?>>[
      <String, Object?>{
        'type': 'mention',
        'name': 'shared',
        'path': 'app://app-shared',
      },
      <String, Object?>{'type': 'text', 'text': r'$shared continue'},
    ]);
  });

  testWidgets(
    'mobile removes the catalog identity for the edited duplicate token',
    (tester) async {
      final client = FakeMobileCodexClient(
        responses: const <String, Map<String, Object?>>{
          'codex.skills.list': <String, Object?>{
            'data': <Object?>[
              <String, Object?>{'name': 'shared', 'path': '/skills/shared'},
            ],
          },
          'codex.apps.list': <String, Object?>{
            'data': <Object?>[
              <String, Object?>{'name': 'shared', 'connectorId': 'app-shared'},
            ],
          },
        },
      );
      addTearDown(client.dispose);
      await _pumpScreen(
        tester,
        client: client,
        hostId: 'host-duplicate-catalog-edit',
      );

      final composer = find.byType(TextField).last;
      await tester.enterText(composer, r'$sha');
      await tester.pump();
      await tester.tap(find.widgetWithText(ListTile, 'shared').first);
      await tester.pump();
      await tester.enterText(composer, r'$shared $sha');
      await tester.pump();
      await tester.tap(find.widgetWithText(ListTile, 'shared').last);
      await tester.pump();

      final textController = tester.widget<TextField>(composer).controller!;
      textController.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 8,
      );
      textController.value = const TextEditingValue(
        text: r'$shared ',
        selection: TextSelection.collapsed(offset: 0),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      final turn = client.calls.lastWhere(
        (call) => call.type == 'codex.turn.start',
      );
      expect(turn.payload['input'], <Map<String, Object?>>[
        <String, Object?>{
          'type': 'mention',
          'name': 'shared',
          'path': 'app://app-shared',
        },
        <String, Object?>{'type': 'text', 'text': r'$shared'},
      ]);
    },
  );

  testWidgets('mobile preserves catalog selections with spaced names', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      responses: const <String, Map<String, Object?>>{
        'codex.skills.list': <String, Object?>{'data': <Object?>[]},
        'codex.apps.list': <String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'name': 'Google Drive',
              'connectorId': 'google-drive',
            },
          ],
        },
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-spaced-catalog');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, r'$goo');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'Google Drive'));
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    final turn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect(turn.payload['input'], <Map<String, Object?>>[
      <String, Object?>{
        'type': 'mention',
        'name': 'Google Drive',
        'path': 'app://google-drive',
      },
      <String, Object?>{'type': 'text', 'text': r'$Google Drive'},
    ]);
  });

  testWidgets('mobile absolute links fall back to prompt attachments', (
    tester,
  ) async {
    final workspaceReads = <String>[];
    final promptReads = <String>[];
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['workspace-capability-marker'],
      promptAttachmentReadSupported: true,
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'absolute-link',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': '[other.md](/other/workspace/other.md)',
        },
      ],
      workspaceFileReader: (workspaceId, relativePath, cwd, offset, length) {
        workspaceReads.add(relativePath);
        return Future<MobileWorkspaceFileRange>.error(
          StateError('not in a known workspace on this host'),
        );
      },
      promptAttachmentReader: (path, offset, length) async {
        promptReads.add(path);
        return const MobileWorkspaceFileRange(
          relativePath: 'other.md',
          offset: 0,
          nextOffset: 13,
          totalBytes: 13,
          mimeType: 'text/markdown',
          isText: true,
          bytes: <int>[
            102,
            97,
            108,
            108,
            98,
            97,
            99,
            107,
            32,
            98,
            111,
            100,
            121,
          ],
        );
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-absolute-link');

    await tester.tap(find.text('other.md'));
    await tester.pump();
    for (var index = 0; index < 5; index++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(workspaceReads, <String>['/other/workspace/other.md']);
    expect(promptReads, <String>['/other/workspace/other.md']);
  });

  testWidgets('mobile reports unavailable external links', (tester) async {
    final previousPlatform = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = _UnavailableUrlLauncherPlatform();
    addTearDown(() => UrlLauncherPlatform.instance = previousPlatform);
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'external-link',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': '[Open site](https://example.com)',
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-external-link');

    await tester.tap(find.text('Open site'));
    await tester.pumpAndSettle();

    expect(find.text('Could not open link.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile disables sharing while a file preview loads', (
    tester,
  ) async {
    final loadMore = Completer<MobileWorkspaceFileRange>();
    var reads = 0;
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['notes.md'],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'workspace-link',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': '[notes.md](notes.md)',
        },
      ],
      workspaceFileReader: (workspaceId, relativePath, cwd, offset, length) {
        reads += 1;
        if (offset == 0) {
          return Future.value(
            const MobileWorkspaceFileRange(
              relativePath: 'notes.md',
              offset: 0,
              nextOffset: 3,
              totalBytes: 6,
              mimeType: 'application/octet-stream',
              isText: false,
              bytes: <int>[97, 98, 99],
            ),
          );
        }
        return loadMore.future;
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-preview-gate');

    await tester.tap(find.text('notes.md'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(reads, 1);
    final shareButton = find.ancestor(
      of: find.byTooltip('Share File'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(shareButton).onPressed, isNotNull);

    await tester.tap(find.text('Load More'));
    await tester.pump();
    expect(tester.widget<IconButton>(shareButton).onPressed, isNull);

    loadMore.complete(
      const MobileWorkspaceFileRange(
        relativePath: 'notes.md',
        offset: 3,
        nextOffset: 6,
        totalBytes: 6,
        mimeType: 'application/octet-stream',
        isText: false,
        bytes: <int>[100, 101, 102],
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(tester.widget<IconButton>(shareButton).onPressed, isNotNull);
  });

  testWidgets('mobile rejects file preview ranges that do not advance', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['stalled.md'],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'stalled-link',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': '[stalled.md](stalled.md)',
        },
      ],
      workspaceFileReader:
          (workspaceId, relativePath, cwd, offset, length) async {
            return const MobileWorkspaceFileRange(
              relativePath: 'stalled.md',
              offset: 0,
              nextOffset: 0,
              totalBytes: 8,
              mimeType: 'text/markdown',
              isText: true,
              bytes: <int>[],
            );
          },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-stalled-preview');

    await tester.tap(find.text('stalled.md'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.textContaining('The remote file preview did not advance.'),
      findsOneWidget,
    );
  });

  testWidgets('mobile skips saved prompts without workspace file support', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      savedPrompts: const <MobileCodexSavedPrompt>[
        MobileCodexSavedPrompt(
          name: 'audit',
          description: 'Audit',
          body: 'Audit',
          scope: 'repo',
        ),
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-old-runtime');
    expect(client.lastSavedPromptWorkspaceId, isNull);
  });
}
