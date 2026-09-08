import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_session_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

void main() {
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
      client.calls.where((call) => call.startsWith('resize ')).toList(),
      <String>[
        'resize session-tab-1 48 22',
        'resize session-tab-1 47 22',
        'resize session-tab-1 48 22',
        'resize session-tab-1 48 22',
      ],
    );
    expect(client.writes, isEmpty);
    expect(client.calls, isNot(contains('restart tab-1')));
  });

  test(
    'First measured viewport pulses the PTY so agent TUIs relayout',
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
      final notifier = container.read(
        terminalSessionControllerProvider('host-1', 'tab-1').notifier,
      );

      await notifier.resize(48, 22);
      await notifier.resize(52, 24);
      await notifier.refreshViewport();

      expect(
        client.calls.where((call) => call.startsWith('resize ')).toList(),
        <String>[
          'resize session-tab-1 48 22',
          'resize session-tab-1 47 22',
          'resize session-tab-1 48 22',
          'resize session-tab-1 52 24',
          'resize session-tab-1 51 24',
          'resize session-tab-1 52 24',
        ],
      );
    },
  );

  test('Viewport pulse restores the measured size if the bump fails', () async {
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
    await notifier.resize(80, 24);
    client.calls.removeWhere((call) => call.startsWith('resize '));
    client.resizeErrors.add(StateError('resize failed'));

    await notifier.refreshViewport();

    expect(
      client.calls.where((call) => call.startsWith('resize ')).toList(),
      <String>['resize session-tab-1 79 24', 'resize session-tab-1 80 24'],
    );
  });
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
  return container;
}
