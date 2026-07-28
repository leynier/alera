import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';

HostedReview mapGitLabReview(Map<String, Object?> json) {
  final state = (json['state'] as String? ?? 'opened').toLowerCase();
  final draft =
      json['draft'] as bool? ?? json['work_in_progress'] as bool? ?? false;
  final author = json['author'];
  return HostedReview(
    provider: GitHostingProvider.gitlab,
    number: (json['iid'] as num?)?.toInt() ?? 0,
    title: json['title'] as String? ?? '',
    state: switch (state) {
      'merged' => HostedReviewState.merged,
      'closed' => HostedReviewState.closed,
      _ => draft ? HostedReviewState.draft : HostedReviewState.open,
    },
    url: json['web_url'] as String? ?? '',
    createdAt: _parseDate(json['created_at']),
    author: author is Map<String, Object?>
        ? author['username'] as String? ?? author['name'] as String?
        : null,
    baseBranch: json['target_branch'] as String?,
    headBranch: json['source_branch'] as String?,
    headSha: json['sha'] as String?,
    mergeable: _mapMergeable(json),
  );
}

HostedReviewMergeable _mapMergeable(Map<String, Object?> json) {
  if (json['has_conflicts'] == true) {
    return HostedReviewMergeable.conflicting;
  }
  final status = (json['detailed_merge_status'] as String? ?? '').toLowerCase();
  return switch (status) {
    'mergeable' || 'can_be_merged' => HostedReviewMergeable.mergeable,
    'conflict' || 'cannot_be_merged' => HostedReviewMergeable.conflicting,
    _ => HostedReviewMergeable.unknown,
  };
}

ReviewCheck mapGitLabPipeline(Map<String, Object?> json) {
  final status = (json['status'] as String? ?? '').toLowerCase();
  final conclusion = switch (status) {
    'success' => ReviewCheckConclusion.success,
    'failed' => ReviewCheckConclusion.failure,
    'canceled' || 'cancelled' => ReviewCheckConclusion.cancelled,
    'skipped' => ReviewCheckConclusion.skipped,
    'manual' => ReviewCheckConclusion.actionRequired,
    _ => ReviewCheckConclusion.pending,
  };
  final phase = switch (status) {
    'created' ||
    'waiting_for_resource' ||
    'waiting_for_callback' ||
    'scheduled' ||
    'preparing' ||
    'pending' => ReviewCheckStatus.queued,
    'running' || 'canceling' => ReviewCheckStatus.inProgress,
    'success' ||
    'failed' ||
    'canceled' ||
    'cancelled' ||
    'skipped' ||
    'manual' => ReviewCheckStatus.completed,
    _ => ReviewCheckStatus.inProgress,
  };
  final id = (json['id'] as num?)?.toInt();
  return ReviewCheck(
    name: id == null ? 'Pipeline' : 'Pipeline #$id',
    status: phase,
    conclusion: conclusion,
    url: _nonEmpty(json['web_url'] as String?),
  );
}

ReviewCheckDetails mapGitLabPipelineDetails(Map<String, Object?> json) {
  return ReviewCheckDetails(
    description: _nonEmpty(json['name'] as String?),
    workflow: _nonEmpty(json['ref'] as String?),
    event: _nonEmpty(json['source'] as String?),
    startedAt: _parseDate(json['started_at']),
    completedAt: _parseDate(json['finished_at']),
    url: _nonEmpty(json['web_url'] as String?),
  );
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

DateTime? _parseDate(Object? value) {
  return value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;
}
