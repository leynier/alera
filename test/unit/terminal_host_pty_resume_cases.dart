part of 'terminal_host_pty_session_test.dart';

void _registerTerminalHostPtyResumeTests() {
  test('host PTY session resumes from a delta without a snapshot', () async {
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
    await session.setOutputPaused(true);
    await session.setOutputPaused(false);
    await _flushAsync();

    expect(client.outputPaused, <(String, bool)>[
      ('session-1', true),
      ('session-1', false),
    ]);
    // Only the attach snapshot. The missed bytes of a delta resume arrive on
    // the output lane, so the emulator is appended to, never rebuilt.
    final snapshots = events.whereType<TerminalPtySnapshotEvent>().toList();
    expect(snapshots, hasLength(1));
    expect(snapshots.single.data, isEmpty);
    expect(snapshots.single.resetInteractionModes, isTrue);
  });

  test(
    'host PTY session rebuilds when the host cannot serve a delta',
    () async {
      final client =
          FakeTerminalHostClient(
              attachment: TerminalHostAttachment(
                sessionId: 'session-1',
                created: true,
                running: true,
                snapshot: Uint8List(0),
              ),
            )
            ..resume = TerminalHostResume(
              isDelta: false,
              snapshot: .fromList(<int>[83, 78, 65, 80]),
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
      await session.setOutputPaused(false);
      await _flushAsync();

      final snapshots = events.whereType<TerminalPtySnapshotEvent>().toList();
      expect(snapshots, hasLength(2));
      expect(snapshots.last.data, <int>[83, 78, 65, 80]);
      expect(snapshots.last.resetInteractionModes, isFalse);
    },
  );

  test('a host without delta resumes still sends a full snapshot', () {
    // An older sidecar answers a resume with the scrollback and no `delta`
    // field. The app can attach to one, so absence must not read as a delta.
    final resume = TerminalHostResume.fromJson(<String, Object?>{
      'sessionId': 'session-1',
      'snapshotBase64': base64Encode(<int>[83, 78, 65, 80]),
    });

    expect(resume.isDelta, isFalse);
    expect(resume.snapshot, <int>[83, 78, 65, 80]);
  });
}
