import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';

/// Pure JSON-to-domain mappers for `gh` CLI output, kept apart from the
/// command construction and error classification in `GitHubForgeProvider`.
HostedReview mapGitHubReview(Map<String, Object?> json) {
  final state = (json['state'] as String? ?? 'OPEN').toUpperCase();
  final isDraft = json['isDraft'] as bool? ?? false;
  final author = json['author'];
  final mergeCommit = json['mergeCommit'];
  return HostedReview(
    provider: .github,
    number: (json['number'] as num?)?.toInt() ?? 0,
    title: json['title'] as String? ?? '',
    state: _mapState(state, isDraft),
    url: json['url'] as String? ?? '',
    createdAt: _parseDate(json['createdAt']),
    author: author is Map<String, Object?> ? author['login'] as String? : null,
    baseBranch: json['baseRefName'] as String?,
    headBranch: json['headRefName'] as String?,
    headSha: json['headRefOid'] as String?,
    comparisonBaseSha: json['baseRefOid'] as String?,
    mergeCommitSha: mergeCommit is Map<String, Object?>
        ? mergeCommit['oid'] as String?
        : null,
    mergeable: _mapMergeable(json['mergeable'] as String?),
  );
}

HostedReviewState _mapState(String state, bool isDraft) {
  return switch (state) {
    'MERGED' => HostedReviewState.merged,
    'CLOSED' => HostedReviewState.closed,
    _ => isDraft ? HostedReviewState.draft : HostedReviewState.open,
  };
}

HostedReviewMergeable _mapMergeable(String? value) {
  return switch (value?.toUpperCase()) {
    'MERGEABLE' => HostedReviewMergeable.mergeable,
    'CONFLICTING' => HostedReviewMergeable.conflicting,
    _ => HostedReviewMergeable.unknown,
  };
}

ReviewCheck mapGitHubCheck(Map<String, Object?> json) {
  final bucket = (json['bucket'] as String? ?? '').toLowerCase();
  final conclusion = switch (bucket) {
    'pass' => ReviewCheckConclusion.success,
    'fail' => ReviewCheckConclusion.failure,
    'cancel' => ReviewCheckConclusion.cancelled,
    'skipping' => ReviewCheckConclusion.skipped,
    _ => ReviewCheckConclusion.pending,
  };
  final status = bucket == 'pending'
      ? ReviewCheckStatus.inProgress
      : ReviewCheckStatus.completed;
  final link = json['link'] as String?;
  return ReviewCheck(
    name: json['name'] as String? ?? 'check',
    status: status,
    conclusion: conclusion,
    url: link != null && link.isNotEmpty ? link : null,
  );
}

/// Maps one GraphQL `StatusCheckRollupContext` union entry. GitHub returns
/// modern Actions runs as `CheckRun` and legacy commit statuses as
/// `StatusContext`, so both forms must participate in the sidebar rollup.
ReviewCheck mapGitHubStatusRollupCheck(Map<String, Object?> json) {
  final type = json['__typename'] as String?;
  if (type == 'StatusContext') {
    final state = (json['state'] as String? ?? 'PENDING').toUpperCase();
    final pending = state == 'EXPECTED' || state == 'PENDING';
    return ReviewCheck(
      name: json['context'] as String? ?? 'status',
      status: pending
          ? ReviewCheckStatus.inProgress
          : ReviewCheckStatus.completed,
      conclusion: switch (state) {
        'SUCCESS' => ReviewCheckConclusion.success,
        'ERROR' || 'FAILURE' => ReviewCheckConclusion.failure,
        _ => ReviewCheckConclusion.pending,
      },
      url: _nonEmpty(json['targetUrl'] as String?),
    );
  }

  final statusValue = (json['status'] as String? ?? 'QUEUED').toUpperCase();
  final completed = statusValue == 'COMPLETED';
  final conclusionValue = (json['conclusion'] as String? ?? '').toUpperCase();
  return ReviewCheck(
    name: json['name'] as String? ?? 'check',
    status: completed
        ? ReviewCheckStatus.completed
        : statusValue == 'QUEUED'
        ? ReviewCheckStatus.queued
        : ReviewCheckStatus.inProgress,
    conclusion: switch (conclusionValue) {
      'SUCCESS' => ReviewCheckConclusion.success,
      'FAILURE' || 'STARTUP_FAILURE' => ReviewCheckConclusion.failure,
      'CANCELLED' || 'STALE' => ReviewCheckConclusion.cancelled,
      'TIMED_OUT' => ReviewCheckConclusion.timedOut,
      'ACTION_REQUIRED' => ReviewCheckConclusion.actionRequired,
      'NEUTRAL' => ReviewCheckConclusion.neutral,
      'SKIPPED' => ReviewCheckConclusion.skipped,
      _ => ReviewCheckConclusion.pending,
    },
    url: _nonEmpty(json['detailsUrl'] as String?),
  );
}

ReviewCheckDetails mapGitHubCheckDetails(Map<String, Object?> json) {
  return ReviewCheckDetails(
    description: _nonEmpty(json['description'] as String?),
    workflow: _nonEmpty(json['workflow'] as String?),
    event: _nonEmpty(json['event'] as String?),
    startedAt: _parseDate(json['startedAt']),
    completedAt: _parseDate(json['completedAt']),
    url: _nonEmpty(json['link'] as String?),
  );
}

String? _nonEmpty(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}
