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
        await Future<void>.delayed(Duration.zero);
      }
      pty.emitExit(7);
      await Future<void>.delayed(Duration.zero);
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
        await Future<void>.delayed(Duration.zero);
      }
      pty.emitExit(7);
      await Future<void>.delayed(Duration.zero);
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
}

const TerminalPulseState _pulseState = TerminalPulseState(
  configuration: TerminalPulseConfiguration(
    command: 'r',
    appendEnter: true,
    delayMilliseconds: 2000,
  ),
  armed: false,
);

class _FakeRecoverablePulseTerminalPtySession extends _FakeTerminalPtySession
    implements RecoverableTerminalPtySession, TerminalPulsePtySession {
  _FakeRecoverablePulseTerminalPtySession(
    this.delayedStatus, {
    this.delayInitialStatus = false,
  });

  final Completer<TerminalPulseState> delayedStatus;
  final bool delayInitialStatus;
  int statusCalls = 0;

  @override
  bool get supportsRestart => true;

  @override
  bool get supportsTerminalPulse => true;

  @override
  Future<void> reconnect() async {}

  @override
  Future<void> restartProcess() async {}

  @override
  Future<TerminalPulseState> terminalPulseStatus() {
    statusCalls += 1;
    return !delayInitialStatus && statusCalls == 1
        ? Future<TerminalPulseState>.value(_pulseState)
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
