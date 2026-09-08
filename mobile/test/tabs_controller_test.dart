import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/tabs_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
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

  test('Closing a non-terminal tab removes it without termination', () async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[
        fakeTab(id: 'editor-1', title: 'Notes', kind: 'editor'),
      ];
    final container = _container(client);
    final notifier = container.read(
      tabsControllerProvider('host-1', 'workspace-1').notifier,
    );
    await container.read(
      tabsControllerProvider('host-1', 'workspace-1').future,
    );

    expect(await notifier.closeTab(client.tabs.single), isTrue);

    expect(client.calls, contains('removeTab editor-1'));
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
      await Future.pause(.zero);
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

    expect(automatic.displayTitle, 'Review Tests');
    expect(generic.displayTitle, 'Terminal 2');
    expect(manual.displayTitle, 'Pinned Title');
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
}
