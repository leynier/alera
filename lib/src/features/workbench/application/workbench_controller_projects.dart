part of 'workbench_controller.dart';

mixin _WorkbenchControllerProjects
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerTabOpening {
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

  Future<void> sleepWorkspace(Workspace workspace) async {
    try {
      final workspaceTabs = state.tabsFor(workspace.id);
      _closingTabWorkspaceIds.add(workspace.id);
      _workspaceIdsWithClearedLayout.add(workspace.id);
      _tabFocusHistory.forget(workspace.id);
      await _repository.removeWorkspaceTabsForWorkspace(workspace.id);
      _removeCodexDrafts(workspaceTabs);
      for (final tab in workspaceTabs) {
        await _releaseHostedReviewTab(workspace, tab);
      }

      final tabsByWorkspace = Map<String, List<WorkspaceTabRecord>>.from(
        state.tabsByWorkspace,
      )..[workspace.id] = const <WorkspaceTabRecord>[];
      final layoutsByWorkspace = Map<String, WorkbenchLayout>.from(
        state.layoutByWorkspace,
      )..remove(workspace.id);
      final activeTabsByWorkspace = Map<String, String>.from(
        state.activeTabIdByWorkspace,
      )..remove(workspace.id);
      final wasActive = state.activeWorkspaceId == workspace.id;
      final prefs = state.viewPrefs;
      final nextPrefs = prefs;

      state = state.copyWith(
        tabsByWorkspace: tabsByWorkspace,
        layoutByWorkspace: layoutsByWorkspace,
        activeTabIdByWorkspace: activeTabsByWorkspace,
        activeWorkspaceId: wasActive ? null : state.activeWorkspaceId,
        viewPrefs: nextPrefs,
        error: null,
      );
      if (!identical(nextPrefs, prefs)) {
        unawaited(_persistViewPrefs());
      }
    } catch (error) {
      _workspaceIdsWithClearedLayout.remove(workspace.id);
      state = state.copyWith(error: error.toString());
      rethrow;
    } finally {
      _closingTabWorkspaceIds.remove(workspace.id);
    }
  }

  Future<void> removeProject(String projectId) async {
    try {
      final removedTabs = <WorkspaceTabRecord>[
        for (final workspace in state.workspacesFor(projectId))
          ...state.tabsFor(workspace.id),
      ];
      for (final workspace in state.workspacesFor(projectId)) {
        _tabFocusHistory.forget(workspace.id);
        for (final tab in state.tabsFor(workspace.id)) {
          await _releaseHostedReviewTab(workspace, tab);
        }
      }
      await _projectsService.removeProject(projectId);
      _removeCodexDrafts(removedTabs);
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
  }) async {
    try {
      final workspaceTabs = state.tabsFor(workspace.id);
      final terminalSessionIds = state
          .tabsFor(workspace.id)
          .where((tab) => tab.kind == WorkspaceTabKind.terminal)
          .map((tab) => tab.terminalSessionId)
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      for (final tab in workspaceTabs) {
        await _releaseHostedReviewTab(workspace, tab);
      }
      await _workspaceService.removeWorkspace(
        project: project,
        workspace: workspace,
        deleteBranch: deleteBranch,
      );
      _removeCodexDrafts(workspaceTabs);
      _tabFocusHistory.forget(workspace.id);
      ref
          .read(workspaceActivityControllerProvider.notifier)
          .removeWorkspace(workspace.id);
      ref
          .read(agentStatusControllerProvider.notifier)
          .clearWorkspace(workspace.id);
      final overlay = ref.read(agentRuntimeOverlayServiceProvider);
      for (final sessionId in terminalSessionIds) {
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

  Future<List<WorkspaceTag>> listWorkspaceTags() async {
    try {
      final tags = await _workspaceGraphRepository.listTags();
      state = state.copyWith(error: null);
      return tags;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<List<WorkspaceRelation>> listWorkspaceRelations() async {
    try {
      final relations = await _workspaceGraphRepository.listRelations();
      state = state.copyWith(error: null);
      return relations;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<WorkspaceTag> createWorkspaceTag(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw WorkspaceException('Tag name is required.');
    }
    try {
      // Tag names are unique case-insensitively in the runtime store, so a
      // duplicate name reuses the existing tag instead of minting a new id.
      final lowered = trimmed.toLowerCase();
      final existing = (await _workspaceGraphRepository.listTags())
          .where((tag) => tag.name.toLowerCase() == lowered)
          .firstOrNull;
      if (existing != null) {
        state = state.copyWith(error: null);
        return existing;
      }
      final tag = await _workspaceGraphRepository.upsertTag(
        WorkspaceTag.create(name: trimmed),
      );
      state = state.copyWith(error: null);
      return tag;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> deleteWorkspaceTag(String tagId) async {
    try {
      await _workspaceGraphRepository.removeTag(tagId);
      state = state.copyWith(error: null);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> updateWorkspaceTags({
    required Workspace workspace,
    required Set<String> tagIds,
  }) async {
    // Diff against the freshest known membership: the workspace snapshot may
    // predate tag changes applied while the dialog was open.
    final latest = state
        .workspacesFor(workspace.projectId)
        .where((candidate) => candidate.id == workspace.id)
        .firstOrNull;
    final current = (latest ?? workspace).tagIds.toSet();
    final next = tagIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    try {
      for (final tagId in current.difference(next)) {
        await _workspaceGraphRepository.unassignTag(
          workspaceId: workspace.id,
          tagId: tagId,
        );
      }
      for (final tagId in next.difference(current)) {
        await _workspaceGraphRepository.assignTag(
          workspaceId: workspace.id,
          tagId: tagId,
        );
      }
      state = state.copyWith(error: null);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> setWorkspaceParent({
    required Workspace workspace,
    String? parentWorkspaceId,
  }) async {
    final currentParentId = workspace.parentWorkspaceId?.trim();
    final nextParentId = parentWorkspaceId?.trim();
    if ((currentParentId == null || currentParentId.isEmpty) &&
        (nextParentId == null || nextParentId.isEmpty)) {
      return;
    }
    if (currentParentId == nextParentId) {
      return;
    }
    var removedCurrentParent = false;
    try {
      if (nextParentId != null && nextParentId.isNotEmpty) {
        // The dialog disables descendant options, but its relations snapshot
        // can be stale; re-validate against fresh relations before linking.
        if (nextParentId == workspace.id) {
          throw WorkspaceException('A workspace cannot be its own parent');
        }
        final relations = await _workspaceGraphRepository.listRelations();
        if (workspaceDescendantIds(
          workspace.id,
          relations,
        ).contains(nextParentId)) {
          throw WorkspaceException(
            'Cannot set a descendant workspace as parent',
          );
        }
      }
      if (currentParentId != null && currentParentId.isNotEmpty) {
        await _workspaceGraphRepository.unlinkWorkspaces(
          parentWorkspaceId: currentParentId,
          childWorkspaceId: workspace.id,
        );
        removedCurrentParent = true;
      }
      if (nextParentId != null && nextParentId.isNotEmpty) {
        try {
          await _workspaceGraphRepository.linkWorkspaces(
            parentWorkspaceId: nextParentId,
            childWorkspaceId: workspace.id,
          );
        } catch (error) {
          if (removedCurrentParent &&
              currentParentId != null &&
              currentParentId.isNotEmpty) {
            try {
              await _workspaceGraphRepository.linkWorkspaces(
                parentWorkspaceId: currentParentId,
                childWorkspaceId: workspace.id,
              );
            } catch (restoreError) {
              throw WorkspaceException(
                'Workspace parent update failed: $error. '
                'Previous parent restore failed: $restoreError',
              );
            }
          }
          rethrow;
        }
      }
      state = state.copyWith(error: null);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> selectWorkspace({
    required Project project,
    required Workspace workspace,
  }) {
    return _selectWorkspace(
      project: project,
      workspace: workspace,
      ensureInitialTerminal: true,
    );
  }

  Future<void> _selectWorkspace({
    required Project project,
    required Workspace workspace,
    required bool ensureInitialTerminal,
    bool recordHistory = true,
  }) async {
    final prefs = state.viewPrefs;
    final nextPrefs = prefs;
    state = state.copyWith(
      activeProjectId: project.id,
      activeWorkspaceId: workspace.id,
      viewPrefs: nextPrefs,
      error: null,
    );
    if (!identical(nextPrefs, prefs)) {
      unawaited(_persistViewPrefs());
    }
    if (ensureInitialTerminal) {
      await _workspaceTabService.ensureInitialTerminalTab(workspace.id);
    }
    final tabs = await _workspaceTabService.listTabs(workspace.id);
    _setTabsForWorkspace(workspace.id, tabs);
    final layout = await _ensureWorkbenchLayout(workspace.id, tabs);
    await _applyLayout(layout, persist: false);
    if (recordHistory &&
        _worktreeNavigationHistory.record(
          WorktreeNavigationTarget(
            projectId: project.id,
            workspaceId: workspace.id,
          ),
        )) {
      _notifyNavigationHistoryChanged();
    }
  }

  Future<void> activateProject(Project project) async {
    final prefs = state.viewPrefs;
    final nextPrefs = prefs;
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
