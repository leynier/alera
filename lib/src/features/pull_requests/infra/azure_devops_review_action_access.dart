part of 'azure_devops_forge_provider.dart';

mixin _AzureDevOpsReviewActionAccess {
  Future<ReviewActionAccess> reviewActionAccess({
    required GitRemoteIdentity identity,
    required String repoPath,
    required HostedReview review,
  }) async {
    final provider = this as AzureDevOpsForgeProvider;
    const namespace = '2e9eb7ed-3c0a-47d4-87c1-0ffdd275fd87';
    final repo = provider._decodeJson(
      await provider._run([
        'repos',
        'show',
        '--organization',
        azureOrgUrl(identity),
        '--project',
        identity.project ?? '',
        '--repository',
        identity.repo,
        '--output',
        'json',
      ], repoPath),
    );
    if (repo is! Map || repo['project'] is! Map || repo['id'] is! String) {
      return const ReviewActionAccess();
    }
    final project = repo['project'] as Map;
    if (project['id'] is! String) return const ReviewActionAccess();
    final token = 'repoV2/${project['id']}/${repo['id']}';
    final rawNamespace = provider._decodeJson(
      await provider._run([
        'devops',
        'security',
        'permission',
        'namespace',
        'show',
        '--organization',
        azureOrgUrl(identity),
        '--id',
        namespace,
        '--output',
        'json',
      ], repoPath),
    );
    final data = rawNamespace is List && rawNamespace.isNotEmpty
        ? rawNamespace.first
        : rawNamespace;
    final actions = data is Map ? data['actions'] : null;
    if (actions is! List) return const ReviewActionAccess();
    int? bit(String name) =>
        actions
                .whereType<Map>()
                .where((action) => action['name'] == name)
                .firstOrNull?['bit']
            as int?;
    Future<bool?> allowed(int? permission, String scope) async {
      if (permission == null) return null;
      final result = provider._decodeJson(
        await provider._run([
          'devops',
          'invoke',
          '--organization',
          azureOrgUrl(identity),
          '--area',
          'security',
          '--resource',
          'permissions',
          '--route-parameters',
          'securityNamespaceId=$namespace',
          'permissions=$permission',
          '--query-parameters',
          'tokens=$scope',
          'alwaysAllowAdministrators=false',
          '--http-method',
          'GET',
          '--api-version',
          '7.1-preview.2',
          '--output',
          'json',
        ], repoPath),
      );
      return result is List && result.length == 1 && result.first is bool
          ? result.first as bool
          : null;
    }

    final branch = review.baseBranch;
    final encoded = branch
        ?.replaceFirst(RegExp(r'^refs/heads/'), '')
        .split('/')
        .map(
          (part) => part.codeUnits
              .map(
                (unit) =>
                    '${(unit & 255).toRadixString(16).padLeft(2, '0')}${(unit >> 8).toRadixString(16).padLeft(2, '0')}',
              )
              .join(),
        )
        .join('/');
    final canContribute = encoded == null
        ? null
        : await allowed(
            bit('GenericContribute'),
            '$token/refs/heads/$encoded/',
          );
    final canUpdate = await allowed(bit('PullRequestContribute'), token);
    return ReviewActionAccess(
      canMerge: canContribute == null || canUpdate == null
          ? null
          : canContribute && canUpdate,
      canMarkReady: canUpdate,
    );
  }
}
