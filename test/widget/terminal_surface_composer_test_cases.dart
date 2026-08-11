part of 'terminal_surface_test.dart';

void _registerTerminalSurfaceComposerTests() {
  testWidgets('composer control sits left of refresh and submits a prompt', (
    tester,
  ) async {
    final session = _ImmediateNotifySessionHandle(tabId: 'tab-1');

    await _pumpTerminalSurface(tester, session);

    final refreshRect = tester.getRect(find.byTooltip('Refresh Terminal'));
    final composerRect = tester.getRect(
      find.byTooltip('Show Terminal Composer'),
    );
    expect(composerRect.right, lessThan(refreshRect.left));
    expect(composerRect.top, refreshRect.top);

    await tester.tap(find.byTooltip('Show Terminal Composer'));
    await tester.pump();

    expect(find.byTooltip('Hide Terminal Composer'), findsOneWidget);
    expect(find.text('Text Actions'), findsOneWidget);

    final dictationRect = tester.getRect(
      find.byKey(const ValueKey<String>('terminal-composer-dictation-control')),
    );
    final sendRect = tester.getRect(
      find.byKey(const ValueKey<String>('composer-send-button')),
    );
    expect(dictationRect.right, lessThanOrEqualTo(sendRect.left));
    expect(
      sendRect.left - dictationRect.right,
      lessThanOrEqualTo(AleraTokens.space8),
    );
    expect(
      (dictationRect.center.dy - sendRect.center.dy).abs(),
      lessThanOrEqualTo(AleraTokens.space2),
    );

    await tester.enterText(find.byType(TextField), 'Review this change');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(session.submittedTexts, <String>['Review this change']);
    expect(find.text('Review this change'), findsNothing);
  });

  testWidgets('composer exposes configured Text Actions for prompt selection', (
    tester,
  ) async {
    final session = _ImmediateNotifySessionHandle(tabId: 'tab-1');
    String? selectedActionId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AleraTextActionsScope(
            enabled: true,
            actions: const <AleraTextActionMenuItem>[
              AleraTextActionMenuItem(id: 'concise', label: 'Make Concise'),
            ],
            onOpen: (_, _, _) {},
            onRun: (_, actionId) => selectedActionId = actionId,
            child: SizedBox.expand(child: TerminalSurface(session: session)),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Show Terminal Composer'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Improve this prompt');
    session.composerController.textController.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 7,
    );
    await tester.pump();
    await tester.tap(find.text('Text Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make Concise'));
    await tester.pumpAndSettle();

    expect(selectedActionId, 'concise');
  });

  testWidgets('runtime prompt submission pastes text before Enter', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final factory = _FakeTerminalPtySessionFactory();
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: factory,
        shellLaunchesBuilder: _testShellLaunches,
      );
      addTearDown(runtime.dispose);
      final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());

      await session.ensureStarted();
      final submitted = await session.submitText('Review this change');

      expect(submitted, isTrue);
      expect(factory.sessions.single.writes.map(utf8.decode).toList(), <String>[
        'Review this change',
      ]);
      await tester.pump(const Duration(milliseconds: 500));
      expect(factory.sessions.single.writes.map(utf8.decode).toList(), <String>[
        'Review this change',
        '\r',
      ]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('composer pastes an image as a clickable attachment', (
    tester,
  ) async {
    final session = _ImmediateNotifySessionHandle(tabId: 'tab-1');
    final clipboard = _FakeComposerClipboard(
      imagePath: '/tmp/alera-paste-\x1b.png',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalComposer(session: session, clipboard: clipboard),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Review this placeholder');
    final focusContext = tester.binding.focusManager.primaryFocus?.context;
    expect(focusContext, isNotNull);

    Actions.invoke(
      focusContext!,
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pump();
    await tester.pump();

    expect(
      session.composerController.textController.text,
      'Review this placeholder',
    );
    expect(session.composerController.attachments, hasLength(1));
    expect(
      session.composerController.attachments.single.path,
      '/tmp/alera-paste-\x1b.png',
    );
    expect(find.text('alera-paste-\u241b.png'), findsOneWidget);
    expect(clipboard.fileReads, 1);
    expect(clipboard.imageReads, 1);

    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'terminal-composer-attachment-open-attachment-0',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('terminal-composer-image-preview')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>('terminal-composer-image-preview-close'),
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('composer removes an image attachment before submission', (
    tester,
  ) async {
    final session = _ImmediateNotifySessionHandle(tabId: 'tab-1');
    session.composerController.addAttachment(
      kind: TerminalComposerAttachmentKind.image,
      path: '/tmp/remove-me.png',
      displayName: 'remove-me.png',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TerminalComposer(session: session)),
      ),
    );

    expect(find.text('remove-me.png'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'terminal-composer-attachment-remove-attachment-0',
        ),
      ),
    );
    await tester.pump();

    expect(session.composerController.attachments, isEmpty);
    expect(find.text('remove-me.png'), findsNothing);
  });

  testWidgets('composer submits text and attachments then clears both', (
    tester,
  ) async {
    final session = _ImmediateNotifySessionHandle(tabId: 'tab-1');
    session.composerController.addAttachment(
      kind: TerminalComposerAttachmentKind.image,
      path: '/tmp/review.png',
      displayName: 'review.png',
    );
    session.composerController.addAttachment(
      kind: TerminalComposerAttachmentKind.file,
      path: '/tmp/report.pdf',
      displayName: 'report.pdf',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TerminalComposer(session: session)),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Review this change');
    await tester.tap(
      find.byKey(const ValueKey<String>('composer-send-button')),
    );
    await tester.pump();

    expect(session.submittedTexts, <String>[
      'Review this change\n\n'
          'Attached images:\n/tmp/review.png\n'
          'Attached files:\n/tmp/report.pdf',
    ]);
    expect(session.composerController.textController.text, isEmpty);
    expect(session.composerController.attachments, isEmpty);
  });

  testWidgets('composer submits an attachment without prompt text', (
    tester,
  ) async {
    final session = _ImmediateNotifySessionHandle(tabId: 'tab-1');
    session.composerController.addAttachment(
      kind: TerminalComposerAttachmentKind.image,
      path: '/tmp/image-only.png',
      displayName: 'image-only.png',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TerminalComposer(session: session)),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('composer-send-button')),
    );
    await tester.pump();

    expect(session.submittedTexts, <String>[
      'Attached images:\n/tmp/image-only.png',
    ]);
    expect(session.composerController.attachments, isEmpty);
  });

  testWidgets('composer pastes copied files and opens file attachments', (
    tester,
  ) async {
    final session = _ImmediateNotifySessionHandle(tabId: 'tab-1');
    final clipboard = _FakeComposerClipboard(
      text: '/tmp/report.pdf',
      filePaths: const <String>['/tmp/photo.webp', '/tmp/report.pdf'],
    );
    final launcher = _FakeExternalUriLauncher();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalComposer(
            session: session,
            clipboard: clipboard,
            externalUriLauncher: launcher,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Review these files');
    final focusContext = tester.binding.focusManager.primaryFocus?.context;
    expect(focusContext, isNotNull);

    Actions.invoke(
      focusContext!,
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pump();
    await tester.pump();

    expect(
      session.composerController.textController.text,
      'Review these files',
    );
    expect(session.composerController.attachments, hasLength(2));
    expect(
      session.composerController.attachments.map((item) => item.kind),
      <TerminalComposerAttachmentKind>[
        TerminalComposerAttachmentKind.image,
        TerminalComposerAttachmentKind.file,
      ],
    );
    expect(find.text('photo.webp'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(clipboard.fileReads, 1);
    expect(clipboard.imageReads, 0);

    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'terminal-composer-attachment-open-attachment-1',
        ),
      ),
    );
    await tester.pump();

    expect(launcher.openedUris, <Uri>[Uri.file('/tmp/report.pdf')]);
  });

  testWidgets('composer opens supported workspace attachments inside Alera', (
    tester,
  ) async {
    final session = _ImmediateNotifySessionHandle(tabId: 'tab-1');
    session.composerController.addAttachment(
      kind: TerminalComposerAttachmentKind.file,
      path: '/workspace/lib/main.dart',
      displayName: 'main.dart',
    );
    final launcher = _FakeExternalUriLauncher();
    final openedWorkspacePaths = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalComposer(
            session: session,
            externalUriLauncher: launcher,
            onOpenWorkspaceFile: (path) async {
              openedWorkspacePaths.add(path);
              return true;
            },
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'terminal-composer-attachment-open-attachment-0',
        ),
      ),
    );
    await tester.pump();

    expect(openedWorkspacePaths, <String>['/workspace/lib/main.dart']);
    expect(launcher.openedUris, isEmpty);
  });

  testWidgets('composer preserves native text paste without probing images', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': 'clipboard text'};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final session = _ImmediateNotifySessionHandle(tabId: 'tab-1');
    final clipboard = _FakeComposerClipboard(text: 'clipboard text');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalComposer(session: session, clipboard: clipboard),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Before ');
    final focusContext = tester.binding.focusManager.primaryFocus?.context;
    expect(focusContext, isNotNull);

    Actions.invoke(
      focusContext!,
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      session.composerController.textController.text,
      'Before clipboard text',
    );
    expect(clipboard.fileReads, 1);
    expect(clipboard.imageReads, 0);
  });
}

final class _FakeComposerClipboard implements TerminalClipboard {
  _FakeComposerClipboard({
    this.text,
    this.imagePath,
    this.filePaths = const <String>[],
  });

  final String? text;
  final String? imagePath;
  final List<String> filePaths;
  int fileReads = 0;
  int imageReads = 0;

  @override
  Future<List<String>> readFilePaths() async {
    fileReads += 1;
    return filePaths;
  }

  @override
  Future<String?> readText() async => text;

  @override
  Future<String?> saveImageAsTempFile() async {
    imageReads += 1;
    return imagePath;
  }

  @override
  Future<void> writeText(String text) async {}
}
