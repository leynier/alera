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
    final nextTab = _supportedContextPanelTabForProject(
      state.activeProject,
      tab,
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

  void _updateViewPrefs(WorkbenchViewPrefs prefs) {
    state = state.copyWith(viewPrefs: prefs);
    unawaited(_persistViewPrefs());
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
    if ((state.sidebarWidth - clamped).abs() < 0.5) {
      return;
    }
    state = state.copyWith(sidebarWidth: clamped);
  }
}
