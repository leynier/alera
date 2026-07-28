import 'dart:async';

import 'package:alera/src/features/runtime_host/domain/runtime_host_quit_decision.dart';
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

typedef RuntimeHostBusyQuitConfirm =
    Future<RuntimeHostQuitDecision> Function({
      required String title,
      required String message,
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
        activePushSubscriptions: status['activePushSubscriptions'] is int
            ? status['activePushSubscriptions'] as int
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
        message: '${runtimeHostBusyMessage(busy)} Force stop terminates them.',
        confirmLabel: 'Force Stop',
      );
      if (!confirmed) {
        return;
      }
      await _client.shutdownRuntime(force: true);
    }
    await _waitUntilStopped();
  }

  Future<void> updateIfNewer({RuntimeHostForceConfirm? confirmForce}) async {
    final status = await loadStatus();
    if (!status.updateAvailable) {
      return;
    }
    await stop(confirmForce: confirmForce);
    await start();
  }

  /// Prepare the local runtime for an intentional app quit.
  ///
  /// Persistent CLI hosts and the keep-open setting leave the host running.
  /// App-launched sidecars soft-stop when idle; when busy, [confirmBusyQuit]
  /// chooses cancel, leave-open, or force-stop. Returns `false` only when the
  /// user cancels so the window should stay open.
  Future<bool> prepareAppQuit({
    required bool keepRuntimeOpen,
    RuntimeHostBusyQuitConfirm? confirmBusyQuit,
  }) async {
    if (keepRuntimeOpen) {
      return true;
    }

    Map<String, Object?>? liveStatus;
    var statusUncertain = false;
    try {
      liveStatus = await _client.probeRuntimeStatus();
    } catch (_) {
      // Probe failure must not skip shutdown: the host may still be live.
      statusUncertain = true;
      liveStatus = null;
    }

    if (!statusUncertain && liveStatus == null) {
      return true;
    }
    if (liveStatus != null && liveStatus['persistent'] == true) {
      return true;
    }
    if (liveStatus != null &&
        liveStatus['activePushSubscriptions'] is int &&
        (liveStatus['activePushSubscriptions'] as int) > 0) {
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
      if (confirmBusyQuit == null) {
        return false;
      }
      final decision = await confirmBusyQuit(
        title: 'Runtime Still Has Work',
        message:
            '${runtimeHostBusyMessage(busy)} '
            'You can quit and leave the runtime running, or force stop it.',
      );
      switch (decision) {
        case RuntimeHostQuitDecision.cancel:
          return false;
        case RuntimeHostQuitDecision.leaveRuntimeOpen:
          return true;
        case RuntimeHostQuitDecision.forceStop:
          await _client.shutdownRuntime(force: true);
          await _waitUntilStopped();
          return true;
      }
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

String runtimeHostBusyMessage(RuntimeHostBusyException busy) {
  final parts = <String>[];
  if (busy.activeAgents > 0) {
    parts.add('${busy.activeAgents} open agent(s)');
  }
  if (busy.activeSessions > 0) {
    parts.add('${busy.activeSessions} active terminal session(s)');
  }
  if (busy.activeJobs > 0) {
    parts.add('${busy.activeJobs} active background job(s)');
  }
  if (busy.activePushSubscriptions > 0) {
    parts.add('${busy.activePushSubscriptions} active push subscription(s)');
  }
  if (parts.isEmpty) {
    return 'The runtime still has active work.';
  }
  if (parts.length == 1) {
    return 'The runtime has ${parts.single}.';
  }
  if (parts.length == 2) {
    return 'The runtime has ${parts[0]} and ${parts[1]}.';
  }
  return 'The runtime has ${parts[0]}, ${parts[1]}, and ${parts[2]}.';
}
