import 'package:alera_mobile/src/core/json_payload_fields.dart';

/// Active Watch and Fix session for one workspace, as the runtime stores it.
class const MobilePullRequestWatch({
  required final String workspaceId,
  required final int reviewNumber,
  required final String mode,
  final bool checks = true,
  final bool comments = true,
  final bool conflicts = true,
}) {
  factory fromJson(Map<String, Object?> json) => MobilePullRequestWatch(
    workspaceId: json.requiredString('workspaceId'),
    reviewNumber: json.requiredInt('reviewNumber'),
    mode: json.optionalString('mode') ?? 'fix',
    checks: json['checks'] != false,
    comments: json['comments'] != false,
    conflicts: json['conflicts'] != false,
  );

  bool get merge => mode == 'fixAndMerge';

  String get tooltip {
    String line(String label, bool enabled) =>
        '$label: ${enabled ? 'On' : 'Off'}';
    return <String>[
      merge ? 'Watching: Fix and Merge' : 'Watching: Fix',
      line('Failed Checks', checks),
      line('Review Comments', comments),
      line('Merge Conflicts', conflicts),
    ].join('\n');
  }
}

class const MobilePullRequestWatchSnapshot({
  final bool supported = false,
  final Map<String, MobilePullRequestWatch> byWorkspace =
      const <String, MobilePullRequestWatch>{},
});

abstract interface class MobilePullRequestWatchClient {
  bool get supportsPullRequestWatch;
  Future<List<MobilePullRequestWatch>> listPullRequestWatches();
}
