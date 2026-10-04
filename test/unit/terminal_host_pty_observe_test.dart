import 'dart:typed_data';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_pty_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

import 'terminal_host_test_fakes.dart';

FakeTerminalHostClient _client({
  bool running = true,
  bool observeSupported = true,
}) => FakeTerminalHostClient(attachment: _attachment(running: running))
  ..runtimeCapabilities = <String>{
    if (observeSupported) aleraRuntimeHostAutomationTerminalObserveCapability,
  };

const GhosttyTerminalShellLaunch _launch = GhosttyTerminalShellLaunch(
  label: 'shell',
  shell: '/bin/sh',
  arguments: <String>[],
);

TerminalHostAttachment _attachment({bool running = true}) =>
    TerminalHostAttachment(
      sessionId: 'session-1',
      created: false,
      running: running,
      snapshot: Uint8List(0),
    );

Future<TerminalHostPtySession> _start(
  FakeTerminalHostClient client, {
  required bool observed,
}) async {
  final session =
      TerminalHostPtySessionFactory(
            client: client,
            observeTab: (_, _) => observed,
          ).create(
            sessionId: 'session-1',
            workspaceId: 'workspace-1',
            tabId: 'tab-1',
          )
          as TerminalHostPtySession;
  addTearDown(session.dispose);
  await session.start(
    launch: _launch,
    workingDirectory: '/repo',
    cols: 80,
    rows: 24,
  );
  return session;
}

void main() {
  test(
    'an observed automation tab never writes, resizes or restarts',
    () async {
      final client = _client();
      final session = await _start(client, observed: true);

      expect(client.observeFlags, <bool>[true]);
      expect(session.isObserving, isTrue);
      expect(session.writeBytes(<int>[65]), isFalse);
      expect(session.writeBytesWithDeferredEnter(<int>[65]), isFalse);
      expect(await session.writeBytesAndWait(<int>[65]), isFalse);
      session.resize(120, 40, 8, 16);
      await session.refreshViewport(120, 40, 8, 16);
      await Future.pause(Duration.zero);
      expect(client.writes, isEmpty);
      expect(client.resizes, isEmpty);
      expect(session.supportsRestart, isFalse);
      await expectLater(session.restartProcess(), throwsStateError);
      expect(client.restarted, isEmpty);
    },
  );

  test('a dead observed session is shown, never respawned', () async {
    final client = _client(running: false);
    await _start(client, observed: true);
    expect(client.observeFlags, <bool>[true]);
    expect(client.restarted, isEmpty);
  });

  test(
    'without runtime support the attach keeps its legacy semantics',
    () async {
      final client = _client(observeSupported: false);
      final session = await _start(client, observed: true);
      expect(client.observeFlags, <bool>[false]);
      expect(session.writeBytes(<int>[65]), isTrue);
    },
  );

  test('ordinary tabs never ask to observe', () async {
    final client = _client();
    final session = await _start(client, observed: false);
    expect(client.observeFlags, <bool>[false]);
    expect(session.isObserving, isFalse);
  });

  test('re-attaching after a takeover switches to the normal mode', () async {
    var observed = true;
    final client = _client();
    final session =
        TerminalHostPtySessionFactory(
              client: client,
              observeTab: (_, _) => observed,
            ).create(
              sessionId: 'session-1',
              workspaceId: 'workspace-1',
              tabId: 'tab-1',
            )
            as TerminalHostPtySession;
    addTearDown(session.dispose);
    await session.start(
      launch: _launch,
      workingDirectory: '/repo',
      cols: 80,
      rows: 24,
    );
    observed = false;
    await session.reconnect();
    expect(client.observeFlags, <bool>[true, false]);
    expect(session.isObserving, isFalse);
  });
}
