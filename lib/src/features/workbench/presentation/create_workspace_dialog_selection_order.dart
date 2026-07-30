part of 'create_workspace_dialog.dart';

extension _CreateWorkspaceDialogSelectionOrder on _CreateWorkspaceDialogState {
  List<Project> get _orderedProjects =>
      sortProjectsForSelection(widget.projects);

  List<WorkspaceParentCandidate> get _parentCandidates {
    final candidates = <WorkspaceParentCandidate>[
      for (final candidate in widget.parentCandidates)
        if (candidate.workspace.status == WorkspaceStatus.active) candidate,
    ];
    candidates.sort(
      (left, right) => compareWorkspaceParentSelectionKeys(
        (
          isDefault: left.workspace.isMain,
          projectId: left.project.id,
          projectName: left.project.name,
          workspaceId: left.workspace.id,
          workspaceName: left.workspace.name,
        ),
        (
          isDefault: right.workspace.isMain,
          projectId: right.project.id,
          projectName: right.project.name,
          workspaceId: right.workspace.id,
          workspaceName: right.workspace.name,
        ),
        preferredProjectId: _selectedProject?.id,
      ),
    );
    return candidates;
  }
}
