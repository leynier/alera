import 'package:alera/src/features/runtime_host/application/runtime_host_lifecycle_service.dart';
import 'package:alera/src/features/runtime_host/domain/runtime_host_quit_decision.dart';
import 'package:alera/src/features/runtime_host/domain/runtime_host_status.dart';
import 'package:alera/src/features/runtime_host/infra/bundled_sidecar_version_probe.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuntimeHostLifecycleService', () {
    test('loadStatus reports stopped when probe returns null', () async {
      final client = _FakeRuntimeClient(status: null);
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: _FakeBundledProbe(
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
      final client = _FakeRuntimeClient(
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
        bundledVersionProbe: _FakeBundledProbe(
          const BundledSidecarVersion(version: '1.3.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
      );

      final status = await service.loadStatus();

      expect(status.running, isTrue);
      expect(status.updateAvailable, isTrue);
      expect(status.activeSessions, 1);
    });

    test('prepareAppQuit skips shutdown when keepRuntimeOpen is true', () async {
      final client = _FakeRuntimeClient(
        status: <String, Object?>{
          'runtimeHostVersion': '1.2.0',
          'persistent': false,
        },
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: _FakeBundledProbe(
          const BundledSidecarVersion(version: '1.2.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
      );

      final allowed = await service.prepareAppQuit(keepRuntimeOpen: true);

      expect(allowed, isTrue);
      expect(client.shutdownCalls, isEmpty);
    });

    test('prepareAppQuit skips shutdown for persistent hosts', () async {
      final client = _FakeRuntimeClient(
        status: <String, Object?>{
          'runtimeHostVersion': '1.2.0',
          'persistent': true,
        },
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: _FakeBundledProbe(
          const BundledSidecarVersion(version: '1.2.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
      );

      final allowed = await service.prepareAppQuit(keepRuntimeOpen: false);

      expect(allowed, isTrue);
      expect(client.shutdownCalls, isEmpty);
    });

    test('prepareAppQuit soft-stops when status probe fails', () async {
      final client = _FakeRuntimeClient(
        status: <String, Object?>{
          'runtimeHostVersion': '1.2.0',
          'persistent': false,
        },
        probeThrows: true,
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: _FakeBundledProbe(
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
      final client = _FakeRuntimeClient(
        status: <String, Object?>{
          'runtimeHostVersion': '1.2.0',
          'persistent': false,
        },
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: _FakeBundledProbe(
          const BundledSidecarVersion(version: '1.2.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
        shutdownSettleTimeout: const Duration(milliseconds: 50),
      );

      final allowed = await service.prepareAppQuit(keepRuntimeOpen: false);

      expect(allowed, isTrue);
      expect(client.shutdownCalls, <bool>[false]);
    });

    test('prepareAppQuit cancels when busy quit is declined', () async {
      final client = _FakeRuntimeClient(
        status: <String, Object?>{
          'runtimeHostVersion': '1.2.0',
          'persistent': false,
        },
        busyOnSoftStop: true,
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: _FakeBundledProbe(
          const BundledSidecarVersion(version: '1.2.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
      );

      final allowed = await service.prepareAppQuit(
        keepRuntimeOpen: false,
        confirmBusyQuit:
            ({required String title, required String message}) async =>
                RuntimeHostQuitDecision.cancel,
      );

      expect(allowed, isFalse);
      expect(client.shutdownCalls, <bool>[false]);
    });

    test('prepareAppQuit leaves host running when busy quit chooses leave', () async {
      final client = _FakeRuntimeClient(
        status: <String, Object?>{
          'runtimeHostVersion': '1.2.0',
          'persistent': false,
        },
        busyOnSoftStop: true,
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: _FakeBundledProbe(
          const BundledSidecarVersion(version: '1.2.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
      );

      final allowed = await service.prepareAppQuit(
        keepRuntimeOpen: false,
        confirmBusyQuit:
            ({required String title, required String message}) async =>
                RuntimeHostQuitDecision.leaveRuntimeOpen,
      );

      expect(allowed, isTrue);
      expect(client.shutdownCalls, <bool>[false]);
      expect(await client.probeRuntimeStatus(), isNotNull);
    });

    test('prepareAppQuit force-stops when busy quit chooses force', () async {
      final client = _FakeRuntimeClient(
        status: <String, Object?>{
          'runtimeHostVersion': '1.2.0',
          'persistent': false,
        },
        busyOnSoftStop: true,
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: _FakeBundledProbe(
          const BundledSidecarVersion(version: '1.2.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
        shutdownSettleTimeout: const Duration(milliseconds: 50),
      );

      final allowed = await service.prepareAppQuit(
        keepRuntimeOpen: false,
        confirmBusyQuit:
            ({required String title, required String message}) async =>
                RuntimeHostQuitDecision.forceStop,
      );

      expect(allowed, isTrue);
      expect(client.shutdownCalls, <bool>[false, true]);
    });

    test('updateIfNewer stops and starts when bundled is newer', () async {
      final client = _FakeRuntimeClient(
        status: <String, Object?>{'runtimeHostVersion': '1.2.0'},
      );
      final service = RuntimeHostLifecycleService(
        client: client,
        bundledVersionProbe: _FakeBundledProbe(
          const BundledSidecarVersion(version: '1.3.0'),
        ),
        readConfig: () => TerminalHostConfig.defaults,
        shutdownSettleTimeout: const Duration(milliseconds: 50),
      );

      await service.updateIfNewer();

      expect(client.shutdownCalls, <bool>[false]);
      expect(client.ensureStartedCalls, 1);
    });

    test('runtimeHostBusyMessage leads with agents', () {
      expect(
        runtimeHostBusyMessage(
          const RuntimeHostBusyException(
            message: 'busy',
            activeAgents: 2,
            activeSessions: 1,
            activeJobs: 0,
          ),
        ),
        'The runtime has 2 open agent(s) and 1 active terminal session(s).',
      );
    });
  });
}

final class _FakeBundledProbe implements BundledSidecarVersionProbe {
  _FakeBundledProbe(this.version);

  final BundledSidecarVersion version;

  @override
  Future<BundledSidecarVersion> probe() async => version;
}

final class _FakeRuntimeClient implements RuntimeHostLifecycleClient {
  _FakeRuntimeClient({
    this.status,
    this.busyOnSoftStop = false,
    this.probeThrows = false,
  });

  Map<String, Object?>? status;
  final bool busyOnSoftStop;
  final bool probeThrows;
  final List<bool> shutdownCalls = <bool>[];
  int ensureStartedCalls = 0;
  bool _stopped = false;

  @override
  Future<Map<String, Object?>?> probeRuntimeStatus() async {
    if (probeThrows && !_stopped) {
      throw StateError('status probe failed');
    }
    if (_stopped) {
      return null;
    }
    return status;
  }

  @override
  Future<RuntimeHostShutdownResult> shutdownRuntime({
    bool force = false,
  }) async {
    shutdownCalls.add(force);
    if (!force && busyOnSoftStop) {
      throw const RuntimeHostBusyException(
        message:
            'Runtime host has 1 active agent(s), 1 active terminal session(s) and 0 active background job(s).',
        activeAgents: 1,
        activeSessions: 1,
      );
    }
    _stopped = true;
    status = null;
    return RuntimeHostShutdownResult(stopped: true, forced: force);
  }

  @override
  Future<void> ensureStarted({required TerminalHostConfig config}) async {
    ensureStartedCalls += 1;
    _stopped = false;
    status ??= <String, Object?>{'runtimeHostVersion': '1.3.0'};
  }
}
