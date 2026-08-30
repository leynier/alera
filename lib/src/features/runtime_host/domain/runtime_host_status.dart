import 'package:alera/src/features/runtime_host/domain/runtime_host_version.dart';

/// Snapshot of the local desktop runtime host for status-bar controls.
final class const RuntimeHostStatusSnapshot({
  required final bool running,
  required final String bundledVersion,
  final String? bundledCommit,
  final String? runtimeHostVersion,
  final String? runtimeHostCommit,
  final bool persistent = false,
  final int activeSessions = 0,
  final int activeAgents = 0,
  final int activePushSubscriptions = 0,
  final String? error,
}) {
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

final class const RuntimeHostShutdownResult({
  required final bool stopped,
  required final bool forced,
  final int activeSessions = 0,
  final int activeJobs = 0,
  final int activeAgents = 0,
  final int activePushSubscriptions = 0,
}) {
  factory fromJson(Map<String, Object?> json) {
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
}

final class const RuntimeHostBusyException({
  required final String message,
  final int activeSessions = 0,
  final int activeJobs = 0,
  final int activeAgents = 0,
  final int activePushSubscriptions = 0,
}) implements Exception {
  @override
  String toString() => message;
}

final class const BundledSidecarVersion({
  required final String version,
  final String? commit,
});
