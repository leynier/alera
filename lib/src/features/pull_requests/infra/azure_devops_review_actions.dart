part of 'azure_devops_forge_provider.dart';

mixin _AzureDevOpsReviewActions {
  List<ReviewMergeMethod> get supportedMergeMethods =>
      const <ReviewMergeMethod>[
        ReviewMergeMethod.mergeCommit,
        ReviewMergeMethod.squash,
      ];

  bool get supportsReviewClosure => true;

  Future<void> mergeReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required ReviewMergeMethod method,
  }) async {
    if (method == ReviewMergeMethod.rebase) {
      throw const ForgeRequestFailed(
        'Azure DevOps Does Not Support Rebase and Merge Through Its CLI.',
      );
    }
    final provider = this as AzureDevOpsForgeProvider;
    await provider._run(<String>[
      'repos',
      'pr',
      'update',
      '--id',
      '$number',
      '--organization',
      azureOrgUrl(identity),
      '--status',
      'completed',
      '--squash',
      method == ReviewMergeMethod.squash ? 'true' : 'false',
      '--output',
      'none',
    ], repoPath);
  }

  Future<void> closeReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async {
    final provider = this as AzureDevOpsForgeProvider;
    await provider._run(<String>[
      'repos',
      'pr',
      'update',
      '--id',
      '$number',
      '--organization',
      azureOrgUrl(identity),
      '--status',
      'abandoned',
      '--output',
      'none',
    ], repoPath);
  }
}
