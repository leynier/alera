part of 'terminal_runtime_native_test.dart';

void _registerXtermRuntimeSessionTests() {
  test('batches visible output until a frame flush', () {
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: _FakeTerminalPtySessionFactory(),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());

    queueTerminalOutputForTesting(session, 'hello');
    expect(terminalBufferTextForTesting(session), isNot(contains('hello')));

    flushTerminalOutputForTesting(session);
    expect(terminalBufferTextForTesting(session), contains('hello'));
  });

  test('terminal output frame cutoff preserves surrogate pairs', () {
    final longText = '${'a' * (64 * 1024 - 1)}😀tail';

    expect(terminalOutputFrameCutoffForTesting(longText), 64 * 1024 - 1);
  });

  test(
    'reuses sessions, syncs metadata, and flushes pending resizes',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final startCompleter = Completer<void>();
      final fakeSession = _FakeTerminalPtySession(
        startCompleter: startCompleter,
      );
      final factory = _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[fakeSession],
      );
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: factory,
        shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
          _launch('shell', shell: '/bin/sh'),
        ],
      );
      addTearDown(runtime.dispose);
      final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
      var notifications = 0;
      session.addListener(() => notifications++);
      try {
        expect(session.tabId, 'tab-1');
        expect(session.workspaceId, 'workspace-1');
        expect(session.displayTitle, 'Terminal 1');
        expect(session.isStarting, isFalse);
        expect(session.errorMessage, isNull);

        setTerminalTitleForTesting(session, 'Runtime title');
        expect(session.displayTitle, 'Runtime title');

        final firstStart = session.ensureStarted();
        final secondStart = session.ensureStarted();
        expect(session.isStarting, isTrue);
        startCompleter.complete();
        await Future.wait(<Future<void>>[firstStart, secondStart]);
        await session.ensureStarted();

        expect(factory.createdSessions, hasLength(1));
        expect(session.isRunning, isTrue);

        handleTerminalResizeForTesting(session, 120, 40, 8, 16);
        flushPendingPtyResizeForTesting(session);
        expect(fakeSession.resizeCalls, <_ResizeCall>[
          const _ResizeCall(
            cols: 120,
            rows: 40,
            cellWidthPx: 8,
            cellHeightPx: 16,
          ),
        ]);

        writeTerminalOutputForTesting(session, 'hello');
        writeTerminalOutputForTesting(session, '');

        final updatedSession = runtime.sessionFor(
          workspace: _workspace(path: '/repo/updated'),
          tab: _tab(
            title: 'Pinned title',
            payload: const <String, Object?>{
              workspaceTabManualTitlePayloadKey: true,
            },
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(identical(updatedSession, session), isTrue);
        expect(session.displayTitle, 'Pinned title');
        expect(notifications, greaterThan(0));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  test('defers PTY resize and input until startup finishes', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final startCompleter = Completer<void>();
    final fakeSession = _FakeTerminalPtySession(startCompleter: startCompleter);
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
      final start = session.ensureStarted();
      await Future<void>.delayed(Duration.zero);

      handleTerminalResizeForTesting(session, 100, 30, 8, 16);
      handleTerminalResizeForTesting(session, 120, 40, 8, 16);
      flushPendingPtyResizeForTesting(session);
      feedTerminalInputForTesting(session, 'early input');

      expect(fakeSession.resizeCalls, isEmpty);
      expect(fakeSession.writes, isEmpty);
      expect(fakeSession.outputPausedCalls, isEmpty);
      expect(
        terminalBufferTextForTesting(session),
        isNot(contains('PTY session has not been started')),
      );

      startCompleter.complete();
      await start;

      expect(fakeSession.resizeCalls, <_ResizeCall>[
        const _ResizeCall(
          cols: 120,
          rows: 40,
          cellWidthPx: 8,
          cellHeightPx: 16,
        ),
      ]);
      expect(session.isRunning, isTrue);
      expect(session.errorMessage, isNull);
    } finally {
      visibility?.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test(
    'closes tabs and workspaces without disposing unrelated sessions',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final first = _FakeTerminalPtySession();
      final second = _FakeTerminalPtySession();
      final third = _FakeTerminalPtySession();
      final factory = _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[first, second, third],
      );
      final cleanedTerminalSessionIds = <String>[];
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: factory,
        shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
          _launch('shell', shell: '/bin/sh'),
        ],
        terminalSessionCleanup: cleanedTerminalSessionIds.add,
      );
      addTearDown(runtime.dispose);
      try {
        final firstSession = runtime.sessionFor(
          workspace: _workspace(),
          tab: _tab(),
        );
        final secondSession = runtime.sessionFor(
          workspace: _workspace(),
          tab: _tab(id: 'tab-2', title: 'Terminal 2'),
        );
        final thirdSession = runtime.sessionFor(
          workspace: _workspace(id: 'workspace-2', path: '/repo/other'),
          tab: _tab(
            id: 'tab-3',
            workspaceId: 'workspace-2',
            title: 'Terminal 3',
          ),
        );

        await firstSession.ensureStarted();
        await secondSession.ensureStarted();
        await thirdSession.ensureStarted();

        runtime.closeTab('tab-1');
        await Future<void>.delayed(Duration.zero);
        expect(first.disposed, isTrue);
        expect(first.terminated, isTrue);
        expect(second.disposed, isFalse);
        expect(third.disposed, isFalse);
        expect(cleanedTerminalSessionIds, <String>['tab-1']);

        runtime.closeWorkspace('workspace-1');
        await Future<void>.delayed(Duration.zero);
        expect(second.disposed, isTrue);
        expect(second.terminated, isTrue);
        expect(third.disposed, isFalse);
        expect(cleanedTerminalSessionIds, <String>['tab-1', 'tab-2']);

        runtime.dispose();
        await Future<void>.delayed(Duration.zero);
        expect(third.disposed, isTrue);
        expect(third.terminated, isFalse);
        expect(cleanedTerminalSessionIds, <String>['tab-1', 'tab-2']);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  test(
    'keeps output visible until every visibility lease is released',
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
      TerminalVisibilityLease? firstVisibility;
      TerminalVisibilityLease? secondVisibility;
      try {
        firstVisibility = acquireTerminalVisibilityForTesting(session);
        secondVisibility = acquireTerminalVisibilityForTesting(session);
        await session.ensureStarted();

        firstVisibility.dispose();
        firstVisibility = null;
        await Future<void>.delayed(Duration.zero);
        expect(fakeSession.outputPausedCalls, isEmpty);

        fakeSession.emitOutput(utf8.encode('still-visible\r\n'));
        await Future<void>.delayed(Duration.zero);
        flushTerminalOutputForTesting(session);
        expect(
          terminalBufferTextForTesting(session),
          contains('still-visible'),
        );

        secondVisibility.dispose();
        secondVisibility = null;
        await Future<void>.delayed(Duration.zero);
        expect(fakeSession.outputPausedCalls, <bool>[true]);
      } finally {
        firstVisibility?.dispose();
        secondVisibility?.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  test('hidden terminal exits still notify the runtime', () async {
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
    final exits = <TerminalRuntimeExitEvent>[];
    final exitSub = runtime.exits.listen(exits.add);
    addTearDown(exitSub.cancel);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
    TerminalVisibilityLease? visibility;
    try {
      visibility = acquireTerminalVisibilityForTesting(session);
      await session.ensureStarted();
      fakeSession.emitOutput(
        utf8.encode('\x1b[?1h\x1b[?25l\x1b[?1004h\x1b=\x1b[?1049h\x1b[?1000h'),
      );
      await Future<void>.delayed(Duration.zero);
      flushTerminalOutputForTesting(session);
      expect(terminalMouseModeForTesting(session), isNot(xterm.MouseMode.none));
      expect(terminalCursorKeysModeForTesting(session), isTrue);
      expect(terminalCursorVisibleModeForTesting(session), isFalse);
      expect(terminalReportFocusModeForTesting(session), isTrue);
      expect(terminalAppKeypadModeForTesting(session), isTrue);
      expect(terminalIsUsingAltBufferForTesting(session), isTrue);
      visibility.dispose();
      visibility = null;
      await Future<void>.delayed(Duration.zero);

      fakeSession.emitExit(12);
      await Future<void>.delayed(Duration.zero);

      expect(session.isRunning, isFalse);
      expect(exits, hasLength(1));
      expect(exits.single.exitCode, 12);
      expect(terminalMouseModeForTesting(session), xterm.MouseMode.none);
      expect(terminalCursorKeysModeForTesting(session), isFalse);
      expect(terminalCursorVisibleModeForTesting(session), isTrue);
      expect(terminalReportFocusModeForTesting(session), isFalse);
      expect(terminalAppKeypadModeForTesting(session), isFalse);
      expect(terminalIsUsingAltBufferForTesting(session), isFalse);
      expect(fakeSession.disposed, isTrue);
      expect(fakeSession.terminated, isFalse);
    } finally {
      visibility?.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test(
    'unsupported mobile platforms fail before creating PTY sessions',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final factory = _FakeTerminalPtySessionFactory();
        final runtime = XtermTerminalRuntime(
          ptySessionFactory: factory,
          shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
            _launch('noop', shell: '/bin/sh'),
          ],
        );
        addTearDown(runtime.dispose);
        final session = runtime.sessionFor(
          workspace: _workspace(),
          tab: _tab(),
        );

        await session.ensureStarted();

        expect(factory.createdSessions, isEmpty);
        expect(session.isRunning, isFalse);
        expect(session.errorMessage, contains('native desktop PTY path'));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  test(
    'falls back to the next shell launch and writes setup commands',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final first = _FakeTerminalPtySession(
        startError: StateError('first failed'),
      );
      final second = _FakeTerminalPtySession();
      final factory = _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[first, second],
      );
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: factory,
        shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
          _launch('first', shell: '/bin/first'),
          _launch(
            'second',
            shell: '/bin/second',
            arguments: const <String>['-l'],
            setupCommand: 'printf setup\n',
          ),
        ],
      );
      addTearDown(runtime.dispose);
      final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
      try {
        final startFuture = session.ensureStarted();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await startFuture;

        expect(session.errorMessage, isNull);
        expect(session.isRunning, isTrue);
        expect(first.disposed, isTrue);
        expect(second.startedLaunch, isNotNull);
        expect(second.startedLaunch!.label, 'second');
        expect(second.startedLaunch!.shell, '/bin/sh');
        expect(
          second.startedLaunch!.arguments.last,
          contains(_workspace().path),
        );
        expect(
          second.writes.map(utf8.decode).join(),
          contains('printf setup\n'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  test(
    'prepares Codex launches without writing restore setup commands',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final fakeSession = _FakeTerminalPtySession();
      final shellStartupPreparer = _RecordingTerminalShellStartupPreparer();
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: _FakeTerminalPtySessionFactory(
          sessions: <_FakeTerminalPtySession>[fakeSession],
        ),
        shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
          _launch('shell', shell: '/bin/zsh', setupCommand: 'printf setup\n'),
        ],
        shellStartupPreparer: shellStartupPreparer,
        agentHookEnvironmentBuilder:
            ({
              required terminalSessionId,
              required workspaceId,
              required tabId,
            }) {
              return const <String, String>{
                'CODEX_HOME': '/runtime/codex',
                'ALERA_CODEX_HOME': '/runtime/codex',
              };
            },
      );
      addTearDown(runtime.dispose);
      final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
      try {
        await session.ensureStarted();

        final startedSetupCommand = fakeSession.startedLaunch!.setupCommand;
        expect(startedSetupCommand, 'printf setup\n');
        final writtenSetupCommand = fakeSession.writes.map(utf8.decode).join();
        expect(writtenSetupCommand, startedSetupCommand);
        expect(shellStartupPreparer.launches, hasLength(1));
        expect(
          shellStartupPreparer.launches.single.environment,
          containsPair('ALERA_CODEX_HOME', '/runtime/codex'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  test(
    'prepares PowerShell working directory without writing setup commands',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final fakeSession = _FakeTerminalPtySession();
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: _FakeTerminalPtySessionFactory(
          sessions: <_FakeTerminalPtySession>[fakeSession],
        ),
        shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
          _launch(
            'PowerShell 7',
            shell: r'C:\Program Files\PowerShell\7\pwsh.exe',
          ),
        ],
        shellStartupPreparer: AleraTerminalShellStartupPreparer(),
      );
      addTearDown(runtime.dispose);
      final session = runtime.sessionFor(
        workspace: _workspace(path: r"C:\Users\O'Brien\Alera Workspace"),
        tab: _tab(),
      );
      try {
        await session.ensureStarted();

        final startedLaunch = fakeSession.startedLaunch;
        expect(startedLaunch, isNotNull);
        expect(startedLaunch!.setupCommand, isNull);
        expect(fakeSession.writes, isEmpty);
        expect(
          startedLaunch.arguments,
          containsAllInOrder(<String>['-NoLogo', '-NoExit', '-EncodedCommand']),
        );
        final encodedCommand = startedLaunch
            .arguments[startedLaunch.arguments.indexOf('-EncodedCommand') + 1];
        final script = _decodePowerShellEncodedCommand(encodedCommand);
        expect(
          script,
          contains(
            "Set-Location -LiteralPath 'C:\\Users\\O''Brien\\Alera Workspace'\r\n",
          ),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  test('surfaces a clear error when every shell launch fails', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final factory = _FakeTerminalPtySessionFactory(
      sessions: <_FakeTerminalPtySession>[
        _FakeTerminalPtySession(startError: StateError('first failed')),
        _FakeTerminalPtySession(startError: StateError('second failed')),
      ],
    );
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: factory,
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('first', shell: '/bin/first'),
        _launch('second', shell: '/bin/second'),
      ],
    );
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
    try {
      await session.ensureStarted();

      expect(factory.createdSessions, hasLength(2));
      expect(session.isRunning, isFalse);
      expect(
        session.errorMessage,
        contains('No desktop PTY shell could be started'),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test(
    'surfaces a clear Windows error when no shell can be resolved',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final factory = _FakeTerminalPtySessionFactory();
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: factory,
        shellLaunchesBuilder: () => const <GhosttyTerminalShellLaunch>[],
      );
      addTearDown(runtime.dispose);
      final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
      try {
        await session.ensureStarted();

        expect(factory.createdSessions, isEmpty);
        expect(session.isRunning, isFalse);
        expect(
          session.errorMessage,
          contains('No Windows terminal shell executable could be resolved'),
        );
        expect(session.errorMessage, isNot(contains(': null')));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  test(
    'does not replay setup commands when attaching existing sessions',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final attached = _FakeTerminalPtySession()
        ..startedNewProcessValue = false;
      final factory = _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[attached],
      );
      final createdSessions = <String>[];
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: factory,
        shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
          _launch('shell', shell: '/bin/sh', setupCommand: 'printf setup\n'),
        ],
        terminalProcessCreated: createdSessions.add,
      );
      addTearDown(runtime.dispose);
      try {
        final session = runtime.sessionFor(
          workspace: _workspace(),
          tab: _tab(
            payload: const <String, Object?>{
              workspaceTabTerminalSessionIdPayloadKey: 'session-1',
            },
          ),
        );

        await session.ensureStarted();

        expect(attached.startedWorkingDirectory, _workspace().path);
        expect(attached.writes, isEmpty);
        expect(createdSessions, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  test(
    'restart suppresses old generations and emits exits for the active one',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final first = _FakeTerminalPtySession();
      final second = _FakeTerminalPtySession();
      final factory = _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[first, second],
      );
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: factory,
        shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
          _launch('shell', shell: '/bin/sh'),
        ],
      );
      addTearDown(runtime.dispose);
      final exits = <TerminalRuntimeExitEvent>[];
      final exitSub = runtime.exits.listen(exits.add);
      addTearDown(exitSub.cancel);
      final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
      try {
        await session.ensureStarted();
        await session.restart();

        expect(factory.createdSessions, hasLength(2));
        expect(first.disposed, isTrue);
        expect(session.isRunning, isTrue);
        expect(exits, isEmpty);

        first.emitExit(9);
        await Future<void>.delayed(Duration.zero);
        expect(exits, isEmpty);

        second.emitExit(5);
        await Future<void>.delayed(Duration.zero);

        expect(exits, hasLength(1));
        expect(exits.single.exitCode, 5);
        expect(session.isRunning, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
