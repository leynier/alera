import 'package:alera_mobile/src/core/json_payload_fields.dart';

/// Lifecycle of the hosted review backing a workspace row indicator.
enum MobileWorkspacePullRequestState { open, draft, merged, closed }

/// Rolled-up check status across all checks of a review.
enum MobileWorkspacePullRequestChecksRollup { none, pending, success, failure }

/// Merge state reported by the forge for an open review.
enum MobileWorkspacePullRequestMergeable { mergeable, conflicting, unknown }

/// Compact, workspace-facing projection of a hosted review and its checks,
/// served by the paired runtime through `mobile.pullRequest.summaries`.
///
/// Mirrors the desktop `WorkspacePullRequestSummary`: only counts plus at most
/// three failing check names, so one response covers every workspace row.
class const MobileWorkspacePullRequestSummary({
  required final String workspaceId,
  required final int number,
  final String title = '',
  final String url = '',
  final MobileWorkspacePullRequestState state =
      MobileWorkspacePullRequestState.open,
  final MobileWorkspacePullRequestMergeable mergeable =
      MobileWorkspacePullRequestMergeable.unknown,
  final MobileWorkspacePullRequestChecksRollup checksRollup =
      MobileWorkspacePullRequestChecksRollup.none,
  final int pendingCheckCount = 0,
  final int failedCheckCount = 0,
  final List<String> failingCheckNames = const <String>[],
}) {
  bool get checksPending =>
      checksRollup == MobileWorkspacePullRequestChecksRollup.pending;

  bool get checksFailed =>
      checksRollup == MobileWorkspacePullRequestChecksRollup.failure;

  bool get hasMergeConflict =>
      state == MobileWorkspacePullRequestState.open &&
      mergeable == MobileWorkspacePullRequestMergeable.conflicting;

  factory fromJson(Map<String, Object?> json) {
    return MobileWorkspacePullRequestSummary(
      workspaceId: json.requiredString('workspaceId'),
      number: (json['number'] as num?)?.toInt() ?? 0,
      title: json.optionalString('title') ?? '',
      url: json.optionalString('url') ?? '',
      state: switch (json.optionalString('state')) {
        'draft' => MobileWorkspacePullRequestState.draft,
        'merged' => MobileWorkspacePullRequestState.merged,
        'closed' => MobileWorkspacePullRequestState.closed,
        _ => MobileWorkspacePullRequestState.open,
      },
      mergeable: switch (json.optionalString('mergeable')?.toUpperCase()) {
        'MERGEABLE' => MobileWorkspacePullRequestMergeable.mergeable,
        'CONFLICTING' => MobileWorkspacePullRequestMergeable.conflicting,
        _ => MobileWorkspacePullRequestMergeable.unknown,
      },
      checksRollup: switch (json.optionalString('checksRollup')) {
        'pending' => MobileWorkspacePullRequestChecksRollup.pending,
        'success' => MobileWorkspacePullRequestChecksRollup.success,
        'failure' => MobileWorkspacePullRequestChecksRollup.failure,
        _ => MobileWorkspacePullRequestChecksRollup.none,
      },
      pendingCheckCount: (json['pendingCheckCount'] as num?)?.toInt() ?? 0,
      failedCheckCount: (json['failedCheckCount'] as num?)?.toInt() ?? 0,
      failingCheckNames: json.stringList('failingCheckNames'),
    );
  }
}

/// One `mobile.pullRequest.summaries` answer: the fresh reviews plus the two
/// workspace id sets the merge needs. `evaluatedWorkspaceIds` names the
/// groups whose batch completed (a group with no review for a workspace
/// clears its icon); `eligibleWorkspaceIds` names every workspace the host
/// considered, so ids that left the set are dropped. Workspaces that are
/// eligible but unevaluated had a failed batch and keep their previous icons,
/// mirroring the desktop monitor's per-group preserve-on-error merge.
class const MobileWorkspacePullRequestSummaries({
  final Map<String, MobileWorkspacePullRequestSummary> byWorkspace =
      const <String, MobileWorkspacePullRequestSummary>{},
  final Set<String> evaluatedWorkspaceIds = const <String>{},
  final Set<String> eligibleWorkspaceIds = const <String>{},
}) {
  /// Merges this fresh answer over [previous] like the desktop monitor: drop
  /// every evaluated workspace, then add the fresh reviews; keep previous
  /// icons for eligible-but-unevaluated workspaces and drop ids the host no
  /// longer considers.
  Map<String, MobileWorkspacePullRequestSummary> mergedOver(
    Map<String, MobileWorkspacePullRequestSummary> previous,
  ) {
    return <String, MobileWorkspacePullRequestSummary>{
      for (final entry in previous.entries)
        if (!evaluatedWorkspaceIds.contains(entry.key) &&
            eligibleWorkspaceIds.contains(entry.key))
          entry.key: entry.value,
      ...byWorkspace,
    };
  }

  factory fromJson(Map<String, Object?> json) {
    final byWorkspace = <String, MobileWorkspacePullRequestSummary>{};
    for (final item in json.objectList('summaries')) {
      final fields = asJsonMap(item);
      if (fields.isEmpty) {
        continue;
      }
      final summary = MobileWorkspacePullRequestSummary.fromJson(fields);
      byWorkspace[summary.workspaceId] = summary;
    }
    return MobileWorkspacePullRequestSummaries(
      byWorkspace: byWorkspace,
      evaluatedWorkspaceIds: json.stringList('evaluatedWorkspaceIds').toSet(),
      eligibleWorkspaceIds: json.stringList('eligibleWorkspaceIds').toSet(),
    );
  }
}

/// Per-host pull-request status for the workspace list, one request for every
/// row. Feature-detected through [supportsPullRequestSummaries] because the
/// runtime enforces an exact mobile protocol version match.
abstract interface class MobileWorkspacePullRequestSummariesClient {
  bool get supportsPullRequestSummaries;

  Future<MobileWorkspacePullRequestSummaries> pullRequestSummaries();
}
