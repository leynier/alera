part of 'terminal_surface_test.dart';

void _registerTerminalSurfaceRuntimeTests() {
  test('working directory launch keeps the shell usable if cd fails', () {
    const launch = GhosttyTerminalShellLaunch(
      label: 'zsh',
      shell: '/bin/zsh',
      arguments: <String>['-l'],
      environment: <String, String>{'TERM': 'xterm-256color'},
      setupCommand: 'echo ready\n',
    );

    final wrapped = launchInWorkingDirectoryForTesting(
      launch,
      "/missing/workspace's path",
    );

    expect(wrapped.shell, '/bin/sh');
    expect(wrapped.arguments, hasLength(2));
    expect(wrapped.arguments.first, '-c');
    expect(
      wrapped.arguments.last,
      "cd '/missing/workspace'\"'\"'s path' || true; exec '/bin/zsh' '-l'",
    );
    expect(wrapped.environment, launch.environment);
    expect(wrapped.setupCommand, launch.setupCommand);
  });

  test('working directory launch preserves Windows command prompt', () {
    const launch = GhosttyTerminalShellLaunch(
      label: 'cmd.exe',
      shell: r'C:\Windows\System32\cmd.exe',
      environment: <String, String>{'TERM': 'xterm-256color'},
    );

    final wrapped = launchInWorkingDirectoryForTesting(
      launch,
      r'C:\Users\alera\workspace',
    );

    expect(wrapped.shell, launch.shell);
    expect(wrapped.arguments, <String>[
      '/d',
      '/s',
      '/k',
      r'cd /d "C:\Users\alera\workspace"',
    ]);
    expect(wrapped.environment, launch.environment);
    expect(wrapped.setupCommand, launch.setupCommand);
  });

  testWidgets('xterm runtime starts with injected PTY on Linux desktop', (
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

      final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());

      await session.ensureStarted();

      expect(session.errorMessage, isNull);
      expect(session.isRunning, isTrue);
      expect(factory.sessions, hasLength(1));
      expect(factory.sessions.single.startedLaunch, isNotNull);
      expect(factory.sessions.single.startedCols, greaterThan(0));
      expect(factory.sessions.single.startedRows, greaterThan(0));

      factory.sessions.single.emitExit(7);
      factory.sessions.single.emitExit(9);
      await tester.pump();

      expect(session.isRunning, isFalse);
      expect(exits, hasLength(1));
      expect(exits.single.workspaceId, 'ws-1');
      expect(exits.single.tabId, 'tab-1');
      expect(exits.single.exitCode, 7);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('terminal host errors become a recoverable session state', (
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
      factory.sessions.single.emitError('writer disconnected');
      await tester.pump();

      expect(session.isRunning, isFalse);
      expect(session.errorMessage, contains('writer disconnected'));
      expect(
        terminalBufferTextForTesting(session),
        isNot(contains('terminal error')),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('xterm runtime suppresses exits from intentional tab closes', (
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

      final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());

      await session.ensureStarted();
      factory.sessions.single.exitCodeOnDispose = 0;

      runtime.closeTab('tab-1');
      await tester.pump();
      await tester.pump();
      factory.sessions.single.emitExit(0);
      await tester.pump();

      expect(exits, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'changing workspace metadata during build does not notify synchronously',
    (tester) async {
      final runtime = XtermTerminalRuntime();
      addTearDown(runtime.dispose);
      final tab = WorkspaceTabRecord(
        id: 'tab-1',
        workspaceId: 'ws-1',
        title: 'Terminal 1',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      Workspace workspaceWithPath(String path) => Workspace(
        id: 'ws-1',
        projectId: 'p-1',
        name: 'Main',
        branch: 'main',
        path: path,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        kind: WorkspaceKind.main,
        status: WorkspaceStatus.active,
      );

      final pathNotifier = ValueNotifier<String>('/tmp/a');
      addTearDown(pathNotifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<String>(
              valueListenable: pathNotifier,
              builder: (context, path, _) {
                // sessionFor().sync() runs here, during build.
                final session = runtime.sessionFor(
                  workspace: workspaceWithPath(path),
                  tab: tab,
                );
                return AnimatedBuilder(
                  animation: session,
                  builder: (context, _) => Text(session.displayTitle),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Mutating the workspace path makes sync() detect a metadata change while
      // the AnimatedBuilder is mounted and listening.
      pathNotifier.value = '/tmp/b';
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('runtime applies visual settings to existing sessions', (
    tester,
  ) async {
    final initialSettings = TerminalSettings.defaults.copyWith(
      fontFamily: 'monospace',
    );
    final runtime = XtermTerminalRuntime(initialSettings: initialSettings);
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
    var notifications = 0;
    session.addListener(() => notifications++);

    runtime.updateSettings(
      initialSettings.copyWith(
        fontSize: 18,
        fontWeight: 500,
        cursorBlink: true,
        themeName: 'Tokyo Night',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SizedBox.expand(child: session.buildView())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final view = tester.widget<xterm.TerminalView>(
      find.byType(xterm.TerminalView),
    );
    final expectedTheme = terminalThemeForName('Tokyo Night');
    expect(notifications, 1);
    expect(view.textStyle.fontSize, 18);
    expect(view.textStyle.fontWeight, 500);
    expect(view.cursorBlink, isTrue);
    expect(view.theme.background, expectedTheme.background);
  });

  testWidgets('cmd-click opens visible terminal urls on macOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
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

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      await tester.tapAt(_cellCenter(tester, const xterm.CellOffset(1, 0)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

      expect(launcher.openedUris, <Uri>[Uri.parse('https://example.com')]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('plain clicks do not open visible terminal urls', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
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

      await tester.tapAt(_cellCenter(tester, const xterm.CellOffset(1, 0)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(launcher.openedUris, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('ensureStarted reports unsupported platforms without a PTY', (
    tester,
  ) async {
    final factory = _FakeTerminalPtySessionFactory();
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: factory,
      shellLaunchesBuilder: _testShellLaunches,
    );
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());

    await session.ensureStarted();
    await tester.pump();

    expect(session.isRunning, isFalse);
    expect(session.isStarting, isFalse);
    expect(session.errorMessage, contains('native desktop PTY path'));
    expect(factory.sessions, isEmpty);
  });

  testWidgets('hover only activates the link cursor on the link row', (
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
      factory.sessions.single.emitOutput(
        utf8.encode('not a link\r\nhttps://example.com'),
      );
      await _pumpTerminalOutput(tester);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(() => mouse.removePointer());
      await mouse.addPointer();
      await mouse.moveTo(_cellCenter(tester, const xterm.CellOffset(1, 0)));
      await tester.pump();

      expect(
        tester
            .widget<xterm.TerminalView>(find.byType(xterm.TerminalView))
            .mouseCursor,
        SystemMouseCursors.text,
      );

      await mouse.moveTo(_cellCenter(tester, const xterm.CellOffset(1, 1)));
      await tester.pump();

      expect(
        tester
            .widget<xterm.TerminalView>(find.byType(xterm.TerminalView))
            .mouseCursor,
        SystemMouseCursors.click,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
