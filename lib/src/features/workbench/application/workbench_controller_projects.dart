part of 'workbench_controller.dart';

mixin _WorkbenchControllerProjects
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerWorkspacePanel,
        _WorkbenchControllerTabOpening {
  Future<List<String>> listSourceBranches(Project project) =>
      _workspaceService.listSourceBranches(project);

  Future<Project> addLocalProject({required String path, String? name}) async {
    try {
      final existingIds = (await _projectsService.projectRepository.listAll())
          .map((project) => project.id)
          .toSet();
      final project = await _projectsService.addLocalProject(
        path: path,
        name: name,
      );
      if (!existingIds.contains(project.id) &&
          _projectsService.runtimeProjectManagement == null) {
        await _workspaceService.createSharedWorkspace(
          project: project,
          name: project.name,
        );
      }
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
      if (_projectsService.runtimeProjectManagement == null) {
        await _workspaceService.createSharedWorkspace(
          project: project,
          name: project.name,
        );
      }
      await _activateAddedProject(project);
      return project;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<ProjectCloneJob> startProjectClone({
    required String gitUrl,
    required String destinationPath,
    String? name,
  }) {
    return _projectsService.startClone(
      gitUrl: gitUrl,
      destinationPath: destinationPath,
      name: name,
    );
  }

  Future<List<ProjectCloneJob>> listProjectCloneJobs() {
    return _projectsService.listCloneJobs();
  }

  Future<void> cancelProjectClone(String id) {
    return _projectsService.cancelClone(id);
  }

  Future<void> activateAddedProject(Project project) {
    return _activateAddedProject(project);
  }

  Future<Project> addProject({required String repoPath, String? name}) =>
      addLocalProject(path: repoPath, name: name);

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
      final removedWorkspaces = state.workspacesFor(projectId);
      await _projectsService.removeProject(projectId);
      for (final workspace in removedWorkspaces) {
        _tabFocusHistory.forget(workspace.id);
        for (final tab in state.tabsFor(workspace.id)) {
          await _releaseHostedReviewTab(workspace, tab);
        }
      }
      state = state.copyWith(error: null);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> deleteWorkspace({
    required Project project,
    required Workspace workspace,
    bool deleteBranch = true,
    String? activeWorkspaceId,
  }) async {
    try {
      final workspaceTabs = state.tabsFor(workspace.id);
      final terminalSessionIds = state
          .tabsFor(workspace.id)
          .where((tab) => tab.kind == WorkspaceTabKind.terminal)
          .map((tab) => tab.terminalSessionId)
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      await _workspaceService.removeWorkspace(
        project: project,
        workspace: workspace,
        deleteBranch: deleteBranch,
        activeWorkspaceId: activeWorkspaceId,
      );
      // The managed runtime has already stopped the process trees. Keep local
      // disposal here so deletion from any caller releases the UI resources.
      ref.read(terminalRuntimeProvider).closeWorkspace(workspace.id);
      for (final tab in workspaceTabs) {
        ref.read(terminalRuntimeProvider).closeTab(tab.id);
      }
      for (final tab in workspaceTabs) {
        ref.read(editorSessionRegistryProvider).forget(tab.id);
      }
      for (final tab in workspaceTabs) {
        await _releaseHostedReviewTab(
          workspace,
          tab,
          fallbackWorkspacePath: project.repoPath,
        );
      }
      _tabFocusHistory.forget(workspace.id);
      ref
          .read(workspaceActivityControllerProvider.notifier)
          .removeWorkspace(workspace.id);
      ref
          .read(agentStatusControllerProvider.notifier)
          .clearWorkspace(workspace.id);
      final overlay = ref.read(agentRuntimeOverlayServiceProvider);
      for (final sessionId in terminalSessionIds) {
        if (ref.exists(agentHookReceiverProvider)) {
          ref.read(agentHookReceiverProvider).clearTerminalSession(sessionId);
        }
        unawaited(
          overlay.clearTerminalOverlays(sessionId).catchError((Object _) {}),
        );
      }
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

  Future<void> setWorkspacePinned({
    required String workspaceId,
    required bool isPinned,
  }) async {
    try {
      final workspace = await _repository.setWorkspacePinned(
        workspaceId,
        isPinned,
      );
      final current = state.workspacesFor(workspace.projectId);
      state = state.copyWith(
        workspacesByProject: <String, List<Workspace>>{
          ...state.workspacesByProject,
          workspace.projectId: <Workspace>[
            for (final candidate in current)
              if (candidate.id == workspace.id) workspace else candidate,
          ],
        },
        error: null,
      );
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  /// Pins or unpins [workspaceId] and every descendant of [workspaceId].
  /// No-ops workspaces that already match [isPinned].
  Future<void> setWorkspaceTreePinned({
    required String workspaceId,
    required bool isPinned,
  }) async {
    final workspaces = <Workspace>[
      for (final group in state.workspacesByProject.values) ...group,
    ];
    for (final id in [
      workspaceId,
      ...workspaceIdsDescendedFrom(workspaces, workspaceId),
    ]) {
      Workspace? current;
      for (final workspace in workspaces) {
        if (workspace.id == id) {
          current = workspace;
          break;
        }
      }
      if (current == null || current.isPinned == isPinned) {
        continue;
      }
      await setWorkspacePinned(workspaceId: id, isPinned: isPinned);
    }
  }
}
