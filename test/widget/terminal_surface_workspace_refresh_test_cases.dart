part of 'terminal_surface_test.dart';

void _registerTerminalSurfaceWorkspaceRefreshTests() {
  testWidgets('foreground resume disables manual refresh until acknowledged', (
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
      final pty = factory.sessions.single;
      expect(_refreshButton(tester).onPressed, isNotNull);
      runtime.setAppForeground(false);
      await tester.pump();
      final resume = Completer<void>();
      pty.nextResumeCompleter = resume;
      runtime.setAppForeground(true);
      await tester.pumpAndSettle();
      expect(session.isResumingOutput, isTrue);
      _expectRefreshUnavailable(tester);
      await tester.tap(find.byTooltip('Refresh Terminal'));
      await tester.pump();
      expect(pty.refreshViewportCalls, isEmpty);
      expect(find.byTooltip('Refreshing Terminal'), findsNothing);

      resume.complete();
      await tester.pumpAndSettle();
      expect(_refreshButton(tester).onPressed, isNotNull);
      await tester.tap(find.byTooltip('Refresh Terminal'));
      await tester.pumpAndSettle();
      expect(pty.refreshViewportCalls, [
        terminalEmulatorViewSizeForTesting(session),
      ]);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('workspace entry waits for the attached snapshot to drain', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final snapshot = '${'restored history ' * 8}\r\n' * 10000;
      final factory = _FakeTerminalPtySessionFactory(
        onStart: (pty) => _emitRefreshSnapshot(pty, snapshot),
      );
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: factory,
        shellLaunchesBuilder: _testShellLaunches,
      );
      addTearDown(runtime.dispose);
      final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
      await _pumpTerminalSurface(
        tester,
        session,
        refreshOnWorkspaceEntry: true,
      );
      final pty = factory.sessions.single;
      expect(session.isStarting, isFalse);
      expect(session.restoreProgress.value, isNotNull);
      expect(pty.refreshViewportCalls, isEmpty);
      _expectRefreshUnavailable(tester);
      await tester.tap(find.byTooltip('Refresh Terminal'));
      await tester.pump();
      expect(find.byTooltip('Refreshing Terminal'), findsNothing);
      await session.refreshRendering();
      expect(pty.refreshViewportCalls, isEmpty);

      await _drainRefreshSnapshot(tester, session);
      expect(pty.refreshViewportCalls, [
        terminalEmulatorViewSizeForTesting(session),
      ]);
      expect(
        terminalBufferTextForTesting(session),
        contains('restored history'),
      );
      expect(pty.writes, isEmpty);
      expect(_refreshButton(tester).onPressed, isNotNull);
      await tester.tap(find.byTooltip('Refresh Terminal'));
      await tester.pumpAndSettle();
      expect(pty.refreshViewportCalls, hasLength(2));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('workspace return waits for a late resume snapshot', (
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
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      final surfaceRuntime = _SurfaceRefreshRuntime(session);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsControllerProvider.overrideWith(
              () => _FakeSettingsController(AleraSettings.defaults),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: visible,
                builder: (context, show, child) => WorkspaceTerminalRefresh(
                  workspaceId: show ? session.workspaceId : null,
                  ready: true,
                  terminalTabIds: [session.tabId],
                  terminalRuntime: surfaceRuntime,
                  child: Visibility(
                    visible: show,
                    maintainState: true,
                    child: child!,
                  ),
                ),
                child: TerminalSurface(session: session),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pty = factory.sessions.single;
      expect(pty.refreshViewportCalls, hasLength(1));
      visible.value = false;
      await tester.pumpAndSettle();
      final resume = Completer<void>();
      pty.nextResumeCompleter = resume;
      visible.value = true;
      await tester.pumpAndSettle();
      expect(session.isResumingOutput, isTrue);
      expect(session.restoreProgress.value, isNull);
      expect(pty.refreshViewportCalls, hasLength(1));
      _expectRefreshUnavailable(tester);
      await tester.tap(find.byTooltip('Refresh Terminal'));
      await tester.pump();
      expect(find.byTooltip('Refreshing Terminal'), findsNothing);

      _emitRefreshSnapshot(pty, '${'resumed history ' * 8}\r\n' * 10000);
      await tester.pump();
      expect(session.restoreProgress.value, isNotNull);
      resume.complete();
      await tester.pump();
      expect(pty.refreshViewportCalls, hasLength(1));
      _expectRefreshUnavailable(tester);
      await _drainRefreshSnapshot(tester, session);
      expect(pty.refreshViewportCalls, hasLength(2));
      expect(
        terminalBufferTextForTesting(session),
        contains('resumed history'),
      );
      expect(factory.sessions, hasLength(1));
      expect(pty.terminated, isFalse);
      expect(tester.takeException(), isNull);
      expect(_refreshButton(tester).onPressed, isNotNull);
      await tester.tap(find.byTooltip('Refresh Terminal'));
      await tester.pumpAndSettle();
      expect(pty.refreshViewportCalls, hasLength(3));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('workspace entry uses the manual refresh at the measured size', (
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

      await _pumpTerminalSurface(
        tester,
        session,
        refreshOnWorkspaceEntry: true,
      );
      await tester.pump();
      final pty = factory.sessions.single;
      final size = terminalEmulatorViewSizeForTesting(session);
      expect(pty.refreshViewportCalls, <(int, int)>[size]);

      pty.emitOutput(utf8.encode('retained output\r\n'));
      await _pumpTerminalOutput(tester);
      final buffer = terminalBufferTextForTesting(session);
      final viewport = tester.getRect(find.byType(xterm.TerminalView));
      await tester.tap(find.byTooltip('Refresh Terminal'));
      await tester.pump();

      expect(pty.refreshViewportCalls, <(int, int)>[size, size]);
      expect(terminalBufferTextForTesting(session), buffer);
      expect(tester.getRect(find.byType(xterm.TerminalView)), viewport);
      expect(factory.sessions, hasLength(1));
      expect(pty.terminated, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

IconButton _refreshButton(WidgetTester tester) => tester.widget<IconButton>(
  find.widgetWithIcon(IconButton, AleraIcons.refresh),
);

void _expectRefreshUnavailable(WidgetTester tester) {
  expect(_refreshButton(tester).onPressed, isNull);
  expect(find.byTooltip('Refreshing Terminal'), findsNothing);
}

void _emitRefreshSnapshot(_FakeTerminalPtySession pty, String text) {
  pty._events.add(
    TerminalPtySnapshotEvent(Uint8List.fromList(utf8.encode(text))),
  );
}

Future<void> _drainRefreshSnapshot(
  WidgetTester tester,
  TerminalSessionHandle session,
) async {
  for (
    var frame = 0;
    frame < 100 && session.restoreProgress.value != null;
    frame++
  ) {
    await _pumpTerminalOutput(tester);
  }
  expect(session.restoreProgress.value, isNull);
  await tester.pumpAndSettle();
}

class _SurfaceRefreshRuntime(final TerminalSessionHandle session)
    implements TerminalRuntime {
  @override
  TerminalSessionHandle? peekSession(String tabId) =>
      tabId == session.tabId ? session : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
