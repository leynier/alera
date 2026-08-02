part of 'terminal_runtime_native_test.dart';

/// Grows a terminal's scrollback so the budget has something to weigh.
void _fillScrollback(TerminalSessionHandle session, {int lines = 4000}) {
  queueTerminalOutputForTesting(session, '\n' * lines);
  flushTerminalOutputForTesting(session);
}

/// PTY teardown runs off the event loop, so poll rather than guess a delay.
Future<void> _settleUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
}

/// Starts a terminal the way the app does, fills its scrollback, and then
/// takes it off screen, which is what makes it an eviction candidate.
///
/// Starting needs a desktop platform, since `ensureStarted` refuses to build a
/// PTY anywhere else. Tests that only care about handle bookkeeping use
/// [_fillAndHide] instead and skip the PTY entirely.
Future<void> _startFillAndHide(TerminalSessionHandle session) async {
  final visibility = acquireTerminalVisibilityForTesting(session);
  await session.ensureStarted();
  _fillScrollback(session);
  visibility.dispose();
}

void _fillAndHide(TerminalSessionHandle session) {
  final visibility = acquireTerminalVisibilityForTesting(session);
  _fillScrollback(session);
  visibility.dispose();
}

void _registerTerminalBufferEvictionTests() {
  test('a cold terminal is evicted without terminating its PTY', () async {
    // The property the whole policy rests on: eviction detaches, so the agent
    // in that terminal keeps running on the host and its scrollback comes back
    // from the host snapshot on return.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final cold = _FakeTerminalPtySession();
    final warm = _FakeTerminalPtySession();
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[cold, warm],
      ),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);

    final coldSession = runtime.sessionFor(
      workspace: _workspace(id: 'workspace-1'),
      tab: _tab(id: 'tab-1', workspaceId: 'workspace-1'),
    );
    await _startFillAndHide(coldSession);

    final warmSession = runtime.sessionFor(
      workspace: _workspace(id: 'workspace-2'),
      tab: _tab(id: 'tab-2', workspaceId: 'workspace-2'),
    );
    await _startFillAndHide(warmSession);

    runtime.setActiveWorkspace('workspace-2');
    final oneTerminal = coldSession.bufferUsage.bytes;
    expect(oneTerminal, greaterThan(0), reason: 'scrollback should have grown');

    // A budget that fits one terminal but not both.
    runtime.updateSettings(
      TerminalSettings.defaults.copyWith(
        bufferBudgetMegabytes: (oneTerminal * 1.5) ~/ (1024 * 1024) + 1,
      ),
    );

    expect(runtime.peekSession('tab-1'), isNull, reason: 'cold tab evicted');
    expect(runtime.peekSession('tab-2'), isNotNull, reason: 'active workspace');
    await _settleUntil(() => cold.disposed);
    expect(cold.disposed, isTrue, reason: 'the client detaches');
    expect(cold.terminated, isFalse, reason: 'the agent must keep running');
  });

  test(
    'off-screen terminals in the active workspace still obey the budget',
    () {
      final first = _FakeTerminalPtySession();
      final second = _FakeTerminalPtySession();
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: _FakeTerminalPtySessionFactory(
          sessions: <_FakeTerminalPtySession>[first, second],
        ),
        shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
          _launch('shell', shell: '/bin/sh'),
        ],
      );
      addTearDown(runtime.dispose);

      for (final id in <String>['tab-1', 'tab-2']) {
        final session = runtime.sessionFor(
          workspace: _workspace(id: 'workspace-1'),
          tab: _tab(id: id, workspaceId: 'workspace-1'),
        );
        _fillAndHide(session);
      }

      runtime.setActiveWorkspace('workspace-1');
      runtime.updateSettings(
        TerminalSettings.defaults.copyWith(bufferBudgetMegabytes: 1),
      );

      expect(runtime.peekSession('tab-1'), isNull);
      expect(runtime.peekSession('tab-2'), isNull);
    },
  );

  test('a terminal pane currently on screen is never evicted', () {
    final coldPty = _FakeTerminalPtySession();
    final visiblePty = _FakeTerminalPtySession();
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[coldPty, visiblePty],
      ),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);

    final cold = runtime.sessionFor(
      workspace: _workspace(id: 'workspace-1'),
      tab: _tab(id: 'tab-1', workspaceId: 'workspace-1'),
    );
    _fillAndHide(cold);
    final visible = runtime.sessionFor(
      workspace: _workspace(id: 'workspace-1'),
      tab: _tab(id: 'tab-2', workspaceId: 'workspace-1'),
    );
    final visibility = acquireTerminalVisibilityForTesting(visible);
    addTearDown(visibility.dispose);
    _fillScrollback(visible);

    runtime.updateSettings(
      TerminalSettings.defaults.copyWith(bufferBudgetMegabytes: 1),
    );

    expect(runtime.peekSession('tab-1'), isNull);
    expect(runtime.peekSession('tab-2'), same(visible));
  });

  test('a zero budget keeps every terminal alive', () {
    final pty = _FakeTerminalPtySession();
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[pty],
      ),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);

    final session = runtime.sessionFor(
      workspace: _workspace(id: 'workspace-1'),
      tab: _tab(id: 'tab-1', workspaceId: 'workspace-1'),
    );
    _fillAndHide(session);

    runtime.setActiveWorkspace('workspace-2');
    runtime.updateSettings(
      TerminalSettings.defaults.copyWith(bufferBudgetMegabytes: 0),
    );

    expect(runtime.peekSession('tab-1'), isNotNull);
  });

  test('returning to an evicted tab builds a fresh handle', () {
    final original = _FakeTerminalPtySession();
    final replacement = _FakeTerminalPtySession();
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[original, replacement],
      ),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);

    final tab = _tab(id: 'tab-1', workspaceId: 'workspace-1');
    final session = runtime.sessionFor(
      workspace: _workspace(id: 'workspace-1'),
      tab: tab,
    );
    _fillAndHide(session);

    runtime.setActiveWorkspace('workspace-2');
    runtime.updateSettings(
      TerminalSettings.defaults.copyWith(bufferBudgetMegabytes: 1),
    );
    expect(runtime.peekSession('tab-1'), isNull);

    final restored = runtime.sessionFor(
      workspace: _workspace(id: 'workspace-1'),
      tab: tab,
    );

    expect(identical(restored, session), isFalse);
    expect(runtime.peekSession('tab-1'), isNotNull);
  });

  test('peekSession never creates a handle', () {
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: _FakeTerminalPtySessionFactory(),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);

    expect(runtime.peekSession('never-opened'), isNull);
    expect(runtime.peekSession('never-opened'), isNull);
  });
}
