part of 'workbench_controller.dart';

mixin _WorkbenchControllerViewPrefs
    on _$WorkbenchController, _WorkbenchControllerInternals {
  void toggleExpanded(String projectId) {
    toggleProjectCollapsed(projectId);
  }

  void toggleProjectCollapsed(String projectId) {
    final next = Set<String>.from(state.viewPrefs.collapsedProjectIds);
    if (!next.add(projectId)) {
      next.remove(projectId);
    }
    _updateViewPrefs(state.viewPrefs.copyWith(collapsedProjectIds: next));
  }

  void setGroupBy(WorkbenchGroupBy groupBy) {
    if (state.viewPrefs.groupBy == groupBy) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(groupBy: groupBy));
  }

  void setProjectSort(WorkbenchSortBy sort) {
    if (state.viewPrefs.projectSort == sort) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(projectSort: sort));
  }

  void setWorkspaceSort(WorkbenchSortBy sort) {
    if (state.viewPrefs.workspaceSort == sort) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(workspaceSort: sort));
  }

  void toggleProjectFilter(String projectId) {
    final next = Set<String>.from(state.viewPrefs.selectedProjectIds);
    if (!next.add(projectId)) {
      next.remove(projectId);
    }
    _updateViewPrefs(state.viewPrefs.copyWith(selectedProjectIds: next));
  }

  void addProjectFilter(String projectId) {
    final current = state.viewPrefs.selectedProjectIds;
    if (current.contains(projectId)) {
      return;
    }
    _updateViewPrefs(
      state.viewPrefs.copyWith(
        selectedProjectIds: <String>{...current, projectId},
      ),
    );
  }

  void removeProjectFilter(String projectId) {
    final current = state.viewPrefs.selectedProjectIds;
    if (!current.contains(projectId)) {
      return;
    }
    _updateViewPrefs(
      state.viewPrefs.copyWith(
        selectedProjectIds: current.where((id) => id != projectId).toSet(),
      ),
    );
  }

  void clearProjectFilters() {
    if (state.viewPrefs.selectedProjectIds.isEmpty) {
      return;
    }
    _updateViewPrefs(
      state.viewPrefs.copyWith(selectedProjectIds: const <String>{}),
    );
  }

  void toggleTagFilter(String tagId) {
    final next = Set<String>.from(state.viewPrefs.selectedTagIds);
    if (!next.add(tagId)) {
      next.remove(tagId);
    }
    _updateViewPrefs(state.viewPrefs.copyWith(selectedTagIds: next));
  }

  void addTagFilter(String tagId) {
    final current = state.viewPrefs.selectedTagIds;
    if (current.contains(tagId)) {
      return;
    }
    _updateViewPrefs(
      state.viewPrefs.copyWith(selectedTagIds: <String>{...current, tagId}),
    );
  }

  void removeTagFilter(String tagId) {
    final current = state.viewPrefs.selectedTagIds;
    if (!current.contains(tagId)) {
      return;
    }
    _updateViewPrefs(
      state.viewPrefs.copyWith(
        selectedTagIds: current.where((id) => id != tagId).toSet(),
      ),
    );
  }

  void clearTagFilters() {
    if (state.viewPrefs.selectedTagIds.isEmpty) {
      return;
    }
    _updateViewPrefs(
      state.viewPrefs.copyWith(selectedTagIds: const <String>{}),
    );
  }

  void toggleParentWorkspaceCollapsed(String workspaceId) {
    final next = Set<String>.from(state.viewPrefs.collapsedParentWorkspaceIds);
    if (!next.add(workspaceId)) {
      next.remove(workspaceId);
    }
    _updateViewPrefs(
      state.viewPrefs.copyWith(collapsedParentWorkspaceIds: next),
    );
  }

  /// Collapses or expands the appropriate items depending on the active group
  /// mode. In [WorkbenchGroupBy.project] this toggles every visible project
  /// group; in [WorkbenchGroupBy.none] it toggles the sidebar-visible agent-run
  /// list of the active workspace.
  void toggleCollapseAll() {
    final prefs = state.viewPrefs;
    if (prefs.groupBy == WorkbenchGroupBy.project) {
      final selected = prefs.selectedProjectIds;
      final visibleProjectIds = <String>[
        for (final project in state.projects)
          if (selected.isEmpty || selected.contains(project.id)) project.id,
      ];
      if (visibleProjectIds.isEmpty) {
        return;
      }
      final allCollapsed = visibleProjectIds.every(
        prefs.collapsedProjectIds.contains,
      );
      final next = Set<String>.from(prefs.collapsedProjectIds);
      if (allCollapsed) {
        next.removeAll(visibleProjectIds);
      } else {
        next.addAll(visibleProjectIds);
      }
      _updateViewPrefs(prefs.copyWith(collapsedProjectIds: next));
      return;
    }
    // Flat mode: toggle the expansion of every visible workspace.
    final allWorkspaceIds = <String>[
      for (final entry in state.workspacesByProject.entries)
        for (final workspace in entry.value) workspace.id,
    ];
    if (allWorkspaceIds.isEmpty) {
      return;
    }
    final anyExpanded = allWorkspaceIds.any(
      prefs.expandedWorkspaceIds.contains,
    );
    final next = Set<String>.from(prefs.expandedWorkspaceIds);
    if (anyExpanded) {
      next.removeAll(allWorkspaceIds);
    } else {
      next.addAll(allWorkspaceIds);
    }
    _updateViewPrefs(prefs.copyWith(expandedWorkspaceIds: next));
  }

  void toggleWorkspaceExpanded(String workspaceId) {
    final next = Set<String>.from(state.viewPrefs.expandedWorkspaceIds);
    if (!next.add(workspaceId)) {
      next.remove(workspaceId);
    }
    _updateViewPrefs(state.viewPrefs.copyWith(expandedWorkspaceIds: next));
  }

  void setWorkspaceExpanded(String workspaceId, bool expanded) {
    final current = state.viewPrefs.expandedWorkspaceIds;
    final isExpanded = current.contains(workspaceId);
    if (expanded == isExpanded) {
      return;
    }
    final next = Set<String>.from(current);
    if (expanded) {
      next.add(workspaceId);
    } else {
      next.remove(workspaceId);
    }
    _updateViewPrefs(state.viewPrefs.copyWith(expandedWorkspaceIds: next));
  }

  void setRightSidebarVisible(bool visible) {
    if (state.viewPrefs.rightSidebarVisible == visible) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(rightSidebarVisible: visible));
  }

  void toggleRightSidebarVisible() {
    setRightSidebarVisible(!state.viewPrefs.rightSidebarVisible);
  }

  void setRightSidebarWidth(double value) {
    final clamped = value.clamp(
      AleraTokens.sidebarMinWidth,
      AleraTokens.sidebarMaxWidth,
    );
    if ((state.viewPrefs.rightSidebarWidth - clamped).abs() < 0.5) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(rightSidebarWidth: clamped));
  }

  void setContextPanelTab(WorkbenchContextPanelTab tab) {
    final nextTab = _supportedContextPanelTabForProjectWorkspace(
      project: state.activeProject,
      workspace: state.activeWorkspace,
      prefs: state.viewPrefs,
      tab: tab,
    );
    if (state.viewPrefs.activeContextPanelTab == nextTab) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(activeContextPanelTab: nextTab));
  }

  void setExplorerMode(WorkspaceExplorerMode mode) {
    if (state.viewPrefs.explorerMode == mode) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(explorerMode: mode));
  }

  void setActiveContextPanelTab(WorkbenchContextPanelTab tab) {
    setContextPanelTab(tab);
  }

  void setGitDiffViewMode(GitDiffViewMode mode) {
    if (state.viewPrefs.gitDiffViewMode == mode) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(gitDiffViewMode: mode));
  }

  Future<bool> focusSourceControlFolder({
    required Workspace workspace,
    required String relativePath,
  }) async {
    final project = _projectById(state.projects, workspace.projectId);
    if (project == null || !project.isFolder) {
      return false;
    }
    if (state.activeProjectId != project.id ||
        state.activeWorkspaceId != workspace.id) {
      return false;
    }
    final normalized = normalizeSourceControlRootRelativePath(relativePath);
    if (normalized == null) {
      return false;
    }
    final path = sourceControlRootAbsolutePath(
      workspacePath: workspace.path,
      relativeRoot: normalized,
    );
    if (!_hasDirectGitEntry(path)) {
      return false;
    }
    final isRepository = await ref
        .read(gitBackendProvider)
        .isGitRepository(path);
    if (!isRepository) {
      return false;
    }
    if (state.activeProjectId != project.id ||
        state.activeWorkspaceId != workspace.id) {
      return false;
    }
    final nextRoots = <String, String>{
      ...state.viewPrefs.sourceControlRootByWorkspaceId,
      workspace.id: normalized,
    };
    _updateViewPrefs(
      state.viewPrefs.copyWith(
        sourceControlRootByWorkspaceId: nextRoots,
        activeContextPanelTab: WorkbenchContextPanelTab.gitDiff,
        rightSidebarVisible: true,
      ),
    );
    state = state.copyWith(error: null);
    return true;
  }

  bool _hasDirectGitEntry(String path) {
    final gitEntryPath = p.join(path, '.git');
    return Directory(gitEntryPath).existsSync() ||
        File(gitEntryPath).existsSync();
  }

  void clearFocusedSourceControlFolder({required Workspace workspace}) {
    if (!state.viewPrefs.sourceControlRootByWorkspaceId.containsKey(
      workspace.id,
    )) {
      return;
    }
    final nextRoots = Map<String, String>.from(
      state.viewPrefs.sourceControlRootByWorkspaceId,
    )..remove(workspace.id);
    final nextTab =
        state.viewPrefs.activeContextPanelTab ==
            WorkbenchContextPanelTab.gitDiff
        ? WorkbenchContextPanelTab.explorer
        : state.viewPrefs.activeContextPanelTab;
    _updateViewPrefs(
      state.viewPrefs.copyWith(
        sourceControlRootByWorkspaceId: nextRoots,
        activeContextPanelTab: nextTab,
      ),
    );
  }

  void syncSourceControlRootAfterPathMove({
    required Workspace workspace,
    required String oldRelativePath,
    required String newRelativePath,
  }) {
    final current =
        state.viewPrefs.sourceControlRootByWorkspaceId[workspace.id];
    if (current == null) {
      return;
    }
    final nextRoot = _replaceSourceControlPathPrefix(
      path: current,
      oldPath: oldRelativePath,
      newPath: newRelativePath,
    );
    if (nextRoot == null || nextRoot == current) {
      return;
    }
    _updateViewPrefs(
      state.viewPrefs.copyWith(
        sourceControlRootByWorkspaceId: <String, String>{
          ...state.viewPrefs.sourceControlRootByWorkspaceId,
          workspace.id: nextRoot,
        },
      ),
    );
  }

  void _updateViewPrefs(WorkbenchViewPrefs prefs) {
    state = state.copyWith(viewPrefs: prefs);
    unawaited(_persistViewPrefs());
  }

  String? _replaceSourceControlPathPrefix({
    required String path,
    required String oldPath,
    required String newPath,
  }) {
    final normalizedPath = normalizeSourceControlRootRelativePath(path);
    final normalizedOld = normalizeSourceControlRootRelativePath(oldPath);
    final normalizedNew = normalizeSourceControlRootRelativePath(newPath);
    if (normalizedPath == null ||
        normalizedOld == null ||
        normalizedNew == null) {
      return null;
    }
    if (normalizedPath == normalizedOld) {
      return normalizedNew;
    }
    final prefix = '$normalizedOld/';
    if (!normalizedPath.startsWith(prefix)) {
      return null;
    }
    return '$normalizedNew/${normalizedPath.substring(prefix.length)}';
  }

  void setSearchQuery(String query) {
    if (state.searchQuery == query) {
      return;
    }
    state = state.copyWith(searchQuery: query);
  }

  void setCollapsed(bool value) {
    if (state.collapsed == value) {
      return;
    }
    state = state.copyWith(collapsed: value);
  }

  void setSidebarWidth(double value) {
    final clamped = value.clamp(
      AleraTokens.sidebarMinWidth,
      AleraTokens.sidebarMaxWidth,
    );
    if ((state.viewPrefs.sidebarWidth - clamped).abs() < 0.5) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(sidebarWidth: clamped));
  }
}
