import 'package:alera/src/features/runtime_host/domain/runtime_host_version.dart';

/// Snapshot of the local desktop runtime host for status-bar controls.
final class RuntimeHostStatusSnapshot {
  const RuntimeHostStatusSnapshot({
    required this.running,
    required this.bundledVersion,
    this.bundledCommit,
    this.runtimeHostVersion,
    this.runtimeHostCommit,
    this.persistent = false,
    this.activeSessions = 0,
    this.activeAgents = 0,
    this.activePushSubscriptions = 0,
    this.error,
  });

  final bool running;
  final String bundledVersion;
  final String? bundledCommit;
  final String? runtimeHostVersion;
  final String? runtimeHostCommit;
  final bool persistent;
  final int activeSessions;
  final int activeAgents;
  final int activePushSubscriptions;
  final String? error;

  bool get updateAvailable {
    final runningVersion = runtimeHostVersion;
    if (!running || runningVersion == null || runningVersion.isEmpty) {
      return false;
    }
    return isRuntimeHostVersionNewer(bundledVersion, runningVersion);
  }
}

final class RuntimeHostShutdownResult {
  const RuntimeHostShutdownResult({
    required this.stopped,
    required this.forced,
    this.activeSessions = 0,
    this.activeJobs = 0,
    this.activeAgents = 0,
    this.activePushSubscriptions = 0,
  });

  factory RuntimeHostShutdownResult.fromJson(Map<String, Object?> json) {
    return RuntimeHostShutdownResult(
      stopped: json['stopped'] == true,
      forced: json['forced'] == true,
      activeSessions: json['activeSessions'] is int
          ? json['activeSessions'] as int
          : 0,
      activeJobs: json['activeJobs'] is int ? json['activeJobs'] as int : 0,
      activeAgents: json['activeAgents'] is int
          ? json['activeAgents'] as int
          : 0,
      activePushSubscriptions: json['activePushSubscriptions'] is int
          ? json['activePushSubscriptions'] as int
          : 0,
    );
  }

  final bool stopped;
  final bool forced;
  final int activeSessions;
  final int activeJobs;
  final int activeAgents;
  final int activePushSubscriptions;
}

final class RuntimeHostBusyException implements Exception {
  const RuntimeHostBusyException({
    required this.message,
    this.activeSessions = 0,
    this.activeJobs = 0,
    this.activeAgents = 0,
    this.activePushSubscriptions = 0,
  });

  final String message;
  final int activeSessions;
  final int activeJobs;
  final int activeAgents;
  final int activePushSubscriptions;

  @override
  String toString() => message;
}

final class BundledSidecarVersion {
  const BundledSidecarVersion({required this.version, this.commit});

  final String version;
  final String? commit;
}
