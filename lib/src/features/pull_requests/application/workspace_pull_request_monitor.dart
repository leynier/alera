import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/forge_review_batch_provider.dart';
import 'package:alera/src/features/pull_requests/application/linked_review_repository.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/linked_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_summary.dart';
import 'package:alera/src/shared/git_hosting/application/hosting_provider_resolver.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:logging/logging.dart';

final Logger _monitorLog = Logger('WorkspacePullRequestMonitor');

/// Immutable input describing one workspace that can be matched to a hosted
/// pull request. Workspaces in the same repository share one provider request.
class const WorkspacePullRequestMonitorTarget({
  required this.projectId,
  required this.projectName,
  required this.workspaceId,
  required this.workspaceName,
  required this.repoPath,
  required this.branch,
  this.providerOverride,
}) {
  final String projectId;
  final String projectName;
  final String workspaceId;
  final String workspaceName;
  final String repoPath;
  final String branch;
  final GitHostingProvider? providerOverride;

  String get configurationKey => <Object?>[
    projectId,
    projectName,
    workspaceId,
    workspaceName,
    repoPath,
    branch,
    providerOverride?.name,
  ].join('|');
}

class const WorkspacePullRequestMonitorLoadResult({
  required this.summaries,
  this.hadErrors = false,
}) {
  final Map<String, WorkspacePullRequestSummary> summaries;
  final bool hadErrors;
}

/// Loads compact PR/check status while doing repository/provider work once per
/// repository. GitHub supplies a true one-request batch; other forges use the
/// existing neutral methods sequentially as a bounded fallback.
class const WorkspacePullRequestMonitorLoader(
  this._gitBackend,
  this._registry,
  this._linkedReviews,
) {
  final GitBackend _gitBackend;
  final ForgeProviderRegistry _registry;
  final LinkedReviewRepository _linkedReviews;

  Future<WorkspacePullRequestMonitorLoadResult> load({
    required List<WorkspacePullRequestMonitorTarget> targets,
    Map<String, WorkspacePullRequestSummary> previous =
        const <String, WorkspacePullRequestSummary>{},
  }) async {
    final activeIds = <String>{
      for (final target in targets) target.workspaceId,
    };
    final next = <String, WorkspacePullRequestSummary>{
      for (final entry in previous.entries)
        if (activeIds.contains(entry.key)) entry.key: entry.value,
    };
    final grouped = <String, List<WorkspacePullRequestMonitorTarget>>{};
    var hadErrors = false;
    for (final target in targets) {
      final key = <Object?>[
        target.repoPath,
        target.providerOverride?.name,
      ].join('|');
      grouped
          .putIfAbsent(key, () => <WorkspacePullRequestMonitorTarget>[])
          .add(target);
    }

    for (final group in grouped.values) {
      try {
        final loaded = await _loadProject(group, previous);
        for (final target in group) {
          next.remove(target.workspaceId);
        }
        next.addAll(loaded);
      } on Object catch (error, stackTrace) {
        hadErrors = true;
        // Preserve the last known status for one transient provider failure;
        // the single monitor timer will retry with backoff.
        _monitorLog.warning(
          'could not refresh pull requests for ${group.first.projectName}',
          error,
          stackTrace,
        );
      }
    }
    return WorkspacePullRequestMonitorLoadResult(
      summaries: Map<String, WorkspacePullRequestSummary>.unmodifiable(next),
      hadErrors: hadErrors,
    );
  }

  Future<Map<String, WorkspacePullRequestSummary>> _loadProject(
    List<WorkspacePullRequestMonitorTarget> targets,
    Map<String, WorkspacePullRequestSummary> previous,
  ) async {
    final first = targets.first;
    final remotes = await _gitBackend.listRemotes(first.repoPath);
    final resolution = resolveHostingProvider(
      remotes: remotes,
      override: first.providerOverride,
    );
    if (resolution is! HostingProviderResolved) {
      return const <String, WorkspacePullRequestSummary>{};
    }
    final identity = resolution.identity;
    final forge = _registry.forProvider(identity.provider);
    if (forge == null) {
      return const <String, WorkspacePullRequestSummary>{};
    }

    final linkedByWorkspace = <String, LinkedReview?>{};
    final branches = <String>{};
    final reviewNumbers = <int>{};
    for (final target in targets) {
      final linked = await _linkedReviews.find(target.workspaceId);
      linkedByWorkspace[target.workspaceId] = linked;
      if (linked?.hasReview == true) {
        reviewNumbers.add(linked!.number!);
      } else {
        branches.add(target.branch);
      }
      final previousNumber = previous[target.workspaceId]?.review.number;
      if (previousNumber != null) {
        // Keeps terminal transitions visible on providers whose branch lookup
        // only returns open reviews.
        reviewNumbers.add(previousNumber);
      }
    }

    final ForgeReviewBatch batch;
    if (forge case final ForgeReviewBatchProvider batchProvider) {
      batch = await batchProvider.getReviewBatch(
        identity: identity,
        repoPath: first.repoPath,
        branches: branches,
        reviewNumbers: reviewNumbers,
      );
    } else {
      batch = await _loadSequentially(
        forge: forge,
        identity: identity,
        repoPath: first.repoPath,
        branches: branches,
        reviewNumbers: reviewNumbers,
      );
    }

    final summaries = <String, WorkspacePullRequestSummary>{};
    for (final target in targets) {
      final linked = linkedByWorkspace[target.workspaceId];
      final snapshot = _snapshotForTarget(
        target: target,
        linked: linked,
        batch: batch,
        previous: previous,
      );
      if (snapshot == null || _isDismissed(linked, snapshot, identity)) {
        continue;
      }
      summaries[target.workspaceId] = WorkspacePullRequestSummary.fromChecks(
        review: snapshot.review,
        checks: snapshot.checks,
      );
    }
    return summaries;
  }

  /// Branch lookup only auto-detects open reviews, matching
  /// [ForgeProvider.getReviewForBranch]. Merged or closed reviews stay visible
  /// when the workspace linked that number, or when this session already showed
  /// it (so a merge mid-poll still reaches the terminal state).
  ForgeReviewSnapshot? _snapshotForTarget({
    required WorkspacePullRequestMonitorTarget target,
    required LinkedReview? linked,
    required ForgeReviewBatch batch,
    required Map<String, WorkspacePullRequestSummary> previous,
  }) {
    if (linked?.hasReview == true) {
      return batch.byNumber[linked!.number];
    }
    final detected = batch.byBranch[target.branch];
    if (detected != null && detected.review.isOpen) {
      return detected;
    }
    final previousNumber = previous[target.workspaceId]?.review.number;
    return previousNumber == null ? null : batch.byNumber[previousNumber];
  }

  Future<ForgeReviewBatch> _loadSequentially({
    required ForgeProvider forge,
    required GitRemoteIdentity identity,
    required String repoPath,
    required Set<String> branches,
    required Set<int> reviewNumbers,
  }) async {
    final byBranch = <String, ForgeReviewSnapshot>{};
    final byNumber = <int, ForgeReviewSnapshot>{};
    final orderedBranches = branches.toList()..sort();
    for (final branch in orderedBranches) {
      final review = await forge.getReviewForBranch(
        identity: identity,
        repoPath: repoPath,
        branch: branch,
      );
      if (review == null) {
        continue;
      }
      final snapshot = ForgeReviewSnapshot(
        review: review,
        checks: await _getChecksForActiveReview(
          forge: forge,
          identity: identity,
          repoPath: repoPath,
          review: review,
        ),
      );
      byBranch[branch] = snapshot;
      byNumber[review.number] = snapshot;
    }
    final orderedNumbers = reviewNumbers.toList()..sort();
    for (final number in orderedNumbers) {
      if (byNumber.containsKey(number)) {
        continue;
      }
      final review = await forge.getReviewByNumber(
        identity: identity,
        repoPath: repoPath,
        number: number,
      );
      if (review == null) {
        continue;
      }
      final snapshot = ForgeReviewSnapshot(
        review: review,
        checks: await _getChecksForActiveReview(
          forge: forge,
          identity: identity,
          repoPath: repoPath,
          review: review,
        ),
      );
      byNumber[number] = snapshot;
      final branch = review.headBranch;
      if (branch != null && branch.isNotEmpty) {
        byBranch.putIfAbsent(branch, () => snapshot);
      }
    }
    return ForgeReviewBatch(byBranch: byBranch, byNumber: byNumber);
  }

  Future<List<ReviewCheck>> _getChecksForActiveReview({
    required ForgeProvider forge,
    required GitRemoteIdentity identity,
    required String repoPath,
    required HostedReview review,
  }) {
    if (review.state == HostedReviewState.merged ||
        review.state == HostedReviewState.closed) {
      return Future<List<ReviewCheck>>.value(const <ReviewCheck>[]);
    }
    return forge.getChecks(
      identity: identity,
      repoPath: repoPath,
      number: review.number,
    );
  }

  bool _isDismissed(
    LinkedReview? linked,
    ForgeReviewSnapshot snapshot,
    GitRemoteIdentity identity,
  ) {
    if (linked?.dismissed != true) {
      return false;
    }
    if (linked!.hasDismissedReview) {
      return linked.provider == identity.provider &&
          linked.number == snapshot.review.number;
    }
    final createdAt = snapshot.review.createdAt;
    return createdAt == null || !createdAt.isAfter(linked.linkedAt);
  }
}
