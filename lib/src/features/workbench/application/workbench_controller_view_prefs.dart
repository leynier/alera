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

  void setWorkspaceKindFilter(WorkspaceKindFilter filter) {
    if (state.viewPrefs.workspaceKindFilter == filter) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(workspaceKindFilter: filter));
  }

  void setShowActiveWorkspacesOnly(bool show) {
    if (state.viewPrefs.showActiveWorkspacesOnly == show) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(showActiveWorkspacesOnly: show));
  }

  void setShowPinnedWorkspacesBelow(bool show) {
    if (state.viewPrefs.showPinnedWorkspacesBelow == show) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(showPinnedWorkspacesBelow: show));
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

  void togglePinnedSectionCollapsed() {
    _updateViewPrefs(
      state.viewPrefs.copyWith(
        pinnedSectionCollapsed: !state.viewPrefs.pinnedSectionCollapsed,
      ),
    );
  }

  void toggleAllSectionCollapsed() {
    _updateViewPrefs(
      state.viewPrefs.copyWith(
        allSectionCollapsed: !state.viewPrefs.allSectionCollapsed,
      ),
    );
  }

  /// Collapses or expands every sidebar-visible grouping surface: project
  /// groups, parent workspace child trees, and workspace agent-run sections.
  void toggleCollapseAll() {
    final prefs = state.viewPrefs;
    final targets = visibleSidebarCollapseTargets(state);
    if (targets.isEmpty) {
      return;
    }
    final allCollapsed = targets.isCollapsed(prefs);
    final actionTargets = allCollapsed
        ? visibleSidebarCollapseTargets(
            state,
            includeCollapsedProjectDescendants: true,
          )
        : targets;
    final nextSections = Set<String>.from(prefs.collapsedSectionIds);
    final nextProjects = Set<String>.from(prefs.collapsedProjectIds);
    final nextParentWorkspaces = Set<String>.from(
      prefs.collapsedParentWorkspaceIds,
    );
    final next = Set<String>.from(prefs.expandedWorkspaceIds);
    if (allCollapsed) {
      nextSections.removeAll(actionTargets.sectionIds);
      nextProjects.removeAll(actionTargets.projectIds);
      nextParentWorkspaces.removeAll(actionTargets.parentWorkspaceIds);
      next.addAll(actionTargets.workspaceIds);
    } else {
      nextSections.addAll(actionTargets.sectionIds);
      nextProjects.addAll(actionTargets.projectIds);
      nextParentWorkspaces.addAll(actionTargets.parentWorkspaceIds);
      next.removeAll(actionTargets.workspaceIds);
    }
    _updateViewPrefs(
      prefs.copyWith(
        collapsedSectionIds: nextSections,
        othersSectionCollapsed: actionTargets.hasOthers
            ? !allCollapsed
            : prefs.othersSectionCollapsed,
        collapsedProjectIds: nextProjects,
        collapsedParentWorkspaceIds: nextParentWorkspaces,
        expandedWorkspaceIds: next,
      ),
    );
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
    if (state.viewPrefs.activeContextPanelTab == tab) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(activeContextPanelTab: tab));
  }

  void revealInExplorer({
    required Workspace workspace,
    required String relativePath,
  }) {
    final normalized = normalizeWorkspaceRelativePath(relativePath);
    if (normalized == null) {
      return;
    }
    ref
        .read(workspaceExplorerRevealControllerProvider.notifier)
        .reveal(workspaceId: workspace.id, relativePath: normalized);
    setRightSidebarVisible(true);
    setContextPanelTab(.explorer);
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

  void setGitDiffGroupMode(GitDiffGroupMode mode) {
    if (state.viewPrefs.gitDiffGroupMode == mode) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(gitDiffGroupMode: mode));
  }

  void setPullRequestCreateAction(PullRequestCreateAction action) {
    if (state.viewPrefs.pullRequestCreateAction == action) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(pullRequestCreateAction: action));
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
        activeContextPanelTab: .gitDiff,
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
    _updateViewPrefs(
      state.viewPrefs.copyWith(sourceControlRootByWorkspaceId: nextRoots),
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
