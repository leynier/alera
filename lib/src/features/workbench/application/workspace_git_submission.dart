import 'package:alera/src/shared/infra/git/git_network_progress.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/workbench/domain/workspace_git_quick_action.dart';
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_workspace_comparison.dart';

class WorkspaceGitSubmission {
  WorkspaceGitSubmission({
    required this.path,
    required this.action,
    required this.snapshot,
    required this.files,
    required this.message,
    this.review,
    this.newBranch,
  });
  final String path;
  final WorkspaceGitQuickAction action;
  GitWorkspaceComparison snapshot;
  final List<String> files;
  final String message;
  final CreateReviewInput? review;
  final String? newBranch;
  String? committedOid;
  bool branchCreated = false;
  bool commitCompleted = false;
  bool pushCompleted = false;
  bool reviewCompleted = false;
  String get pendingLabel => reviewCompleted
      ? 'Retry Refresh'
      : pushCompleted && action.includesPr
      ? 'Retry Create PR'
      : !commitCompleted
      ? 'Retry ${action.label}'
      : action.includesPr
      ? 'Retry Push & Create PR'
      : 'Retry Push';
  String get completedSummary => reviewCompleted
      ? 'The PR was created and the branch was pushed. '
      : pushCompleted
      ? commitCompleted
            ? 'The commit was created and pushed. '
            : 'The branch was pushed. '
      : commitCompleted
      ? 'The commit was created. '
      : branchCreated
      ? 'The branch was created. '
      : '';

  Future<void> run(
    GitBackend git,
    Future<CreateReviewResult> Function(CreateReviewInput) createReview, {
    void Function(String phase)? onPhase,
    void Function(String line)? onOutput,
  }) async {
    if (!branchCreated && newBranch != null) {
      final current = await git.workspaceComparison(path);
      if (current.headOid != snapshot.headOid ||
          current.headRef != snapshot.headRef ||
          current.treeOid != snapshot.treeOid ||
          current.indexOid != snapshot.indexOid) {
        throw StateError('Files or HEAD changed. Review the action again.');
      }
      onPhase?.call('Creating Branch');
      await git.createAndCheckoutBranch(
        path: path,
        branch: newBranch!,
        expectedHead: snapshot.headRef.substring('refs/heads/'.length),
        expectedOid: snapshot.headOid,
      );
      branchCreated = true;
      final next = await git.workspaceComparison(path);
      if (next.treeOid != current.treeOid ||
          next.indexOid != current.indexOid) {
        throw StateError(
          'Files changed after creating the branch. Review the commit again.',
        );
      }
      snapshot = next;
    }
    if (action.includesCommit && !commitCompleted) {
      onPhase?.call('Committing');
      committedOid = await git.commitSelected(path, snapshot, files, message);
      commitCompleted = true;
    }
    if (action != WorkspaceGitQuickAction.commit) {
      final current = await git.workspaceComparison(path);
      if (current.headRef != snapshot.headRef ||
          current.headOid != (committedOid ?? snapshot.headOid)) {
        throw StateError(
          'The branch moved. Review the remaining action again.',
        );
      }
    }
    if (action.includesPr) {
      if (!pushCompleted) {
        onPhase?.call('Pushing');
        await runGitNetworkWithProgress(
          git,
          path,
          push: true,
          onOutput: onOutput ?? (_) {},
        );
        pushCompleted = true;
      }
      if (!reviewCompleted) {
        onPhase?.call('Creating PR');
        final result = await createReview(review!);
        if (result is CreateReviewFailure) throw StateError(result.message);
        reviewCompleted = true;
      }
      pushCompleted = true;
    } else if (action == WorkspaceGitQuickAction.pull) {
      onPhase?.call('Pulling');
      await runGitNetworkWithProgress(
        git,
        path,
        push: false,
        onOutput: onOutput ?? (_) {},
      );
    } else if (action != WorkspaceGitQuickAction.commit && !pushCompleted) {
      onPhase?.call('Pushing');
      await runGitNetworkWithProgress(
        git,
        path,
        push: true,
        onOutput: onOutput ?? (_) {},
      );
      pushCompleted = true;
    }
  }
}
