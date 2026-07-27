import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_pty_session.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

import 'terminal_host_test_fakes.dart';

part 'terminal_host_pty_output_resync_cases.dart';
part 'terminal_host_pty_resume_cases.dart';

void main() {
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

  test(
    'host PTY session replays snapshots and suppresses restored exits',
    () async {
      final client = FakeTerminalHostClient(
        attachment: TerminalHostAttachment(
          sessionId: 'session-1',
          created: false,
          running: false,
          snapshot: Uint8List.fromList(<int>[65, 66]),
          exitCode: 0,
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
      await Future<void>.delayed(Duration.zero);

      expect(session.startedNewProcess, isFalse);
      expect(client.attachedWorkingDirectory, '/repo');
      final snapshot = events.whereType<TerminalPtySnapshotEvent>().single;
      expect(snapshot.data, <int>[65, 66]);
      expect(snapshot.resetInteractionModes, isTrue);
      final exit = events.whereType<TerminalPtyExitEvent>().single;
      expect(exit.exitCode, 0);
      expect(exit.notifyRuntime, isFalse);
    },
  );

  test(
    'host PTY session writes, resizes, detaches, and terminates by id',
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

      await session.start(
        launch: _launch(),
        workingDirectory: '/repo',
        cols: 80,
        rows: 24,
      );
      expect(session.startedNewProcess, isTrue);

      expect(session.writeBytes(<int>[1, 2]), isTrue);
      session.resize(120, 40, 8, 16);
      await Future<void>.delayed(Duration.zero);

      expect(client.writes, <List<int>>[
        <int>[1, 2],
      ]);
      expect(client.resizes, <(String, int, int)>[('session-1', 120, 40)]);

      session.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(client.detached, <String>['session-1']);

      final second = TerminalHostPtySession(
        client: client,
        sessionId: 'session-2',
        workspaceId: 'workspace-1',
        tabId: 'tab-2',
      );
      await second.start(
        launch: _launch(),
        workingDirectory: '/repo',
        cols: 80,
        rows: 24,
      );
      second.terminate();
      await Future<void>.delayed(Duration.zero);

      expect(client.terminated, <String>['session-2']);
    },
  );

  test(
    'reconnect attaches without restarting and restart is explicit',
    () async {
      final client = FakeTerminalHostClient(
        attachment: TerminalHostAttachment(
          sessionId: 'session-1',
          created: false,
          running: true,
          snapshot: Uint8List.fromList(<int>[65]),
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
      await session.reconnect();

      expect(client.attachCalls, hasLength(2));
      expect(client.restarted, isEmpty);

      await session.restartProcess();

      expect(session.supportsRestart, isTrue);
      expect(client.restarted, <String>['session-1']);
    },
  );

  _registerTerminalHostPtyResumeTests();

  _registerTerminalHostPtyOutputResyncTests();

  test(
    'host PTY session ignores host operations while startup is pending',
    () async {
      final attachCompleter = Completer<void>();
      final client = FakeTerminalHostClient(
        attachment: TerminalHostAttachment(
          sessionId: 'session-1',
          created: true,
          running: true,
          snapshot: Uint8List(0),
        ),
        attachCompleter: attachCompleter,
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

      final start = session.start(
        launch: _launch(),
        workingDirectory: '/repo',
        cols: 80,
        rows: 24,
      );
      await Future<void>.delayed(Duration.zero);

      expect(session.writeBytes(<int>[1]), isFalse);
      session.resize(100, 30, 8, 16);
      await session.setOutputPaused(true);
      await _flushAsync();

      expect(client.attachCalls, hasLength(1));
      expect(client.writes, isEmpty);
      expect(client.resizes, isEmpty);
      expect(client.outputPaused, isEmpty);
      expect(events.whereType<TerminalPtyErrorEvent>(), isEmpty);

      attachCompleter.complete();
      await start;

      expect(session.writeBytes(<int>[2]), isTrue);
      session.resize(120, 40, 8, 16);
      await session.setOutputPaused(false);
      await _flushAsync();

      expect(client.writes, <List<int>>[
        <int>[2],
      ]);
      expect(client.resizes, <(String, int, int)>[('session-1', 120, 40)]);
      expect(client.outputPaused, <(String, bool)>[('session-1', false)]);
      expect(events.whereType<TerminalPtyErrorEvent>(), isEmpty);
    },
  );

  test(
    'host PTY session reattaches with the latest size before resizing',
    () async {
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
            created: true,
            running: true,
            snapshot: Uint8List(0),
          ),
        ],
      );
      client.resizeErrors.add(
        StateError('Bad state: Terminal session is not attached: session-1'),
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
      session.resize(120, 40, 8, 16);
      await _flushAsync();

      expect(client.attachCalls, hasLength(2));
      expect(client.attachCalls.last.cols, 120);
      expect(client.attachCalls.last.rows, 40);
      expect(client.resizes, <(String, int, int)>[('session-1', 120, 40)]);
    },
  );

  test(
    'host PTY session never replays a write after connection loss',
    () async {
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
            created: true,
            running: true,
            snapshot: Uint8List(0),
          ),
        ],
      );
      client.writeErrors.add(
        StateError('Terminal host connection closed: reset'),
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
      expect(session.writeBytes(<int>[9]), isTrue);
      await _flushAsync();

      expect(client.attachCalls, hasLength(1));
      expect(client.writes, isEmpty);
      final error = events.whereType<TerminalPtyErrorEvent>().single.error;
      expect(
        error,
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Terminal host connection closed'),
        ),
      );
    },
  );

  test(
    'host PTY session forwards matching host events and write errors',
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
      final events = <TerminalPtySessionEvent>[];
      final sub = session.events.listen(events.add);
      addTearDown(sub.cancel);

      await session.start(
        launch: _launch(),
        workingDirectory: '/repo',
        cols: 80,
        rows: 24,
      );
      client.emit(TerminalHostOutputEvent('other-session', Uint8List(0)));
      client.emit(
        TerminalHostOutputEvent('session-1', Uint8List.fromList(<int>[67])),
      );
      client.emit(const TerminalHostExitEvent('session-1', 4));
      client.emit(const TerminalHostErrorEvent('session-1', 'host failed'));
      client.writeError = StateError('write failed');
      expect(session.writeBytes(<int>[9]), isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<TerminalPtyOutputEvent>().single.data, <int>[67]);
      expect(events.whereType<TerminalPtyExitEvent>().single.exitCode, 4);
      expect(
        events.whereType<TerminalPtyErrorEvent>().map((event) => event.error),
        containsAll(<Object>['host failed', isA<StateError>()]),
      );
    },
  );

  test('host PTY session keeps input backpressure non-fatal', () async {
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
    client.writeErrors.add(
      StateError('terminal_input_backpressure: terminal input queue is full'),
    );
    expect(session.writeBytes(<int>[1]), isTrue);
    client.emit(
      const TerminalHostErrorEvent(
        'session-1',
        'terminal_input_backpressure: terminal input queue is full',
      ),
    );
    await _flushAsync();

    expect(events.whereType<TerminalPtyErrorEvent>(), isEmpty);
    expect(client.attachCalls, hasLength(1));
    expect(session.writeBytes(<int>[2]), isTrue);
    await _flushAsync();
    expect(client.writes, <List<int>>[
      <int>[2],
    ]);
  });

  test('host PTY session rejects use after disposal', () async {
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

    session.dispose();
    session.dispose();

    expect(session.writeBytes(<int>[1]), isFalse);
    session.resize(80, 24, 8, 16);
    await expectLater(
      session.start(
        launch: _launch(),
        workingDirectory: '/repo',
        cols: 80,
        rows: 24,
      ),
      throwsStateError,
    );
  });
}

GhosttyTerminalShellLaunch _launch() {
  return const GhosttyTerminalShellLaunch(
    label: 'shell',
    shell: '/bin/sh',
    arguments: <String>['-l'],
    environment: <String, String>{'TERM': 'xterm-256color'},
  );
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
