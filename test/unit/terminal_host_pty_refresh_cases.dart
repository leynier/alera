part of 'terminal_host_pty_session_test.dart';

void _registerTerminalHostPtyRefreshTests() {
  test('host PTY session pulses and restores the viewport in order', () async {
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

    await session.start(
      launch: _launch(),
      workingDirectory: '/repo',
      cols: 80,
      rows: 24,
    );
    await session.refreshViewport(120, 40, 8, 16);

    expect(client.resizes, <(String, int, int)>[
      ('session-1', 119, 40),
      ('session-1', 120, 40),
    ]);
    expect(client.writes, isEmpty);
    expect(client.restarted, isEmpty);
    expect(client.terminated, isEmpty);

    client.resizes.clear();
    await session.refreshViewport(1, 1, 8, 16);

    expect(client.resizes, <(String, int, int)>[
      ('session-1', 2, 1),
      ('session-1', 1, 1),
    ]);

    client.resizeErrors.add(StateError('resize failed'));
    client.resizes.clear();
    await session.refreshViewport(80, 24, 8, 16);

    expect(client.resizes, <(String, int, int)>[('session-1', 80, 24)]);

    client.resizes.clear();
    final refresh = session.refreshViewport(100, 30, 8, 16);
    session.resize(130, 50, 8, 16);
    await refresh;
    await _flushAsync();

    expect(client.resizes, <(String, int, int)>[
      ('session-1', 99, 30),
      ('session-1', 100, 30),
      ('session-1', 130, 50),
    ]);
  });
}
