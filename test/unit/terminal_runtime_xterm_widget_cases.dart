part of 'terminal_runtime_native_test.dart';

void _registerXtermRuntimeWidgetTests() {
  testWidgets(
    'render refresh reapplies the measured viewport without replacing state',
    (tester) async {
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
        await session.refreshRendering();
        expect(fakeSession.resizeCalls, isEmpty);

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

        await session.refreshRendering();
        await tester.pump(const Duration(milliseconds: 200));

        expect(fakeSession.resizeCalls, hasLength(2));
        expect(
          fakeSession.resizeCalls.first.cols,
          fakeSession.resizeCalls.last.cols - 1,
        );
        expect(
          fakeSession.resizeCalls.first.rows,
          fakeSession.resizeCalls.last.rows,
        );
        expect(fakeSession.resizeCalls.last.cols, greaterThan(0));
        expect(fakeSession.resizeCalls.last.rows, greaterThan(0));
        expect(terminalBufferTextForTesting(session), bufferBefore);
        expect(runtime.peekSession('tab-1'), same(session));
        expect(fakeSession.writes, isEmpty);
        expect(fakeSession.terminated, isFalse);
      } finally {
        runtime.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('completed restore refreshes the measured viewport once', (
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
    final visibility = acquireTerminalVisibilityForTesting(session);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: session,
              builder: (context, _) => session.buildView(),
            ),
          ),
        ),
      );
      await tester.pump();
      await session.ensureStarted();
      await tester.pump(const Duration(milliseconds: 200));
      fakeSession.resizeCalls.clear();
      fakeSession.writes.clear();

      const marker = 'restored-tail-marker';
      fakeSession.emitSnapshot(utf8.encode('$marker\r\n'));
      await tester.idle();

      while (pendingRestoreTerminalOutputCharsForTesting(session) > 0) {
        flushTerminalOutputForTesting(session);
      }
      final bufferBeforeRefresh = terminalBufferTextForTesting(session);
      expect(session.restoreProgress.value, isNull);
      expect(bufferBeforeRefresh, contains(marker));
      expect(fakeSession.resizeCalls, isEmpty);

      await tester.pump();

      expect(fakeSession.resizeCalls, hasLength(2));
      expect(
        fakeSession.resizeCalls.first.cols,
        fakeSession.resizeCalls.last.cols - 1,
      );
      expect(
        fakeSession.resizeCalls.first.rows,
        fakeSession.resizeCalls.last.rows,
      );
      expect(terminalBufferTextForTesting(session), bufferBeforeRefresh);
      expect(runtime.peekSession('tab-1'), same(session));
      expect(fakeSession.writes, isEmpty);
      expect(fakeSession.terminated, isFalse);
    } finally {
      visibility.dispose();
      runtime.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a replacement invalidates a pending restore refresh', (
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
    final visibility = acquireTerminalVisibilityForTesting(session);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: session,
              builder: (context, _) => session.buildView(),
            ),
          ),
        ),
      );
      await tester.pump();
      await session.ensureStarted();
      await tester.pump(const Duration(milliseconds: 200));
      fakeSession.resizeCalls.clear();

      fakeSession.emitSnapshot(utf8.encode('superseded'));
      await tester.idle();
      flushTerminalOutputForTesting(session);
      expect(session.restoreProgress.value, isNull);

      fakeSession.emitSnapshot(utf8.encode('latest-tail-marker\r\n'));
      await tester.idle();
      expect(session.restoreProgress.value, isNotNull);
      flushTerminalOutputForTesting(session);
      expect(session.restoreProgress.value, isNull);
      expect(fakeSession.resizeCalls, isEmpty);

      await tester.pump();

      expect(fakeSession.resizeCalls, hasLength(2));
    } finally {
      visibility.dispose();
      runtime.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'build view supports deferred focus, direct input, and OSC updates',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      final fakeSession = _FakeTerminalPtySession();
      final factory = _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[fakeSession],
      );
      final launcher = _FakeExternalUriLauncher();
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: factory,
        externalUriLauncher: launcher,
        shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
          _launch('shell', shell: '/bin/sh'),
        ],
      );
      addTearDown(runtime.dispose);
      final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(child: session.buildView(autofocus: false)),
          ),
        ),
      );
      try {
        await tester.pump();

        await session.ensureStarted();
        feedTerminalInputForTesting(session, 'abc');
        expect(fakeSession.writes.map(utf8.decode).join(), contains('abc'));

        final focusNode = terminalFocusNodeForTesting(session);
        expect(focusNode.hasFocus, isFalse);
        expect(focusNode.canRequestFocus, isTrue);
        requestTerminalFocusNowForTesting(session);
        session.requestFocus();
        await tester.pump();
        await tester.pump();
        expect(focusNode.context, isNotNull);

        handlePrivateOscForTesting(session, '8', <String>[
          '',
          'https://example.com',
        ]);
        fakeSession.emitError(StateError('boom'));
        await tester.pump();

        expect(find.byType(xterm.TerminalView), findsOneWidget);
      } finally {
        runtime.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('build view clears hovered links on exit and session updates', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    final launcher = _FakeExternalUriLauncher(
      error: StateError('cannot launch'),
    );
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[
          _FakeTerminalPtySession(),
          _FakeTerminalPtySession(),
        ],
      ),
      externalUriLauncher: launcher,
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);
    final firstSession = runtime.sessionFor(
      workspace: _workspace(),
      tab: _tab(id: 'tab-1'),
    );
    final secondSession = runtime.sessionFor(
      workspace: _workspace(),
      tab: _tab(id: 'tab-2'),
    );

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: firstSession.buildView(autofocus: false),
            ),
          ),
        ),
      );
      await tester.pump();

      handlePrivateOscForTesting(firstSession, '8', <String>[
        '',
        'https://example.com',
      ]);
      writeTerminalOutputForTesting(firstSession, 'open');
      handlePrivateOscForTesting(firstSession, '8', const <String>['', '']);
      await tester.pump();

      final mouse = await tester.createGesture(kind: .mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: .zero);
      await tester.pump();

      final linkOffset =
          tester.getTopLeft(find.byType(xterm.TerminalView)) +
          const Offset(8, 8);
      await mouse.moveTo(linkOffset);
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(.metaLeft);
      final view = tester.widget<xterm.TerminalView>(
        find.byType(xterm.TerminalView),
      );
      view.onTapUp?.call(
        TapUpDetails(kind: .mouse),
        const xterm.CellOffset(1, 0),
      );
      await tester.pump();
      await tester.sendKeyUpEvent(.metaLeft);
      await tester.pump();

      expect(launcher.openedUris, <Uri>[Uri.parse('https://example.com')]);
      expect(
        find.text('Could not open link: https://example.com'),
        findsOneWidget,
      );

      await mouse.moveTo(const Offset(-10, -10));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: secondSession.buildView(autofocus: false),
            ),
          ),
        ),
      );
      await tester.pump();
    } finally {
      runtime.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('build view forwards autofocus and key callbacks', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[_FakeTerminalPtySession()],
      ),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
    try {
      KeyEvent? capturedEvent;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: session.buildView(
                autofocus: true,
                onKeyEvent: (_, event) {
                  capturedEvent = event;
                  return KeyEventResult.handled;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final view = tester.widget<xterm.TerminalView>(
        find.byType(xterm.TerminalView),
      );
      expect(view.autofocus, isTrue);
      expect(
        view.onKeyEvent?.call(
          FocusNode(),
          const KeyUpEvent(
            timeStamp: .zero,
            physicalKey: .keyA,
            logicalKey: .keyA,
          ),
        ),
        KeyEventResult.handled,
      );
      expect(capturedEvent, isA<KeyUpEvent>());
      expect(view.hardwareKeyboardOnly, isFalse);
    } finally {
      runtime.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('build view uses text input composition on Windows', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[_FakeTerminalPtySession()],
      ),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: r'C:\Program Files\PowerShell\7\pwsh.exe'),
      ],
    );
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(child: session.buildView(autofocus: true)),
          ),
        ),
      );
      await tester.pump();

      final view = tester.widget<xterm.TerminalView>(
        find.byType(xterm.TerminalView),
      );
      expect(view.hardwareKeyboardOnly, isFalse);
    } finally {
      runtime.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
