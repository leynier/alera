part of 'terminal_surface_test.dart';

void _registerTerminalSurfaceComposerTests() {
  testWidgets('composer control sits below refresh and submits a prompt', (
    tester,
  ) async {
    final session = _ImmediateNotifySessionHandle(tabId: 'tab-1');

    await _pumpTerminalSurface(tester, session);

    final refreshRect = tester.getRect(find.byTooltip('Refresh Terminal'));
    final composerRect = tester.getRect(
      find.byTooltip('Show Terminal Composer'),
    );
    expect(composerRect.top, greaterThan(refreshRect.bottom));
    expect(composerRect.right, refreshRect.right);

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
}
