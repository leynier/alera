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
      _surfaceActionError('This pull request cannot be merged.');
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
      _surfaceActionError('This pull request cannot be closed.');
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

  /// Converts the linked review between draft and ready-for-review states.
  Future<void> setReviewDraft(bool draft) async {
    final current = state.value;
    final review = current?.review;
    final alreadyDraft = review?.state == HostedReviewState.draft;
    if (current == null ||
        review == null ||
        !review.isOpen ||
        !current.canChangeDraftStatus ||
        alreadyDraft == draft) {
      _surfaceActionError('This pull request draft status cannot be changed.');
      return;
    }
    await _runReviewMutation(
      current: current,
      action: PullRequestAction.draftStatus,
      mutate: (forge, identity) => forge.setReviewDraft(
        identity: identity,
        repoPath: _controller.scope.repoPath,
        number: review.number,
        draft: draft,
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
      _surfaceActionError('Comments are not available for this pull request.');
      return false;
    }
    if (body.isEmpty) {
      _surfaceActionError('Enter a comment before posting.');
      return false;
    }
    final identity = current.identity;
    final forge = identity == null
        ? null
        : controller._registry.forProvider(identity.provider);
    if (identity == null || forge == null) {
      _surfaceActionError('No hosting provider is configured.');
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
        final visibleReload = controller._applyPendingCommentBodies(reloaded);
        state = AsyncData(
          visibleReload.errorMessage == null
              ? visibleReload
              : current.copyWith(
                  clearAction: true,
                  errorMessage: visibleReload.errorMessage,
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

  /// Toggles one task-list item and updates only its containing comment.
  Future<void> toggleReviewCommentTask(
    String commentId,
    int taskItemIndex,
  ) async {
    final controller = _controller;
    final current = state.value;
    if (current == null) {
      _surfaceActionError('Comments are not available for this pull request.');
      return;
    }
    if (current.savingCommentIds.contains(commentId)) {
      return;
    }
    final review = current.review;
    final commentIndex = current.comments.indexWhere(
      (comment) => comment.id == commentId,
    );
    if (review == null ||
        !review.isOpen ||
        !current.canEditComments ||
        commentIndex < 0) {
      _surfaceActionError('This comment cannot be edited.');
      return;
    }
    final comment = current.comments[commentIndex];
    final locator = comment.locator;
    if (locator == null) {
      _surfaceActionError('This comment cannot be edited.');
      return;
    }
    final changedBody = toggleReviewCommentTaskListItem(
      comment.body,
      taskItemIndex,
    );
    if (changedBody == null) {
      return;
    }
    final identity = current.identity;
    final forge = identity == null
        ? null
        : controller._registry.forProvider(identity.provider);
    if (identity == null || forge == null) {
      _surfaceActionError('No hosting provider is configured.');
      return;
    }

    final pending = _PendingReviewCommentSave(
      originalBody: comment.body,
      optimisticBody: changedBody,
    );
    controller._pendingCommentSaves[commentId] = pending;
    controller._savingCommentIds.add(commentId);
    state = AsyncData(
      current.copyWith(
        comments: _replaceCommentBody(
          current.comments,
          commentId: commentId,
          body: changedBody,
        ),
        savingCommentIds: <String>{...current.savingCommentIds, commentId},
        clearError: true,
      ),
    );

    try {
      await forge.updateReviewComment(
        identity: identity,
        repoPath: controller.scope.repoPath,
        number: review.number,
        locator: locator,
        body: changedBody,
      );
      List<ReviewComment>? refreshed;
      String? refreshWarning;
      try {
        refreshed = await forge.getReviewComments(
          identity: identity,
          repoPath: controller.scope.repoPath,
          number: review.number,
        );
      } catch (error) {
        refreshWarning =
            'Comment was updated, but the comments could not be refreshed: '
            '${_commentErrorMessage(error)}';
      }
      final refreshedComment = refreshed
          ?.where((comment) => comment.id == commentId)
          .firstOrNull;
      if (refreshedComment?.body == changedBody) {
        controller._pendingCommentSaves.remove(commentId);
      }
      if (!controller._disposed) {
        final latest = state.value ?? current;
        final visible = refreshed == null
            ? latest.comments
            : controller
                  ._applyPendingCommentBodies(
                    latest.copyWith(comments: refreshed),
                  )
                  .comments;
        final saving = <String>{...latest.savingCommentIds}..remove(commentId);
        state = AsyncData(
          latest.copyWith(
            comments: _replaceCommentBody(
              visible,
              commentId: commentId,
              body: changedBody,
            ),
            savingCommentIds: saving,
            errorMessage: refreshWarning,
            clearError: refreshWarning == null,
          ),
        );
      }
    } on ForgeException catch (error) {
      _failCommentSave(commentId, pending, error);
    } catch (error) {
      _failCommentSave(commentId, pending, error);
    } finally {
      controller._savingCommentIds.remove(commentId);
      controller._schedulePoll(controller.scope);
    }
  }

  List<ReviewComment> _replaceCommentBody(
    List<ReviewComment> comments, {
    required String commentId,
    required String body,
  }) {
    var found = false;
    final result = <ReviewComment>[];
    for (final comment in comments) {
      if (comment.id == commentId) {
        found = true;
        result.add(comment.copyWith(body: body));
      } else {
        result.add(comment);
      }
    }
    if (!found) {
      final current = state.value?.comments;
      if (current != null) {
        for (final comment in current) {
          if (comment.id == commentId) {
            result.add(comment.copyWith(body: body));
            break;
          }
        }
      }
    }
    return result;
  }

  void _failCommentSave(
    String commentId,
    _PendingReviewCommentSave pending,
    Object error,
  ) {
    final controller = _controller;
    if (controller._disposed) {
      return;
    }
    final current = state.value;
    if (current == null) {
      return;
    }
    final saving = <String>{...current.savingCommentIds}..remove(commentId);
    controller._pendingCommentSaves.remove(commentId);
    controller._savingCommentIds.remove(commentId);
    state = AsyncData(
      current.copyWith(
        comments: _replaceCommentBody(
          current.comments,
          commentId: commentId,
          body: pending.originalBody,
        ),
        savingCommentIds: saving,
        errorMessage:
            'Could not update comment: ${_commentErrorMessage(error)}',
      ),
    );
  }

  String _commentErrorMessage(Object error) {
    return error is ForgeException ? error.message : error.toString();
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
      _surfaceActionError('No linked pull request to update.');
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
