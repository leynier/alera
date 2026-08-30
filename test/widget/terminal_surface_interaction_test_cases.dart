part of 'terminal_surface_test.dart';

void _registerTerminalSurfaceInteractionTests() {
  testWidgets('ctrl-click opens visible terminal urls on Windows', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final factory = _FakeTerminalPtySessionFactory();
      final launcher = _FakeExternalUriLauncher();
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: factory,
        externalUriLauncher: launcher,
        shellLaunchesBuilder: _testShellLaunches,
      );
      addTearDown(runtime.dispose);
      final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());

      await _pumpTerminalSurface(tester, session);
      factory.sessions.single.emitOutput(utf8.encode('https://example.com'));
      await _pumpTerminalOutput(tester);

      await tester.sendKeyDownEvent(.controlLeft);
      await tester.pump();
      await tester.tapAt(_cellCenter(tester, const xterm.CellOffset(1, 0)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.sendKeyUpEvent(.controlLeft);

      expect(launcher.openedUris, <Uri>[Uri.parse('https://example.com')]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('shows a snackbar when opening a terminal url fails', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final factory = _FakeTerminalPtySessionFactory();
      final launcher = _FakeExternalUriLauncher(error: StateError('boom'));
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: factory,
        externalUriLauncher: launcher,
        shellLaunchesBuilder: _testShellLaunches,
      );
      addTearDown(runtime.dispose);
      final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());

      await _pumpTerminalSurface(tester, session);
      factory.sessions.single.emitOutput(utf8.encode('https://example.com'));
      await _pumpTerminalOutput(tester);

      await tester.sendKeyDownEvent(.metaLeft);
      await tester.pump();
      await tester.tapAt(_cellCenter(tester, const xterm.CellOffset(1, 0)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.sendKeyUpEvent(.metaLeft);

      expect(
        find.text('Could not open link: https://example.com'),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('manual tab title takes precedence over runtime title', (
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
      final visibility = session.acquireVisibility();
      addTearDown(visibility.dispose);

      await session.ensureStarted();
      factory.sessions.single.emitOutput(
        utf8.encode('\x1b]0;Runtime title\x07'),
      );
      await tester.pump();
      flushTerminalOutputForTesting(session);

      expect(session.displayTitle, 'Runtime title');

      runtime.sessionFor(
        workspace: _workspace(),
        tab: _tab().copyWith(
          title: 'Pinned title',
          payload: const <String, Object?>{
            workspaceTabManualTitlePayloadKey: true,
          },
        ),
      );
      await tester.pump();

      expect(session.displayTitle, 'Pinned title');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('shows the terminal error state and reconnects on demand', (
    tester,
  ) async {
    final session = _ErrorSessionHandle(tabId: 'tab-1', message: 'boom');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(child: TerminalSurface(session: session)),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Terminal unavailable'), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);

    await tester.tap(find.text('Reconnect'));
    await tester.pump();

    expect(session.restartCallCount, 1);
  });

  testWidgets('shows a startup progress indicator while starting', (
    tester,
  ) async {
    final session = _StartingSessionHandle(tabId: 'tab-1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(child: TerminalSurface(session: session)),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('terminal-tab-1')),
      findsOneWidget,
    );
  });

  testWidgets('closeWorkspace drops only the target workspace sessions', (
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
      final exits = <TerminalRuntimeExitEvent>[];
      final exitSub = runtime.exits.listen(exits.add);
      addTearDown(exitSub.cancel);

      final firstSession = runtime.sessionFor(
        workspace: _workspace(),
        tab: _tab(),
      );
      final secondSession = runtime.sessionFor(
        workspace: _workspace(),
        tab: _tab(id: 'tab-2', title: 'Terminal 2'),
      );
      final thirdSession = runtime.sessionFor(
        workspace: _workspace(id: 'ws-2', path: '/tmp/other'),
        tab: _tab(id: 'tab-3', workspaceId: 'ws-2', title: 'Terminal 3'),
      );

      await firstSession.ensureStarted();
      await secondSession.ensureStarted();
      await thirdSession.ensureStarted();

      runtime.closeWorkspace('ws-1');
      await tester.pump();

      expect(exits, isEmpty);

      final reopenedFirst = runtime.sessionFor(
        workspace: _workspace(),
        tab: _tab(),
      );
      final reopenedSecond = runtime.sessionFor(
        workspace: _workspace(),
        tab: _tab(id: 'tab-2', title: 'Terminal 2'),
      );
      final persistedThird = runtime.sessionFor(
        workspace: _workspace(id: 'ws-2', path: '/tmp/other'),
        tab: _tab(id: 'tab-3', workspaceId: 'ws-2', title: 'Terminal 3'),
      );

      expect(identical(reopenedFirst, firstSession), isFalse);
      expect(identical(reopenedSecond, secondSession), isFalse);
      expect(identical(persistedThird, thirdSession), isTrue);

      await reopenedFirst.ensureStarted();
      await reopenedSecond.ensureStarted();
      expect(factory.sessions, hasLength(5));

      factory.sessions[2].emitExit(5);
      await tester.pump();

      expect(exits, hasLength(1));
      expect(exits.single.workspaceId, 'ws-2');
      expect(exits.single.tabId, 'tab-3');
      expect(exits.single.exitCode, 5);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('defers startup notifications until after the first frame', (
    tester,
  ) async {
    final session = _ImmediateNotifySessionHandle(tabId: 'tab-1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(child: TerminalSurface(session: session)),
        ),
      ),
    );
    await tester.pump();

    expect(session.ensureStartedCallCount, 1);
    expect(
      find.byKey(const ValueKey<String>('terminal-tab-1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('restarts deferred startup when the session changes', (
    tester,
  ) async {
    final first = _ImmediateNotifySessionHandle(tabId: 'tab-1');
    final second = _ImmediateNotifySessionHandle(tabId: 'tab-2');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(child: TerminalSurface(session: first)),
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(child: TerminalSurface(session: second)),
        ),
      ),
    );
    await tester.pump();

    expect(first.ensureStartedCallCount, 1);
    expect(second.ensureStartedCallCount, 1);
    expect(
      find.byKey(const ValueKey<String>('terminal-tab-2')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'terminal shortcuts handle allowed actions and respect terminal-first policy',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);

        Future<ProviderContainer> pumpShortcutSurface({
          required AleraSettings settings,
          required _ShortcutCaptureSessionHandle session,
          required _FakeWorkbenchController controller,
        }) async {
          final container = ProviderContainer(
            overrides: [
              settingsControllerProvider.overrideWith(
                () => _FakeSettingsController(settings),
              ),
              workbenchControllerProvider.overrideWith(() => controller),
            ],
          );
          addTearDown(container.dispose);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                home: Scaffold(
                  body: SizedBox.expand(
                    child: TerminalSurface(session: session),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pumpAndSettle();
          return container;
        }

        final allowedSession = _ShortcutCaptureSessionHandle(tabId: 'tab-1');
        final allowedController = _FakeWorkbenchController();
        await pumpShortcutSurface(
          settings: .defaults,
          session: allowedSession,
          controller: allowedController,
        );

        expect(
          allowedSession.onKeyEvent?.call(
            focusNode,
            const KeyUpEvent(
              timeStamp: .zero,
              physicalKey: .keyB,
              logicalKey: .keyB,
            ),
          ),
          KeyEventResult.ignored,
        );

        await tester.sendKeyDownEvent(.metaLeft);
        final allowedResult = allowedSession.onKeyEvent!.call(
          focusNode,
          const KeyDownEvent(
            timeStamp: .zero,
            physicalKey: .keyB,
            logicalKey: .keyB,
          ),
        );
        await tester.sendKeyUpEvent(.metaLeft);
        await tester.pump();

        expect(allowedResult, KeyEventResult.handled);
        expect(allowedController.collapsedValues, <bool>[true]);

        await tester.sendKeyDownEvent(.metaLeft);
        final allowedSearchResult = allowedSession.onKeyEvent!.call(
          focusNode,
          const KeyDownEvent(
            timeStamp: .zero,
            physicalKey: .keyF,
            logicalKey: .keyF,
          ),
        );
        await tester.sendKeyUpEvent(.metaLeft);

        expect(allowedSearchResult, KeyEventResult.handled);
        expect(allowedSession.openSearchCallCount, 1);

        await tester.sendKeyDownEvent(.metaLeft);
        await tester.sendKeyDownEvent(.shiftLeft);
        final composerResult = allowedSession.onKeyEvent!.call(
          focusNode,
          const KeyDownEvent(
            timeStamp: .zero,
            physicalKey: .enter,
            logicalKey: .enter,
          ),
        );
        await tester.sendKeyUpEvent(.shiftLeft);
        await tester.sendKeyUpEvent(.metaLeft);

        expect(composerResult, KeyEventResult.handled);
        expect(allowedSession.composerController.visible, isTrue);

        final blockedSession = _ShortcutCaptureSessionHandle(tabId: 'tab-2');
        final blockedController = _FakeWorkbenchController();
        await pumpShortcutSurface(
          settings: AleraSettings.defaults.copyWith(
            keyboard: AleraSettings.defaults.keyboard.copyWithPolicy(
              .terminalFirst,
            ),
          ),
          session: blockedSession,
          controller: blockedController,
        );

        await tester.sendKeyDownEvent(.metaLeft);
        final blockedResult = blockedSession.onKeyEvent!.call(
          focusNode,
          const KeyDownEvent(
            timeStamp: .zero,
            physicalKey: .keyT,
            logicalKey: .keyT,
          ),
        );
        await tester.sendKeyUpEvent(.metaLeft);

        expect(blockedResult, KeyEventResult.ignored);
        expect(blockedController.collapsedValues, isEmpty);

        await tester.sendKeyDownEvent(.metaLeft);
        final terminalFirstSearchResult = blockedSession.onKeyEvent!.call(
          focusNode,
          const KeyDownEvent(
            timeStamp: .zero,
            physicalKey: .keyF,
            logicalKey: .keyF,
          ),
        );
        await tester.sendKeyUpEvent(.metaLeft);

        expect(terminalFirstSearchResult, KeyEventResult.handled);
        expect(blockedSession.openSearchCallCount, 1);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('terminal search closes on Escape and restores terminal focus', (
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

      await _pumpTerminalSurface(tester, session);
      session.openSearch();
      await tester.pump();
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      expect(tester.binding.focusManager.primaryFocus, isNotNull);

      await tester.sendKeyDownEvent(.escape);
      await tester.pump();
      await tester.pump();

      expect(find.byType(TextField), findsNothing);
      expect(terminalFocusHasFocusForTesting(session), isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
