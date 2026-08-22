part of 'workspace_pull_request_controller.dart';

Future<void> _validateStackReviewChain({
  required WorkspacePullRequestController controller,
  required List<HostedReview> reviews,
  required HostedReviewStack? existingStack,
}) async {
  final existingTop = existingStack?.entries.lastOrNull?.review.headBranch;
  final initialBranch = existingTop ?? reviews.first.baseBranch;
  if (initialBranch == null || initialBranch.trim().isEmpty) {
    throw const _ActionError(
      'Could not determine the base branch for this stack.',
    );
  }
  await _validateStackBranchChain(
    controller: controller,
    baseBranch: initialBranch,
    branches: reviews.map((review) {
      final branch = review.headBranch?.trim();
      if (branch == null || branch.isEmpty) {
        throw _ActionError(
          'Pull request #${review.number} does not expose a head branch.',
        );
      }
      return branch;
    }),
  );
}

Future<void> _validateStackBranchChain({
  required WorkspacePullRequestController controller,
  required String baseBranch,
  required Iterable<String> branches,
}) async {
  var previousBranch = baseBranch.trim();
  if (previousBranch.isEmpty) {
    throw const _ActionError(
      'Could not determine the base branch for this stack.',
    );
  }
  var fetched = false;
  for (final rawBranch in branches) {
    final branch = rawBranch.trim();
    if (branch.isEmpty) {
      throw const _ActionError('Every stack layer needs a branch.');
    }
    if (branch == previousBranch) {
      throw _ActionError(
        'Branch `$branch` is also used by the layer below it.',
      );
    }

    bool isDescendant;
    try {
      isDescendant = await controller._gitBackend.isAncestor(
        path: controller.scope.repoPath,
        ancestorRef: previousBranch,
        descendantRef: branch,
      );
    } on BranchNotFoundException {
      if (fetched) {
        rethrow;
      }
      await controller._gitBackend.fetch(controller.scope.repoPath);
      fetched = true;
      isDescendant = await controller._gitBackend.isAncestor(
        path: controller.scope.repoPath,
        ancestorRef: previousBranch,
        descendantRef: branch,
      );
    }
    if (!isDescendant) {
      throw _ActionError(
        'Branch `$branch` must descend from `$previousBranch` before its pull request can join the stack.',
      );
    }
    previousBranch = branch;
  }
}

Future<void> _validateStackWorkspaceRepositories({
  required WorkspacePullRequestController controller,
  required GitRemoteIdentity identity,
  required List<ReviewStackWorkspaceLayerInput> layers,
}) async {
  for (final layer in layers) {
    final remotes = await controller._gitBackend.listRemotes(layer.repoPath);
    final resolution = resolveHostingProvider(
      remotes: remotes,
      override: identity.provider,
    );
    if (resolution is! HostingProviderResolved ||
        !_sameStackRepository(identity, resolution.identity)) {
      throw _ActionError(
        'Workspace `${layer.branch}` does not belong to ${identity.host}/${identity.owner}/${identity.repo}.',
      );
    }
  }
}

bool _sameStackRepository(GitRemoteIdentity left, GitRemoteIdentity right) {
  return left.provider == right.provider &&
      left.host == right.host &&
      left.owner == right.owner &&
      left.repo == right.repo &&
      left.project == right.project;
}
