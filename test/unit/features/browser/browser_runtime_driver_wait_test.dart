import 'package:alera/src/features/browser/application/browser_session_registry.dart';
import 'package:alera/src/features/browser/domain/browser_engine_event.dart';
import 'package:alera/src/features/browser/infra/browser_runtime_driver.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'browser_runtime_driver_test_support.dart';
import 'fake_browser_engine.dart';

void main() {
  late FakeBrowserEngine engine;
  late BrowserSessionRegistry registry;
  late FakeBrowserRuntimeHostClient client;
  late BrowserRuntimeDriver driver;

  setUp(() async {
    engine = FakeBrowserEngine();
    registry = BrowserSessionRegistry(engine: engine);
    await registry.sessionFor(browserRuntimeTestTab());
    client = FakeBrowserRuntimeHostClient();
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

  test('finished pages have reached every supported load threshold', () async {
    for (final phase in <String>['started', 'committed', 'finished']) {
      final correlationId = 'finished-$phase';
      _requestWait(client, correlationId, phase);
      final completion = await _completion(client, correlationId);
      final outcome = completion['outcome']! as Map<Object?, Object?>;

      expect(outcome['ok'], isTrue);
      expect(outcome['loadState'], 'finished');
    }
  });

  test(
    'committed and finished thresholds wait for their exact milestones',
    () async {
      _emitStarted(engine);
      await waitForBrowserRuntime(() => client.generation == 2);

      _requestWait(client, 'committed', 'committed');
      await waitForBrowserRuntime(() => driver.debugActiveCallCount == 1);
      _emitCommitted(engine);
      final committed = await _completion(client, 'committed');
      expect(
        (committed['outcome']! as Map<Object?, Object?>)['loadState'],
        'committed',
      );

      _requestWait(client, 'finished', 'finished');
      await waitForBrowserRuntime(() => driver.debugActiveCallCount == 1);
      _emitFinished(engine);
      final finished = await _completion(client, 'finished');
      expect(
        (finished['outcome']! as Map<Object?, Object?>)['loadState'],
        'finished',
      );
    },
  );

  test('rejects unsupported load state values', () async {
    _requestWait(client, 'invalid', 'idle');

    final completion = await _completion(client, 'invalid');
    final outcome = completion['outcome']! as Map<Object?, Object?>;
    final error = outcome['error']! as Map<Object?, Object?>;

    expect(error['code'], 'invalid_payload');
  });
}

void _requestWait(
  FakeBrowserRuntimeHostClient client,
  String correlationId,
  String loadState,
) {
  client.events.add(
    RuntimeHostEvent('browserDriverRequest', <String, Object?>{
      'driverInstanceId': 'driver-instance',
      'correlationId': correlationId,
      'pageId': 'page-1',
      'generation': client.generation,
      'method': 'browser.wait',
      'params': <String, Object?>{'loadState': loadState},
      'deadlineAt': DateTime.utc(
        2026,
        1,
        1,
      ).add(const Duration(minutes: 1)).millisecondsSinceEpoch,
    }),
  );
}

Future<Map<String, Object?>> _completion(
  FakeBrowserRuntimeHostClient client,
  String correlationId,
) async {
  await waitForBrowserRuntime(
    () => client.payloads.any(
      (payload) => payload['correlationId'] == correlationId,
    ),
  );
  return client.payloads.lastWhere(
    (payload) => payload['correlationId'] == correlationId,
  );
}

void _emitStarted(FakeBrowserEngine engine) {
  engine.eventController.add(
    BrowserNavigationStarted(
      pageId: 'page-1',
      occurredAt: .utc(2026),
      url: Uri.parse('https://example.com/next'),
    ),
  );
}

void _emitCommitted(FakeBrowserEngine engine) {
  engine.eventController.add(
    BrowserNavigationCommitted(
      pageId: 'page-1',
      occurredAt: .utc(2026),
      url: Uri.parse('https://example.com/next'),
    ),
  );
}

void _emitFinished(FakeBrowserEngine engine) {
  engine.eventController.add(
    BrowserNavigationFinished(
      pageId: 'page-1',
      occurredAt: .utc(2026),
      url: Uri.parse('https://example.com/next'),
      title: 'Next',
    ),
  );
}
