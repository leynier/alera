import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_pull_request_actions.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_action_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_pull_request_conversation.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_comment_sheet.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_link_create_sheets.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_ship_sheet.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_removal_launcher.dart';
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
    if (action.kind == .removeWorkspace) {
      await _removeWorkspace(context);
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
      .removeWorkspace => throw StateError(
        'Remove Workspace uses the workspace removal dialog.',
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
    MobilePullRequestSnapshot snapshot, {
    bool canGenerate = false,
  }) {
    final controller = _controller;
    // Read before the sheet opens: the panel that owns [ref] may be gone by
    // the time the user taps Generate.
    final client = ref.read(workspaceClientProvider(hostId).future);
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
      onGenerate: canGenerate
          ? (baseBranch) async {
              final actions = await client;
              if (actions is! MobilePullRequestActionsClient) {
                throw UnsupportedError(
                  'Update the paired Alera runtime to generate pull request details.',
                );
              }
              return (actions as MobilePullRequestActionsClient)
                  .generatePullRequestDetails(
                    workspaceId: workspaceId,
                    baseBranch: baseBranch,
                  );
            }
          : null,
    );
  }

  Future<void> ship(
    BuildContext context,
    MobilePullRequestSnapshot snapshot,
  ) async {
    final controller = _controller;
    final askWorkingTreeScope = await _askWorkingTreeScope();
    if (!context.mounted) {
      return;
    }
    return showShipPullRequestSheet(
      context,
      headBranch: snapshot.branch,
      baseBranches: snapshot.baseBranches,
      suggestedBaseBranch: snapshot.suggestedBaseBranch,
      askWorkingTreeScope: askWorkingTreeScope,
      onSubmit: (input) => controller.run(
        .ship,
        (client) =>
            client.shipPullRequest(workspaceId: workspaceId, input: input),
      ),
    );
  }

  /// Statuses the workspace root, not the Source Control panel's nested root.
  /// Host Ship always plans against `workspace.path`, matching desktop.
  Future<bool> _askWorkingTreeScope() async {
    try {
      final client = await ref.read(workspaceClientProvider(hostId).future);
      if (client case final MobileWorkspacePanelsClient panels
          when panels.supportsSourceControl) {
        final snapshot = await panels.gitStatus(workspaceId);
        return shipShowsWorkingTreeScopeChoice(snapshot);
      }
      return true;
    } on Object {
      return true;
    }
  }

  Future<void> _removeWorkspace(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    late final WorkspaceListData list;
    final loaded = ref.read(workspaceListControllerProvider(hostId)).value;
    if (loaded != null) {
      list = loaded;
    } else {
      try {
        list = await ref.read(workspaceListControllerProvider(hostId).future);
      } on Object catch (error) {
        _report(messenger, pullRequestActionErrorMessage(error));
        return;
      }
    }
    if (!list.supportsMutations) {
      _report(
        messenger,
        'Update the paired Alera runtime to remove workspaces.',
      );
      return;
    }
    final workspace = list.workspaceById(workspaceId);
    if (workspace == null) {
      _report(messenger, 'Workspace no longer exists. Refresh the list.');
      return;
    }
    if (!context.mounted) {
      return;
    }
    try {
      final removed = await confirmAndDeleteWorkspace(
        context,
        ref.read(workspaceListControllerProvider(hostId).notifier),
        workspace,
        list,
      );
      if (removed && context.mounted) {
        await navigator.maybePop();
      }
    } on Object catch (error) {
      _report(messenger, pullRequestActionErrorMessage(error));
    }
  }

  void _report(ScaffoldMessengerState messenger, String? error) {
    if (error != null && messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }
}
