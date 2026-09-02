part of 'workspace_pull_request_controller.dart';

mixin _WorkspacePullRequestReviewEditing on _$WorkspacePullRequestController {
  WorkspacePullRequestController get _editingController =>
      this as WorkspacePullRequestController;

  /// Creates a review from [input]: pushes the branch, calls the forge, and
  /// links the result on success.
  Future<CreateReviewResult> createReview(CreateReviewInput input) =>
      _createReview(input, action: .create);

  Future<CreateReviewResult> _createReview(
    CreateReviewInput input, {
    required PullRequestAction action,
  }) async {
    final controller = _editingController;
    final identity = state.value?.identity;
    final forge = identity == null
        ? null
        : controller._registry.forProvider(identity.provider);
    if (identity == null || forge == null) {
      return const CreateReviewFailure(
        code: .blocked,
        message: 'No hosting provider is configured.',
      );
    }
    controller._pollTimer?.cancel();
    state = AsyncData(
      (state.value ?? const WorkspacePullRequestState()).copyWith(
        action: action,
        clearError: true,
      ),
    );
    try {
      await controller._gitBackend.push(controller.scope.repoPath);
    } on GitException catch (error) {
      final result = CreateReviewFailure(
        code: .pushFailed,
        message: 'Could not push the branch: ${error.context}',
      );
      controller._applyActionOutcome(failureMessage: result.message);
      return result;
    }
    // A thrown ForgeException (vs a returned failure) must not skip
    // _applyActionOutcome, or the action would stay busy and block polling.
    final CreateReviewResult result;
    try {
      result = await forge.createReview(
        identity: identity,
        repoPath: controller.scope.repoPath,
        input: input,
      );
    } on ForgeException catch (error) {
      final failure = CreateReviewFailure(
        code: .unknown,
        message: error.message,
      );
      controller._applyActionOutcome(failureMessage: failure.message);
      return failure;
    } catch (error) {
      final failure = CreateReviewFailure(
        code: .unknown,
        message: error.toString(),
      );
      controller._applyActionOutcome(failureMessage: failure.message);
      return failure;
    }
    if (result is CreateReviewSuccess) {
      await controller._linkedReviews.save(
        .linked(
          workspaceId: controller.scope.workspaceId,
          provider: identity.provider,
          number: result.review.number,
          url: result.review.url,
        ),
      );
    }
    controller._applyActionOutcome(
      failureMessage: result is CreateReviewFailure ? result.message : null,
    );
    if (!controller._disposed && controller._visible) {
      await controller.refresh();
    }
    return result;
  }

  /// Detail metadata for [check] of the linked review; null when nothing is
  /// linked or the check is gone. Transport/auth failures throw.
  Future<ReviewCheckDetails?> loadCheckDetails(ReviewCheck check) async {
    final controller = _editingController;
    final current = state.value;
    final identity = current?.identity;
    final review = current?.review;
    final forge = identity == null
        ? null
        : controller._registry.forProvider(identity.provider);
    if (identity == null || review == null || forge == null) {
      return null;
    }
    return forge.getCheckDetails(
      identity: identity,
      repoPath: controller.scope.repoPath,
      number: review.number,
      check: check,
    );
  }

  /// Updates the linked review from [input], then reloads.
  Future<UpdateReviewResult> updateReview(UpdateReviewInput input) async {
    final controller = _editingController;
    final identity = state.value?.identity;
    final review = state.value?.review;
    final forge = identity == null
        ? null
        : controller._registry.forProvider(identity.provider);
    if (identity == null || review == null || forge == null) {
      return const UpdateReviewFailure(
        code: .blocked,
        message: 'No linked pull request to update.',
      );
    }
    if (input.isEmpty) {
      return const UpdateReviewFailure(
        code: .blocked,
        message: 'Nothing to update.',
      );
    }
    controller._pollTimer?.cancel();
    state = AsyncData(
      (state.value ?? const WorkspacePullRequestState()).copyWith(
        action: .update,
        clearError: true,
      ),
    );
    // Same containment as createReview: a thrown error must clear the action.
    final UpdateReviewResult result;
    try {
      result = await forge.updateReview(
        identity: identity,
        repoPath: controller.scope.repoPath,
        number: review.number,
        input: input,
      );
    } on ForgeException catch (error) {
      final failure = UpdateReviewFailure(
        code: .unknown,
        message: error.message,
      );
      controller._applyActionOutcome(failureMessage: failure.message);
      return failure;
    } catch (error) {
      final failure = UpdateReviewFailure(
        code: .unknown,
        message: error.toString(),
      );
      controller._applyActionOutcome(failureMessage: failure.message);
      return failure;
    }
    controller._applyActionOutcome(
      failureMessage: result is UpdateReviewFailure ? result.message : null,
    );
    // Reload only on success; the refresh path would clear the error message.
    if (!controller._disposed &&
        controller._visible &&
        result is UpdateReviewSuccess) {
      await controller.refresh();
    }
    return result;
  }
}
