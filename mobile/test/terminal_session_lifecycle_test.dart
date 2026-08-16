import 'dart:async';

import 'package:alera_mobile/src/app/lifecycle/app_lifecycle_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_session_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_tab_session.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

void main() {
  test('Disposing during the initial attach does not bind a driver', () async {
    final attachCompletion = Completer<void>();
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')]
      ..attachCompletion = attachCompletion.future;
    final container = ProviderContainer(
      overrides: [
        terminalClientProvider('host-1').overrideWith((ref) async => client),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(client.dispose);
    final subscription = container.listen(
      terminalSessionControllerProvider('host-1', 'tab-1'),
      (_, _) {},
    );
    final sessionFuture = container.read(
      terminalSessionControllerProvider('host-1', 'tab-1').future,
    );

    await _waitUntil(() => client.attachments.isNotEmpty);
    subscription.close();
    await pumpEventQueue();
    attachCompletion.complete();

    await sessionFuture;
    await pumpEventQueue();

    expect(client.calls, contains('detach session-tab-1'));
  });

  test(
    'Disposing during recovery does not bind to closed client events',
    () async {
      final client = FakeTerminalClient()
        ..tabs = <WorkspaceTabSummary>[
          fakeTab(id: 'tab-1', title: 'Terminal 1'),
        ];
      final lifecycle = _TestAppLifecycleController(AppLifecycleState.resumed);
      final container = ProviderContainer(
        overrides: [
          terminalClientProvider('host-1').overrideWith((ref) async => client),
          appLifecycleControllerProvider.overrideWith(() => lifecycle),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(client.dispose);
      final subscription = container.listen(
        terminalSessionControllerProvider('host-1', 'tab-1'),
        (_, _) {},
      );
      await container.read(
        terminalSessionControllerProvider('host-1', 'tab-1').future,
      );

      final attachCompletion = Completer<void>();
      client.attachCompletion = attachCompletion.future;
      lifecycle.setLifecycleState(AppLifecycleState.inactive);
      lifecycle.setLifecycleState(AppLifecycleState.resumed);
      await _waitUntil(() => client.attachments.length == 2);

      subscription.close();
      await pumpEventQueue();
      attachCompletion.complete();
      await _waitUntil(
        () =>
            client.calls
                .where((call) => call == 'detach session-tab-1')
                .length ==
            2,
      );

      await client.dispose();
      await pumpEventQueue();
      expect(
        client.calls.where((call) => call == 'detach session-tab-1'),
        hasLength(2),
      );
    },
  );

  test(
    'Open session starts again when the app returns to foreground',
    () async {
      final client = FakeTerminalClient()
        ..tabs = <WorkspaceTabSummary>[
          fakeTab(id: 'tab-1', title: 'Terminal 1'),
        ];
      final lifecycle = _TestAppLifecycleController(AppLifecycleState.resumed);
      final container = ProviderContainer(
        overrides: [
          terminalClientProvider('host-1').overrideWith((ref) async => client),
          appLifecycleControllerProvider.overrideWith(() => lifecycle),
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
      final notifier = container.read(
        terminalSessionControllerProvider('host-1', 'tab-1').notifier,
      );
      await notifier.resize(48, 22);
      final foregroundAttach = Completer<void>();
      client.attachCompletion = foregroundAttach.future;

      lifecycle.setLifecycleState(AppLifecycleState.inactive);
      expect(client.attachments, hasLength(1));
      lifecycle.setLifecycleState(AppLifecycleState.resumed);
      await _waitUntil(() => client.attachments.length == 2);

      expect(client.attachments.last, (tabId: 'tab-1', cols: 48, rows: 22));
      expect(
        container.read(terminalSessionControllerProvider('host-1', 'tab-1')),
        isA<AsyncLoading<TerminalTabSession>>().having(
          (value) => value.progress,
          'progress',
          isNull,
        ),
      );
      expect(client.calls, isNot(contains('restart tab-1')));

      foregroundAttach.complete();
      await _waitUntil(
        () => container
            .read(terminalSessionControllerProvider('host-1', 'tab-1'))
            .hasValue,
      );
    },
  );

  test('Stale terminal write reattaches and retries once', () async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    final container = ProviderContainer(
      overrides: [
        terminalClientProvider('host-1').overrideWith((ref) async => client),
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
    final notifier = container.read(
      terminalSessionControllerProvider('host-1', 'tab-1').notifier,
    );
    await notifier.resize(48, 22);
    client.writeErrors.add(
      StateError('Terminal session is not attached: session-tab-1'),
    );

    await notifier.write(<int>[1, 2]);

    expect(client.attachments, hasLength(2));
    expect(client.attachments.last, (tabId: 'tab-1', cols: 48, rows: 22));
    expect(
      client.calls.where((call) => call.startsWith('write session-tab-1')),
      hasLength(2),
    );
    expect(client.writes, <List<int>>[
      <int>[1, 2],
    ]);
    expect(
      container.read(terminalSessionControllerProvider('host-1', 'tab-1')),
      isA<AsyncData<TerminalTabSession>>(),
    );
  });

  test(
    'Stale terminal resize reattaches with the requested dimensions',
    () async {
      final client = FakeTerminalClient()
        ..tabs = <WorkspaceTabSummary>[
          fakeTab(id: 'tab-1', title: 'Terminal 1'),
        ]
        ..resizeErrors.add(
          StateError('Terminal session is not attached: session-tab-1'),
        );
      final container = ProviderContainer(
        overrides: [
          terminalClientProvider('host-1').overrideWith((ref) async => client),
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
      final notifier = container.read(
        terminalSessionControllerProvider('host-1', 'tab-1').notifier,
      );

      await notifier.resize(48, 22);

      expect(client.attachments, hasLength(2));
      expect(client.attachments.last, (tabId: 'tab-1', cols: 48, rows: 22));
      expect(
        client.calls.where((call) => call == 'resize session-tab-1 48 22'),
        hasLength(2),
      );
    },
  );

  test('Unrelated terminal write failures still propagate', () async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')]
      ..writeErrors.add(StateError('write failed'));
    final container = ProviderContainer(
      overrides: [
        terminalClientProvider('host-1').overrideWith((ref) async => client),
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
    final notifier = container.read(
      terminalSessionControllerProvider('host-1', 'tab-1').notifier,
    );

    await expectLater(
      notifier.write(<int>[1]),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'write failed',
        ),
      ),
    );

    expect(client.attachments, hasLength(1));
  });

  test(
    'Disposal during stale-session reattach discards the late result',
    () async {
      final attachCompletion = Completer<void>();
      final client = FakeTerminalClient()
        ..tabs = <WorkspaceTabSummary>[
          fakeTab(id: 'tab-1', title: 'Terminal 1'),
        ]
        ..writeErrors.add(
          StateError('Terminal session is not attached: session-tab-1'),
        );
      final container = ProviderContainer(
        overrides: [
          terminalClientProvider('host-1').overrideWith((ref) async => client),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(client.dispose);
      final subscription = container.listen(
        terminalSessionControllerProvider('host-1', 'tab-1'),
        (_, _) {},
      );
      await container.read(
        terminalSessionControllerProvider('host-1', 'tab-1').future,
      );
      final notifier = container.read(
        terminalSessionControllerProvider('host-1', 'tab-1').notifier,
      );
      client.attachCompletion = attachCompletion.future;

      final write = notifier.write(<int>[1]);
      await _waitUntil(() => client.attachments.length == 2);
      subscription.close();
      await pumpEventQueue();
      attachCompletion.complete();

      await write;
      await _waitUntil(
        () =>
            client.calls
                .where((call) => call == 'detach session-tab-1')
                .length ==
            2,
      );
      expect(client.writes, isEmpty);
    },
  );
}

class _TestAppLifecycleController extends AppLifecycleController {
  _TestAppLifecycleController(this.initialState);

  final AppLifecycleState initialState;

  @override
  AppLifecycleState build() => initialState;

  void setLifecycleState(AppLifecycleState next) {
    state = next;
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not reached.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
