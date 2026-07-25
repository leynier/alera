part of 'terminal_runtime_native_test.dart';

void _registerXtermRuntimeRemintTests() {
  test('interaction reset leaves every alternate-screen dialect', () {
    final cursorTerminal = xterm.Terminal()
      ..write('\x1b[?1h\x1b[?25l\x1b[?1004h\x1b=');
    expect(cursorTerminal.cursorKeysMode, isTrue);
    expect(cursorTerminal.cursorVisibleMode, isFalse);
    expect(cursorTerminal.reportFocusMode, isTrue);
    expect(cursorTerminal.appKeypadMode, isTrue);
    cursorTerminal.write(terminalInteractionModeReset);
    expect(cursorTerminal.cursorKeysMode, isFalse);
    expect(cursorTerminal.cursorVisibleMode, isTrue);
    expect(cursorTerminal.reportFocusMode, isFalse);
    expect(cursorTerminal.appKeypadMode, isFalse);

    for (final encodingMode in <int>[1005, 1015]) {
      final terminal = xterm.Terminal()..write('\x1b[?${encodingMode}h');
      expect(
        terminal.mouseReportMode,
        isNot(xterm.MouseReportMode.normal),
        reason: 'mode $encodingMode enabled',
      );

      terminal.write(terminalInteractionModeReset);

      expect(
        terminal.mouseReportMode,
        xterm.MouseReportMode.normal,
        reason: 'mode $encodingMode reset',
      );
    }

    final mouseOutput = <String>[];
    final mouseTerminal = xterm.Terminal(onOutput: mouseOutput.add)
      ..write('\x1b[?1000h\x1b[?1005h\x1b[?1006h\x1b[?1015h\x1b[?1016h');
    expect(mouseTerminal.mouseReportMode, xterm.MouseReportMode.sgrPixels);
    mouseTerminal
      ..write(terminalInteractionModeReset)
      ..write('\x1b[?1000h')
      ..mouseInput(
        xterm.TerminalMouseButton.left,
        xterm.TerminalMouseButtonState.down,
        const xterm.CellOffset(1, 2),
      );
    expect(mouseTerminal.mouseReportMode, xterm.MouseReportMode.normal);
    expect(mouseOutput, <String>['\x1b[M "#']);

    for (final mode in <int>[47, 1047, 1049]) {
      final terminal = xterm.Terminal();
      terminal.write('\x1b[?${mode}h');
      expect(terminal.isUsingAltBuffer, isTrue, reason: 'mode $mode');

      terminal.write(terminalInteractionModeReset);

      expect(terminal.isUsingAltBuffer, isFalse, reason: 'mode $mode');
    }
  });

  test('remint snapshot restores a fresh main-buffer state', () async {
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
    TerminalVisibilityLease? visibility;
    TerminalVisibilityLease? resumedVisibility;
    try {
      visibility = acquireTerminalVisibilityForTesting(session);
      await session.ensureStarted();
      fakeSession.emitOutput(utf8.encode('stale-cursor'));
      await Future<void>.delayed(Duration.zero);

      visibility.dispose();
      visibility = null;
      await Future<void>.delayed(Duration.zero);
      resumedVisibility = acquireTerminalVisibilityForTesting(session);
      await Future<void>.delayed(Duration.zero);

      fakeSession.emitSnapshot(
        utf8.encode(
          'fresh prompt\x1b[?1h\x1b[?25l\x1b[?1004h\x1b=\x1b[?1049h\x1b[?2004hdead tui',
        ),
        resetInteractionModes: true,
      );
      await Future<void>.delayed(Duration.zero);
      // A restored snapshot is drained by the frame batcher, not written
      // synchronously, so it lands on the next flush.
      flushTerminalOutputForTesting(session);

      final restored = terminalBufferTextForTesting(session);
      expect(restored.split('\n').first, 'fresh prompt');
      expect(restored, isNot(contains('stale-cursor')));
      expect(restored, isNot(contains('dead tui')));
      expect(terminalCursorKeysModeForTesting(session), isFalse);
      expect(terminalCursorVisibleModeForTesting(session), isTrue);
      expect(terminalReportFocusModeForTesting(session), isFalse);
      expect(terminalAppKeypadModeForTesting(session), isFalse);
      expect(terminalBracketedPasteModeForTesting(session), isFalse);
      expect(terminalIsUsingAltBufferForTesting(session), isFalse);
    } finally {
      visibility?.dispose();
      resumedVisibility?.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('hidden remint resets modes on the next visible snapshot', () async {
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
    TerminalVisibilityLease? visibility;
    try {
      visibility = acquireTerminalVisibilityForTesting(session);
      await session.ensureStarted();
      visibility.dispose();
      visibility = null;
      await Future<void>.delayed(Duration.zero);

      fakeSession.emitSnapshot(const <int>[], resetInteractionModes: true);
      await Future<void>.delayed(Duration.zero);

      visibility = acquireTerminalVisibilityForTesting(session);
      await Future<void>.delayed(Duration.zero);
      fakeSession.emitSnapshot(
        utf8.encode(
          'fresh prompt\x1b[?1h\x1b[?25l\x1b[?1004h\x1b=\x1b[?1049h\x1b[?1000h\x1b[?2004hdead tui',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      flushTerminalOutputForTesting(session);

      expect(terminalBufferTextForTesting(session), contains('fresh prompt'));
      expect(
        terminalBufferTextForTesting(session),
        isNot(contains('dead tui')),
      );
      expect(terminalCursorKeysModeForTesting(session), isFalse);
      expect(terminalCursorVisibleModeForTesting(session), isTrue);
      expect(terminalReportFocusModeForTesting(session), isFalse);
      expect(terminalAppKeypadModeForTesting(session), isFalse);
      expect(terminalMouseModeForTesting(session), xterm.MouseMode.none);
      expect(terminalBracketedPasteModeForTesting(session), isFalse);
      expect(terminalIsUsingAltBufferForTesting(session), isFalse);
    } finally {
      visibility?.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final shell in <String>['/bin/bash', '/bin/zsh', '/usr/bin/fish']) {
    test('wrapped $shell keeps bracketed-paste startup delivery', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final fakeSession = _FakeTerminalPtySession();
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: _FakeTerminalPtySessionFactory(
          sessions: <_FakeTerminalPtySession>[fakeSession],
        ),
        shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
          _launch('shell', shell: shell),
        ],
      );
      addTearDown(runtime.dispose);

      await runtime
          .sessionFor(
            workspace: _workspace(),
            tab: _tab(
              payload: const <String, Object?>{
                workspaceTabInitialCommandPayloadKey: 'echo one\necho\ttwo',
              },
            ),
          )
          .ensureStarted();

      expect(fakeSession.startedLaunch?.shell, '/bin/sh');
      final paste = utf8.decode(fakeSession.writes.first);
      expect(paste, startsWith(terminalBracketedPasteStart));
      expect(paste, contains('echo one\necho\ttwo'));
      expect(paste, endsWith(terminalBracketedPasteEnd));
      expect(fakeSession.writes.map(utf8.decode).toList(), <String>[
        paste,
        '\r',
      ]);
    });
  }

  test('wrapped unsupported shell keeps controls inert', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final fakeSession = _FakeTerminalPtySession();
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[fakeSession],
      ),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/dash'),
      ],
    );
    addTearDown(runtime.dispose);

    await runtime
        .sessionFor(
          workspace: _workspace(),
          tab: _tab(
            payload: const <String, Object?>{
              workspaceTabInitialCommandPayloadKey: 'echo one\necho\ttwo',
            },
          ),
        )
        .ensureStarted();

    expect(fakeSession.startedLaunch?.shell, '/bin/sh');
    expect(fakeSession.writes.map(utf8.decode), <String>[
      'echo one<LF>echo<TAB>two\r',
    ]);
  });

  test('transparent remint replays setup and initial commands once', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final fakeSession = _FakeTerminalPtySession();
    final createdSessions = <String>[];
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[fakeSession],
      ),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/bash', setupCommand: 'printf setup\n'),
      ],
      terminalProcessCreated: (terminalSessionId) {
        expect(fakeSession.writes, isEmpty);
        createdSessions.add(terminalSessionId);
      },
    );
    addTearDown(runtime.dispose);
    final handle = runtime.sessionFor(
      workspace: _workspace(),
      tab: _tab(
        payload: const <String, Object?>{
          workspaceTabInitialCommandPayloadKey: 'claude',
        },
      ),
    );

    await handle.ensureStarted();
    expect(createdSessions, <String>['tab-1']);
    expect(fakeSession.writes.map(utf8.decode), <String>[
      'printf setup\n',
      'claude\r',
    ]);

    fakeSession.writes.clear();
    await fakeSession.remint();
    expect(createdSessions, <String>['tab-1', 'tab-1']);
    expect(fakeSession.writes.map(utf8.decode), <String>[
      'printf setup\n',
      'claude\r',
    ]);
  });
}
