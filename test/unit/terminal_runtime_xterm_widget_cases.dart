part of 'terminal_runtime_native_test.dart';

void _registerXtermRuntimeWidgetTests() {
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

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await tester.pump();

      final linkOffset =
          tester.getTopLeft(find.byType(xterm.TerminalView)) +
          const Offset(8, 8);
      await mouse.moveTo(linkOffset);
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      final view = tester.widget<xterm.TerminalView>(
        find.byType(xterm.TerminalView),
      );
      view.onTapUp?.call(
        TapUpDetails(kind: PointerDeviceKind.mouse),
        const xterm.CellOffset(1, 0),
      );
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
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
            timeStamp: Duration.zero,
            physicalKey: PhysicalKeyboardKey.keyA,
            logicalKey: LogicalKeyboardKey.keyA,
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

  testWidgets('build view uses hardware keyboard input on Windows', (
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
      expect(view.hardwareKeyboardOnly, isTrue);
    } finally {
      runtime.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
