/// Describes the machine and build a diagnostics bundle came from.
///
/// Logs on their own rarely explain a report: the same line means different
/// things on a dev build against a stale sidecar than on a release build with
/// matching versions.
class const DiagnosticsBundleMetadata({
  required final String appVersion,
  required final String flavor,
  required final String operatingSystem,
  required final String operatingSystemVersion,
  required final DateTime collectedAt,
  this.runtimeHostVersion,
  final String? runtimeHostCommit,
  final int? protocolVersion,
  final List<String> runtimeCapabilities = const <String>[],
}) {
  /// Absent when the runtime host was not reachable while collecting, which is
  /// itself worth recording: a bundle with no runtime section usually means the
  /// sidecar was down.
  final String? runtimeHostVersion;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'collectedAt': collectedAt.toUtc().toIso8601String(),
      'app': <String, Object?>{'version': appVersion, 'flavor': flavor},
      'platform': <String, Object?>{
        'operatingSystem': operatingSystem,
        'operatingSystemVersion': operatingSystemVersion,
      },
      'runtime': <String, Object?>{
        'reachable': runtimeHostVersion != null,
        if (runtimeHostVersion != null) 'version': runtimeHostVersion,
        if (runtimeHostCommit != null) 'commit': runtimeHostCommit,
        if (protocolVersion != null) 'protocolVersion': protocolVersion,
        if (runtimeCapabilities.isNotEmpty) 'capabilities': runtimeCapabilities,
      },
    };
  }
}
