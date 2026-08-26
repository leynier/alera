part of 'workspace_git_diff_panel.dart';

extension _WorkspaceGitDiffPanelNavigation on _WorkspaceGitDiffPanelState {
  void _openWorkspaceFile(String sourceRelativePath) {
    final workspaceRelativePath = widget.sourceControlScope
        .toWorkspaceRelativePath(sourceRelativePath);
    if (workspaceRelativePath == null) {
      return;
    }
    widget.onOpenFile?.call(workspaceRelativePath);
  }

  void _revealInExplorer(String sourceRelativePath) {
    final workspaceRelativePath = widget.sourceControlScope
        .toWorkspaceRelativePath(sourceRelativePath);
    if (workspaceRelativePath == null) {
      return;
    }
    final onRevealInExplorer = widget.onRevealInExplorer;
    if (onRevealInExplorer != null) {
      onRevealInExplorer(workspaceRelativePath);
      return;
    }
    ref
        .read(workspaceExplorerRevealControllerProvider.notifier)
        .reveal(
          workspaceId: widget.workspace.id,
          relativePath: workspaceRelativePath,
        );
  }
}
