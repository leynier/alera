import 'dart:typed_data';

import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/tabs_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_session_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

void main() {
  test('Lists tabs and creates numbered terminal tabs', () async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[
        fakeTab(id: 'tab-1', title: 'Terminal 1'),
        fakeTab(id: 'editor-1', title: 'Notes', kind: 'editor'),
      ];
    final container = _container(client);
    final notifier = container.read(
      tabsControllerProvider('host-1', 'workspace-1').notifier,
    );

    final tabs = await container.read(
      tabsControllerProvider('host-1', 'workspace-1').future,
    );
    expect(tabs, hasLength(2));

    final createdId = await notifier.createTerminalTab();
    expect(createdId, isNotEmpty);
    expect(client.calls, contains('create workspace-1 Terminal 2'));
    expect(client.calls.where((call) => call.startsWith('detach')), isNotEmpty);
  });

  test(
    'Closing a terminal tab terminates the session then removes the tab',
    () async {
      final client = FakeTerminalClient()
        ..tabs = <WorkspaceTabSummary>[
          fakeTab(id: 'tab-1', title: 'Terminal 1'),
        ];
      final container = _container(client);
      final notifier = container.read(
        tabsControllerProvider('host-1', 'workspace-1').notifier,
      );
      await container.read(
        tabsControllerProvider('host-1', 'workspace-1').future,
      );

      await notifier.closeTab(client.tabs.single);

      expect(
        client.calls.where(
          (call) =>
              call == 'terminate session-tab-1' || call == 'removeTab tab-1',
        ),
        hasLength(2),
      );
      final terminateIndex = client.calls.indexOf('terminate session-tab-1');
      final removeIndex = client.calls.indexOf('removeTab tab-1');
      expect(terminateIndex, lessThan(removeIndex));
    },
  );

  test('Renames terminal and non-terminal tabs through the runtime', () async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[
        fakeTab(id: 'tab-1', title: 'Terminal 1'),
        fakeTab(id: 'editor-1', title: 'Notes', kind: 'editor'),
      ];
    final container = _container(client);
    final notifier = container.read(
      tabsControllerProvider('host-1', 'workspace-1').notifier,
    );
    await container.read(
      tabsControllerProvider('host-1', 'workspace-1').future,
    );

    await notifier.renameTab(client.tabs.first, 'Build');
    await notifier.renameTab(client.tabs.last, 'Plan');

    expect(
      client.calls,
      containsAll(<String>['renameTab tab-1 Build', 'renameTab editor-1 Plan']),
    );
    expect(client.tabs.map((tab) => tab.title), <String>['Build', 'Plan']);
  });

  test('Session controller attaches, writes, resizes, and detaches', () async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    final container = _container(client);
    final subscription = container.listen(
      terminalSessionControllerProvider('host-1', 'tab-1'),
      (_, _) {},
    );

    final session = await container.read(
      terminalSessionControllerProvider('host-1', 'tab-1').future,
    );
    expect(session.sessionId, 'session-tab-1');
    expect(client.calls, contains('attach tab-1'));

    final received = <List<int>>[];
    final outputSub = session.output.listen(received.add);
    client.emitOutput('session-tab-1', Uint8List.fromList(<int>[104, 105]));
    client.emitOutput('other-session', Uint8List.fromList(<int>[120]));
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(1));
    await outputSub.cancel();

    final notifier = container.read(
      terminalSessionControllerProvider('host-1', 'tab-1').notifier,
    );
    await notifier.write(<int>[108, 115]);
    expect(client.calls, contains('write session-tab-1 2'));
    await notifier.resize(48, 22);
    expect(client.calls, contains('resize session-tab-1 48 22'));
    await notifier.resize(0, 22);
    expect(client.calls, isNot(contains('resize session-tab-1 0 22')));

    subscription.close();
    await Future<void>.delayed(Duration.zero);
    expect(client.calls, contains('detach session-tab-1'));
  });

  test(
    'Desktop reclaim flips the session into the reclaimed error state',
    () async {
      final client = FakeTerminalClient()
        ..tabs = <WorkspaceTabSummary>[
          fakeTab(id: 'tab-1', title: 'Terminal 1'),
        ];
      final container = _container(client);
      final subscription = container.listen(
        terminalSessionControllerProvider('host-1', 'tab-1'),
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.read(
        terminalSessionControllerProvider('host-1', 'tab-1').future,
      );

      // A driver change for another session is ignored.
      client.emitDriverChanged('other-session', 'desktop');
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(terminalSessionControllerProvider('host-1', 'tab-1')),
        isA<AsyncData<Object?>>(),
      );

      // A mobile driver change (another phone claiming) does not eject.
      client.emitDriverChanged('session-tab-1', 'mobile');
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(terminalSessionControllerProvider('host-1', 'tab-1')),
        isA<AsyncData<Object?>>(),
      );

      client.emitDriverChanged('session-tab-1', 'desktop');
      await Future<void>.delayed(Duration.zero);
      final state = container.read(
        terminalSessionControllerProvider('host-1', 'tab-1'),
      );
      expect(
        state,
        isA<AsyncError<Object?>>().having(
          (error) => error.error,
          'error',
          isA<DesktopReclaimedTerminal>(),
        ),
      );
    },
  );
}

ProviderContainer _container(FakeTerminalClient client) {
  final container = ProviderContainer(
    overrides: [
      terminalClientProvider('host-1').overrideWith((ref) async => client),
      workspaceClientProvider('host-1').overrideWith((ref) async => client),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(client.dispose);
  final subscription = container.listen(
    tabsControllerProvider('host-1', 'workspace-1'),
    (_, _) {},
  );
  addTearDown(subscription.close);
  return container;
}
