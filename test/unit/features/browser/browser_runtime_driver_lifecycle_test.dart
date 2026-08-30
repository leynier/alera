import 'dart:async';

import 'package:alera/src/features/browser/application/browser_session_registry.dart';
import 'package:alera/src/features/browser/domain/browser_engine_models.dart';
import 'package:alera/src/features/browser/infra/browser_runtime_driver.dart';
import 'package:flutter_test/flutter_test.dart';

import 'browser_runtime_driver_test_support.dart';
import 'fake_browser_engine.dart';

void main() {
  test('dispose cannot register a driver after a delayed start', () async {
    final engine = FakeBrowserEngine();
    final capabilities = Completer<BrowserEngineCapabilities>();
    engine.capabilitiesCompleter = capabilities;
    final registry = BrowserSessionRegistry(engine: engine);
    final client = FakeBrowserRuntimeHostClient();
    final driver = BrowserRuntimeDriver(
      client: client,
      registry: registry,
      engine: engine,
      appInstanceId: 'app-instance',
      driverInstanceId: 'driver-instance',
    );
    addTearDown(() async {
      await driver.dispose();
      await registry.dispose();
      await engine.dispose();
      await client.dispose();
    });

    final starting = driver.start();
    await Future<void>.delayed(.zero);
    await driver.dispose();
    capabilities.complete(stableBrowserCapabilities);
    await starting;

    expect(client.types, isNot(contains('browser.driver.register')));
    expect(client.types, isNot(contains('browser.driver.sync')));
  });
}
