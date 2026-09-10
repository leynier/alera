part of 'github_forge_provider.dart';

mixin _GitHubReviewActions {
  Future<List<ReviewMergeMethod>> allowedMergeMethods({
    required GitRemoteIdentity identity,
    required String repoPath,
    String? baseBranch,
  }) async {
    final provider = this as GitHubForgeProvider;
    provider._ensureSupportedHost(identity);
    final repoAllowed = await _repoAllowedMergeMethods(
      identity: identity,
      repoPath: repoPath,
    );
    if (baseBranch == null || baseBranch.isEmpty) {
      return repoAllowed;
    }
    final rulesetAllowed = await _rulesetAllowedMergeMethods(
      identity: identity,
      repoPath: repoPath,
      baseBranch: baseBranch,
    );
    if (rulesetAllowed == null) {
      return repoAllowed;
    }
    return <ReviewMergeMethod>[
      for (final method in repoAllowed)
        if (rulesetAllowed.contains(method)) method,
    ];
  }

  Future<List<ReviewMergeMethod>> _repoAllowedMergeMethods({
    required GitRemoteIdentity identity,
    required String repoPath,
  }) async {
    final provider = this as GitHubForgeProvider;
    final output = await provider._run(<String>[
      'repo',
      'view',
      provider._repoSlug(identity),
      '--json',
      'mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed',
    ], repoPath);
    final decoded = provider._decodeJson(output);
    if (decoded is! Map) {
      throw const ForgeRequestFailed(
        'GitHub did not return the repository merge methods.',
      );
    }
    final mapped = mapGitHubRepoAllowedMergeMethods(
      Map<String, Object?>.from(decoded),
    );
    if (mapped == null) {
      throw const ForgeRequestFailed(
        'GitHub did not return the repository merge methods.',
      );
    }
    return mapped;
  }

  Future<Set<ReviewMergeMethod>?> _rulesetAllowedMergeMethods({
    required GitRemoteIdentity identity,
    required String repoPath,
    required String baseBranch,
  }) async {
    final provider = this as GitHubForgeProvider;
    final output = await provider._run(<String>[
      'api',
      '--hostname',
      identity.host,
      '--paginate',
      '--slurp',
      '${provider._apiRepoPath(identity)}/rules/branches/'
          '${Uri.encodeComponent(baseBranch)}',
    ], repoPath);
    return mapGitHubRulesetAllowedMergeMethods(provider._decodeJson(output));
  }

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
