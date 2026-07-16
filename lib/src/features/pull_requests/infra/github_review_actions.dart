part of 'github_forge_provider.dart';

mixin _GitHubReviewActions {
  List<ReviewMergeMethod> get supportedMergeMethods =>
      const <ReviewMergeMethod>[
        ReviewMergeMethod.mergeCommit,
        ReviewMergeMethod.squash,
        ReviewMergeMethod.rebase,
      ];

  bool get supportsReviewClosure => true;

  Future<void> mergeReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required ReviewMergeMethod method,
  }) async {
    final provider = this as GitHubForgeProvider;
    final flag = switch (method) {
      ReviewMergeMethod.mergeCommit => '--merge',
      ReviewMergeMethod.squash => '--squash',
      ReviewMergeMethod.rebase => '--rebase',
    };
    await provider._run(<String>[
      'pr',
      'merge',
      '$number',
      '--repo',
      provider._repoSlug(identity),
      flag,
    ], repoPath);
  }

  Future<void> closeReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async {
    final provider = this as GitHubForgeProvider;
    await provider._run(<String>[
      'pr',
      'close',
      '$number',
      '--repo',
      provider._repoSlug(identity),
    ], repoPath);
  }
}
