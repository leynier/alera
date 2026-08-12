part of 'terminal_host_pty_session_test.dart';

void _registerTerminalHostPtyPulseTests() {
  test('host PTY session forwards Terminal Pulse state changes', () async {
    final client = FakeTerminalHostClient(
      attachment: TerminalHostAttachment(
        sessionId: 'session-1',
        created: true,
        running: true,
        snapshot: Uint8List(0),
      ),
    );
    final session = TerminalHostPtySession(
      client: client,
      sessionId: 'session-1',
      workspaceId: 'workspace-1',
      tabId: 'tab-1',
    );
    addTearDown(session.dispose);
    final pulseEvent = session.events
        .where((event) => event is TerminalPtyPulseChangedEvent)
        .cast<TerminalPtyPulseChangedEvent>()
        .first;
    await session.start(
      launch: _launch(),
      workingDirectory: '/repo',
      cols: 80,
      rows: 24,
    );

    const state = TerminalPulseState(
      configuration: TerminalPulseConfiguration(),
      armed: false,
      error: 'watcher stopped',
    );
    client.emit(const TerminalHostPulseChangedEvent('session-1', state));

    expect((await pulseEvent).state.error, 'watcher stopped');
  });
}
