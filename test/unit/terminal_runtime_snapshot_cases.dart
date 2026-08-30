part of 'terminal_runtime_native_test.dart';

String _terminalRestorePayload(int length, String suffix) {
  const control = '\x1b[0m';
  final bodyLength = length - suffix.length;
  assert(bodyLength >= 0);
  final controls = List<String>.filled(
    bodyLength ~/ control.length,
    control,
  ).join();
  final padding = List<String>.filled(bodyLength - controls.length, ' ').join();
  return '$controls$padding$suffix';
}

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
        await Future.pause(.zero);
        flushTerminalOutputForTesting(session);
        expect(terminalBufferTextForTesting(session), contains('visible'));
        visibility.dispose();
        visibility = null;
        await Future.pause(.zero);
        expect(fakeSession.outputPausedCalls, contains(true));
        fakeSession.emitOutput(utf8.encode('hidden\r\n'));
        await Future.pause(.zero);
        expect(
          terminalBufferTextForTesting(session),
          isNot(contains('hidden')),
        );
        resumedVisibility = acquireTerminalVisibilityForTesting(session);
        await Future.pause(.zero);
        expect(fakeSession.outputPausedCalls.last, isFalse);
        fakeSession.emitSnapshot(
          utf8.encode(
            '\x1b[?1h\x1b[?25l\x1b[?1004h\x1b=\x1b[?1000h\x1b[?2004h\x1b[?1049hvisible\r\nhidden\r\n',
          ),
        );
        await Future.pause(.zero);
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
      await Future.pause(.zero);
      flushTerminalOutputForTesting(session);
      expect(session.restoreProgress.value, isNotNull);

      fakeSession.emitExit(0);
      await Future.pause(.zero);

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
      await Future.pause(.zero);

      expect(terminalPointerInputSuspendedForTesting(session), isTrue);

      flushTerminalOutputForTesting(session);

      expect(terminalPointerInputSuspendedForTesting(session), isFalse);
      expect(terminalMouseModeForTesting(session), isNot(xterm.MouseMode.none));
    } finally {
      visibility.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('live output cannot evict a restore before its first flush', () async {
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
      const snapshotLength = 64 * 1024 * 18;
      const snapshotMarker = 'snapshot-tail-marker';
      const liveMarker = 'live-tail-marker';
      final snapshot = _terminalRestorePayload(
        snapshotLength,
        '\r\n$snapshotMarker\r\n',
      );

      fakeSession.emitSnapshot(utf8.encode(snapshot));
      await Future.pause(.zero);
      fakeSession.emitOutput(utf8.encode('$liveMarker\r\n'));
      await Future.pause(.zero);

      expect(
        pendingRestoreTerminalOutputCharsForTesting(session),
        snapshotLength,
      );
      expect(
        pendingLiveTerminalOutputCharsForTesting(session),
        '$liveMarker\r\n'.length,
      );
      expect(session.restoreProgress.value?.totalChars, snapshotLength);

      while (pendingRestoreTerminalOutputCharsForTesting(session) > 0) {
        flushTerminalOutputForTesting(session);
        final remaining = pendingRestoreTerminalOutputCharsForTesting(session);
        final progress = session.restoreProgress.value;
        if (remaining == 0) {
          expect(progress, isNull);
        } else {
          expect(progress, isNotNull);
          expect(progress!.writtenChars + remaining, snapshotLength);
        }
      }

      expect(
        pendingLiveTerminalOutputCharsForTesting(session),
        '$liveMarker\r\n'.length,
      );
      while (pendingTerminalOutputCharsForTesting(session) > 0) {
        flushTerminalOutputForTesting(session);
      }
      final text = terminalBufferTextForTesting(session);
      expect(text, contains(snapshotMarker));
      expect(text, contains(liveMarker));
      expect(text.indexOf(snapshotMarker), lessThan(text.indexOf(liveMarker)));
    } finally {
      visibility.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test(
    'backpressure trims only live output during a partial restore',
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
      final visibility = acquireTerminalVisibilityForTesting(session);
      try {
        await session.ensureStarted();
        const snapshotLength = 64 * 1024 * 18;
        const snapshotMarker = 'protected-snapshot-marker';
        const oldLiveMarker = 'discarded-live-marker';
        const newLiveMarker = 'retained-live-marker';
        final snapshot = _terminalRestorePayload(
          snapshotLength,
          '\r\n$snapshotMarker\r\n\x1b[?1000h\x1b[?2004h',
        );

        fakeSession.emitSnapshot(
          utf8.encode(snapshot),
          resetInteractionModes: true,
        );
        await Future.pause(.zero);
        flushTerminalOutputForTesting(session);
        final restoreAfterFirstFlush =
            pendingRestoreTerminalOutputCharsForTesting(session);

        const oldLivePrefix = '$oldLiveMarker\r\n';
        final oldLive =
            oldLivePrefix +
            _terminalRestorePayload(128 * 1024 - oldLivePrefix.length, '');
        final newLive = _terminalRestorePayload(
          1200 * 1024,
          '$newLiveMarker\r\n',
        );
        fakeSession.emitOutput(utf8.encode(oldLive));
        fakeSession.emitOutput(utf8.encode(newLive));
        await Future.pause(.zero);

        expect(
          pendingRestoreTerminalOutputCharsForTesting(session),
          restoreAfterFirstFlush,
        );
        expect(
          pendingLiveTerminalOutputCharsForTesting(session),
          lessThanOrEqualTo(1024 * 1024),
        );
        expect(terminalPointerInputSuspendedForTesting(session), isTrue);

        while (pendingRestoreTerminalOutputCharsForTesting(session) > 0) {
          flushTerminalOutputForTesting(session);
        }
        expect(session.restoreProgress.value, isNull);
        expect(terminalPointerInputSuspendedForTesting(session), isTrue);

        while (pendingTerminalOutputCharsForTesting(session) > 0) {
          flushTerminalOutputForTesting(session);
        }

        final text = terminalBufferTextForTesting(session);
        expect(terminalPointerInputSuspendedForTesting(session), isFalse);
        expect(text, contains(snapshotMarker));
        expect(text, isNot(contains(oldLiveMarker)));
        expect(text, contains(newLiveMarker));
        expect(terminalMouseModeForTesting(session), xterm.MouseMode.none);
        expect(terminalBracketedPasteModeForTesting(session), isFalse);
      } finally {
        visibility.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('a snapshot reschedules the deferred flush it replaces', (
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
      await session.ensureStarted();
      queueTerminalOutputForTesting(session, 'first');
      await tester.pump();
      expect(pendingTerminalOutputCharsForTesting(session), 0);
      queueTerminalOutputForTesting(session, 'pending before replacement');
      forceDeferredTerminalOutputFlushForTesting(session);
      expect(terminalOutputFlushDeferredForTesting(session), isTrue);

      const replacement = 'replacement snapshot';
      fakeSession.emitSnapshot(utf8.encode(replacement));
      await tester.pump(terminalOutputMinFlushIntervalForTesting * 2);

      expect(pendingRestoreTerminalOutputCharsForTesting(session), 0);
      expect(session.restoreProgress.value, isNull);
      expect(terminalBufferTextForTesting(session), contains(replacement));
    } finally {
      visibility.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
