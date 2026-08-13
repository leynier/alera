part of 'rust_git_backend.dart';

mixin _RustGitBackendHostedReview {
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on rust.GitError catch (error) {
      throw _toException(error);
    }
  }

  GitException _toException(rust.GitError error) {
    final context = error.context;
    return switch (error.kind) {
      rust.GitErrorKind.notARepository => NotARepositoryException(context),
      rust.GitErrorKind.accessDenied => AccessDeniedException(context),
      rust.GitErrorKind.branchNotFound => BranchNotFoundException(context),
      rust.GitErrorKind.branchAlreadyExists => BranchAlreadyExistsException(
        context,
      ),
      rust.GitErrorKind.invalidBranchName => InvalidBranchNameException(
        context,
      ),
      rust.GitErrorKind.worktreeAlreadyExists => WorktreeAlreadyExistsException(
        context,
      ),
      rust.GitErrorKind.worktreeNotFound => WorktreeNotFoundException(context),
      rust.GitErrorKind.cloneFailed => CloneFailedException(context),
      rust.GitErrorKind.gitCli => GitCliException(context),
      rust.GitErrorKind.detachedHead => DetachedHeadException(context),
      rust.GitErrorKind.noUpstream => NoUpstreamException(context),
      rust.GitErrorKind.remoteNotFound => RemoteNotFoundException(context),
      rust.GitErrorKind.nothingToCommit => NothingToCommitException(context),
      rust.GitErrorKind.workspaceScope => WorkspaceScopeException(context),
      rust.GitErrorKind.missingIdentity => MissingIdentityException(context),
      rust.GitErrorKind.conflict => GitConflictException(context),
      rust.GitErrorKind.internal => GitInternalException(context),
    };
  }

  Future<GitHostedReviewRange> fetchHostedReviewRange({
    required String path,
    required String baseBranch,
    required String headSha,
    String? reviewRef,
  }) => _guard(() async {
    final range = await hosted_review_rust.gitFetchHostedReviewRange(
      path: path,
      baseBranch: baseBranch,
      headSha: headSha,
      reviewRef: reviewRef,
    );
    return GitHostedReviewRange(
      baseOid: range.baseOid,
      headOid: range.headOid,
      retentionId: range.retentionId,
    );
  });

  Future<void> releaseHostedReviewRange({
    required String path,
    required String retentionId,
  }) => _guard(
    () => hosted_review_rust.gitReleaseHostedReviewRange(
      path: path,
      retentionId: retentionId,
    ),
  );
}
