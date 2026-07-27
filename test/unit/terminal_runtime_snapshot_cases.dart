part of 'terminal_runtime_native_test.dart';

void _registerTerminalRuntimeSnapshotTests() {
  test(
    'pauses hidden terminal output and restores from snapshots when visible',
    () async {
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

        fakeSession.emitOutput(utf8.encode('visible\r\n'));
        await Future<void>.delayed(Duration.zero);
        flushTerminalOutputForTesting(session);
        expect(terminalBufferTextForTesting(session), contains('visible'));
        visibility.dispose();
        visibility = null;
        await Future<void>.delayed(Duration.zero);
        expect(fakeSession.outputPausedCalls, contains(true));
        fakeSession.emitOutput(utf8.encode('hidden\r\n'));
        await Future<void>.delayed(Duration.zero);
        expect(
          terminalBufferTextForTesting(session),
          isNot(contains('hidden')),
        );
        resumedVisibility = acquireTerminalVisibilityForTesting(session);
        await Future<void>.delayed(Duration.zero);
        expect(fakeSession.outputPausedCalls.last, isFalse);
        fakeSession.emitSnapshot(
          utf8.encode(
            '\x1b[?1h\x1b[?25l\x1b[?1004h\x1b=\x1b[?1000h\x1b[?2004h\x1b[?1049hvisible\r\nhidden\r\n',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        flushTerminalOutputForTesting(session);
        final restored = terminalBufferTextForTesting(session);
        expect(restored, contains('visible'));
        expect(restored, contains('hidden'));
        expect(
          terminalMouseModeForTesting(session),
          isNot(xterm.MouseMode.none),
        );
        expect(terminalBracketedPasteModeForTesting(session), isTrue);
        expect(terminalCursorKeysModeForTesting(session), isTrue);
        expect(terminalCursorVisibleModeForTesting(session), isFalse);
        expect(terminalReportFocusModeForTesting(session), isTrue);
        expect(terminalAppKeypadModeForTesting(session), isTrue);
        expect(terminalIsUsingAltBufferForTesting(session), isTrue);
      } finally {
        visibility?.dispose();
        resumedVisibility?.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  test('a process exit mid-restore takes the restore overlay down', () async {
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

      // Three frames' worth, so one drain cannot finish the restore.
      fakeSession.emitSnapshot(utf8.encode('a' * (64 * 1024 * 3)));
      await Future<void>.delayed(Duration.zero);
      flushTerminalOutputForTesting(session);
      expect(session.restoreProgress.value, isNotNull);

      fakeSession.emitExit(0);
      await Future<void>.delayed(Duration.zero);

      expect(session.restoreProgress.value, isNull);
    } finally {
      visibility?.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('a snapshot keeps pointer input suspended until it is parsed', () async {
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
      await session.ensureStarted();

      fakeSession.emitSnapshot(utf8.encode('\x1b[?1000h\x1b[?1006hactive tui'));
      await Future<void>.delayed(Duration.zero);

      expect(terminalPointerInputSuspendedForTesting(session), isTrue);

      flushTerminalOutputForTesting(session);

      expect(terminalPointerInputSuspendedForTesting(session), isFalse);
      expect(terminalMouseModeForTesting(session), isNot(xterm.MouseMode.none));
    } finally {
      visibility.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
