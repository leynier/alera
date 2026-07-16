part of 'workspace_pull_request_controller.dart';

mixin _WorkspacePullRequestReviewActions on _$WorkspacePullRequestController {
  WorkspacePullRequestController get _controller =>
      this as WorkspacePullRequestController;

  /// Merges the linked review and keeps it linked so the terminal state remains
  /// visible after the provider no longer returns it as an open branch review.
  Future<void> mergeReview(ReviewMergeMethod method) async {
    final current = state.value;
    final review = current?.review;
    if (current == null ||
        review == null ||
        review.state != HostedReviewState.open ||
        !current.mergeMethods.contains(method)) {
      _surfaceActionError('This Pull Request Cannot Be Merged.');
      return;
    }
    await _runReviewMutation(
      current: current,
      action: PullRequestAction.merge,
      mutate: (forge, identity) => forge.mergeReview(
        identity: identity,
        repoPath: _controller.scope.repoPath,
        number: review.number,
        method: method,
      ),
    );
  }

  /// Closes the linked review without merging it.
  Future<void> closeReview() async {
    final current = state.value;
    final review = current?.review;
    if (current == null ||
        review == null ||
        !review.isOpen ||
        !current.canCloseReview) {
      _surfaceActionError('This Pull Request Cannot Be Closed.');
      return;
    }
    await _runReviewMutation(
      current: current,
      action: PullRequestAction.close,
      mutate: (forge, identity) => forge.closeReview(
        identity: identity,
        repoPath: _controller.scope.repoPath,
        number: review.number,
      ),
    );
  }

  /// Adds a top-level conversation comment and refreshes the visible snapshot.
  Future<bool> addReviewComment(String rawBody) async {
    final controller = _controller;
    final current = state.value;
    final review = current?.review;
    final body = rawBody.trim();
    if (current == null ||
        review == null ||
        !review.isOpen ||
        !current.canComment) {
      _surfaceActionError('Comments Are Not Available For This Pull Request.');
      return false;
    }
    if (body.isEmpty) {
      _surfaceActionError('Enter A Comment Before Posting.');
      return false;
    }
    final identity = current.identity;
    final forge = identity == null
        ? null
        : controller._registry.forProvider(identity.provider);
    if (identity == null || forge == null) {
      _surfaceActionError('No Hosting Provider Is Configured.');
      return false;
    }

    controller._pollTimer?.cancel();
    state = AsyncData(
      current.copyWith(action: PullRequestAction.comment, clearError: true),
    );
    try {
      await forge.addReviewComment(
        identity: identity,
        repoPath: controller.scope.repoPath,
        number: review.number,
        body: body,
      );
      final reloaded = await controller._loader.load(controller.scope);
      if (!controller._disposed) {
        state = AsyncData(
          reloaded.errorMessage == null
              ? reloaded
              : current.copyWith(
                  clearAction: true,
                  errorMessage: reloaded.errorMessage,
                ),
        );
        controller._resetPollInterval();
      }
      return true;
    } on ForgeException catch (error) {
      _surfaceActionError(error.message);
      return false;
    } catch (error) {
      _surfaceActionError(error.toString());
      return false;
    } finally {
      controller._schedulePoll(controller.scope);
    }
  }

  Future<void> _runReviewMutation({
    required WorkspacePullRequestState current,
    required PullRequestAction action,
    required Future<void> Function(ForgeProvider, GitRemoteIdentity) mutate,
  }) async {
    final controller = _controller;
    final identity = current.identity;
    final review = current.review;
    final forge = identity == null
        ? null
        : controller._registry.forProvider(identity.provider);
    if (identity == null || review == null || forge == null) {
      _surfaceActionError('No Linked Pull Request To Update.');
      return;
    }
    await controller._run(
      scope: controller.scope,
      action: action,
      body: () async {
        await mutate(forge, identity);
        if (!current.linkedManually) {
          await controller._linkedReviews.save(
            LinkedReview.linked(
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

  void _surfaceActionError(String message) {
    final controller = _controller;
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
