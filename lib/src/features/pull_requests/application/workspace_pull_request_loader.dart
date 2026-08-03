import 'package:alera/src/features/pull_requests/application/base_branch_resolver.dart';
import 'package:alera/src/features/pull_requests/application/forge_exception.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/shared/git_hosting/application/hosting_provider_resolver.dart';
import 'package:alera/src/features/pull_requests/application/linked_review_repository.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/linked_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_remote.dart';
import 'package:logging/logging.dart';

/// Loads the forge and repository snapshot displayed by the pull-request panel.
final Logger _log = Logger('WorkspacePullRequestLoader');

class WorkspacePullRequestLoader {
  const WorkspacePullRequestLoader(
    this._gitBackend,
    this._registry,
    this._linkedReviews,
  );

  final GitBackend _gitBackend;
  final ForgeProviderRegistry _registry;
  final LinkedReviewRepository _linkedReviews;

  Future<WorkspacePullRequestState> load(
    WorkspacePullRequestScope scope,
  ) async {
    final resolution = await _resolveIdentity(scope);
    if (resolution.identity == null) {
      return WorkspacePullRequestState(unavailableReason: resolution.reason);
    }
    final identity = resolution.identity!;
    final forge = _registry.forProvider(identity.provider);
    if (forge == null) {
      return WorkspacePullRequestState(
        identity: identity,
        unavailableReason: PullRequestUnavailableReason.unsupported,
      );
    }
    final authStatus = await forge.checkAuth(identity: identity);
    final branch = await _resolveBranch(scope);
    final baseInfo = await _resolveBaseBranches(scope);
    final persisted = await _linkedReviews.find(scope.workspaceId);

    if (authStatus != ForgeAuthStatus.authenticated) {
      return WorkspacePullRequestState(
        identity: identity,
        authStatus: authStatus,
        currentBranch: branch,
        baseBranches: baseInfo.branches,
        suggestedBaseBranch: baseInfo.suggested,
      );
    }

    final linkedManually = persisted != null && persisted.hasReview;
    try {
      HostedReview? review;
      HostedReview? suggestedReview;
      var dismissed = false;
      if (linkedManually) {
        review = await forge.getReviewByNumber(
          identity: identity,
          repoPath: scope.repoPath,
          number: persisted.number!,
        );
      } else {
        final detected = await _detectReview(forge, identity, scope, branch);
        if (persisted != null &&
            persisted.dismissed &&
            detected != null &&
            _dismisses(persisted, detected)) {
          suggestedReview = detected;
          dismissed = true;
        } else {
          review = detected;
          dismissed = persisted?.dismissed == true && detected == null;
        }
      }
      var checks = const <ReviewCheck>[];
      var comments = const <ReviewComment>[];
      if (review != null) {
        final checksFuture = forge.getChecks(
          identity: identity,
          repoPath: scope.repoPath,
          number: review.number,
        );
        final commentsFuture = forge.supportsReviewComments
            ? forge.getReviewComments(
                identity: identity,
                repoPath: scope.repoPath,
                number: review.number,
              )
            : Future<List<ReviewComment>>.value(const <ReviewComment>[]);
        final results = await Future.wait<Object>([
          checksFuture,
          commentsFuture,
        ]);
        checks = results[0] as List<ReviewCheck>;
        comments = results[1] as List<ReviewComment>;
      }
      return WorkspacePullRequestState(
        identity: identity,
        authStatus: authStatus,
        review: review,
        suggestedReview: suggestedReview,
        checks: checks,
        comments: comments,
        linkedManually: linkedManually,
        dismissed: dismissed,
        currentBranch: branch,
        baseBranches: baseInfo.branches,
        suggestedBaseBranch: baseInfo.suggested,
        mergeMethods: forge.supportedMergeMethods,
        canCloseReview: forge.supportsReviewClosure,
        canChangeDraftStatus: forge.supportsReviewDraftConversion,
        canComment: forge.supportsReviewComments,
        canEditComments: forge.supportsReviewCommentEditing,
      );
    } on ForgeNotAuthenticated {
      return WorkspacePullRequestState(
        identity: identity,
        authStatus: ForgeAuthStatus.notAuthenticated,
        currentBranch: branch,
        baseBranches: baseInfo.branches,
        suggestedBaseBranch: baseInfo.suggested,
      );
    } on ForgeCliMissing {
      return WorkspacePullRequestState(
        identity: identity,
        authStatus: ForgeAuthStatus.cliMissing,
        currentBranch: branch,
        baseBranches: baseInfo.branches,
        suggestedBaseBranch: baseInfo.suggested,
      );
    } on ForgeException catch (error) {
      return WorkspacePullRequestState(
        identity: identity,
        authStatus: authStatus,
        currentBranch: branch,
        baseBranches: baseInfo.branches,
        suggestedBaseBranch: baseInfo.suggested,
        errorMessage: error.message,
      );
    }
  }

  Future<({List<String> branches, String suggested})> _resolveBaseBranches(
    WorkspacePullRequestScope scope,
  ) async {
    List<String> raw;
    try {
      raw = await _gitBackend.listBranches(scope.repoPath);
    } on GitException catch (error, stackTrace) {
      // An empty list leaves the create form with no base branch to pick and
      // nothing on screen saying why.
      _log.warning(
        'could not list base branches for ${scope.repoPath}',
        error,
        stackTrace,
      );
      raw = const <String>[];
    }
    final branches = normalizeBaseBranches(raw);
    final suggested = pickDefaultBaseBranch(
      branches,
      preferred: scope.sourceBranch,
    );
    return (branches: branches, suggested: suggested);
  }

  Future<String?> _resolveBranch(WorkspacePullRequestScope scope) async {
    // The scope hint is the branch recorded at workspace creation; agents can
    // switch branches inside the worktree afterwards, so live HEAD wins and
    // the hint only covers detached HEAD or git failures.
    try {
      final current = await _gitBackend.currentBranch(scope.repoPath);
      if (current.isNotEmpty && current != 'HEAD') {
        return current;
      }
    } on GitException {
      // Fall back to the scope hint below.
    }
    final hinted = scope.branch;
    if (hinted != null && hinted.isNotEmpty && hinted != 'HEAD') {
      return hinted;
    }
    return null;
  }

  Future<HostedReview?> _detectReview(
    ForgeProvider forge,
    GitRemoteIdentity identity,
    WorkspacePullRequestScope scope,
    String? branch,
  ) async {
    if (branch == null || branch.isEmpty) {
      return null;
    }
    return forge.getReviewForBranch(
      identity: identity,
      repoPath: scope.repoPath,
      branch: branch,
    );
  }

  bool _dismisses(LinkedReview dismissal, HostedReview review) {
    if (dismissal.hasDismissedReview) {
      return dismissal.provider == review.provider &&
          dismissal.number == review.number;
    }
    final createdAt = review.createdAt;
    return createdAt == null || !createdAt.isAfter(dismissal.linkedAt);
  }

  Future<({GitRemoteIdentity? identity, PullRequestUnavailableReason? reason})>
  _resolveIdentity(WorkspacePullRequestScope scope) async {
    List<GitRemote> remotes;
    try {
      remotes = await _gitBackend.listRemotes(scope.repoPath);
    } on GitException catch (error, stackTrace) {
      // Reported as "no remote", which is also what a broken repository looks
      // like from here; the git error is the only way to tell them apart.
      _log.warning(
        'could not list remotes for ${scope.repoPath}',
        error,
        stackTrace,
      );
      return (identity: null, reason: PullRequestUnavailableReason.noRemote);
    }
    final resolution = resolveHostingProvider(
      remotes: remotes,
      override: scope.providerOverride,
    );
    return switch (resolution) {
      HostingProviderResolved(:final identity) => (
        identity: identity,
        reason: null,
      ),
      HostingProviderUndetectable() => (
        identity: null,
        reason: PullRequestUnavailableReason.undetectable,
      ),
      HostingProviderNoRemote() => (
        identity: null,
        reason: PullRequestUnavailableReason.noRemote,
      ),
    };
  }
}
