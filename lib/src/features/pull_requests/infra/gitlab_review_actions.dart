part of 'gitlab_forge_provider.dart';

mixin _GitLabReviewActions {
  GitLabForgeProvider get _gitlab => this as GitLabForgeProvider;

  bool get supportsReviewClosure => true;

  bool get supportsReviewDraftConversion => true;

  List<ReviewMergeMethod> get supportedMergeMethods =>
      const <ReviewMergeMethod>[
        ReviewMergeMethod.providerDefault,
        ReviewMergeMethod.squash,
      ];

  Future<void> mergeReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required ReviewMergeMethod method,
  }) async {
    if (method == ReviewMergeMethod.rebase ||
        method == ReviewMergeMethod.mergeCommit) {
      throw const ForgeRequestFailed(
        'GitLab merge topology is controlled by the project settings.',
      );
    }
    await _gitlab._run(<String>[
      'mr',
      'merge',
      '$number',
      '--repo',
      _gitlab._repoUrl(identity),
      if (method == ReviewMergeMethod.squash) '--squash',
      '--auto-merge=false',
      '--yes',
    ], repoPath);
  }

  Future<void> closeReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async {
    await _gitlab._run(<String>[
      'mr',
      'close',
      '$number',
      '--repo',
      _gitlab._repoUrl(identity),
    ], repoPath);
  }

  Future<void> setReviewDraft({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required bool draft,
  }) async {
    await _gitlab._run(<String>[
      'mr',
      'update',
      '$number',
      '--repo',
      _gitlab._repoUrl(identity),
      draft ? '--draft' : '--ready',
      '--yes',
    ], repoPath);
  }
}
