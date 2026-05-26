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

final class _FakeTerminalHostClient implements TerminalHostClient {
  _FakeTerminalHostClient({required this.attachment});

  final TerminalHostAttachment attachment;
  final StreamController<TerminalHostEvent> _events =
      StreamController<TerminalHostEvent>.broadcast();
  final List<List<int>> writes = <List<int>>[];
  final List<(String, int, int)> resizes = <(String, int, int)>[];
  final List<String> detached = <String>[];
  final List<String> terminated = <String>[];
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
    attachedWorkingDirectory = workingDirectory;
    return attachment;
  }

  @override
  Future<void> write({
    required String sessionId,
    required List<int> bytes,
  }) async {
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
