import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/browser/application/browser_session_registry.dart';
import 'package:alera/src/features/browser/domain/browser_engine_models.dart';
import 'package:alera/src/features/browser/infra/browser_runtime_driver.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'browser_runtime_driver_test_support.dart';
import 'fake_browser_engine.dart';

void main() {
  test(
    'cancelled capture removes an artifact written while draining',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'alera-browser-artifact-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final destination = File('${directory.path}/capture.png');
      final engine = FakeBrowserEngine();
      final capture = Completer<BrowserArtifactResult>();
      engine.screenshotCompleter = capture;
      final registry = BrowserSessionRegistry(engine: engine);
      await registry.sessionFor(browserRuntimeTestTab());
      final client = FakeBrowserRuntimeHostClient();
      final driver = BrowserRuntimeDriver(
        client: client,
        registry: registry,
        engine: engine,
        appInstanceId: 'app-instance',
        driverInstanceId: 'driver-instance',
        now: () => DateTime.utc(2026),
      );
      await driver.start();
      addTearDown(() async {
        await driver.dispose();
        await registry.dispose();
        await engine.dispose();
        await client.dispose();
      });

      client.events.add(
        RuntimeHostEvent('browserDriverRequest', <String, Object?>{
          'driverInstanceId': 'driver-instance',
          'correlationId': 'capture',
          'pageId': 'page-1',
          'generation': 1,
          'method': 'browser.screenshot',
          'params': <String, Object?>{
            'destinationPath': destination.path,
            'expiresAt': DateTime.utc(2026, 1, 2).toIso8601String(),
          },
          'deadlineAt': DateTime.utc(
            2026,
            1,
            1,
          ).add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        }),
      );
      await waitForBrowserRuntime(
        () => engine.calls.any((call) => call.startsWith('screenshot:')),
      );
      client.events.add(
        const RuntimeHostEvent('browserDriverCancel', <String, Object?>{
          'correlationId': 'capture',
        }),
      );

      await destination.writeAsBytes(<int>[1, 2, 3], flush: true);
      capture.complete(
        BrowserArtifactResult(
          path: destination.path,
          mimeType: 'image/png',
          sizeBytes: 3,
          expiresAt: .utc(2026, 1, 2),
        ),
      );

      await waitForBrowserRuntime(() => driver.debugActiveCallCount == 0);
      expect(await destination.exists(), isFalse);
      expect(
        client.payloads.where(
          (payload) => payload['correlationId'] == 'capture',
        ),
        isEmpty,
      );
    },
  );
}
