part of 'github_forge_provider.dart';

mixin _GitHubStackActions {
  Future<HostedReviewStack?> getStackForReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int reviewNumber,
  }) async {
    final provider = this as GitHubForgeProvider;
    provider._ensureSupportedHost(identity);
    final output = await provider._run(
      <String>[
        'api',
        '--hostname',
        identity.host,
        '${provider._apiRepoPath(identity)}/stacks?pull_request=$reviewNumber',
      ],
      repoPath,
      allowNotFound: true,
    );
    if (output == null) {
      return null;
    }
    final decoded = provider._decodeJson(output);
    if (decoded is! List) {
      throw const ForgeRequestFailed(
        'Unexpected GitHub stack search response.',
      );
    }
    if (decoded.isEmpty) {
      return null;
    }
    final first = decoded.first;
    if (first is! Map) {
      throw const ForgeRequestFailed('Unexpected GitHub stack search entry.');
    }
    final stackNumber = (first['number'] as num?)?.toInt();
    if (stackNumber == null || stackNumber <= 0) {
      throw const ForgeRequestFailed(
        'GitHub returned a stack without a valid number.',
      );
    }
    return _getStackByNumber(
      identity: identity,
      repoPath: repoPath,
      stackNumber: stackNumber,
    );
  }

  Future<HostedReviewStack> linkReviewStack({
    required GitRemoteIdentity identity,
    required String repoPath,
    required List<int> reviewNumbers,
    int? stackNumber,
    String? baseBranch,
  }) async {
    final provider = this as GitHubForgeProvider;
    provider._ensureSupportedHost(identity);
    final normalized = <int>[];
    final seen = <int>{};
    for (final number in reviewNumbers) {
      if (number > 0 && seen.add(number)) {
        normalized.add(number);
      }
    }
    if (stackNumber == null && normalized.length < 2) {
      throw const ForgeRequestFailed(
        'A new stack requires at least two pull requests.',
      );
    }
    if (stackNumber != null && normalized.isEmpty) {
      throw const ForgeRequestFailed(
        'Choose at least one pull request to add to the stack.',
      );
    }

    final branch = baseBranch?.trim();
    await _runStackCommand(<String>[
      'stack',
      'link',
      if (stackNumber != null) '$stackNumber',
      for (final number in normalized) '$number',
      if (branch != null && branch.isNotEmpty) ...<String>['--base', branch],
    ], repoPath);

    HostedReviewStack? stack;
    if (normalized.isNotEmpty) {
      stack = await getStackForReview(
        identity: identity,
        repoPath: repoPath,
        reviewNumber: normalized.last,
      );
    }
    if (stack == null && stackNumber != null) {
      stack = await _getStackByNumber(
        identity: identity,
        repoPath: repoPath,
        stackNumber: stackNumber,
      );
    }
    if (stack == null) {
      throw const ForgeRequestFailed(
        'The stack was linked but GitHub did not return it yet. Refresh and try again.',
      );
    }
    return stack;
  }

  Future<void> mergeReviewStack({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int reviewNumber,
    required ReviewMergeMethod method,
  }) async {
    final provider = this as GitHubForgeProvider;
    provider._ensureSupportedHost(identity);
    final mergeMethod = switch (method) {
      ReviewMergeMethod.mergeCommit => 'merge',
      ReviewMergeMethod.squash => 'squash',
      ReviewMergeMethod.rebase => 'rebase',
      ReviewMergeMethod.providerDefault => throw const ForgeRequestFailed(
        'GitHub stacks require an explicit merge method.',
      ),
    };
    await _runStackCommand(<String>[
      'stack',
      'merge',
      '$reviewNumber',
      '--yes',
      '--merge-method',
      mergeMethod,
    ], repoPath);
  }

  Future<HostedReviewStack?> _getStackByNumber({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int stackNumber,
  }) async {
    final provider = this as GitHubForgeProvider;
    final output = await provider._run(
      <String>[
        'api',
        '--hostname',
        identity.host,
        '${provider._apiRepoPath(identity)}/stacks/$stackNumber',
      ],
      repoPath,
      allowNotFound: true,
    );
    if (output == null) {
      return null;
    }
    final decoded = provider._decodeJson(output);
    if (decoded is! Map) {
      throw const ForgeRequestFailed('Unexpected GitHub stack response.');
    }
    return mapGitHubStack(
      Map<String, Object?>.from(decoded),
      repositoryUrl: provider._repositoryUrl(identity),
    );
  }

  Future<void> _runStackCommand(List<String> arguments, String repoPath) async {
    final provider = this as GitHubForgeProvider;
    ProcessRunOutput result;
    try {
      result = await provider._processRunner.run(
        'gh',
        arguments,
        workingDirectory: repoPath,
      );
    } catch (_) {
      throw const ForgeCliMissing('The gh CLI was not found on PATH.');
    }
    if (result.exitCode == 0) {
      return;
    }
    if (ghLooksLikeMissingCli(result)) {
      throw const ForgeCliMissing('The gh CLI was not found on PATH.');
    }
    if (_looksLikeMissingStackExtension(result)) {
      throw const ForgeCliMissing(
        'The gh-stack extension is required. Run `gh extension install github/gh-stack`.',
      );
    }
    provider._throwClassified(result);
  }

  bool _looksLikeMissingStackExtension(ProcessRunOutput result) {
    final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
    return output.contains('unknown command "stack"') ||
        output.contains("unknown command 'stack'") ||
        output.contains("'stack' is not a gh command") ||
        output.contains('extension stack not found') ||
        output.contains('gh-stack extension was not found');
  }
}
