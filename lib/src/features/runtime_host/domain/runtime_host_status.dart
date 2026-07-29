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
  final String? error;

  bool get hasBuildMismatch {
    final runningVersion = runtimeHostVersion;
    if (!running ||
        runningVersion == null ||
        runningVersion.isEmpty ||
        compareRuntimeHostVersions(bundledVersion, runningVersion) != 0) {
      return false;
    }
    final bundledBuild = _knownRuntimeHostCommit(bundledCommit);
    final runningBuild = _knownRuntimeHostCommit(runtimeHostCommit);
    return bundledBuild != null &&
        runningBuild != null &&
        bundledBuild != runningBuild;
  }

  bool get updateAvailable {
    final runningVersion = runtimeHostVersion;
    if (!running || runningVersion == null || runningVersion.isEmpty) {
      return false;
    }
    final versionComparison = compareRuntimeHostVersions(
      bundledVersion,
      runningVersion,
    );
    return versionComparison > 0 ||
        (versionComparison == 0 && hasBuildMismatch);
  }
}

String? _knownRuntimeHostCommit(String? value) {
  final commit = value?.trim();
  if (commit == null || commit.isEmpty || commit.toLowerCase() == 'unknown') {
    return null;
  }
  return commit;
}

final class RuntimeHostShutdownResult {
  const RuntimeHostShutdownResult({
    required this.stopped,
    required this.forced,
    this.activeSessions = 0,
    this.activeJobs = 0,
    this.activeAgents = 0,
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
    );
  }

  final bool stopped;
  final bool forced;
  final int activeSessions;
  final int activeJobs;
  final int activeAgents;
}

final class RuntimeHostBusyException implements Exception {
  const RuntimeHostBusyException({
    required this.message,
    this.activeSessions = 0,
    this.activeJobs = 0,
    this.activeAgents = 0,
  });

  final String message;
  final int activeSessions;
  final int activeJobs;
  final int activeAgents;

  @override
  String toString() => message;
}

final class BundledSidecarVersion {
  const BundledSidecarVersion({required this.version, this.commit});

  final String version;
  final String? commit;
}
