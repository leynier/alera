part of 'terminal_surface_test.dart';

void _registerTerminalSurfaceWorkspaceRefreshTests() {
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

class _SurfaceRefreshRuntime(final TerminalSessionHandle session)
    implements TerminalRuntime {
  @override
  TerminalSessionHandle? peekSession(String tabId) =>
      tabId == session.tabId ? session : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
