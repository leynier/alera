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
            onOpen: (_, _) {},
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
        '\r',
      ]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('composer pastes an image path at the current selection', (
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
    session.composerController.textController.selection = const TextSelection(
      baseOffset: 12,
      extentOffset: 23,
    );
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
      'Review this /tmp/alera-paste-\u241b.png',
    );
    expect(clipboard.imageReads, 1);
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
    expect(clipboard.imageReads, 0);
  });
}

final class _FakeComposerClipboard implements TerminalClipboard {
  _FakeComposerClipboard({this.text, this.imagePath});

  final String? text;
  final String? imagePath;
  int imageReads = 0;

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
