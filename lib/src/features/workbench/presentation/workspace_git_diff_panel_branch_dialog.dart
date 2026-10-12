part of 'workspace_git_diff_panel.dart';

extension _SharedCheckoutBranchConfirmation on _WorkspaceGitDiffPanelState {
  Future<bool> _confirmSharedBranchChange(String branch) =>
      confirmWorkspaceBranchChange(context, widget.workspace, branch);
}
