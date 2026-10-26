part of 'workspace_pull_request_loader.dart';

Future<({List<ReviewCheck> checks, String? error})> _loadReviewChecks(
  ForgeProvider forge,
  GitRemoteIdentity identity,
  WorkspacePullRequestScope scope,
  HostedReview review,
) async {
  try {
    return (
      checks: await forge.getChecks(
        identity: identity,
        repoPath: scope.repoPath,
        number: review.number,
      ),
      error: null,
    );
  } catch (error, stackTrace) {
    _log.warning('Could not load pull request checks', error, stackTrace);
    return (
      checks: const <ReviewCheck>[],
      error: userFacingErrorMessage(error),
    );
  }
}

Future<({List<ReviewComment> comments, String? error})> _loadReviewComments(
  ForgeProvider forge,
  GitRemoteIdentity identity,
  WorkspacePullRequestScope scope,
  HostedReview review,
) async {
  if (!forge.supportsReviewComments) {
    return (comments: const <ReviewComment>[], error: null);
  }
  try {
    return (
      comments: await forge.getReviewComments(
        identity: identity,
        repoPath: scope.repoPath,
        number: review.number,
      ),
      error: null,
    );
  } catch (error, stackTrace) {
    _log.warning('Could not load pull request comments', error, stackTrace);
    return (
      comments: const <ReviewComment>[],
      error: userFacingErrorMessage(error),
    );
  }
}

Future<ReviewActionAccess> _loadReviewAccess(
  ForgeProvider forge,
  GitRemoteIdentity identity,
  WorkspacePullRequestScope scope,
  HostedReview review,
) async {
  if (forge is! ForgeReviewActionAccessProvider) {
    return const ReviewActionAccess();
  }
  try {
    return await (forge as ForgeReviewActionAccessProvider).reviewActionAccess(
      identity: identity,
      repoPath: scope.repoPath,
      review: review,
    );
  } catch (_) {
    return const ReviewActionAccess();
  }
}
