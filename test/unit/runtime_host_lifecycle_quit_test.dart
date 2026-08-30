import 'package:alera/src/features/runtime_host/application/runtime_host_lifecycle_service.dart';
import 'package:alera/src/features/runtime_host/domain/runtime_host_quit_decision.dart';
import 'package:alera/src/features/runtime_host/domain/runtime_host_status.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'runtime_host_lifecycle_fakes.dart';

void main() {
  group('RuntimeHostLifecycleService quit', () {
    test(
      'prepareAppQuit skips shutdown when keepRuntimeOpen is true',
      () async {
        final client = FakeRuntimeHostLifecycleClient(
          status: <String, Object?>{
            'runtimeHostVersion': '1.2.0',
            'persistent': false,
          },
        );
        final service = RuntimeHostLifecycleService(
          client: client,
          bundledVersionProbe: FakeBundledSidecarVersionProbe(
            const BundledSidecarVersion(version: '1.2.0'),
          ),
          readConfig: () => TerminalHostConfig.defaults,
        );

        final allowed = await service.prepareAppQuit(keepRuntimeOpen: true);

        expect(allowed, isTrue);
        expect(client.shutdownCalls, isEmpty);
      },
    );

    test('prepareAppQuit skips shutdown for persistent hosts', () async {
      final client = FakeRuntimeHostLifecycleClient(
        status: <String, Object?>{
          'runtimeHostVersion': '1.2.0',
          'persistent': true,
        },
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: FakeBundledSidecarVersionProbe(
          const BundledSidecarVersion(version: '1.2.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
      );

      final allowed = await service.prepareAppQuit(keepRuntimeOpen: false);

      expect(allowed, isTrue);
      expect(client.shutdownCalls, isEmpty);
    });

    test('prepareAppQuit leaves an active push runtime running', () async {
      final client = FakeRuntimeHostLifecycleClient(
        status: <String, Object?>{
          'runtimeHostVersion': '1.2.0',
          'persistent': false,
          'activePushSubscriptions': 1,
        },
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: FakeBundledSidecarVersionProbe(
          const BundledSidecarVersion(version: '1.2.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
      );

      final allowed = await service.prepareAppQuit(keepRuntimeOpen: false);

      expect(allowed, isTrue);
      expect(client.shutdownCalls, isEmpty);
    });

    test('prepareAppQuit soft-stops when status probe fails', () async {
      final client = FakeRuntimeHostLifecycleClient(
        status: <String, Object?>{
          'runtimeHostVersion': '1.2.0',
          'persistent': false,
        },
        probeThrows: true,
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: FakeBundledSidecarVersionProbe(
          const BundledSidecarVersion(version: '1.2.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
        shutdownSettleTimeout: const Duration(milliseconds: 50),
      );

      final allowed = await service.prepareAppQuit(keepRuntimeOpen: false);

      expect(allowed, isTrue);
      expect(client.shutdownCalls, <bool>[false]);
    });

    test('prepareAppQuit soft-stops an idle sidecar', () async {
      final client = FakeRuntimeHostLifecycleClient(
        status: <String, Object?>{
          'runtimeHostVersion': '1.2.0',
          'persistent': false,
        },
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: FakeBundledSidecarVersionProbe(
          const BundledSidecarVersion(version: '1.2.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
        shutdownSettleTimeout: const Duration(milliseconds: 50),
      );

      final allowed = await service.prepareAppQuit(keepRuntimeOpen: false);

      expect(allowed, isTrue);
      expect(client.shutdownCalls, <bool>[false]);
    });

    test('prepareAppQuit does not wait for detached host cleanup', () async {
      final client = FakeRuntimeHostLifecycleClient(
        status: <String, Object?>{
          'runtimeHostVersion': '1.2.0',
          'persistent': false,
        },
        shutdownLeavesHostRunning: true,
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: FakeBundledSidecarVersionProbe(
          const BundledSidecarVersion(version: '1.2.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
        shutdownSettleTimeout: const Duration(seconds: 5),
      );

      final allowed = await service.prepareAppQuit(keepRuntimeOpen: false);

      expect(allowed, isTrue);
      expect(client.shutdownCalls, <bool>[false]);
      expect(await client.probeRuntimeStatus(), isNotNull);
    });

    test('prepareAppQuit cancels when busy quit is declined', () async {
      final client = FakeRuntimeHostLifecycleClient(
        status: <String, Object?>{
          'runtimeHostVersion': '1.2.0',
          'persistent': false,
        },
        busyOnSoftStop: true,
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: FakeBundledSidecarVersionProbe(
          const BundledSidecarVersion(version: '1.2.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
      );

      final allowed = await service.prepareAppQuit(
        keepRuntimeOpen: false,
        confirmBusyQuit: ({
          required String title,
          required String message,
        }) async => RuntimeHostQuitDecision.cancel,
      );

      expect(allowed, isFalse);
      expect(client.shutdownCalls, <bool>[false]);
    });

    test(
      'prepareAppQuit leaves host running when busy quit chooses leave',
      () async {
        final client = FakeRuntimeHostLifecycleClient(
          status: <String, Object?>{
            'runtimeHostVersion': '1.2.0',
            'persistent': false,
          },
          busyOnSoftStop: true,
        );
        final service = RuntimeHostLifecycleService(
          client: client,
          bundledVersionProbe: FakeBundledSidecarVersionProbe(
            const BundledSidecarVersion(version: '1.2.0'),
          ),
          readConfig: () => TerminalHostConfig.defaults,
        );

        final allowed = await service.prepareAppQuit(
          keepRuntimeOpen: false,
          confirmBusyQuit: ({
            required String title,
            required String message,
          }) async => RuntimeHostQuitDecision.leaveRuntimeOpen,
        );

        expect(allowed, isTrue);
        expect(client.shutdownCalls, <bool>[false]);
        expect(await client.probeRuntimeStatus(), isNotNull);
      },
    );

    test('prepareAppQuit force-stops when busy quit chooses force', () async {
      final client = FakeRuntimeHostLifecycleClient(
        status: <String, Object?>{
          'runtimeHostVersion': '1.2.0',
          'persistent': false,
        },
        busyOnSoftStop: true,
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: FakeBundledSidecarVersionProbe(
          const BundledSidecarVersion(version: '1.2.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
        shutdownSettleTimeout: const Duration(milliseconds: 50),
      );

      final allowed = await service.prepareAppQuit(
        keepRuntimeOpen: false,
        confirmBusyQuit: ({
          required String title,
          required String message,
        }) async => RuntimeHostQuitDecision.forceStop,
      );

      expect(allowed, isTrue);
      expect(client.shutdownCalls, <bool>[false, true]);
    });

    test('prepareAppQuit treats a shutdown disconnect as success', () async {
      final client = FakeRuntimeHostLifecycleClient(
        status: <String, Object?>{
          'runtimeHostVersion': '1.2.0',
          'persistent': false,
        },
        shutdownErrorOnSoft: const TerminalHostConnectionClosedException(),
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: FakeBundledSidecarVersionProbe(
          const BundledSidecarVersion(version: '1.2.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
      );

      final allowed = await service.prepareAppQuit(keepRuntimeOpen: false);

      expect(allowed, isTrue);
      expect(client.shutdownCalls, <bool>[false]);
    });
  });
}
