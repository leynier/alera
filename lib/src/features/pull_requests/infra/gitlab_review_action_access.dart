part of 'gitlab_forge_provider.dart';

mixin _GitLabReviewActionAccess {
  Future<ReviewActionAccess> reviewActionAccess({
    required GitRemoteIdentity identity,
    required String repoPath,
    required HostedReview review,
  }) async {
    final provider = this as GitLabForgeProvider;
    final decoded = provider._decodeJson(
      await provider._api(
        identity,
        repoPath,
        '${provider._projectEndpoint(identity)}/merge_requests/${review.number}',
      ),
    );
    final user = decoded is Map ? decoded['user'] : null;
    final project = provider._decodeJson(
      await provider._api(
        identity,
        repoPath,
        provider._projectEndpoint(identity),
      ),
    );
    final permissions = project is Map ? project['permissions'] : null;
    int level(String key) {
      final permission = permissions is Map ? permissions[key] : null;
      return permission is Map ? permission['access_level'] as int? ?? 0 : 0;
    }

    return ReviewActionAccess(
      canMerge: user is Map ? user['can_merge'] as bool? : null,
      canMarkReady: permissions is Map
          ? level('project_access') >= 30 || level('group_access') >= 30
          : null,
    );
  }
}
