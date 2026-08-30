import 'package:alera/src/shared/git_hosting/application/repository_web_url.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';

/// Pure JSON-to-domain mappers for `az` CLI output, kept apart from the
/// command construction and error classification in `AzureDevOpsForgeProvider`.

String azureWebUrl(GitRemoteIdentity identity, int number) {
  final project = identity.project ?? '';
  return '${azureOrgUrl(identity)}/$project/_git/${identity.repo}/pullrequest/$number';
}

HostedReview mapAzureReview(
  GitRemoteIdentity identity,
  Map<String, Object?> json,
) {
  final number = (json['pullRequestId'] as num?)?.toInt() ?? 0;
  final status = (json['status'] as String? ?? 'active').toLowerCase();
  final isDraft = json['isDraft'] as bool? ?? false;
  final createdBy = json['createdBy'];
  final lastMerge = json['lastMergeSourceCommit'];
  final lastMergeTarget = json['lastMergeTargetCommit'];
  final sourceRepository = json['sourceRepository'];
  return HostedReview(
    provider: .azureDevops,
    number: number,
    title: json['title'] as String? ?? '',
    state: _mapState(status, isDraft),
    url: azureWebUrl(identity, number),
    createdAt: _parseDate(json['creationDate']),
    author: createdBy is Map<String, Object?>
        ? createdBy['displayName'] as String?
        : null,
    baseBranch: shortAzureRef(json['targetRefName'] as String?),
    headBranch: shortAzureRef(json['sourceRefName'] as String?),
    headSha: lastMerge is Map<String, Object?>
        ? lastMerge['commitId'] as String?
        : null,
    headRepositoryUrl: sourceRepository is Map<String, Object?>
        ? _nonEmpty(sourceRepository['remoteUrl'] as String?)
        : null,
    comparisonBaseSha: lastMergeTarget is Map<String, Object?>
        ? lastMergeTarget['commitId'] as String?
        : null,
    mergeable: _mapMergeable(json['mergeStatus'] as String?),
  );
}

HostedReviewState _mapState(String status, bool isDraft) {
  return switch (status) {
    'completed' => HostedReviewState.merged,
    'abandoned' => HostedReviewState.closed,
    _ => isDraft ? HostedReviewState.draft : HostedReviewState.open,
  };
}

HostedReviewMergeable _mapMergeable(String? value) {
  return switch (value?.toLowerCase()) {
    'succeeded' => HostedReviewMergeable.mergeable,
    'conflicts' => HostedReviewMergeable.conflicting,
    _ => HostedReviewMergeable.unknown,
  };
}

ReviewCheck mapAzureCheck(Map<String, Object?> json) {
  final status = (json['status'] as String? ?? '').toLowerCase();
  final conclusion = switch (status) {
    'approved' => ReviewCheckConclusion.success,
    'rejected' => ReviewCheckConclusion.failure,
    'notapplicable' => ReviewCheckConclusion.skipped,
    'queued' || 'running' => ReviewCheckConclusion.pending,
    _ => ReviewCheckConclusion.neutral,
  };
  final checkStatus = (status == 'queued' || status == 'running')
      ? ReviewCheckStatus.inProgress
      : ReviewCheckStatus.completed;
  return ReviewCheck(
    name: azurePolicyName(json),
    status: checkStatus,
    conclusion: conclusion,
  );
}

ReviewCheckDetails mapAzureCheckDetails(
  GitRemoteIdentity identity,
  Map<String, Object?> json,
) {
  String? workflow;
  String? description;
  final configuration = json['configuration'];
  if (configuration is Map<String, Object?>) {
    final type = configuration['type'];
    if (type is Map<String, Object?>) {
      workflow = _nonEmpty(type['displayName'] as String?);
    }
    final settings = configuration['settings'];
    if (settings is Map<String, Object?>) {
      description = _nonEmpty(settings['displayName'] as String?);
    }
  }
  String? url;
  final context = json['context'];
  if (context is Map<String, Object?>) {
    final buildId = context['buildId'];
    if (buildId is num) {
      final project = identity.project ?? '';
      url =
          '${azureOrgUrl(identity)}/$project/_build/results'
          '?buildId=${buildId.toInt()}';
    }
  }
  return ReviewCheckDetails(
    description: description,
    workflow: workflow,
    startedAt: _parseDate(json['startedDate']),
    completedAt: _parseDate(json['completedDate']),
    url: url,
  );
}

String azurePolicyName(Map<String, Object?> json) {
  final configuration = json['configuration'];
  if (configuration is Map<String, Object?>) {
    final type = configuration['type'];
    if (type is Map<String, Object?>) {
      final displayName = type['displayName'];
      if (displayName is String && displayName.isNotEmpty) {
        return displayName;
      }
    }
  }
  return 'Policy';
}

String? shortAzureRef(String? ref) {
  if (ref == null) {
    return null;
  }
  const prefix = 'refs/heads/';
  return ref.startsWith(prefix) ? ref.substring(prefix.length) : ref;
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
