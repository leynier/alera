part of 'workbench_listing.dart';

class _WorkbenchSidebarRowBuilder(
  final WorkbenchState state, {
  required final Map<String, AgentStatusEntry> agentStatuses,
  required final Map<String, DateTime> lastActivityByWorkspaceId,
  required final DateTime now,
}) {
  this
    : prefs = state.viewPrefs, query = state.searchQuery.trim().toLowerCase();

  final WorkbenchViewPrefs prefs;

  final String query;

  final _attentionByWorkspaceId = <String, WorkspaceAttention>{};
  final _activityByWorkspaceId = <String, AgentActivityRank?>{};

  List<WorkbenchSidebarRow> build() {
    final visibleProjects = _visibleProjects();
    final pinnedRows = <WorkbenchSidebarRow>[];
    final pinnedWorkspaceCount = _appendPinnedWorkspaceRows(
      pinnedRows,
      visibleProjects,
    );
    final rows = <WorkbenchSidebarRow>[];
    _appendPinnedSection(rows, pinnedRows, pinnedWorkspaceCount);
    _appendWorkspaceSections(
      rows,
      visibleProjects,
      hasPinnedSection: pinnedRows.isNotEmpty,
    );
    return rows;
  }

  List<Project> _visibleProjects() {
    final projects = <Project>[];
    for (final project in state.projects) {
      // Positive selection: when no projects are selected we show everything;
      // otherwise we show only the explicitly selected ones.
      if (_projectVisible(prefs, project)) {
        projects.add(project);
      }
    }
    return projects;
  }

  bool _isWorkspaceVisible(Project project, Workspace workspace) {
    return _workspaceVisible(
      prefs,
      query,
      project,
      workspace,
      state.tabsFor(workspace.id),
    );
  }

  bool _isWorkspaceVisibleBelow(Project project, Workspace workspace) {
    return _isWorkspaceVisible(project, workspace) &&
        (prefs.showPinnedWorkspacesBelow || !workspace.isPinned);
  }

  int _appendPinnedWorkspaceRows(
    List<WorkbenchSidebarRow> rows,
    List<Project> visibleProjects,
  ) {
    if (prefs.groupBy == WorkbenchGroupBy.project &&
        prefs.workspaceSort != WorkbenchSortBy.activity) {
      return _appendProjectGroupedPinnedRows(rows, visibleProjects);
    }
    return _appendGlobalPinnedRows(rows, visibleProjects);
  }

  int _appendProjectGroupedPinnedRows(
    List<WorkbenchSidebarRow> rows,
    List<Project> visibleProjects,
  ) {
    var workspaceCount = 0;
    for (final project in _sortProjects(visibleProjects)) {
      final pinned = _sortWorkspaces(
        state
            .workspacesFor(project.id)
            .where(
              (workspace) =>
                  workspace.isPinned && _isWorkspaceVisible(project, workspace),
            )
            .toList(),
        pinMainOnRecent: true,
      );
      workspaceCount += pinned.length;
      _appendWorkspaceTreeRows(
        rows,
        workspaces: pinned,
        projectOf: (_) => project,
        baseIndent: 0,
        showProjectChip: true,
        isPinnedCopy: true,
        collapsedParentIds: const <String>{},
      );
    }
    return workspaceCount;
  }

  int _appendGlobalPinnedRows(
    List<WorkbenchSidebarRow> rows,
    List<Project> visibleProjects,
  ) {
    final projectByWorkspaceId = <String, Project>{};
    final pinned = <Workspace>[];
    for (final project in visibleProjects) {
      for (final workspace in state.workspacesFor(project.id)) {
        if (!workspace.isPinned || !_isWorkspaceVisible(project, workspace)) {
          continue;
        }
        projectByWorkspaceId[workspace.id] = project;
        pinned.add(workspace);
      }
    }
    _appendWorkspaceTreeRows(
      rows,
      workspaces: _sortWorkspaces(pinned, pinMainOnRecent: false),
      projectOf: (workspace) => projectByWorkspaceId[workspace.id]!,
      baseIndent: 0,
      showProjectChip: true,
      isPinnedCopy: true,
      collapsedParentIds: const <String>{},
    );
    return pinned.length;
  }

  void _appendPinnedSection(
    List<WorkbenchSidebarRow> rows,
    List<WorkbenchSidebarRow> pinnedRows,
    int workspaceCount,
  ) {
    if (pinnedRows.isEmpty) {
      return;
    }
    rows.add(
      WorkbenchPinnedHeaderRow(
        workspaceCount: workspaceCount,
        collapsed: prefs.pinnedSectionCollapsed,
      ),
    );
    if (!prefs.pinnedSectionCollapsed) {
      rows.addAll(pinnedRows);
    }
  }

  void _appendWorkspaceSections(
    List<WorkbenchSidebarRow> rows,
    List<Project> visibleProjects, {
    required bool hasPinnedSection,
  }) {
    switch (prefs.groupBy) {
      case WorkbenchGroupBy.project:
        _appendProjectGroups(rows, visibleProjects);
      case WorkbenchGroupBy.none:
        _appendFlatWorkspaceSection(
          rows,
          visibleProjects,
          hasPinnedSection: hasPinnedSection,
        );
    }
  }

  void _appendProjectGroups(
    List<WorkbenchSidebarRow> rows,
    List<Project> visibleProjects,
  ) {
    final filtersHideEmptyProjects =
        query.isNotEmpty ||
        prefs.selectedTagIds.isNotEmpty ||
        prefs.workspaceKindFilter != WorkspaceKindFilter.all ||
        prefs.showActiveWorkspacesOnly ||
        !prefs.showPinnedWorkspacesBelow;
    for (final project in _sortProjects(visibleProjects)) {
      final workspaces = _sortWorkspaces(
        state
            .workspacesFor(project.id)
            .where((workspace) => _isWorkspaceVisibleBelow(project, workspace))
            .toList(),
        pinMainOnRecent: true,
      );
      if (filtersHideEmptyProjects && workspaces.isEmpty) {
        continue;
      }
      final collapsed = prefs.collapsedProjectIds.contains(project.id);
      rows.add(
        WorkbenchProjectHeaderRow(
          project: project,
          workspaceCount: workspaces.length,
          collapsed: collapsed,
        ),
      );
      if (collapsed) {
        continue;
      }
      _appendWorkspaceTreeRows(
        rows,
        workspaces: workspaces,
        projectOf: (_) => project,
        baseIndent: 1,
        showProjectChip: false,
      );
    }
  }

  void _appendFlatWorkspaceSection(
    List<WorkbenchSidebarRow> rows,
    List<Project> visibleProjects, {
    required bool hasPinnedSection,
  }) {
    final projectByWorkspaceId = <String, Project>{};
    final workspaces = <Workspace>[];
    for (final project in visibleProjects) {
      for (final workspace in state.workspacesFor(project.id)) {
        if (!_isWorkspaceVisibleBelow(project, workspace)) {
          continue;
        }
        projectByWorkspaceId[workspace.id] = project;
        workspaces.add(workspace);
      }
    }
    // The flat list only gets an "All" header when a pinned section sits
    // above it - without pins there is nothing to separate it from.
    final showAllSection = hasPinnedSection && workspaces.isNotEmpty;
    if (showAllSection) {
      rows.add(
        WorkbenchAllHeaderRow(
          workspaceCount: workspaces.length,
          collapsed: prefs.allSectionCollapsed,
        ),
      );
    }
    if (!showAllSection || !prefs.allSectionCollapsed) {
      _appendWorkspaceTreeRows(
        rows,
        workspaces: _sortWorkspaces(workspaces, pinMainOnRecent: false),
        projectOf: (workspace) => projectByWorkspaceId[workspace.id]!,
        baseIndent: 0,
        showProjectChip: true,
      );
    }
  }

  void _appendWorkspaceTreeRows(
    List<WorkbenchSidebarRow> rows, {
    required List<Workspace> workspaces,
    required Project Function(Workspace) projectOf,
    required int baseIndent,
    required bool showProjectChip,
    bool isPinnedCopy = false,
    Set<String>? collapsedParentIds,
  }) {
    final tree = buildWorkspaceTree(
      entries: workspaces,
      collapsedParentIds:
          collapsedParentIds ?? prefs.collapsedParentWorkspaceIds,
    );
    for (final entry in tree) {
      final tabs = state.tabsFor(entry.workspace.id);
      final agentRuns = visibleWorkspaceAgentRuns(
        tabs: tabs,
        agentStatuses: agentStatuses,
      );
      rows.add(
        WorkbenchWorkspaceRow(
          project: projectOf(entry.workspace),
          workspace: entry.workspace,
          showProjectChip: showProjectChip,
          indent: baseIndent + entry.depth,
          expanded: prefs.expandedWorkspaceIds.contains(entry.workspace.id),
          agentRuns: agentRuns,
          agentRunGroups: groupWorkspaceAgentRuns(agentRuns),
          hasTerminalTabs: tabs.any(
            (tab) => tab.kind == WorkspaceTabKind.terminal,
          ),
          visibleChildCount: entry.visibleChildCount,
          childrenCollapsed: entry.childrenCollapsed,
          isPinnedCopy: isPinnedCopy,
        ),
      );
    }
  }

  List<Workspace> _sortWorkspaces(
    List<Workspace> workspaces, {
    required bool pinMainOnRecent,
  }) {
    // The flat view mixes several projects, so pinning each project's main
    // worktree only applies to the name sort there; grouped mode pins it for
    // name and recent. Agent Activity never pins - urgency owns the order.
    return _sortSidebarWorkspaces(
      workspaces,
      sortBy: prefs.workspaceSort,
      pinMainOnRecent: pinMainOnRecent,
      activityOf: _activityOf,
    );
  }

  List<Project> _sortProjects(List<Project> projects) {
    return _sortSidebarProjects(
      projects,
      sortBy: prefs.projectSort,
      workspacesFor: state.workspacesFor,
      workspaceVisible: _isWorkspaceVisible,
      activityOf: _activityOf,
    );
  }

  WorkspaceAttention _attentionOf(Workspace workspace) {
    return _attentionByWorkspaceId.putIfAbsent(
      workspace.id,
      () => workspaceAttention(
        tabs: state.tabsFor(workspace.id),
        agentStatuses: agentStatuses,
        now: now,
      ),
    );
  }

  AgentActivityRank? _activityOf(Workspace workspace) {
    if (_activityByWorkspaceId.containsKey(workspace.id)) {
      return _activityByWorkspaceId[workspace.id];
    }
    final tabs = state.tabsFor(workspace.id);
    final activity =
        tabs.any(
          (tab) =>
              tab.kind == WorkspaceTabKind.terminal ||
              tab.kind == WorkspaceTabKind.codex,
        )
        ? agentActivityRank(
            attention: _attentionOf(workspace),
            fallback:
                lastActivityByWorkspaceId[workspace.id] ?? workspace.updatedAt,
          )
        : null;
    _activityByWorkspaceId[workspace.id] = activity;
    return activity;
  }
}
