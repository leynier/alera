part of 'terminal_runtime_native_test.dart';

void _registerTerminalRuntimeOutputBackpressureTests() {
  test('bounds pending terminal output during a burst', () {
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: _FakeTerminalPtySessionFactory(),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());

    queueTerminalOutputForTesting(session, 'a' * (1024 * 1024 + 64 * 1024));

    expect(
      pendingTerminalOutputCharsForTesting(session),
      lessThanOrEqualTo(1024 * 1024),
    );
  });

  test('drains a large chunk without recopying the pending head', () {
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: _FakeTerminalPtySessionFactory(),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());

    const frame = 64 * 1024;
    queueTerminalOutputForTesting(session, 'a' * (frame * 3));
    final queued = pendingTerminalOutputHeadChunkForTesting(session);

    for (var drained = 1; drained < 3; drained++) {
      flushTerminalOutputForTesting(session);
      expect(
        pendingTerminalOutputCharsForTesting(session),
        frame * (3 - drained),
      );
      expect(pendingTerminalOutputHeadForTesting(session), frame * drained);
      // The remainder must be the very same string, not a fresh substring:
      // re-queueing the tail is what made a snapshot replay quadratic.
      expect(
        identical(pendingTerminalOutputHeadChunkForTesting(session), queued),
        isTrue,
      );
    }

    flushTerminalOutputForTesting(session);
    expect(pendingTerminalOutputCharsForTesting(session), 0);
    expect(pendingTerminalOutputHeadChunkForTesting(session), isNull);
    expect(pendingTerminalOutputHeadForTesting(session), 0);
  });

  test('writes a multi-frame chunk through intact', () {
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: _FakeTerminalPtySessionFactory(),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());

    // The emoji straddles the 64 KiB frame boundary, so the head offset has to
    // back off a code unit without losing or duplicating it.
    queueTerminalOutputForTesting(
      session,
      '${'a' * (64 * 1024 - 1)}😀\r\ntail line\r\n',
    );
    while (pendingTerminalOutputCharsForTesting(session) > 0) {
      flushTerminalOutputForTesting(session);
    }

    final text = terminalBufferTextForTesting(session);
    expect(text, contains('😀'));
    expect(text, contains('tail line'));
  });

  test(
    'paces flushes under sustained output instead of one per frame',
    () async {
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: _FakeTerminalPtySessionFactory(),
        shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
          _launch('shell', shell: '/bin/sh'),
        ],
      );
      addTearDown(runtime.dispose);
      final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
      final visibility = acquireTerminalVisibilityForTesting(session);
      addTearDown(visibility.dispose);

      // A terminal that has been quiet flushes on the very next frame: the
      // cadence floor must not add latency to an echoed keystroke.
      queueTerminalOutputForTesting(session, 'first\r\n');
      expect(terminalOutputFlushScheduledForTesting(session), isTrue);
      expect(terminalOutputFlushDeferredForTesting(session), isFalse);

      flushTerminalOutputForTesting(session);

      // Output arriving right behind a flush waits out the floor rather than
      // driving another frame immediately.
      queueTerminalOutputForTesting(session, 'second\r\n');
      expect(terminalOutputFlushDeferredForTesting(session), isTrue);

      await Future<void>.delayed(terminalOutputMinFlushIntervalForTesting * 2);

      expect(terminalOutputFlushDeferredForTesting(session), isFalse);
      expect(terminalOutputFlushScheduledForTesting(session), isTrue);
    },
  );

  test('a deferred flush is dropped when the terminal goes hidden', () async {
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: _FakeTerminalPtySessionFactory(),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
    final visibility = acquireTerminalVisibilityForTesting(session);

    queueTerminalOutputForTesting(session, 'first\r\n');
    flushTerminalOutputForTesting(session);
    queueTerminalOutputForTesting(session, 'second\r\n');
    expect(terminalOutputFlushDeferredForTesting(session), isTrue);

    visibility.dispose();
    await Future<void>.delayed(terminalOutputMinFlushIntervalForTesting * 2);

    // The backlog is kept, but a hidden terminal must not pay frame time for
    // it; it drains when it becomes visible again.
    expect(terminalOutputFlushScheduledForTesting(session), isFalse);
    expect(pendingTerminalOutputCharsForTesting(session), greaterThan(0));
  });
}
