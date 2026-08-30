import 'dart:async';
import 'dart:convert';

import 'package:alera/src/features/browser/application/browser_session_registry.dart';
import 'package:alera/src/features/browser/domain/browser_automation.dart';
import 'package:alera/src/features/browser/domain/browser_engine_event.dart';
import 'package:alera/src/features/browser/infra/browser_runtime_driver.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera_browser/alera_browser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'browser_runtime_driver_test_support.dart';
import 'fake_browser_engine.dart';

void main() {
  late FakeBrowserEngine engine;
  late BrowserSessionRegistry registry;
  late _FakeRuntimeHostClient client;
  late BrowserRuntimeDriver driver;

  setUp(() async {
    engine = FakeBrowserEngine();
    registry = BrowserSessionRegistry(engine: engine);
    await registry.sessionFor(_tab());
    client = _FakeRuntimeHostClient();
    driver = BrowserRuntimeDriver(
      client: client,
      registry: registry,
      engine: engine,
      appInstanceId: 'app-instance',
      driverInstanceId: 'driver-instance',
      now: () => DateTime.utc(2026),
    );
    await driver.start();
  });

  tearDown(() async {
    await driver.dispose();
    await registry.dispose();
    await engine.dispose();
    await client.dispose();
  });

  test('registers, syncs, and completes routed snapshot requests', () async {
    expect(client.types.take(2), <String>[
      'browser.driver.register',
      'browser.driver.sync',
    ]);

    client.events.add(
      RuntimeHostEvent('browserDriverRequest', <String, Object?>{
        'driverInstanceId': 'driver-instance',
        'correlationId': 'call-1',
        'pageId': 'page-1',
        'generation': 1,
        'method': 'browser.snapshot',
        'params': <String, Object?>{
          'pageId': 'page-1',
          'interactiveOnly': true,
          'maxNodes': 25,
        },
        'deadlineAt': DateTime.utc(
          2026,
          1,
          1,
        ).add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      }),
    );
    await _waitFor(() => client.types.contains('browser.driver.complete'));

    final completion = client.payloads.lastWhere(
      (payload) => payload['correlationId'] == 'call-1',
    );
    final outcome = completion['outcome']! as Map<Object?, Object?>;
    expect(outcome['ok'], isTrue);
    expect(outcome['snapshot'], isA<Map>());
    expect(engine.calls, contains('attach:page-1'));
    expect(engine.calls, contains('detach:page-1'));
    expect(engine.lastSnapshotInteractiveOnly, isTrue);
    expect(engine.lastSnapshotMaxNodes, 25);
  });

  test('reports document generation before navigation completion', () async {
    engine.eventController.add(
      BrowserNavigationStarted(
        pageId: 'page-1',
        occurredAt: .utc(2026),
        url: Uri.parse('https://example.com/next'),
      ),
    );
    engine.eventController.add(
      BrowserNavigationFinished(
        pageId: 'page-1',
        occurredAt: .utc(2026),
        url: Uri.parse('https://example.com/next'),
        title: 'Next',
      ),
    );
    await _waitFor(
      () =>
          client.types
              .where((type) => type == 'browser.driver.pageChanged')
              .length >=
          2,
    );

    final changes = <Map<String, Object?>>[
      for (var index = 0; index < client.types.length; index += 1)
        if (client.types[index] == 'browser.driver.pageChanged')
          client.payloads[index],
    ];
    expect(changes.first['documentChanged'], isTrue);
    expect(changes.first['documentGeneration'], 1);
    expect(changes.first['navigationCompleted'], isFalse);
    expect(changes.last['documentChanged'], isFalse);
    expect(changes.last['documentGeneration'], 1);
    expect(changes.last['navigationCompleted'], isTrue);
  });

  test('bounds reported titles and omits titles for sensitive URLs', () async {
    final rawTitle = ' \u0000Docs\n${List<String>.filled(300, '🚀').join()}\t ';
    engine.eventController.add(
      BrowserNavigationFinished(
        pageId: 'page-1',
        occurredAt: .utc(2026),
        url: Uri.parse('https://example.com/docs'),
        title: rawTitle,
      ),
    );
    await _waitFor(() => client.types.contains('browser.driver.pageChanged'));
    final safeIndex = client.types.lastIndexOf('browser.driver.pageChanged');
    final safeTitle = client.payloads[safeIndex]['title']! as String;
    expect(utf8.encode(safeTitle), hasLength(aleraBrowserTitleMaximumBytes));
    expect(safeTitle.codeUnits, isNot(contains(0)));

    engine.eventController.add(
      BrowserNavigationFinished(
        pageId: 'page-1',
        occurredAt: .utc(2026),
        url: Uri.parse('https://example.com/oauth/callback?code=secret'),
        title: 'Private Account',
      ),
    );
    await _waitFor(
      () =>
          client.types
              .where((type) => type == 'browser.driver.pageChanged')
              .length >=
          2,
    );
    final sensitiveIndex = client.types.lastIndexOf(
      'browser.driver.pageChanged',
    );
    expect(client.payloads[sensitiveIndex]['title'], isNull);
  });

  for (final scenario
      in <({String method, String engineCall, Map<String, Object?> params})>[
        (
          method: 'browser.navigate',
          engineCall: 'load:page-1',
          params: <String, Object?>{'url': 'https://example.com/next'},
        ),
        (
          method: 'browser.back',
          engineCall: 'back:page-1',
          params: const <String, Object?>{},
        ),
        (
          method: 'browser.forward',
          engineCall: 'forward:page-1',
          params: const <String, Object?>{},
        ),
        (
          method: 'browser.reload',
          engineCall: 'reload:page-1',
          params: const <String, Object?>{},
        ),
      ]) {
    test(
      'preserves ${scenario.method} when document start precedes completion',
      () async {
        final navigation = Completer<void>();
        engine.navigationCompleter = navigation;
        client.events.add(
          RuntimeHostEvent('browserDriverRequest', <String, Object?>{
            'driverInstanceId': 'driver-instance',
            'correlationId': 'navigation-call',
            'pageId': 'page-1',
            'generation': 1,
            'method': scenario.method,
            'params': scenario.params,
            'deadlineAt': DateTime.utc(
              2026,
              1,
              1,
            ).add(const Duration(minutes: 1)).millisecondsSinceEpoch,
          }),
        );
        await _waitFor(() => engine.calls.contains(scenario.engineCall));

        engine.eventController.add(
          BrowserNavigationStarted(
            pageId: 'page-1',
            occurredAt: .utc(2026),
            url: Uri.parse('https://example.com/next'),
          ),
        );
        await _waitFor(
          () => client.payloads.any(
            (payload) =>
                payload['navigationCorrelationId'] == 'navigation-call',
          ),
        );
        expect(driver.debugActiveCallCount, 1);

        navigation.complete();
        await _waitFor(
          () => client.payloads.any(
            (payload) => payload['correlationId'] == 'navigation-call',
          ),
        );

        final completion = client.payloads.lastWhere(
          (payload) => payload['correlationId'] == 'navigation-call',
        );
        expect(completion['generation'], 2);
        final outcome = completion['outcome']! as Map<Object?, Object?>;
        expect(outcome['ok'], isTrue);
      },
    );
  }

  test(
    'reports a document start after navigation completion normally',
    () async {
      client.events.add(
        RuntimeHostEvent('browserDriverRequest', <String, Object?>{
          'driverInstanceId': 'driver-instance',
          'correlationId': 'completed-navigation',
          'pageId': 'page-1',
          'generation': 1,
          'method': 'browser.reload',
          'deadlineAt': DateTime.utc(
            2026,
            1,
            1,
          ).add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        }),
      );
      await _waitFor(
        () => client.payloads.any(
          (payload) => payload['correlationId'] == 'completed-navigation',
        ),
      );
      final completion = client.payloads.lastWhere(
        (payload) => payload['correlationId'] == 'completed-navigation',
      );
      expect(completion['generation'], 1);

      engine.eventController.add(
        BrowserNavigationStarted(
          pageId: 'page-1',
          occurredAt: .utc(2026),
          url: Uri.parse('https://example.com/reloaded'),
        ),
      );
      await _waitFor(
        () =>
            client.types
                .where((type) => type == 'browser.driver.pageChanged')
                .length ==
            1,
      );
      final changeIndex = client.types.indexOf('browser.driver.pageChanged');
      expect(
        client.payloads[changeIndex].containsKey('navigationCorrelationId'),
        isFalse,
      );
    },
  );

  test('rejects stale driver generations before touching the page', () async {
    client.events.add(
      RuntimeHostEvent('browserDriverRequest', <String, Object?>{
        'driverInstanceId': 'driver-instance',
        'correlationId': 'stale-call',
        'pageId': 'page-1',
        'generation': 99,
        'method': 'browser.back',
        'deadlineAt': DateTime.utc(
          2026,
          1,
          1,
        ).add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      }),
    );
    await _waitFor(
      () => client.payloads.any(
        (payload) => payload['correlationId'] == 'stale-call',
      ),
    );

    final completion = client.payloads.lastWhere(
      (payload) => payload['correlationId'] == 'stale-call',
    );
    final outcome = completion['outcome']! as Map<Object?, Object?>;
    final error = outcome['error']! as Map<Object?, Object?>;
    expect(outcome['ok'], isFalse);
    expect(error['code'], 'stale_automation_reference');
    expect(engine.calls, isNot(contains('back:page-1')));
  });

  test('blocks requests locally while navigation invalidates a page', () async {
    engine.eventController.add(
      BrowserNavigationStarted(
        pageId: 'page-1',
        occurredAt: .utc(2026),
        url: Uri.parse('https://example.com/next'),
      ),
    );
    client.events.add(
      RuntimeHostEvent('browserDriverRequest', <String, Object?>{
        'driverInstanceId': 'driver-instance',
        'correlationId': 'navigation-race',
        'pageId': 'page-1',
        'generation': 1,
        'method': 'browser.back',
        'deadlineAt': DateTime.utc(
          2026,
          1,
          1,
        ).add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      }),
    );
    await _waitFor(
      () => client.payloads.any(
        (payload) => payload['correlationId'] == 'navigation-race',
      ),
    );

    final completion = client.payloads.lastWhere(
      (payload) => payload['correlationId'] == 'navigation-race',
    );
    final outcome = completion['outcome']! as Map<Object?, Object?>;
    expect(outcome['ok'], isFalse);
    expect(engine.calls, isNot(contains('back:page-1')));
  });

  test(
    'cancelled native work drains before another command or close',
    () async {
      final snapshot = Completer<BrowserAutomationSnapshot>();
      engine.snapshotCompleter = snapshot;
      client.events.add(
        RuntimeHostEvent('browserDriverRequest', <String, Object?>{
          'driverInstanceId': 'driver-instance',
          'correlationId': 'cancelled-call',
          'pageId': 'page-1',
          'generation': 1,
          'method': 'browser.snapshot',
          'deadlineAt': DateTime.utc(
            2026,
            1,
            1,
          ).add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        }),
      );
      await _waitFor(() => driver.debugActiveCallCount == 1);
      await _waitFor(() => engine.lastSnapshotMaxNodes != null);
      client.events.add(
        RuntimeHostEvent('browserDriverCancel', <String, Object?>{
          'correlationId': 'cancelled-call',
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(driver.debugActiveCallCount, 1);

      client.events.add(
        RuntimeHostEvent('browserDriverRequest', <String, Object?>{
          'driverInstanceId': 'driver-instance',
          'correlationId': 'while-draining',
          'pageId': 'page-1',
          'generation': 1,
          'method': 'browser.back',
          'deadlineAt': DateTime.utc(
            2026,
            1,
            1,
          ).add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        }),
      );
      await _waitFor(
        () => client.payloads.any(
          (payload) => payload['correlationId'] == 'while-draining',
        ),
      );
      final rejected = client.payloads.lastWhere(
        (payload) => payload['correlationId'] == 'while-draining',
      );
      final rejectedOutcome = rejected['outcome']! as Map<Object?, Object?>;
      expect(
        (rejectedOutcome['error']! as Map<Object?, Object?>)['code'],
        'operation_in_progress',
      );
      expect(engine.calls, isNot(contains('back:page-1')));

      var closed = false;
      final close = registry.closePage('page-1').then((_) => closed = true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(closed, isFalse);

      snapshot.complete(
        BrowserAutomationSnapshot(
          pageId: 'page-1',
          snapshotId: 'snapshot',
          url: Uri.parse('https://example.com'),
          title: 'Example',
          nodes: const <BrowserAutomationNode>[],
          capturedAt: .utc(2026),
        ),
      );
      await close.timeout(const Duration(seconds: 1));
      await _waitFor(() => driver.debugActiveCallCount == 0);
      expect(
        client.payloads.where(
          (payload) => payload['correlationId'] == 'cancelled-call',
        ),
        isEmpty,
      );
    },
  );

  test('deadline keeps native work quarantined until it drains', () async {
    final snapshot = Completer<BrowserAutomationSnapshot>();
    engine.snapshotCompleter = snapshot;
    client.events.add(
      RuntimeHostEvent('browserDriverRequest', <String, Object?>{
        'driverInstanceId': 'driver-instance',
        'correlationId': 'deadline-call',
        'pageId': 'page-1',
        'generation': 1,
        'method': 'browser.snapshot',
        'deadlineAt': DateTime.utc(
          2026,
          1,
          1,
        ).add(const Duration(milliseconds: 5)).millisecondsSinceEpoch,
      }),
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(driver.debugActiveCallCount, 1);
    var closed = false;
    final close = registry.closePage('page-1').then((_) => closed = true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(closed, isFalse);

    snapshot.complete(
      BrowserAutomationSnapshot(
        pageId: 'page-1',
        snapshotId: 'snapshot',
        url: Uri.parse('https://example.com'),
        title: 'Example',
        nodes: const <BrowserAutomationNode>[],
        capturedAt: .utc(2026),
      ),
    );
    await close.timeout(const Duration(seconds: 1));
    await _waitFor(() => driver.debugActiveCallCount == 0);

    final completion = client.payloads.lastWhere(
      (payload) => payload['correlationId'] == 'deadline-call',
    );
    final outcome = completion['outcome']! as Map<Object?, Object?>;
    final error = outcome['error']! as Map<Object?, Object?>;
    expect(error['code'], 'timeout');
  });
}

typedef _FakeRuntimeHostClient = FakeBrowserRuntimeHostClient;

Future<void> _waitFor(bool Function() predicate) =>
    waitForBrowserRuntime(predicate);

WorkspaceTabRecord _tab() => browserRuntimeTestTab();
