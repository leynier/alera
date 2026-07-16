import 'package:alera/src/features/pull_requests/domain/git_hosting_provider.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';

/// Pure JSON-to-domain mappers for `gh` CLI output, kept apart from the
/// command construction and error classification in `GitHubForgeProvider`.
HostedReview mapGitHubReview(Map<String, Object?> json) {
  final state = (json['state'] as String? ?? 'OPEN').toUpperCase();
  final isDraft = json['isDraft'] as bool? ?? false;
  final author = json['author'];
  return HostedReview(
    provider: GitHostingProvider.github,
    number: (json['number'] as num?)?.toInt() ?? 0,
    title: json['title'] as String? ?? '',
    state: _mapState(state, isDraft),
    url: json['url'] as String? ?? '',
    createdAt: _parseDate(json['createdAt']),
    author: author is Map<String, Object?> ? author['login'] as String? : null,
    baseBranch: json['baseRefName'] as String?,
    headBranch: json['headRefName'] as String?,
    headSha: json['headRefOid'] as String?,
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
