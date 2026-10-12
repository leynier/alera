import 'package:alera/src/shared/infra/git/git_diff_models.dart';

enum WorkspaceGitQuickAction {
  commit('Commit'),
  commitPush('Commit & Push'),
  commitPushPr('Commit, Push & Create PR'),
  push('Push'),
  pull('Pull'),
  createPr('Push & Create PR');

  WorkspaceGitQuickAction(this.label);
  final String label;
  bool get includesCommit =>
      this == commit || this == commitPush || this == commitPushPr;
  bool get includesPr => this == commitPushPr || this == createPr;
}

class const WorkspaceGitQuickActionState({this.action, this.hint}) {
  final WorkspaceGitQuickAction? action;
  final String? hint;
  String get label => action?.label ?? 'Commit';
}

WorkspaceGitQuickActionState resolveWorkspaceGitQuickAction({
  required GitRepositoryState repository,
  required bool hasChanges,
  required bool hasRemote,
  required bool hasOpenPr,
  required bool canCreatePr,
  required bool isDefaultBranch,
  required bool hasBranchChanges,
  bool busy = false,
}) {
  if (busy) {
    return const WorkspaceGitQuickActionState(
      hint: 'Another Git action is running.',
    );
  }
  if (repository.hasConflicts) {
    return const WorkspaceGitQuickActionState(hint: 'Resolve conflicts first.');
  }
  if (repository.branch == 'HEAD') {
    return const WorkspaceGitQuickActionState(
      hint: 'Check out a branch first.',
    );
  }
  if (repository.ahead > 0 && repository.behind > 0) {
    return WorkspaceGitQuickActionState(
      action: hasChanges ? .commit : null,
      hint: 'The branch has diverged. Merge or rebase before pushing.',
    );
  }
  if (hasChanges && repository.behind > 0) {
    return const WorkspaceGitQuickActionState(
      action: .commit,
      hint: 'Commit locally, then pull before pushing.',
    );
  }
  if (hasChanges) {
    return WorkspaceGitQuickActionState(
      action: !hasRemote
          ? .commit
          : !isDefaultBranch && !hasOpenPr && canCreatePr
          ? .commitPushPr
          : .commitPush,
    );
  }
  if (repository.behind > 0) {
    return const WorkspaceGitQuickActionState(action: .pull);
  }
  final unpublished = !repository.hasUpstream && repository.headMessage != null;
  if (hasRemote && (repository.ahead > 0 || unpublished)) {
    return WorkspaceGitQuickActionState(
      action: !isDefaultBranch && !hasOpenPr && canCreatePr ? .createPr : .push,
    );
  }
  if (hasRemote &&
      !isDefaultBranch &&
      !hasOpenPr &&
      canCreatePr &&
      hasBranchChanges) {
    return const WorkspaceGitQuickActionState(action: .createPr);
  }
  return const WorkspaceGitQuickActionState(hint: 'The branch is up to date.');
}
