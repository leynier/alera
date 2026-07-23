import 'dart:async';

import 'package:alera/src/features/runtime_host/domain/runtime_host_status.dart';
import 'package:alera/src/features/runtime_host/infra/bundled_sidecar_version_probe.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

typedef RuntimeHostForceConfirm =
    Future<bool> Function({
      required String title,
      required String message,
      required String confirmLabel,
    });

abstract interface class RuntimeHostLifecycleClient {
  Future<Map<String, Object?>?> probeRuntimeStatus();

  Future<RuntimeHostShutdownResult> shutdownRuntime({bool force = false});

  Future<void> ensureStarted({required TerminalHostConfig config});
}

final class SocketRuntimeHostLifecycleClient
    implements RuntimeHostLifecycleClient {
  SocketRuntimeHostLifecycleClient(this._client);

  final SocketTerminalHostClient _client;

  @override
  Future<Map<String, Object?>?> probeRuntimeStatus() =>
      _client.probeRuntimeStatus();

  @override
  Future<RuntimeHostShutdownResult> shutdownRuntime({bool force = false}) =>
      _client.shutdownRuntime(force: force);

  @override
  Future<void> ensureStarted({required TerminalHostConfig config}) =>
      _client.ensureStarted(config: config);
}

final class RuntimeHostLifecycleService {
  RuntimeHostLifecycleService({
    required this._client,
    required this._bundledVersionProbe,
    required this._readConfig,
    this._shutdownSettleTimeout = const Duration(seconds: 8),
  });

  final RuntimeHostLifecycleClient _client;
  final BundledSidecarVersionProbe _bundledVersionProbe;
  final TerminalHostConfig Function() _readConfig;
  final Duration _shutdownSettleTimeout;

  Future<RuntimeHostStatusSnapshot> loadStatus() async {
    BundledSidecarVersion bundled;
    try {
      bundled = await _bundledVersionProbe.probe();
    } catch (error) {
      return RuntimeHostStatusSnapshot(
        running: false,
        bundledVersion: 'unknown',
        error: error.toString(),
      );
    }
    try {
      final status = await _client.probeRuntimeStatus();
      if (status == null) {
        return RuntimeHostStatusSnapshot(
          running: false,
          bundledVersion: bundled.version,
          bundledCommit: bundled.commit,
        );
      }
      return RuntimeHostStatusSnapshot(
        running: true,
        bundledVersion: bundled.version,
        bundledCommit: bundled.commit,
        runtimeHostVersion: status['runtimeHostVersion'] as String?,
        runtimeHostCommit: status['runtimeHostCommit'] as String?,
        persistent: status['persistent'] == true,
        activeSessions: status['activeSessions'] is int
            ? status['activeSessions'] as int
            : 0,
        activeAgents: status['activeAgents'] is int
            ? status['activeAgents'] as int
            : 0,
      );
    } catch (error) {
      return RuntimeHostStatusSnapshot(
        running: false,
        bundledVersion: bundled.version,
        bundledCommit: bundled.commit,
        error: error.toString(),
      );
    }
  }

  Future<void> start() async {
    await _client.ensureStarted(config: _readConfig());
  }

  Future<void> stop({
    bool force = false,
    RuntimeHostForceConfirm? confirmForce,
  }) async {
    try {
      await _client.shutdownRuntime(force: force);
    } on RuntimeHostBusyException catch (busy) {
      if (force || confirmForce == null) {
        rethrow;
      }
      final confirmed = await confirmForce(
        title: 'Force Stop Runtime',
        message:
            'The runtime has ${busy.activeSessions} active terminal '
            'session(s) and ${busy.activeJobs} active background job(s). '
            'Force stop terminates them.',
        confirmLabel: 'Force Stop',
      );
      if (!confirmed) {
        return;
      }
      await _client.shutdownRuntime(force: true);
    }
    await _waitUntilStopped();
  }

  Future<void> updateIfNewer({
    RuntimeHostForceConfirm? confirmForce,
  }) async {
    final status = await loadStatus();
    if (!status.updateAvailable) {
      return;
    }
    await stop(confirmForce: confirmForce);
    await start();
  }

  /// Soft-stop the runtime when quitting the app. Returns `false` when the
  /// user cancels a force-stop confirmation so the window should stay open.
  Future<bool> prepareAppQuit({
    required bool stopOnQuit,
    RuntimeHostForceConfirm? confirmForce,
  }) async {
    if (!stopOnQuit) {
      return true;
    }
    try {
      await _client.shutdownRuntime(force: false);
      await _waitUntilStopped();
      return true;
    } on StateError catch (error) {
      if (error.message.contains('No live Alera runtime host')) {
        return true;
      }
      rethrow;
    } on RuntimeHostBusyException catch (busy) {
      if (confirmForce == null) {
        return false;
      }
      final confirmed = await confirmForce(
        title: 'Force Stop And Quit',
        message:
            'The runtime has ${busy.activeSessions} active terminal '
            'session(s) and ${busy.activeJobs} active background job(s). '
            'Force stop terminates them and quits Alera.',
        confirmLabel: 'Force Stop And Quit',
      );
      if (!confirmed) {
        return false;
      }
      await _client.shutdownRuntime(force: true);
      await _waitUntilStopped();
      return true;
    }
  }

  Future<void> _waitUntilStopped() async {
    final deadline = DateTime.now().add(_shutdownSettleTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = await _client.probeRuntimeStatus();
      if (status == null) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
