import 'package:alera/src/features/runtime_host/application/runtime_host_lifecycle_service.dart';
import 'package:alera/src/features/runtime_host/domain/runtime_host_status.dart';
import 'package:alera/src/features/runtime_host/infra/bundled_sidecar_version_probe.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

final class FakeBundledSidecarVersionProbe
    implements BundledSidecarVersionProbe {
  FakeBundledSidecarVersionProbe(this.version);

  final BundledSidecarVersion version;

  @override
  Future<BundledSidecarVersion> probe() async => version;
}

final class FakeRuntimeHostLifecycleClient
    implements RuntimeHostLifecycleClient {
  FakeRuntimeHostLifecycleClient({
    this.status,
    this.busyOnSoftStop = false,
    this.probeThrows = false,
    this.shutdownLeavesHostRunning = false,
    this.ensureStartedError,
    this.shutdownErrorOnSoft,
    this.shutdownErrorOnForce,
    this.probeErrorsAfterShutdown = const <Object>[],
  });

  Map<String, Object?>? status;
  final bool busyOnSoftStop;
  final bool probeThrows;
  final bool shutdownLeavesHostRunning;
  final Object? ensureStartedError;
  final Object? shutdownErrorOnSoft;
  final Object? shutdownErrorOnForce;
  final List<Object> probeErrorsAfterShutdown;
  final List<bool> shutdownCalls = <bool>[];
  int ensureStartedCalls = 0;
  bool _stopped = false;
  int _probeErrorsConsumed = 0;

  @override
  Future<Map<String, Object?>?> probeRuntimeStatus() async {
    if (probeThrows && !_stopped) {
      throw StateError('status probe failed');
    }
    if (_stopped) {
      if (_probeErrorsConsumed < probeErrorsAfterShutdown.length) {
        final error = probeErrorsAfterShutdown[_probeErrorsConsumed];
        _probeErrorsConsumed += 1;
        throw error;
      }
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
    if (!shutdownLeavesHostRunning) {
      _stopped = true;
      status = null;
    }
    final shutdownError = force ? shutdownErrorOnForce : shutdownErrorOnSoft;
    if (shutdownError != null) {
      throw shutdownError;
    }
    return RuntimeHostShutdownResult(stopped: true, forced: force);
  }

  @override
  Future<void> ensureStarted({required TerminalHostConfig config}) async {
    ensureStartedCalls += 1;
    final error = ensureStartedError;
    if (error != null) {
      throw error;
    }
    _stopped = false;
    status ??= <String, Object?>{'runtimeHostVersion': '1.3.0'};
  }
}
