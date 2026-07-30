part of 'prompt_workspace_dialog.dart';

extension _PromptWorkspaceDialogSelectionOrder on _PromptWorkspaceDialogState {
  List<Project> get _orderedProjects =>
      sortProjectsForSelection(widget.projects);

  List<Workspace> get _parentWorkspaces {
    final projectNameById = <String, String>{
      for (final project in widget.projects) project.id: project.name,
    };
    final workspaces = <Workspace>[
      for (final workspace in widget.parentWorkspaces)
        if (workspace.isActive) workspace,
    ];
    workspaces.sort(
      (left, right) => compareWorkspaceParentSelectionKeys(
        (
          isDefault: left.isMain,
          projectId: left.projectId,
          projectName: projectNameById[left.projectId] ?? left.projectId,
          workspaceId: left.id,
          workspaceName: left.name,
        ),
        (
          isDefault: right.isMain,
          projectId: right.projectId,
          projectName: projectNameById[right.projectId] ?? right.projectId,
          workspaceId: right.id,
          workspaceName: right.name,
        ),
        preferredProjectId: _project?.id,
      ),
    );
    return workspaces;
  }
}
