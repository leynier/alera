part of 'workbench_controller.dart';

mixin _WorkbenchControllerWorkspaceReconciliation on _$WorkbenchController {
  void _reconcileCreatedWorkspace(Project project, Workspace workspace) {
    final workspaces = List<Workspace>.from(state.workspacesFor(project.id));
    final index = workspaces.indexWhere((entry) => entry.id == workspace.id);
    if (index == -1) {
      workspaces.add(workspace);
    } else {
      workspaces[index] = workspace;
    }
    state = state.copyWith(
      workspacesByProject: Map<String, List<Workspace>>.from(
        state.workspacesByProject,
      )..[project.id] = workspaces,
    );
  }
}
