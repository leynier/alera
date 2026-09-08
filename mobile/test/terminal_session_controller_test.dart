import 'dart:async';
import 'dart:typed_data';

import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_session_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_tab_session.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

void main() {
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
    client.emitOutput('session-tab-1', .fromList(<int>[104, 105]));
    client.emitOutput('other-session', .fromList(<int>[120]));
    await Future.pause(.zero);
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
    expect(
      client.calls.where((call) => call.startsWith('resize ')).toList(),
      <String>[
        'resize session-tab-1 48 22',
        'resize session-tab-1 47 22',
        'resize session-tab-1 48 22',
      ],
    );
    await notifier.resize(0, 22);
    expect(client.calls, isNot(contains('resize session-tab-1 0 22')));

    subscription.close();
    await Future.pause(.zero);
    expect(client.calls, contains('detach session-tab-1'));
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
        terminalClientProvider('host-1')
            .overrideWith((ref) async => currentClient),
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
      .fromList(<int>[114, 101, 97, 100, 121]),
    );
    await Future.pause(.zero);
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
      await Future.pause(.zero);
      expect(
        container.read(terminalSessionControllerProvider('host-1', 'tab-1')),
        isA<AsyncData<Object?>>(),
      );

      // A mobile driver change (another phone claiming) does not eject.
      client.emitDriverChanged('session-tab-1', 'mobile');
      await Future.pause(.zero);
      expect(
        container.read(terminalSessionControllerProvider('host-1', 'tab-1')),
        isA<AsyncData<Object?>>(),
      );

      client.emitDriverChanged('session-tab-1', 'desktop');
      await Future.pause(.zero);
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
  return container;
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not reached.');
    }
    await Future.pause(const Duration(milliseconds: 10));
  }
}
