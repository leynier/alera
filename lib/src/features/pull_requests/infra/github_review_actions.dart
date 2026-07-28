part of 'github_forge_provider.dart';

mixin _GitHubReviewActions {
  List<ReviewMergeMethod> get supportedMergeMethods =>
      const <ReviewMergeMethod>[
        ReviewMergeMethod.mergeCommit,
        ReviewMergeMethod.squash,
        ReviewMergeMethod.rebase,
      ];

  bool get supportsReviewClosure => true;

  bool get supportsReviewDraftConversion => true;

  Future<void> mergeReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required ReviewMergeMethod method,
  }) async {
    final provider = this as GitHubForgeProvider;
    if (method == ReviewMergeMethod.providerDefault) {
      throw const ForgeRequestFailed(
        'GitHub does not expose a provider-default merge method through gh.',
      );
    }
    final flag = switch (method) {
      ReviewMergeMethod.providerDefault => throw StateError('unreachable'),
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

  Future<void> setReviewDraft({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required bool draft,
  }) async {
    final provider = this as GitHubForgeProvider;
    await provider._run(<String>[
      'pr',
      'ready',
      '$number',
      '--repo',
      provider._repoSlug(identity),
      if (draft) '--undo',
    ], repoPath);
  }
}
