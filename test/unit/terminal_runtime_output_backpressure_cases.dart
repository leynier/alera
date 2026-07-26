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
}
