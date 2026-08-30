part of 'terminal_runtime_native_test.dart';

void _registerTerminalRuntimePulseTests() {
  test('exit during initial pulse refresh keeps the session stopped', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final delayedStatus = Completer<TerminalPulseState>();
    final pty = _FakeRecoverablePulseTerminalPtySession(
      delayedStatus,
      delayInitialStatus: true,
    );
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[pty],
      ),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
    try {
      final startup = session.ensureStarted();
      while (pty.statusCalls == 0) {
        await Future.pause(.zero);
      }
      pty.emitExit(7);
      await Future.pause(.zero);
      delayedStatus.complete(_pulseState);
      await startup;

      expect(session.isRunning, isFalse);
      expect(session.supportsTerminalPulse, isFalse);
      expect(session.terminalPulseState.value.armed, isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('exit during pulse refresh keeps a recovered session stopped', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final delayedStatus = Completer<TerminalPulseState>();
    final pty = _FakeRecoverablePulseTerminalPtySession(delayedStatus);
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[pty],
      ),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
    try {
      await session.ensureStarted();
      expect(session.isRunning, isTrue);
      expect(session.supportsTerminalPulse, isTrue);

      final restart = session.restart();
      while (pty.statusCalls < 2) {
        await Future.pause(.zero);
      }
      pty.emitExit(7);
      await Future.pause(.zero);
      expect(session.isRunning, isFalse);
      expect(session.supportsTerminalPulse, isFalse);
      expect(session.terminalPulseState.value.armed, isFalse);

      delayedStatus.complete(_pulseState);
      await restart;

      expect(session.isRunning, isFalse);
      expect(session.supportsTerminalPulse, isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('failed restart preserves the armed pulse state', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final pty = _FakeRecoverablePulseTerminalPtySession(
      Completer<TerminalPulseState>(),
      initialStatus: _armedPulseState,
      restartError: StateError('restart failed'),
    );
    final runtime = XtermTerminalRuntime(
      ptySessionFactory: _FakeTerminalPtySessionFactory(
        sessions: <_FakeTerminalPtySession>[pty],
      ),
      shellLaunchesBuilder: () => <GhosttyTerminalShellLaunch>[
        _launch('shell', shell: '/bin/sh'),
      ],
    );
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
    try {
      await session.ensureStarted();
      expect(session.terminalPulseState.value.armed, isTrue);

      await session.restart();

      expect(session.terminalPulseState.value.armed, isTrue);
      expect(session.errorMessage, contains('restart failed'));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

const TerminalPulseState _pulseState = TerminalPulseState(
  configuration: TerminalPulseConfiguration(
    command: 'r',
    appendEnter: true,
    delayMilliseconds: 2000,
  ),
  armed: false,
);

const TerminalPulseState _armedPulseState = TerminalPulseState(
  configuration: TerminalPulseConfiguration(
    command: 'r',
    appendEnter: true,
    delayMilliseconds: 2000,
  ),
  armed: true,
);

class _FakeRecoverablePulseTerminalPtySession(
  final Completer<TerminalPulseState> delayedStatus, {
  final bool delayInitialStatus = false,
  final TerminalPulseState initialStatus = _pulseState,
  final Object? restartError,
}) extends _FakeTerminalPtySession
    implements RecoverableTerminalPtySession, TerminalPulsePtySession {
  int statusCalls = 0;

  @override
  bool get supportsRestart => true;

  @override
  bool get supportsTerminalPulse => true;

  @override
  Future<void> reconnect() async {}

  @override
  Future<void> restartProcess() async {
    final error = restartError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<TerminalPulseState> terminalPulseStatus() {
    statusCalls += 1;
    return !delayInitialStatus && statusCalls == 1
        ? Future<TerminalPulseState>.value(initialStatus)
        : delayedStatus.future;
  }

  @override
  Future<TerminalPulseState> configureTerminalPulse({
    required TerminalPulseConfiguration configuration,
    required bool armed,
  }) async {
    return TerminalPulseState(configuration: configuration, armed: armed);
  }
}
