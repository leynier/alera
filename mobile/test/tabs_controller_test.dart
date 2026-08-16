import 'dart:async';
import 'dart:typed_data';

import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/tabs_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_session_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_tab_session.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

part 'tabs_controller_test_support.dart';

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

      expect(await notifier.closeTab(client.tabs.single), isTrue);

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

  test('Closing a Codex tab removes it without terminal termination', () async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[
        fakeTab(id: 'codex-1', title: 'Codex', kind: 'codex'),
      ];
    final container = _container(client);
    final notifier = container.read(
      tabsControllerProvider('host-1', 'workspace-1').notifier,
    );
    await container.read(
      tabsControllerProvider('host-1', 'workspace-1').future,
    );

    expect(await notifier.closeTab(client.tabs.single), isTrue);

    expect(client.calls, contains('removeTab codex-1'));
    expect(client.calls.where((call) => call.startsWith('terminate')), isEmpty);
  });

  test(
    'Closing reports failure when its provider is disposed in flight',
    () async {
      final termination = Completer<void>();
      final client = FakeTerminalClient()
        ..tabs = <WorkspaceTabSummary>[
          fakeTab(id: 'tab-1', title: 'Terminal 1'),
        ]
        ..terminateCompletion = termination.future;
      final container = _container(client);
      final notifier = container.read(
        tabsControllerProvider('host-1', 'workspace-1').notifier,
      );
      await container.read(
        tabsControllerProvider('host-1', 'workspace-1').future,
      );

      final closing = notifier.closeTab(client.tabs.single);
      await Future<void>.delayed(Duration.zero);
      container.dispose();
      termination.complete();

      expect(await closing, isFalse);
      expect(client.calls, isNot(contains('removeTab tab-1')));
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

  test('Resolves automatic titles with desktop precedence', () async {
    final automatic = fakeTab(
      id: 'tab-1',
      title: 'Terminal 1',
      runtimeTitle: '  Review Tests  ',
    );
    final generic = fakeTab(
      id: 'tab-2',
      title: 'Terminal 2',
      runtimeTitle: 'Terminal',
    );
    final manual = fakeTab(
      id: 'tab-3',
      title: 'Pinned Title',
      runtimeTitle: 'Ignored Runtime Title',
      manualTitle: true,
    );
    final manualCodex = fakeTab(
      id: 'codex-1',
      title: 'Renamed Chat',
      kind: 'codex',
      manualTitle: true,
    );
    final automaticCodex = fakeTab(
      id: 'codex-2',
      title: 'Codex',
      kind: 'codex',
    );

    expect(automatic.displayTitle, 'Review Tests');
    expect(generic.displayTitle, 'Terminal 2');
    expect(manual.displayTitle, 'Pinned Title');
    expect(manualCodex.displayTitle, 'Renamed Chat');
    expect(automaticCodex.displayTitle, 'Codex Chat');
  });

  test('Loads the current runtime title from the initial tab list', () async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[
        fakeTab(
          id: 'tab-1',
          title: 'Terminal 1',
          runtimeTitle: 'Existing Agent Task',
        ),
      ];
    final container = _container(client);

    final tabs = await container.read(
      tabsControllerProvider('host-1', 'workspace-1').future,
    );

    expect(tabs.single.displayTitle, 'Existing Agent Task');
  });

  test(
    'Updates titles for selected and background tabs from host events',
    () async {
      final client = FakeTerminalClient()
        ..tabs = <WorkspaceTabSummary>[
          fakeTab(id: 'tab-1', title: 'Terminal 1'),
          fakeTab(id: 'tab-2', title: 'Terminal 2'),
          fakeTab(id: 'tab-3', title: 'Pinned Title', manualTitle: true),
        ];
      final container = _container(client);
      await container.read(
        tabsControllerProvider('host-1', 'workspace-1').future,
      );

      client.emitTerminalTitle(
        workspaceId: 'workspace-1',
        tabId: 'tab-1',
        title: 'Implement Feature',
      );
      client.emitTerminalTitle(
        workspaceId: 'workspace-1',
        tabId: 'tab-2',
        title: 'Run Tests',
      );
      client.emitTerminalTitle(
        workspaceId: 'workspace-1',
        tabId: 'tab-3',
        title: 'Must Not Replace Manual',
      );
      client.emitTerminalTitle(
        workspaceId: 'other-workspace',
        tabId: 'tab-1',
        title: 'Wrong Workspace',
      );
      await pumpEventQueue();

      final tabs = container
          .read(tabsControllerProvider('host-1', 'workspace-1'))
          .requireValue;
      expect(tabs.map((tab) => tab.displayTitle), <String>[
        'Implement Feature',
        'Run Tests',
        'Pinned Title',
      ]);
    },
  );

  test(
    'Keeps static titles when the host lacks title synchronization',
    () async {
      final client = FakeTerminalClient()
        ..supportsTerminalTitles = false
        ..tabs = <WorkspaceTabSummary>[
          fakeTab(id: 'tab-1', title: 'Terminal 1'),
        ];
      final container = _container(client);
      await container.read(
        tabsControllerProvider('host-1', 'workspace-1').future,
      );

      client.emitTerminalTitle(
        workspaceId: 'workspace-1',
        tabId: 'tab-1',
        title: 'Unsupported Title',
      );
      await pumpEventQueue();

      expect(
        container
            .read(tabsControllerProvider('host-1', 'workspace-1'))
            .requireValue
            .single
            .displayTitle,
        'Terminal 1',
      );
    },
  );

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

    final received = <Uint8List>[];
    final outputSub = session.output.listen(
      (event) => received.add(event.data),
    );
    client.emitOutput('session-tab-1', Uint8List.fromList(<int>[104, 105]));
    client.emitOutput('other-session', Uint8List.fromList(<int>[120]));
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(1));
    await outputSub.cancel();

    final notifier = container.read(
      terminalSessionControllerProvider('host-1', 'tab-1').notifier,
    );
    await notifier.write(<int>[108, 115]);
    expect(
      client.calls,
      contains('write session-tab-1 2 paste=false enter=false'),
    );
    await notifier.resize(48, 22);
    expect(client.calls, contains('resize session-tab-1 48 22'));
    await notifier.resize(0, 22);
    expect(client.calls, isNot(contains('resize session-tab-1 0 22')));

    subscription.close();
    await Future<void>.delayed(Duration.zero);
    expect(client.calls, contains('detach session-tab-1'));
  });

  test('Session controller forwards a repeated viewport size', () async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    final container = _container(client);
    final subscription = container.listen(
      terminalSessionControllerProvider('host-1', 'tab-1'),
      (_, _) {},
    );
    addTearDown(subscription.close);
    await container.read(
      terminalSessionControllerProvider('host-1', 'tab-1').future,
    );
    final notifier = container.read(
      terminalSessionControllerProvider('host-1', 'tab-1').notifier,
    );

    await notifier.resize(48, 22);
    await notifier.resize(48, 22);

    expect(
      client.calls.where((call) => call == 'resize session-tab-1 48 22'),
      hasLength(2),
    );
    expect(client.writes, isEmpty);
    expect(client.calls, isNot(contains('restart tab-1')));
  });

  test('Session recovery reconnects before an explicit restart', () async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    final container = _container(client);
    final subscription = container.listen(
      terminalSessionControllerProvider('host-1', 'tab-1'),
      (_, _) {},
    );
    addTearDown(subscription.close);
    await container.read(
      terminalSessionControllerProvider('host-1', 'tab-1').future,
    );
    final notifier = container.read(
      terminalSessionControllerProvider('host-1', 'tab-1').notifier,
    );

    await notifier.reconnect();
    expect(client.calls.where((call) => call == 'attach tab-1'), hasLength(2));
    expect(client.calls, isNot(contains('restart tab-1')));

    await notifier.restartTerminal();
    expect(client.calls, contains('restart tab-1'));
    expect(
      container
          .read(terminalSessionControllerProvider('host-1', 'tab-1'))
          .requireValue
          .running,
      isTrue,
    );
  });

  test('Session automatically reattaches when the client changes', () async {
    final firstClient = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    final secondAttach = Completer<void>();
    final secondClient = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')]
      ..attachCompletion = secondAttach.future;
    final thirdClient = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    var currentClient = firstClient;
    final container = ProviderContainer(
      overrides: [
        terminalClientProvider(
          'host-1',
        ).overrideWith((ref) async => currentClient),
      ],
    );
    addTearDown(firstClient.dispose);
    addTearDown(secondClient.dispose);
    addTearDown(thirdClient.dispose);
    addTearDown(container.dispose);
    final subscription = container.listen(
      terminalSessionControllerProvider('host-1', 'tab-1'),
      (_, _) {},
    );
    addTearDown(subscription.close);
    await container.read(
      terminalSessionControllerProvider('host-1', 'tab-1').future,
    );
    final notifier = container.read(
      terminalSessionControllerProvider('host-1', 'tab-1').notifier,
    );
    await notifier.resize(48, 22);

    currentClient = secondClient;
    container.invalidate(terminalClientProvider('host-1'));
    await _waitUntil(() => secondClient.attachments.isNotEmpty);
    currentClient = thirdClient;
    container.invalidate(terminalClientProvider('host-1'));
    secondAttach.complete();
    await _waitUntil(() => thirdClient.attachments.isNotEmpty);

    expect(secondClient.attachments.single, (
      tabId: 'tab-1',
      cols: 48,
      rows: 22,
    ));
    expect(thirdClient.attachments.single, (
      tabId: 'tab-1',
      cols: 48,
      rows: 22,
    ));
    expect(thirdClient.calls, isNot(contains('restart tab-1')));
    expect(
      thirdClient.calls.where((call) => call.startsWith('terminate ')),
      isEmpty,
    );
    final recovered = container
        .read(terminalSessionControllerProvider('host-1', 'tab-1'))
        .requireValue;
    expect(recovered.sessionId, 'session-tab-1');

    final output = <Uint8List>[];
    final outputSub = recovered.output.listen(
      (event) => output.add(event.data),
    );
    addTearDown(outputSub.cancel);
    thirdClient.emitOutput(
      'session-tab-1',
      Uint8List.fromList(<int>[114, 101, 97, 100, 121]),
    );
    await Future<void>.delayed(Duration.zero);
    expect(output.single, Uint8List.fromList(<int>[114, 101, 97, 100, 121]));
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
