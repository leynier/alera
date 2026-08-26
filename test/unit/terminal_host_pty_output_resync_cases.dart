part of 'terminal_host_pty_session_test.dart';

void _registerTerminalHostPtyOutputResyncTests() {
  test('host PTY session resyncs after output backpressure', () async {
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
    final events = <TerminalPtySessionEvent>[];
    final sub = session.events.listen(events.add);
    addTearDown(sub.cancel);
    await session.start(
      launch: _launch(),
      workingDirectory: '/repo',
      cols: 80,
      rows: 24,
    );

    client.emit(const TerminalHostOutputResyncRequiredEvent('session-1'));
    await _flushAsync();

    expect(client.outputPaused, <(String, bool)>[('session-1', false)]);
    // The resync costs a delta on the output lane, not another full replay:
    // replaying the scrollback is what slowed the client into the next resync.
    expect(events.whereType<TerminalPtySnapshotEvent>(), hasLength(1));
  });

  test('serializes output resync behind a resize reattach', () async {
    final client = FakeTerminalHostClient(
      attachment: TerminalHostAttachment(
        sessionId: 'session-1',
        created: true,
        running: true,
        snapshot: Uint8List(0),
      ),
      attachments: <TerminalHostAttachment>[
        TerminalHostAttachment(
          sessionId: 'session-1',
          created: true,
          running: true,
          snapshot: Uint8List(0),
        ),
        TerminalHostAttachment(
          sessionId: 'session-1',
          created: false,
          running: true,
          snapshot: Uint8List(0),
        ),
      ],
    );
    client.reattachCompleter = Completer<void>();
    client.resizeErrors.add(
      StateError('Terminal session is not attached: session-1'),
    );
    final session = TerminalHostPtySession(
      client: client,
      sessionId: 'session-1',
      workspaceId: 'workspace-1',
      tabId: 'tab-1',
    );
    addTearDown(session.dispose);
    final events = <TerminalPtySessionEvent>[];
    final sub = session.events.listen(events.add);
    addTearDown(sub.cancel);

    await session.start(
      launch: _launch(),
      workingDirectory: '/repo',
      cols: 80,
      rows: 24,
    );
    session.resize(120, 40, 8, 16);
    client.emit(const TerminalHostOutputResyncRequiredEvent('session-1'));
    await _flushAsync();

    expect(client.attachCalls, hasLength(2));
    expect(client.outputPaused, isEmpty);

    client.reattachCompleter!.complete();
    await _flushAsync();

    expect(client.resizes, <(String, int, int)>[('session-1', 120, 40)]);
    expect(client.outputPaused, <(String, bool)>[('session-1', false)]);
    expect(events.whereType<TerminalPtyErrorEvent>(), isEmpty);
  });

  test(
    'hidden host PTY defers output resync until it becomes visible',
    () async {
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
      await session.setOutputPaused(true);

      client.emit(const TerminalHostOutputResyncRequiredEvent('session-1'));
      await _flushAsync();

      expect(client.outputPaused, <(String, bool)>[('session-1', true)]);
      await session.setOutputPaused(false);
      expect(client.outputPaused.last, ('session-1', false));
    },
  );
}
