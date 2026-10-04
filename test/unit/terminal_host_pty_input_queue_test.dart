import 'dart:async';
import 'dart:typed_data';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_pty_session.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

import 'terminal_host_test_fakes.dart';

void main() {
  test(
    'input arriving behind an in-flight write is merged, in order',
    () async {
      final client = FakeTerminalHostClient(
        attachment: TerminalHostAttachment(
          sessionId: 'session-1',
          created: false,
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
        launch: const GhosttyTerminalShellLaunch(
          label: 'shell',
          shell: '/bin/sh',
          arguments: <String>['-l'],
          environment: <String, String>{'TERM': 'xterm-256color'},
        ),
        workingDirectory: '/repo',
        cols: 80,
        rows: 24,
      );
      final gate = Completer<void>();
      client.writeGate = gate;

      expect(session.writeBytes(<int>[1]), isTrue);
      // A wheel burst over a TUI: several reports while the first is in flight.
      expect(session.writeBytes(<int>[2]), isTrue);
      expect(session.writeBytes(<int>[3]), isTrue);
      expect(session.writeBytesWithDeferredEnter(<int>[13]), isTrue);
      expect(session.writeBytes(<int>[4]), isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(client.writes, <List<int>>[
        <int>[1],
      ], reason: 'the first byte must not wait for anything');

      client.writeGate = null;
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(client.writes, <List<int>>[
        <int>[1],
        <int>[2, 3],
        <int>[13],
        <int>[4],
      ]);
      expect(client.deferredEnterFlags, <bool>[false, false, true, false]);
    },
  );

  test(
    'a failed write reports its error and later input still flows',
    () async {
      final client = FakeTerminalHostClient(
        attachment: TerminalHostAttachment(
          sessionId: 'session-1',
          created: false,
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
      final errors = <Object>[];
      final sub = session.events.listen((event) {
        if (event case TerminalPtyErrorEvent(:final error)) {
          errors.add(error);
        }
      });
      addTearDown(sub.cancel);
      await session.start(
        launch: const GhosttyTerminalShellLaunch(
          label: 'shell',
          shell: '/bin/sh',
          arguments: <String>['-l'],
          environment: <String, String>{'TERM': 'xterm-256color'},
        ),
        workingDirectory: '/repo',
        cols: 80,
        rows: 24,
      );
      client.writeErrors.add(StateError('write failed'));

      expect(session.writeBytes(<int>[1]), isTrue);
      expect(session.writeBytes(<int>[2]), isTrue);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(client.writes, <List<int>>[
        <int>[2],
      ]);
    },
  );
}
