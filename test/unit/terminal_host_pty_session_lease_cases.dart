part of 'terminal_host_pty_session_test.dart';

void _registerTerminalHostPtySessionLeaseTests() {
  test('factory creates sessions with the provided ids', () {
    final client = FakeTerminalHostClient(
      attachment: TerminalHostAttachment(
        sessionId: 'session-1',
        created: true,
        running: true,
        snapshot: Uint8List(0),
      ),
    );
    final factory = TerminalHostPtySessionFactory(client: client);

    final session = factory.create(
      sessionId: 'session-1',
      workspaceId: 'workspace-1',
      tabId: 'tab-1',
    );
    addTearDown(session.dispose);

    expect(session, isA<TerminalHostPtySession>());
  });

  test('replacement session keeps the shared host attachment alive', () async {
    final client = FakeTerminalHostClient(
      attachment: TerminalHostAttachment(
        sessionId: 'session-1',
        created: false,
        running: true,
        snapshot: Uint8List(0),
      ),
    );
    final factory = TerminalHostPtySessionFactory(client: client);
    final previous = factory.create(
      sessionId: 'session-1',
      workspaceId: 'workspace-1',
      tabId: 'tab-1',
    );
    final replacement = factory.create(
      sessionId: 'session-1',
      workspaceId: 'workspace-1',
      tabId: 'tab-1',
    );
    addTearDown(previous.dispose);
    addTearDown(replacement.dispose);

    await previous.start(
      launch: _launch(),
      workingDirectory: '/repo',
      cols: 80,
      rows: 24,
    );
    await replacement.start(
      launch: _launch(),
      workingDirectory: '/repo',
      cols: 80,
      rows: 24,
    );

    previous.dispose();
    await _flushAsync();

    expect(client.detached, isEmpty);
    expect(replacement.writeBytes(<int>[7]), isTrue);
    await _flushAsync();
    expect(client.writes, <List<int>>[
      <int>[7],
    ]);

    replacement.dispose();
    await _flushAsync();
    expect(client.detached, <String>['session-1']);
  });
}
