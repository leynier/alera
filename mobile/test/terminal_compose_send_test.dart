import 'dart:convert';

import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_session_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

void main() {
  test('A composed prompt defers the Enter instead of appending it', () async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    final notifier = await _notifier(client);

    await notifier.sendComposedText('ls -la', withEnter: true);

    expect(
      client.calls,
      contains('write session-tab-1 6 paste=false enter=true'),
    );
    expect(client.writes.single, utf8.encode('ls -la'));
  });

  test('A multi-line prompt is pasted and still defers the Enter', () async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    final notifier = await _notifier(client);

    await notifier.sendComposedText('first\nsecond', withEnter: true);

    expect(
      client.calls,
      contains('write session-tab-1 12 paste=true enter=true'),
    );
  });

  test('An empty send still asks the host to press Enter', () async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    final notifier = await _notifier(client);

    await notifier.sendComposedText('', withEnter: true);

    expect(
      client.calls,
      contains('write session-tab-1 0 paste=false enter=true'),
    );
  });

  test('A host without the capability falls back to one write', () async {
    final client = FakeTerminalClient()
      ..supportsDeferredTerminalInput = false
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    final notifier = await _notifier(client);

    await notifier.sendComposedText('ls -la', withEnter: true);

    expect(
      client.calls,
      contains('write session-tab-1 7 paste=false enter=false'),
    );
    expect(client.writes.single, utf8.encode('ls -la\r'));
  });

  test('Raw keystrokes never take the paste path', () async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    final notifier = await _notifier(client);

    // Ctrl+C from the accessory bar, and a multi-line burst from direct mode:
    // both are already keys, so neither may be wrapped or deferred.
    await notifier.write(<int>[0x03]);
    await notifier.write(utf8.encode('a\nb'));

    expect(
      client.calls,
      containsAll(<String>[
        'write session-tab-1 1 paste=false enter=false',
        'write session-tab-1 3 paste=false enter=false',
      ]),
    );
  });
}

Future<TerminalSessionController> _notifier(FakeTerminalClient client) async {
  final container = ProviderContainer(
    overrides: [
      terminalClientProvider('host-1').overrideWith((ref) async => client),
      workspaceClientProvider('host-1').overrideWith((ref) async => client),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(client.dispose);
  final subscription = container.listen(
    terminalSessionControllerProvider('host-1', 'tab-1'),
    (_, _) {},
  );
  addTearDown(subscription.close);
  await container.read(
    terminalSessionControllerProvider('host-1', 'tab-1').future,
  );
  return container.read(
    terminalSessionControllerProvider('host-1', 'tab-1').notifier,
  );
}
