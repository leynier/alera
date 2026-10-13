part of 'github_forge_provider.dart';

mixin _GitHubReviewActionAccess {
  Future<ReviewActionAccess> reviewActionAccess({
    required GitRemoteIdentity identity,
    required String repoPath,
    required HostedReview review,
  }) async {
    final provider = this as GitHubForgeProvider;
    final output = await provider._run([
      'api',
      '--hostname',
      identity.host,
      provider._apiRepoPath(identity),
    ], repoPath);
    final decoded = provider._decodeJson(output);
    final permissions = decoded is Map ? decoded['permissions'] : null;
    final write = permissions is Map ? permissions['push'] as bool? : null;
    final pull = provider._decodeJson(
      await provider._run([
        'api',
        '--hostname',
        identity.host,
        '${provider._apiRepoPath(identity)}/pulls/${review.number}',
      ], repoPath),
    );
    final mergeState = pull is Map ? pull['mergeable_state'] : null;
    final allowed = mergeState == 'clean' || mergeState == 'unstable';
    return ReviewActionAccess(
      canMerge: write == null || mergeState == null ? null : write && allowed,
      canMarkReady: write,
      mergeBlockReason: write != true
          ? null
          : switch (mergeState) {
              'blocked' => 'Branch protection requirements have not been met.',
              'behind' =>
                'Update this branch with the base branch before merging.',
              'unknown' || null => 'Mergeability has not been confirmed.',
              _ => null,
            },
    );
  }
}
