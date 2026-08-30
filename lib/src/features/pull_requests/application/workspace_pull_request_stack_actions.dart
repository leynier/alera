part of 'workspace_pull_request_controller.dart';

mixin _WorkspacePullRequestStackActions on _$WorkspacePullRequestController {
  WorkspacePullRequestController get _stackController =>
      this as WorkspacePullRequestController;

  /// Creates a native GitHub stack from existing pull requests, or appends
  /// pull requests to the current stack. Numbers are ordered bottom to top.
  Future<void> linkReviewStack(List<int> rawReviewNumbers) async {
    final controller = _stackController;
    final current = state.value;
    final identity = current?.identity;
    final currentReview = current?.review;
    final forge = identity == null
        ? null
        : controller._registry.forProvider(identity.provider);
    final stackProvider = forge is ForgeStackProvider
        ? forge as ForgeStackProvider
        : null;
    if (current == null ||
        identity == null ||
        currentReview == null ||
        forge == null ||
        stackProvider == null) {
      _surfaceStackError('Native pull request stacks are not available.');
      return;
    }
    final reviewProvider = forge;

    final reviewNumbers = _normalizeReviewNumbers(rawReviewNumbers);
    final existingStack = current.stack;
    if (existingStack == null) {
      if (reviewNumbers.length < 2) {
        _surfaceStackError(
          'Choose at least two pull requests in bottom-to-top order.',
        );
        return;
      }
      if (!reviewNumbers.contains(currentReview.number)) {
        _surfaceStackError(
          'The current pull request must be included in the new stack.',
        );
        return;
      }
    } else {
      final existingNumbers = existingStack.entries
          .map((entry) => entry.review.number)
          .toSet();
      if (reviewNumbers.isEmpty) {
        _surfaceStackError('Choose at least one pull request to add.');
        return;
      }
      final duplicate = reviewNumbers
          .where(existingNumbers.contains)
          .firstOrNull;
      if (duplicate != null) {
        _surfaceStackError(
          'Pull request #$duplicate is already in this stack.',
        );
        return;
      }
    }

    await controller._run(
      scope: controller.scope,
      action: .linkStack,
      reloadAfterFailure: true,
      body: () async {
        final reviews = <HostedReview>[];
        for (final number in reviewNumbers) {
          final review = await reviewProvider.getReviewByNumber(
            identity: identity,
            repoPath: controller.scope.repoPath,
            number: number,
          );
          if (review == null) {
            throw _ActionError('No pull request #$number was found.');
          }
          if (!review.isOpen) {
            throw _ActionError('Pull request #$number is not open.');
          }
          reviews.add(review);
        }
        await _validateStackReviewChain(
          controller: controller,
          reviews: reviews,
          existingStack: existingStack,
        );
        await stackProvider.linkReviewStack(
          identity: identity,
          repoPath: controller.scope.repoPath,
          reviewNumbers: reviewNumbers,
          stackNumber: existingStack?.number,
          baseBranch: existingStack == null ? reviews.first.baseBranch : null,
        );
        if (!current.linkedManually) {
          await controller._linkedReviews.save(
            .linked(
              workspaceId: controller.scope.workspaceId,
              provider: identity.provider,
              number: currentReview.number,
              url: currentReview.url,
            ),
          );
        }
      },
    );
  }

  /// Creates missing pull requests for local workspace branches, reuses open
  /// pull requests when present, then links the ordered layers into a stack.
  Future<void> createReviewStackFromWorkspaces(
    ReviewStackWorkspaceRequest request,
  ) async {
    final controller = _stackController;
    final current = state.value;
    final identity = current?.identity;
    final currentReview = current?.review;
    final forge = identity == null
        ? null
        : controller._registry.forProvider(identity.provider);
    final stackProvider = forge is ForgeStackProvider
        ? forge as ForgeStackProvider
        : null;
    if (current == null ||
        identity == null ||
        forge == null ||
        stackProvider == null) {
      _surfaceStackError('Native pull request stacks are not available.');
      return;
    }
    final currentStackBranch = current.currentBranch?.trim().isNotEmpty == true
        ? current.currentBranch!.trim()
        : currentReview?.headBranch?.trim();
    if (currentStackBranch == null || currentStackBranch.isEmpty) {
      _surfaceStackError(
        'The current workspace must have an active branch to create a stack.',
      );
      return;
    }

    final layers = request.layers;
    final existingStack = current.stack;
    if (existingStack == null && layers.length < 2) {
      _surfaceStackError(
        'Choose at least two workspaces in bottom-to-top order.',
      );
      return;
    }
    if (existingStack != null && layers.isEmpty) {
      _surfaceStackError('Choose at least one workspace to add.');
      return;
    }
    final baseBranch = existingStack == null
        ? request.baseBranch.trim()
        : existingStack.entries.lastOrNull?.review.headBranch?.trim() ?? '';
    if (baseBranch.isEmpty) {
      _surfaceStackError('Choose a valid base branch for the stack.');
      return;
    }

    final workspaceIds = <String>{};
    final branches = <String>{};
    for (final layer in layers) {
      final branch = layer.branch.trim();
      if (!workspaceIds.add(layer.workspaceId)) {
        _surfaceStackError('A workspace can appear only once in a stack.');
        return;
      }
      if (branch.isEmpty || !branches.add(branch)) {
        _surfaceStackError('Each stack layer must use a unique branch.');
        return;
      }
      if (layer.title.trim().isEmpty) {
        _surfaceStackError('Every new pull request needs a title.');
        return;
      }
    }
    if (existingStack == null && !branches.contains(currentStackBranch)) {
      _surfaceStackError(
        'The current workspace must be included in the new stack.',
      );
      return;
    }
    final existingBranches = existingStack?.entries
        .map((entry) => entry.review.headBranch)
        .whereType<String>()
        .toSet();
    final duplicateBranch = layers
        .map((layer) => layer.branch.trim())
        .where((branch) => existingBranches?.contains(branch) ?? false)
        .firstOrNull;
    if (duplicateBranch != null) {
      _surfaceStackError('Branch `$duplicateBranch` is already in this stack.');
      return;
    }

    await controller._run(
      scope: controller.scope,
      action: .createStack,
      reloadAfterFailure: true,
      body: () async {
        await _validateStackWorkspaceRepositories(
          controller: controller,
          identity: identity,
          layers: layers,
        );
        await _validateStackBranchChain(
          controller: controller,
          baseBranch: baseBranch,
          branches: layers.map((layer) => layer.branch),
        );

        for (final layer in layers) {
          final branch = layer.branch.trim();
          final liveBranch = await controller._gitBackend.currentBranch(
            layer.repoPath,
          );
          if (liveBranch != branch) {
            throw _ActionError(
              'Workspace branch `$branch` is currently checked out as `$liveBranch`.',
            );
          }
        }

        for (final layer in layers) {
          await controller._gitBackend.push(layer.repoPath);
        }

        final reviewNumbers = <int>[];
        var previousBranch = baseBranch;
        for (final layer in layers) {
          final branch = layer.branch.trim();
          var review = await forge.getReviewForBranch(
            identity: identity,
            repoPath: layer.repoPath,
            branch: branch,
          );
          if (review == null) {
            final result = await forge.createReview(
              identity: identity,
              repoPath: layer.repoPath,
              input: CreateReviewInput(
                provider: identity.provider,
                title: layer.title.trim(),
                baseBranch: previousBranch,
                headBranch: branch,
                body: layer.body?.trim().isEmpty == true
                    ? null
                    : layer.body?.trim(),
                draft: layer.draft,
              ),
            );
            review = switch (result) {
              CreateReviewSuccess(:final review) => review,
              CreateReviewFailure(:final message) => throw _ActionError(
                'Could not create the pull request for `$branch`: $message',
              ),
            };
          }
          if (!review.isOpen) {
            throw _ActionError(
              'Pull request #${review.number} for `$branch` is not open.',
            );
          }

          reviewNumbers.add(review.number);
          await controller._linkedReviews.save(
            .linked(
              workspaceId: layer.workspaceId,
              provider: identity.provider,
              number: review.number,
              url: review.url,
            ),
          );
          previousBranch = branch;
        }

        await stackProvider.linkReviewStack(
          identity: identity,
          repoPath: controller.scope.repoPath,
          reviewNumbers: reviewNumbers,
          stackNumber: existingStack?.number,
          baseBranch: existingStack == null ? request.baseBranch.trim() : null,
        );
      },
    );
  }

  /// Merges every unmerged member at or below the current pull request using
  /// GitHub's atomic stack merge operation.
  Future<void> mergeCurrentReviewStack(ReviewMergeMethod method) async {
    final controller = _stackController;
    final current = state.value;
    final identity = current?.identity;
    final review = current?.review;
    final stack = current?.stack;
    final forge = identity == null
        ? null
        : controller._registry.forProvider(identity.provider);
    final stackProvider = forge is ForgeStackProvider
        ? forge as ForgeStackProvider
        : null;
    if (current == null ||
        identity == null ||
        review == null ||
        stack == null ||
        stackProvider == null) {
      _surfaceStackError('No pull request stack is available to merge.');
      return;
    }
    if (!current.mergeMethods.contains(method) ||
        method == ReviewMergeMethod.providerDefault) {
      _surfaceStackError('This stack cannot use the selected merge method.');
      return;
    }
    final affected = stack.entriesThrough(review.number);
    if (affected.isEmpty) {
      _surfaceStackError('The current pull request is not in this stack.');
      return;
    }
    final blocked = affected.where(
      (entry) =>
          entry.review.state == HostedReviewState.draft ||
          entry.review.state == HostedReviewState.closed,
    );
    if (blocked.isNotEmpty) {
      final number = blocked.first.review.number;
      _surfaceStackError(
        'Pull request #$number must be open and ready before merging the stack.',
      );
      return;
    }

    await controller._run(
      scope: controller.scope,
      action: .mergeStack,
      reloadAfterFailure: true,
      body: () async {
        await stackProvider.mergeReviewStack(
          identity: identity,
          repoPath: controller.scope.repoPath,
          reviewNumber: review.number,
          method: method,
        );
        if (!current.linkedManually) {
          await controller._linkedReviews.save(
            .linked(
              workspaceId: controller.scope.workspaceId,
              provider: identity.provider,
              number: review.number,
              url: review.url,
            ),
          );
        }
      },
    );
  }

  List<int> _normalizeReviewNumbers(Iterable<int> values) {
    final result = <int>[];
    final seen = <int>{};
    for (final value in values) {
      if (value > 0 && seen.add(value)) {
        result.add(value);
      }
    }
    return result;
  }

  void _surfaceStackError(String message) {
    final controller = _stackController;
    if (controller._disposed) {
      return;
    }
    state = AsyncData(
      (state.value ?? const WorkspacePullRequestState()).copyWith(
        clearAction: true,
        errorMessage: message,
      ),
    );
  }
}
