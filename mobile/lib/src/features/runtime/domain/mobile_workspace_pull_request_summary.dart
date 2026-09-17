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

/// Per-host pull-request status for the workspace list, one request for every
/// row. Feature-detected through [supportsPullRequestSummaries] because the
/// runtime enforces an exact mobile protocol version match.
abstract interface class MobileWorkspacePullRequestSummariesClient {
  bool get supportsPullRequestSummaries;

  Future<Map<String, MobileWorkspacePullRequestSummary>> pullRequestSummaries();
}
