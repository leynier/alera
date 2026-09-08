part of 'terminal_runtime_native_test.dart';

void _registerXtermRuntimeEmulatorFakeResizeTests() {
  test('emulator pulse restores size without notifying onResize', () {
    var notifications = 0;
    final terminal = xterm.Terminal()..resize(80, 24);
    terminal.onResize = (_, _, _, _) {
      notifications += 1;
    };

    applyTerminalEmulatorFakeResizeForTesting(terminal);

    expect(terminal.viewWidth, 80);
    expect(terminal.viewHeight, 24);
    expect(notifications, 0);
    expect(terminal.onResize, isNotNull);
  });

  testWidgets('render refresh fake-resizes the emulator without a PTY resize', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final fakeSession = _FakeTerminalPtySession();
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[fakeSession],
      ),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SizedBox.expand(child: session.buildView())),
        ),
      );
      await tester.pump();
      await session.ensureStarted();
      await tester.pump(const Duration(milliseconds: 200));
      fakeSession.resizeCalls.clear();
      fakeSession.writes.clear();
      writeTerminalOutputForTesting(session, 'preserved output');
      final bufferBefore = terminalBufferTextForTesting(session);
      final sizeBefore = terminalEmulatorViewSizeForTesting(session);

      handleTerminalResizeForTesting(session, 100, 30, 8, 16);
      await session.refreshRendering();
      flushPendingPtyResizeForTesting(session);

      expect(terminalEmulatorViewSizeForTesting(session), sizeBefore);
      expect(terminalBufferTextForTesting(session), bufferBefore);
      expect(fakeSession.resizeCalls, <_ResizeCall>[
        const _ResizeCall(
          cols: 100,
          rows: 30,
          cellWidthPx: 8,
          cellHeightPx: 16,
        ),
      ]);
      expect(fakeSession.writes, isEmpty);
      expect(fakeSession.terminated, isFalse);
      expect(runtime.peekSession('tab-1'), same(session));
    } finally {
      runtime.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
