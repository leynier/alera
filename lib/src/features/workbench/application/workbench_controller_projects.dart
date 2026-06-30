part of 'workbench_controller.dart';

mixin _WorkbenchControllerProjects
    on _$WorkbenchController, _WorkbenchControllerInternals {
  Future<List<String>> listSourceBranches(Project project) {
    return _workspaceService.listSourceBranches(project);
  }

  Future<Project> addLocalProject({required String path, String? name}) async {
    try {
      final project = await _projectsService.addLocalProject(
        path: path,
        name: name,
      );
      await _activateAddedProject(project);
      return project;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<Project> cloneProject({
    required String gitUrl,
    required String destinationPath,
    String? name,
  }) async {
    try {
      final project = await _projectsService.cloneProject(
        gitUrl: gitUrl,
        destinationPath: destinationPath,
        name: name,
      );
      await _activateAddedProject(project);
      return project;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<Project> addProject({required String repoPath, String? name}) {
    return addLocalProject(path: repoPath, name: name);
  }

  Future<void> renameProject({
    required String projectId,
    required String name,
  }) async {
    try {
      final project = await _projectsService.renameProject(
        projectId: projectId,
        name: name,
      );
      final projects = <Project>[
        for (final candidate in state.projects)
          if (candidate.id == project.id) project else candidate,
      ];
      state = state.copyWith(projects: projects, error: null);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> removeProject(String projectId) async {
    try {
      await _projectsService.removeProject(projectId);
      state = state.copyWith(error: null);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<WorkspaceCreationResult> createWorkspace({
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    bool reuseExistingBranch = false,
    String? name,
  }) async {
    try {
      final result = await _workspaceService.createLinkedWorkspace(
        project: project,
        sourceBranch: sourceBranch,
        newBranchName: newBranchName,
        reuseExistingBranch: reuseExistingBranch,
        name: name,
      );
      await selectWorkspace(project: project, workspace: result.workspace);
      state = state.copyWith(error: null);
      return result;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> deleteWorkspace({
    required Project project,
    required Workspace workspace,
    bool deleteBranch = true,
  }) async {
    try {
      await _workspaceService.removeWorkspace(
        project: project,
        workspace: workspace,
        deleteBranch: deleteBranch,
      );
      state = state.copyWith(error: null);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> renameWorkspace({
    required String workspaceId,
    required String name,
  }) async {
    try {
      final workspace = await _workspaceService.renameWorkspace(
        workspaceId: workspaceId,
        name: name,
      );
      final current = state.workspacesFor(workspace.projectId);
      final nextWorkspaces = <String, List<Workspace>>{
        ...state.workspacesByProject,
        workspace.projectId: <Workspace>[
          for (final candidate in current)
            if (candidate.id == workspace.id) workspace else candidate,
        ],
      };
      state = state.copyWith(workspacesByProject: nextWorkspaces, error: null);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> selectWorkspace({
    required Project project,
    required Workspace workspace,
  }) async {
    // Selecting a workspace also reveals its sidebar agent-run list so the
    // user can jump into a run right away. Subsequent toggles via the chevron
    // can hide it back independently of the active selection.
    final prefs = state.viewPrefs;
    final expandedPrefs = prefs.expandedWorkspaceIds.contains(workspace.id)
        ? prefs
        : prefs.copyWith(
            expandedWorkspaceIds: <String>{
              ...prefs.expandedWorkspaceIds,
              workspace.id,
            },
          );
    final nextPrefs = _viewPrefsForProjectContext(
      project: project,
      workspace: workspace,
      prefs: expandedPrefs,
    );
    state = state.copyWith(
      activeProjectId: project.id,
      activeWorkspaceId: workspace.id,
      viewPrefs: nextPrefs,
      error: null,
    );
    if (!identical(nextPrefs, prefs)) {
      unawaited(_persistViewPrefs());
    }
    await _workspaceTabService.ensureInitialTerminalTab(workspace.id);
    final tabs = await _workspaceTabService.listTabs(workspace.id);
    final layout = await _ensureWorkbenchLayout(workspace.id, tabs);
    await _applyLayout(layout, persist: false);
  }

  Future<void> activateProject(Project project) async {
    final prefs = state.viewPrefs;
    final nextPrefs = _viewPrefsForProjectContext(
      project: project,
      workspace: null,
      prefs: prefs,
    );
    state = state.copyWith(
      activeProjectId: project.id,
      activeWorkspaceId: null,
      viewPrefs: nextPrefs,
      error: null,
    );
    if (!identical(nextPrefs, prefs)) {
      unawaited(_persistViewPrefs());
    }
  }
}
