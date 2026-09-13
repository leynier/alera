import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_pull_request_actions.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_action_controller.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_pull_request_conversation.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_comment_sheet.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_link_create_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The flows behind the Pull Request panel's controls: confirm, run the write
/// through the kept-alive [PullRequestActionController], and report failure.
/// The controller is read before any await, because the panel that owns
/// [ref] can be disposed while GitHub answers.
class const PullRequestPanelActions({
  required final WidgetRef ref,
  required final String hostId,
  required final String workspaceId,
}) {
  PullRequestActionController get _controller => ref.read(
    pullRequestActionControllerProvider(hostId, workspaceId).notifier,
  );

  Future<void> runReviewAction(
    BuildContext context,
    MobilePullRequestSnapshot snapshot,
    MobilePullRequestReviewAction action,
  ) async {
    final review = snapshot.review;
    if (review == null) {
      return;
    }
    final controller = _controller;
    final messenger = ScaffoldMessenger.of(context);
    final copy = pullRequestActionConfirmation(action, review.number);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: copy.title,
        message: copy.message,
        confirmLabel: copy.confirmLabel,
        destructive: copy.destructive,
      ),
    );
    if (confirmed != true) {
      return;
    }
    final number = review.number;
    final error = await switch (action.kind) {
      .merge => controller.run(
        .merge,
        (client) => client.mergePullRequest(
          workspaceId: workspaceId,
          number: number,
          method: action.method!,
        ),
      ),
      .markReady || .convertToDraft => controller.run(
        .draftStatus,
        (client) => client.setPullRequestDraft(
          workspaceId: workspaceId,
          number: number,
          draft: action.kind == .convertToDraft,
        ),
      ),
      .close => controller.run(
        .close,
        (client) =>
            client.closePullRequest(workspaceId: workspaceId, number: number),
      ),
      .unlink => controller.run(
        .unlink,
        (client) => client.unlinkPullRequest(
          workspaceId: workspaceId,
          number: number,
          url: review.url.isEmpty ? null : review.url,
        ),
      ),
    };
    _report(messenger, error);
  }

  Future<void> addComment(BuildContext context, int number) {
    final controller = _controller;
    return showPullRequestCommentSheet(
      context,
      title: 'Add Comment',
      submitLabel: 'Post Comment',
      onSubmit: (body) => controller.run(
        .comment,
        (client) => client.commentOnPullRequest(
          workspaceId: workspaceId,
          number: number,
          body: body,
        ),
      ),
    );
  }

  Future<void> reply(
    BuildContext context,
    int number,
    MobilePullRequestConversationThread thread,
  ) {
    final controller = _controller;
    final root = thread.comments.first;
    return showPullRequestCommentSheet(
      context,
      title: thread.location == null ? 'Reply' : 'Reply On ${thread.location}',
      submitLabel: 'Reply',
      onSubmit: (body) => controller.run(
        .comment,
        (client) => client.commentOnPullRequest(
          workspaceId: workspaceId,
          number: number,
          body: body,
          replyToCommentId: root.id,
        ),
      ),
    );
  }

  Future<void> edit(
    BuildContext context,
    int number,
    MobilePullRequestComment comment,
  ) {
    final controller = _controller;
    return showPullRequestCommentSheet(
      context,
      title: 'Edit Comment',
      submitLabel: 'Save',
      initialText: comment.body,
      onSubmit: (body) => controller.run(
        .editComment,
        (client) => client.editPullRequestComment(
          workspaceId: workspaceId,
          number: number,
          comment: comment,
          body: body,
        ),
      ),
    );
  }

  Future<void> link(BuildContext context, {String? reference}) async {
    final controller = _controller;
    final messenger = ScaffoldMessenger.of(context);
    final value = reference ?? await showLinkPullRequestDialog(context);
    if (value == null) {
      return;
    }
    final error = await controller.run(
      .link,
      (client) =>
          client.linkPullRequest(workspaceId: workspaceId, reference: value),
    );
    _report(messenger, error);
  }

  Future<void> create(
    BuildContext context,
    MobilePullRequestSnapshot snapshot,
  ) {
    final controller = _controller;
    return showCreatePullRequestSheet(
      context,
      headBranch: snapshot.branch,
      baseBranches: snapshot.baseBranches,
      suggestedBaseBranch: snapshot.suggestedBaseBranch,
      onSubmit: (input) => controller.run(
        .create,
        (client) =>
            client.createPullRequest(workspaceId: workspaceId, input: input),
      ),
    );
  }

  void _report(ScaffoldMessengerState messenger, String? error) {
    if (error != null && messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }
}
