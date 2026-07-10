import 'dart:async';
import 'dart:typed_data';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_pty_session.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

import 'terminal_host_test_fakes.dart';

void main() {
  test('initial process callback can write startup input', () async {
    final client = _clientWithReattach(created: false);
    final session = _session(client);
    addTearDown(session.dispose);

    await session.start(
      launch: _launch(),
      workingDirectory: '/repo',
      cols: 80,
      rows: 24,
      onProcessCreated: () async {
        expect(await session.writeBytesAndWait(<int>[1, 2]), isTrue);
      },
    );
    await _flushAsync();

    expect(client.writes, <List<int>>[
      <int>[1, 2],
    ]);
  });

  test('awaited startup write retries after a live reattach', () async {
    final client = _clientWithReattach(created: false);
    client.writeErrors.add(
      StateError('Terminal session is not attached: session-1'),
    );
    final session = _session(client);
    addTearDown(session.dispose);

    await session.start(
      launch: _launch(),
      workingDirectory: '/repo',
      cols: 80,
      rows: 24,
      onProcessCreated: () async {
        expect(await session.writeBytesAndWait(<int>[1, 2]), isTrue);
      },
    );

    expect(client.attachCalls, hasLength(2));
    expect(client.writes, <List<int>>[
      <int>[1, 2],
    ]);
  });

  test('awaited startup write yields to a complete remint replay', () async {
    final client = _clientWithReattach(created: true);
    client.writeErrors.add(
      StateError('Terminal host connection closed: reset'),
    );
    final session = _session(client);
    addTearDown(session.dispose);
    var processCount = 0;
    final results = <bool>[];

    await session.start(
      launch: _launch(),
      workingDirectory: '/repo',
      cols: 80,
      rows: 24,
      onProcessCreated: () async {
        processCount += 1;
        results.add(await session.writeBytesAndWait(<int>[1, 2]));
      },
    );

    expect(processCount, 2);
    expect(results, <bool>[true, false]);
    expect(client.attachCalls, hasLength(2));
    expect(client.writes, <List<int>>[
      <int>[1, 2],
    ]);
  });

  test('awaited startup write preserves unrecoverable errors', () async {
    final client = _clientWithReattach(created: false);
    client.writeErrors.add(StateError('write failed'));
    final session = _session(client);
    addTearDown(session.dispose);

    await expectLater(
      session.start(
        launch: _launch(),
        workingDirectory: '/repo',
        cols: 80,
        rows: 24,
        onProcessCreated: () async {
          await session.writeBytesAndWait(<int>[1, 2]);
        },
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'write failed',
        ),
      ),
    );

    expect(client.attachCalls, hasLength(1));
    expect(client.writes, isEmpty);
  });

  test(
    'created reattach awaits startup replay before retrying input',
    () async {
      final client = _clientWithReattach(created: true);
      client.writeErrors.add(
        StateError('Terminal session is not attached: session-1'),
      );
      final session = _session(client);
      addTearDown(session.dispose);
      final events = <TerminalPtySessionEvent>[];
      final sub = session.events.listen(events.add);
      addTearDown(sub.cancel);
      var processCount = 0;
      final replayStarted = Completer<void>();
      final allowReplay = Completer<void>();

      await session.start(
        launch: _launch(),
        workingDirectory: '/repo',
        cols: 80,
        rows: 24,
        onProcessCreated: () async {
          processCount += 1;
          if (processCount == 2) {
            replayStarted.complete();
            await allowReplay.future;
            await session.writeBytesAndWait(<int>[1]);
          }
        },
      );
      expect(processCount, 1);

      expect(session.writeBytes(<int>[9, 10]), isTrue);
      await replayStarted.future;
      expect(client.writes, isEmpty);

      allowReplay.complete();
      await _flushAsync();
      expect(processCount, 2);
      expect(client.attachCalls, hasLength(2));
      expect(client.attachCalls.last.workingDirectory, '/repo');
      expect(client.attachCalls.last.cols, 80);
      expect(client.attachCalls.last.rows, 24);
      expect(client.writes, <List<int>>[
        <int>[1],
        <int>[9, 10],
      ]);
      final snapshots = events.whereType<TerminalPtySnapshotEvent>().toList();
      expect(snapshots, hasLength(2));
      expect(snapshots.every((snapshot) => snapshot.data.isEmpty), isTrue);
      expect(
        snapshots.every((snapshot) => snapshot.resetInteractionModes),
        isTrue,
      );
      expect(events.whereType<TerminalPtyErrorEvent>(), isEmpty);
    },
  );

  test('live reattach does not replay startup', () async {
    final client = _clientWithReattach(created: false);
    client.writeErrors.add(
      StateError('Terminal session is not attached: session-1'),
    );
    final session = _session(client);
    addTearDown(session.dispose);
    var processCount = 0;

    await session.start(
      launch: _launch(),
      workingDirectory: '/repo',
      cols: 80,
      rows: 24,
      onProcessCreated: () async => processCount += 1,
    );
    expect(session.writeBytes(<int>[7]), isTrue);
    await _flushAsync();

    expect(processCount, 1);
    expect(client.writes, <List<int>>[
      <int>[7],
    ]);
  });
}

FakeTerminalHostClient _clientWithReattach({required bool created}) {
  final initial = _attachment(created: true);
  return FakeTerminalHostClient(
    attachment: initial,
    attachments: <TerminalHostAttachment>[
      initial,
      _attachment(created: created),
    ],
  );
}

TerminalHostAttachment _attachment({required bool created}) {
  return TerminalHostAttachment(
    sessionId: 'session-1',
    created: created,
    running: true,
    snapshot: Uint8List(0),
  );
}

TerminalHostPtySession _session(FakeTerminalHostClient client) {
  return TerminalHostPtySession(
    client: client,
    sessionId: 'session-1',
    workspaceId: 'workspace-1',
    tabId: 'tab-1',
  );
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
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
