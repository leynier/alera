import 'package:alera/src/features/runtime_host/application/runtime_host_lifecycle_service.dart';
import 'package:alera/src/features/runtime_host/domain/runtime_host_status.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'runtime_host_lifecycle_fakes.dart';

void main() {
  group('RuntimeHostLifecycleService', () {
    test('loadStatus reports stopped when probe returns null', () async {
      final client = FakeRuntimeHostLifecycleClient(status: null);
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: FakeBundledSidecarVersionProbe(
          const BundledSidecarVersion(version: '1.3.0', commit: 'abc'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
      );

      final status = await service.loadStatus();

      expect(status.running, isFalse);
      expect(status.bundledVersion, '1.3.0');
      expect(status.updateAvailable, isFalse);
    });

    test('loadStatus reports update when bundled is newer', () async {
      final client = FakeRuntimeHostLifecycleClient(
        status: <String, Object?>{
          'runtimeHostVersion': '1.2.0',
          'runtimeHostCommit': 'old',
          'persistent': false,
          'activeSessions': 1,
          'activeAgents': 0,
        },
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: FakeBundledSidecarVersionProbe(
          const BundledSidecarVersion(version: '1.3.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
      );

      final status = await service.loadStatus();

      expect(status.running, isTrue);
      expect(status.updateAvailable, isTrue);
      expect(status.activeSessions, 1);
    });

    test('start propagates a terminal host startup failure', () async {
      final error = TerminalHostStartupException(StateError('sidecar failed'));
      final client = FakeRuntimeHostLifecycleClient(ensureStartedError: error);
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: FakeBundledSidecarVersionProbe(
          const BundledSidecarVersion(version: '1.3.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
      );

      await expectLater(service.start(), throwsA(same(error)));

      expect(client.ensureStartedCalls, 1);
    });

    test('updateIfAvailable stops and starts when bundled is newer', () async {
      final client = FakeRuntimeHostLifecycleClient(
        status: <String, Object?>{'runtimeHostVersion': '1.2.0'},
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: FakeBundledSidecarVersionProbe(
          const BundledSidecarVersion(version: '1.3.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
        shutdownSettleTimeout: const Duration(milliseconds: 50),
      );

      await service.updateIfAvailable();

      expect(client.shutdownCalls, <bool>[false]);
      expect(client.ensureStartedCalls, 1);
    });

    test('updateIfAvailable replaces a different same-version build', () async {
      final client = FakeRuntimeHostLifecycleClient(
        status: <String, Object?>{
          'runtimeHostVersion': '0.1.0',
          'runtimeHostCommit': '1032e34',
        },
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: FakeBundledSidecarVersionProbe(
          const BundledSidecarVersion(version: '0.1.0', commit: '9d848d7'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
        shutdownSettleTimeout: const Duration(milliseconds: 50),
      );

      await service.updateIfAvailable();

      expect(client.shutdownCalls, <bool>[false]);
      expect(client.ensureStartedCalls, 1);
    });

    test('updateIfAvailable preserves a busy host when declined', () async {
      final client = FakeRuntimeHostLifecycleClient(
        status: <String, Object?>{
          'runtimeHostVersion': '0.1.0',
          'runtimeHostCommit': 'old',
        },
        busyOnSoftStop: true,
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: FakeBundledSidecarVersionProbe(
          const BundledSidecarVersion(version: '0.1.0', commit: 'new'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
      );

      await service.updateIfAvailable(
        confirmForce:
            ({
              required String title,
              required String message,
              required String confirmLabel,
            }) async => false,
      );

      expect(client.shutdownCalls, <bool>[false]);
      expect(client.ensureStartedCalls, 0);
      expect(await client.probeRuntimeStatus(), isNotNull);
    });

    test('updateIfAvailable force replaces a confirmed busy host', () async {
      final client = FakeRuntimeHostLifecycleClient(
        status: <String, Object?>{
          'runtimeHostVersion': '0.1.0',
          'runtimeHostCommit': 'old',
        },
        busyOnSoftStop: true,
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: FakeBundledSidecarVersionProbe(
          const BundledSidecarVersion(version: '0.1.0', commit: 'new'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
        shutdownSettleTimeout: const Duration(milliseconds: 50),
      );

      await service.updateIfAvailable(
        confirmForce:
            ({
              required String title,
              required String message,
              required String confirmLabel,
            }) async => true,
      );

      expect(client.shutdownCalls, <bool>[false, true]);
      expect(client.ensureStartedCalls, 1);
    });

    test(
      'updateIfAvailable continues when force shutdown closes the connection',
      () async {
        final client = FakeRuntimeHostLifecycleClient(
          status: <String, Object?>{
            'runtimeHostVersion': '0.1.0',
            'runtimeHostCommit': 'old',
          },
          busyOnSoftStop: true,
          shutdownErrorOnForce: const TerminalHostConnectionClosedException(),
        );
        final service = RuntimeHostLifecycleService(
          client: client,
          bundledVersionProbe: FakeBundledSidecarVersionProbe(
            const BundledSidecarVersion(version: '0.1.0', commit: 'new'),
          ),
          readConfig: () => TerminalHostConfig.defaults,
          shutdownSettleTimeout: const Duration(milliseconds: 50),
        );

        await service.updateIfAvailable(
          confirmForce:
              ({
                required String title,
                required String message,
                required String confirmLabel,
              }) async => true,
        );

        expect(client.shutdownCalls, <bool>[false, true]);
        expect(client.ensureStartedCalls, 1);
      },
    );

    test(
      'updateIfAvailable continues when shutdown reports the host already gone',
      () async {
        final client = FakeRuntimeHostLifecycleClient(
          status: <String, Object?>{
            'runtimeHostVersion': '0.1.0',
            'runtimeHostCommit': 'old',
          },
          shutdownErrorOnSoft: StateError(
            'No live Alera runtime host is available.',
          ),
        );
        final service = RuntimeHostLifecycleService(
          client: client,
          bundledVersionProbe: FakeBundledSidecarVersionProbe(
            const BundledSidecarVersion(version: '0.1.0', commit: 'new'),
          ),
          readConfig: () => TerminalHostConfig.defaults,
          shutdownSettleTimeout: const Duration(milliseconds: 50),
        );

        await service.updateIfAvailable();

        expect(client.shutdownCalls, <bool>[false]);
        expect(client.ensureStartedCalls, 1);
      },
    );

    test(
      'updateIfAvailable continues when shutdown returns a closed StateError',
      () async {
        final client = FakeRuntimeHostLifecycleClient(
          status: <String, Object?>{
            'runtimeHostVersion': '0.1.0',
            'runtimeHostCommit': 'old',
          },
          shutdownErrorOnSoft: StateError(
            'Terminal host connection closed during authentication.',
          ),
        );
        final service = RuntimeHostLifecycleService(
          client: client,
          bundledVersionProbe: FakeBundledSidecarVersionProbe(
            const BundledSidecarVersion(version: '0.1.0', commit: 'new'),
          ),
          readConfig: () => TerminalHostConfig.defaults,
          shutdownSettleTimeout: const Duration(milliseconds: 50),
        );

        await service.updateIfAvailable();

        expect(client.shutdownCalls, <bool>[false]);
        expect(client.ensureStartedCalls, 1);
      },
    );

    test('stop propagates an unexpected shutdown error', () async {
      final client = FakeRuntimeHostLifecycleClient(
        status: <String, Object?>{'runtimeHostVersion': '1.2.0'},
        shutdownErrorOnSoft: StateError('permission denied'),
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: FakeBundledSidecarVersionProbe(
          const BundledSidecarVersion(version: '1.2.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
      );

      await expectLater(
        service.stop(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('permission denied'),
          ),
        ),
      );
    });

    test(
      'updateIfAvailable retries after a closed status probe then starts',
      () async {
        final client = FakeRuntimeHostLifecycleClient(
          status: <String, Object?>{
            'runtimeHostVersion': '0.1.0',
            'runtimeHostCommit': 'old',
          },
          probeErrorsAfterShutdown: const [
            TerminalHostConnectionClosedException(),
            TerminalHostRequestTimeoutException(
              'status.get',
              Duration(seconds: 10),
            ),
          ],
        );
        final service = RuntimeHostLifecycleService(
          client: client,
          bundledVersionProbe: FakeBundledSidecarVersionProbe(
            const BundledSidecarVersion(version: '0.1.0', commit: 'new'),
          ),
          readConfig: () => TerminalHostConfig.defaults,
          shutdownSettleTimeout: const Duration(milliseconds: 400),
        );

        await service.updateIfAvailable();

        expect(client.shutdownCalls, <bool>[false]);
        expect(client.ensureStartedCalls, 1);
      },
    );

    test('updateIfAvailable treats a missing host probe as stopped', () async {
      final client = FakeRuntimeHostLifecycleClient(
        status: <String, Object?>{
          'runtimeHostVersion': '0.1.0',
          'runtimeHostCommit': 'old',
        },
        probeErrorsAfterShutdown: [
          StateError('No live Alera runtime host is available.'),
        ],
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: FakeBundledSidecarVersionProbe(
          const BundledSidecarVersion(version: '0.1.0', commit: 'new'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
        shutdownSettleTimeout: const Duration(milliseconds: 50),
      );

      await service.updateIfAvailable();

      expect(client.ensureStartedCalls, 1);
    });

    test('stop propagates an unexpected status probe error', () async {
      final client = FakeRuntimeHostLifecycleClient(
        status: <String, Object?>{'runtimeHostVersion': '1.2.0'},
        probeErrorsAfterShutdown: [StateError('status probe failed')],
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: FakeBundledSidecarVersionProbe(
          const BundledSidecarVersion(version: '1.2.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
        shutdownSettleTimeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        service.stop(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('status probe failed'),
          ),
        ),
      );
    });

    test(
      'updateIfAvailable does not start when the host stays up after shutdown',
      () async {
        final client = FakeRuntimeHostLifecycleClient(
          status: <String, Object?>{
            'runtimeHostVersion': '1.2.0',
            'runtimeHostCommit': 'old',
          },
          shutdownLeavesHostRunning: true,
        );
        final service = RuntimeHostLifecycleService(
          client: client,
          bundledVersionProbe: FakeBundledSidecarVersionProbe(
            const BundledSidecarVersion(version: '1.3.0', commit: 'new'),
          ),
          readConfig: () => TerminalHostConfig.defaults,
          shutdownSettleTimeout: const Duration(milliseconds: 50),
        );

        await expectLater(
          service.updateIfAvailable(),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('did not stop in time'),
            ),
          ),
        );
        expect(client.ensureStartedCalls, 0);
      },
    );

    test('runtimeHostBusyMessage leads with agents', () {
      expect(
        runtimeHostBusyMessage(
          const RuntimeHostBusyException(
            message: 'busy',
            activeAgents: 2,
            activeSessions: 1,
            activeJobs: 0,
            activePushSubscriptions: 1,
          ),
        ),
        'The runtime has 2 open agent(s), 1 active terminal session(s), and '
        '1 active push subscription(s).',
      );
    });
  });
}
