part of 'workbench_controller.dart';

mixin _WorkbenchControllerViewPrefs
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerWorkspacePanelPanes {
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
    if (!visible && state.activeWorkspaceId != null) {
      final id = state.activeWorkspaceId!;
      final panel = state.workspacePanelFor(id);
      _panelSelectionRevisionByWorkspace[id] =
          (_panelSelectionRevisionByWorkspace[id] ?? 0) + 1;
      final mainKey =
          panel.ensuredMainLayout(id).activeTabId ?? panel.mainKeys.firstOrNull;
      if (mainKey != null) {
        _saveWorkspacePanel(id, panel.select(mainKey));
        _focusPanelTerminal(id, mainKey);
      }
    }
  }

  void toggleRightSidebarVisible() {
    setRightSidebarVisible(!state.viewPrefs.rightSidebarVisible);
  }

  void setRightSidebarWidth(double value) {
    if (!value.isFinite) {
      return;
    }
    final clamped = value.clamp(AleraTokens.sidebarMinWidth, double.infinity);
    final workspaceId = state.activeWorkspaceId;
    final prefs = state.viewPrefs;
    final fallback = prefs.rightSidebarWidth;
    if (workspaceId == null) {
      if ((fallback - clamped).abs() < 0.5) {
        return;
      }
      _updateViewPrefs(prefs.copyWith(rightSidebarWidth: clamped));
      return;
    }
    final nextWidths = Map<String, double>.from(
      prefs.rightSidebarWidthByWorkspaceId,
    );
    if ((fallback - clamped).abs() < 0.5) {
      if (!nextWidths.containsKey(workspaceId)) {
        return;
      }
      nextWidths.remove(workspaceId);
    } else if ((prefs.rightSidebarWidthFor(workspaceId, fallback: fallback) -
                clamped)
            .abs() <
        0.5) {
      return;
    } else {
      nextWidths[workspaceId] = clamped;
    }
    _updateViewPrefs(
      prefs.copyWith(rightSidebarWidthByWorkspaceId: nextWidths),
    );
  }

  void setContextPanelTab(WorkbenchContextPanelTab tab) {
    var prefs = state.viewPrefs;
    if (prefs.activeContextPanelTab != tab) {
      prefs = prefs.copyWith(activeContextPanelTab: tab);
      state = state.copyWith(viewPrefs: prefs);
      unawaited(_persistViewPrefs());
    }
    final id = state.activeWorkspaceId;
    if (id == null) {
      return;
    }
    final tool = switch (tab) {
      WorkbenchContextPanelTab.explorer => WorkspaceTool.explorer,
      WorkbenchContextPanelTab.search => WorkspaceTool.search,
      WorkbenchContextPanelTab.gitDiff => WorkspaceTool.sourceControl,
      WorkbenchContextPanelTab.pullRequests => WorkspaceTool.pullRequest,
    };
    _panelSelectionRevisionByWorkspace[id] =
        (_panelSelectionRevisionByWorkspace[id] ?? 0) + 1;
    _saveWorkspacePanel(
      id,
      state.workspacePanelFor(id).select(tool.key),
      reveal: true,
    );
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

  void setSearchViewAsTree(bool value) {
    if (state.viewPrefs.searchViewAsTree == value) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(searchViewAsTree: value));
  }

  void setSearchIncludeIgnored(bool value) {
    if (state.viewPrefs.searchIncludeIgnored == value) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(searchIncludeIgnored: value));
  }

  void setPullRequestCreateAction(PullRequestCreateAction action) {
    if (state.viewPrefs.pullRequestCreateAction == action) {
      return;
    }
    _updateViewPrefs(state.viewPrefs.copyWith(pullRequestCreateAction: action));
  }

  void setNewWorkspaceTools(List<WorkspaceTool> tools) {
    final next = WorkspaceTool.uniqueInOrder(tools);
    final current = state.viewPrefs.newWorkspaceTools;
    if (current.length == next.length) {
      var same = true;
      for (var i = 0; i < current.length; i++) {
        if (current[i] != next[i]) {
          same = false;
          break;
        }
      }
      if (same) {
        return;
      }
    }
    _updateViewPrefs(state.viewPrefs.copyWith(newWorkspaceTools: next));
  }

  void _updateViewPrefs(WorkbenchViewPrefs prefs) {
    state = state.copyWith(viewPrefs: prefs);
    unawaited(_persistViewPrefs());
  }

  void _applySharedViewPrefs(WorkbenchViewPrefs prefs) {
    if (_disposed) {
      return;
    }
    final current = state.viewPrefs;
    state = state.copyWith(
      viewPrefs: prefs.copyWith(
        workspacePanels: current.workspacePanels,
        expandedWorkspaceIds: current.expandedWorkspaceIds,
        sourceControlRootByWorkspaceId: current.sourceControlRootByWorkspaceId,
        rightSidebarVisible: current.rightSidebarVisible,
        rightSidebarWidth: current.rightSidebarWidth,
        rightSidebarWidthByWorkspaceId: current.rightSidebarWidthByWorkspaceId,
        sidebarWidth: current.sidebarWidth,
        activeContextPanelTab: current.activeContextPanelTab,
        explorerMode: current.explorerMode,
        pullRequestCreateAction: current.pullRequestCreateAction,
        newWorkspaceTools: current.newWorkspaceTools,
      ),
    );
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
