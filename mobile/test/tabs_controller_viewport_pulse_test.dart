import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_session_controller.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_viewport_pulse.dart';
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

  test('A later viewport change pulses after it settles', () async {
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
    await notifier.resize(52, 24);
    await Future<void>.delayed(terminalViewportPulseDebounce);
    await pumpEventQueue();

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
  });

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

    final pulse = terminalViewportRefreshPulseSize(80, 24);
    expect(
      client.calls.where((call) => call.startsWith('resize ')).toList(),
      <String>[
        'resize session-tab-1 ${pulse.$1} ${pulse.$2}',
        'resize session-tab-1 80 24',
      ],
    );
  });

  test(
    'Refresh uses a 30 percent bump, not the one-column layout pulse',
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
      await notifier.resize(80, 24);
      client.calls.removeWhere((call) => call.startsWith('resize '));

      await notifier.refreshViewport();

      final refresh = terminalViewportRefreshPulseSize(80, 24);
      final layout = terminalViewportPulseSize(80, 24);
      expect(refresh, isNot(layout));
      expect(
        client.calls.where((call) => call.startsWith('resize ')).toList(),
        <String>[
          'resize session-tab-1 ${refresh.$1} ${refresh.$2}',
          'resize session-tab-1 80 24',
        ],
      );
      expect(
        client.calls,
        isNot(contains('resize session-tab-1 ${layout.$1} ${layout.$2}')),
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
  return container;
}
