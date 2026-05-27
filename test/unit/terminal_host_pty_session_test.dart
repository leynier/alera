import 'dart:async';
import 'dart:typed_data';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_pty_session.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

void main() {
  test('factory creates sessions with the provided ids', () {
    final client = _FakeTerminalHostClient(
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
      final client = _FakeTerminalHostClient(
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
      expect(events.whereType<TerminalPtyOutputEvent>().single.data, <int>[
        65,
        66,
      ]);
      final exit = events.whereType<TerminalPtyExitEvent>().single;
      expect(exit.exitCode, 0);
      expect(exit.notifyRuntime, isFalse);
    },
  );

  test(
    'host PTY session writes, resizes, detaches, and terminates by id',
    () async {
      final client = _FakeTerminalHostClient(
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
    'host PTY session reattaches and retries writes after stale host state',
    () async {
      final client = _FakeTerminalHostClient(
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
      expect(session.writeBytes(<int>[9, 10]), isTrue);
      await _flushAsync();

      expect(client.attachCalls, hasLength(2));
      expect(client.attachCalls.last.workingDirectory, '/repo');
      expect(client.attachCalls.last.cols, 80);
      expect(client.attachCalls.last.rows, 24);
      expect(client.writes, <List<int>>[
        <int>[9, 10],
      ]);
      expect(events.whereType<TerminalPtyErrorEvent>(), isEmpty);
    },
  );

  test(
    'host PTY session reattaches with the latest size before resizing',
    () async {
      final client = _FakeTerminalHostClient(
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
    'host PTY session emits one error when stale-session recovery fails',
    () async {
      final client = _FakeTerminalHostClient(
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
      client.writeErrors.addAll(<Object>[
        StateError('Terminal session is not attached: session-1'),
        StateError('Terminal session is not attached: session-1'),
      ]);
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

      expect(client.attachCalls, hasLength(2));
      expect(client.writes, isEmpty);
      final error = events.whereType<TerminalPtyErrorEvent>().single.error;
      expect(
        error,
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Terminal session is not attached'),
        ),
      );
    },
  );

  test(
    'host PTY session forwards matching host events and write errors',
    () async {
      final client = _FakeTerminalHostClient(
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

  test('host PTY session rejects use after disposal', () async {
    final client = _FakeTerminalHostClient(
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

final class _FakeTerminalHostClient implements TerminalHostClient {
  _FakeTerminalHostClient({
    required TerminalHostAttachment attachment,
    List<TerminalHostAttachment>? attachments,
  }) : _attachments = attachments ?? <TerminalHostAttachment>[attachment];

  final List<TerminalHostAttachment> _attachments;
  final StreamController<TerminalHostEvent> _events =
      StreamController<TerminalHostEvent>.broadcast();
  final List<
    ({
      String sessionId,
      String workspaceId,
      String tabId,
      String workingDirectory,
      int cols,
      int rows,
    })
  >
  attachCalls =
      <
        ({
          String sessionId,
          String workspaceId,
          String tabId,
          String workingDirectory,
          int cols,
          int rows,
        })
      >[];
  final List<List<int>> writes = <List<int>>[];
  final List<(String, int, int)> resizes = <(String, int, int)>[];
  final List<String> detached = <String>[];
  final List<String> terminated = <String>[];
  final List<Object> writeErrors = <Object>[];
  final List<Object> resizeErrors = <Object>[];
  String? attachedWorkingDirectory;
  Object? writeError;

  @override
  Stream<TerminalHostEvent> get events => _events.stream;

  @override
  Future<void> configure(TerminalHostConfig config) async {}

  @override
  Future<void> ensureStarted({required TerminalHostConfig config}) async {}

  @override
  Future<TerminalHostAttachment> createOrAttach({
    required String sessionId,
    required String workspaceId,
    required String tabId,
    required String workingDirectory,
    required GhosttyTerminalShellLaunch launch,
    required int cols,
    required int rows,
  }) async {
    attachCalls.add((
      sessionId: sessionId,
      workspaceId: workspaceId,
      tabId: tabId,
      workingDirectory: workingDirectory,
      cols: cols,
      rows: rows,
    ));
    attachedWorkingDirectory = workingDirectory;
    final index = attachCalls.length - 1;
    return _attachments[index < _attachments.length
        ? index
        : _attachments.length - 1];
  }

  @override
  Future<void> write({
    required String sessionId,
    required List<int> bytes,
  }) async {
    if (writeErrors.isNotEmpty) {
      throw writeErrors.removeAt(0);
    }
    if (writeError case final error?) {
      throw error;
    }
    writes.add(List<int>.from(bytes));
  }

  @override
  Future<void> resize({
    required String sessionId,
    required int cols,
    required int rows,
  }) async {
    if (resizeErrors.isNotEmpty) {
      throw resizeErrors.removeAt(0);
    }
    resizes.add((sessionId, cols, rows));
  }

  @override
  Future<void> detach(String sessionId) async {
    detached.add(sessionId);
  }

  @override
  Future<void> terminate(String sessionId) async {
    terminated.add(sessionId);
  }

  @override
  void dispose() {
    unawaited(_events.close());
  }

  void emit(TerminalHostEvent event) {
    _events.add(event);
  }
}
