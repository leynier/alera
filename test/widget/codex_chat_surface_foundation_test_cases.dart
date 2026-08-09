part of 'codex_chat_surface_test.dart';

void registerCodexComposerFoundationTests() {
  testWidgets('an immediately sent dropped path stays with that prompt', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(pendingRequests: const <Object?>[]);
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client);
    final composer = find.byType(TextField).last;
    await tester.enterText(composer, 'Inspect this file');
    await tester.pump();

    final target = tester.widget<DragTarget<TerminalPathDragPayload>>(
      find.byType(DragTarget<TerminalPathDragPayload>),
    );
    target.onAcceptWithDetails!(
      DragTargetDetails<TerminalPathDragPayload>(
        data: const TerminalPathDragData(paths: <String>['/tmp/notes.md']),
        offset: Offset.zero,
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('composer-action-button')),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    expect(client.startTurnPayloads, hasLength(1));
    final input = client.startTurnPayloads.single['input']! as List<Object?>;
    expect(
      input.whereType<Map>().any(
        (part) => part['text']?.toString().contains('/tmp/notes.md') == true,
      ),
      isTrue,
    );
  });

  test('classifies local directories for dropped attachments', () async {
    final directory = await Directory.systemTemp.createTemp(
      'alera-codex-directory-attachment-',
    );
    addTearDown(() => directory.delete(recursive: true));

    expect(await codexAttachmentPathIsDirectory(directory.path), isTrue);
  });

  test('arrow up preserves drafts that can be soft wrapped', () {
    const draft =
        'This draft is intentionally long enough to wrap across several visual lines in a narrow composer.';
    expect(
      codexCanNavigatePromptHistory(
        key: LogicalKeyboardKey.arrowUp,
        value: const TextEditingValue(
          text: draft,
          selection: TextSelection.collapsed(offset: draft.length),
        ),
        browsingHistory: false,
      ),
      isFalse,
    );
    expect(
      codexCanNavigatePromptHistory(
        key: LogicalKeyboardKey.arrowUp,
        value: const TextEditingValue(
          selection: TextSelection.collapsed(offset: 0),
        ),
        browsingHistory: false,
      ),
      isTrue,
    );
  });

  testWidgets('stale mention results do not add an attachment', (tester) async {
    final client = _SurfaceRuntimeClient(pendingRequests: const <Object?>[]);
    final workspaceFiles = _RecordingWorkspaceFileService(
      quickOpenMatches: const <native.WorkspaceQuickOpenMatch>[
        native.WorkspaceQuickOpenMatch(
          relativePath: 'assets/logo.png',
          score: 0,
        ),
      ],
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client, workspaceFiles: workspaceFiles);
    final composer = find.byType(TextField).last;

    await tester.enterText(composer, '@logo');
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('assets/logo.png'), findsOneWidget);

    await tester.enterText(composer, 'different text');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('codex-composer-file-bar')),
      findsNothing,
    );
    expect(
      tester.widget<TextField>(composer).controller?.text,
      'different text',
    );
  });

  testWidgets('catalog input invalidates an in-flight mention search', (
    tester,
  ) async {
    final search = Completer<List<native.WorkspaceQuickOpenMatch>>();
    final client = _SurfaceRuntimeClient(pendingRequests: const <Object?>[]);
    final workspaceFiles = _RecordingWorkspaceFileService(
      quickOpenSearch: search,
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client, workspaceFiles: workspaceFiles);
    final composer = find.byType(TextField).last;

    await tester.enterText(composer, '@logo');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(composer, r'$');
    await tester.pump(const Duration(milliseconds: 250));

    search.complete(const <native.WorkspaceQuickOpenMatch>[
      native.WorkspaceQuickOpenMatch(
        relativePath: 'assets/stale.png',
        score: 0,
      ),
    ]);
    await tester.pump();

    expect(find.text('assets/stale.png'), findsNothing);
  });

  testWidgets('skill removal targets the selected token occurrence', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      skills: const <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'name': 'review',
            'path': '/skills/review/SKILL.md',
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client);
    final composer = find.byType(TextField).last;

    await tester.enterText(composer, r'$review before $rev');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('review'));
    await tester.pump();

    expect(
      tester.widget<TextField>(composer).controller?.text,
      r'$review before $review ',
    );
    await tester.enterText(composer, r'$review before $review $rev');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('review'));
    await tester.pump();

    expect(
      tester.widget<TextField>(composer).controller?.text,
      r'$review before $review ',
    );
    await tester.tap(find.byIcon(AleraIcons.close));
    await tester.pump();

    expect(
      tester.widget<TextField>(composer).controller?.text,
      r'$review before ',
    );
  });

  testWidgets('removing an image mention also removes its composer token', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(pendingRequests: const <Object?>[]);
    final workspaceFiles = _RecordingWorkspaceFileService(
      quickOpenMatches: const <native.WorkspaceQuickOpenMatch>[
        native.WorkspaceQuickOpenMatch(
          relativePath: 'assets/logo.png',
          score: 0,
        ),
      ],
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client, workspaceFiles: workspaceFiles);
    final composer = find.byType(TextField).last;

    await tester.enterText(composer, '@logo');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('assets/logo.png'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    const attachmentKey = ValueKey<String>(
      'codex-attached-file-/repo/workspace/assets/logo.png',
    );
    expect(find.byKey(attachmentKey), findsOneWidget);
    expect(
      tester.widget<TextField>(composer).controller?.text,
      'assets/logo.png ',
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(attachmentKey),
        matching: find.byIcon(AleraIcons.close),
      ),
    );
    await tester.pump();

    expect(find.byKey(attachmentKey), findsNothing);
    expect(tester.widget<TextField>(composer).controller?.text, isEmpty);
  });

  testWidgets('selecting an existing mention still resolves its query', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(pendingRequests: const <Object?>[]);
    final workspaceFiles = _RecordingWorkspaceFileService(
      quickOpenMatches: const <native.WorkspaceQuickOpenMatch>[
        native.WorkspaceQuickOpenMatch(relativePath: 'readme.md', score: 0),
      ],
    );
    addTearDown(client.dispose);
    await _pumpComposerSurface(tester, client, workspaceFiles: workspaceFiles);
    final composer = find.byType(TextField).last;

    await tester.enterText(composer, '@read');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tester.widget<TextField>(composer).controller?.text, 'readme.md ');

    await tester.enterText(composer, 'readme.md @read');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(tester.widget<TextField>(composer).controller?.text, 'readme.md ');
    expect(
      find.byKey(
        const ValueKey<String>('codex-mentioned-file-mention-readme.md'),
      ),
      findsOneWidget,
    );
  });

  registerCodexTimelineSegmentTests();
  registerCodexTimelineFileChangeTests();
  registerCodexTimelineInteractionTests();
  registerCodexTimelineReviewTests();
  registerCodexTimelineProgressTests();
  registerCodexTimelineContextTests();
  registerCodexTimelineQuestionAnswerTests();
  registerCodexChatSurfaceSessionTests();
}
