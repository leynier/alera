import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_agent_activity_sort.dart';
import 'package:alera/src/features/workbench/application/workbench_listing_tree.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workbench_workspace_filters.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_run_groups.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';

part 'workbench_sidebar_rows.dart';
part 'workbench_sidebar_row_builder.dart';
part 'workbench_listing_sort.dart';

/// Builds the flat list of rows the sidebar should render for the current
/// [state]. Pure function - easy to unit test.
///
/// [lastActivityByWorkspaceId] supplies the persisted recency fallback for the
/// Agent Activity sort.
List<WorkbenchSidebarRow> buildSidebarRows(
  WorkbenchState state, {
  Map<String, AgentStatusEntry> agentStatuses =
      const <String, AgentStatusEntry>{},
  Map<String, DateTime> lastActivityByWorkspaceId = const <String, DateTime>{},
  DateTime? now,
}) {
  return _WorkbenchSidebarRowBuilder(
    state,
    agentStatuses: agentStatuses,
    lastActivityByWorkspaceId: lastActivityByWorkspaceId,
    now: now ?? DateTime.now().toUtc(),
  ).build();
}

WorkbenchSidebarCollapseTargets visibleSidebarCollapseTargets(
  WorkbenchState state, {
  bool includeCollapsedProjectDescendants = false,
}) {
  final prefs = state.viewPrefs;
  final query = state.searchQuery.trim().toLowerCase();
  final filtersHideEmptyProjects =
      query.isNotEmpty ||
      prefs.selectedTagIds.isNotEmpty ||
      prefs.workspaceKindFilter != WorkspaceKindFilter.all ||
      prefs.showActiveWorkspacesOnly;
  final visibleProjects = state.projects
      .where((project) => _projectVisible(prefs, project))
      .toList(growable: false);
  final projectIds = <String>{};
  final workspaceIds = <String>{};
  final parentWorkspaceIds = <String>{};

  Iterable<Workspace> visibleWorkspacesFor(Project project) {
    return state
        .workspacesFor(project.id)
        .where(
          (workspace) => _workspaceVisible(
            prefs,
            query,
            project,
            workspace,
            state.tabsFor(workspace.id),
          ),
        );
  }

  void collectParentIds(Iterable<Workspace> workspaces) {
    final ids = <String>{for (final workspace in workspaces) workspace.id};
    for (final workspace in workspaces) {
      final parentId = workspace.parentWorkspaceId;
      if (parentId != null &&
          parentId != workspace.id &&
          ids.contains(parentId)) {
        parentWorkspaceIds.add(parentId);
      }
    }
  }

  switch (prefs.groupBy) {
    case WorkbenchGroupBy.project:
      for (final project in visibleProjects) {
        final workspaces = visibleWorkspacesFor(project)
            .toList(growable: false);
        if (filtersHideEmptyProjects && workspaces.isEmpty) {
          continue;
        }
        projectIds.add(project.id);
        if (includeCollapsedProjectDescendants ||
            !prefs.collapsedProjectIds.contains(project.id)) {
          workspaceIds.addAll(workspaces.map((workspace) => workspace.id));
          collectParentIds(workspaces);
        }
      }
    case WorkbenchGroupBy.none:
      final workspaces = <Workspace>[];
      for (final project in visibleProjects) {
        workspaces.addAll(visibleWorkspacesFor(project));
      }
      workspaceIds.addAll(workspaces.map((workspace) => workspace.id));
      collectParentIds(workspaces);
  }

  return WorkbenchSidebarCollapseTargets(
    projectIds: projectIds,
    workspaceIds: workspaceIds,
    parentWorkspaceIds: parentWorkspaceIds,
  );
}

bool _projectVisible(WorkbenchViewPrefs prefs, Project project) {
  if (prefs.selectedProjectIds.isEmpty) {
    return true;
  }
  return prefs.selectedProjectIds.contains(project.id);
}

bool _workspaceVisible(
  WorkbenchViewPrefs prefs,
  String query,
  Project project,
  Workspace workspace,
  Iterable<WorkspaceTabRecord> tabs,
) {
  if (!workspaceMatchesKindFilter(prefs, workspace)) {
    return false;
  }
  if (!workspaceMatchesTagFilter(prefs, workspace)) {
    return false;
  }
  if (!workspaceMatchesActiveFilter(prefs, tabs)) {
    return false;
  }
  if (query.isEmpty) {
    return true;
  }
  if (project.name.toLowerCase().contains(query)) {
    return true;
  }
  if (workspace.name.toLowerCase().contains(query)) {
    return true;
  }
  if (workspace.branch?.toLowerCase().contains(query) ?? false) {
    return true;
  }
  final source = workspace.sourceBranch;
  if (source != null && source.toLowerCase().contains(query)) {
    return true;
  }
  return false;
}

/// The workspace-id order of the rendered non-pinned rows.
List<String> workspaceOrderOfRows(List<WorkbenchSidebarRow> rows) {
  return <String>[
    for (final row in rows)
      if (row is WorkbenchWorkspaceRow && !row.isPinnedCopy) row.workspace.id,
  ];
}

/// Counts the workspaces currently visible in the sidebar for the header label
/// (`Workspaces N`). Honors filters and search but ignores group collapse.
int countVisibleWorkspaces(WorkbenchState state) {
  final prefs = state.viewPrefs;
  final query = state.searchQuery.trim().toLowerCase();
  var count = 0;
  for (final project in state.projects) {
    if (!_projectVisible(prefs, project)) {
      continue;
    }
    for (final workspace in state.workspacesFor(project.id)) {
      if (_workspaceVisible(
        prefs,
        query,
        project,
        workspace,
        state.tabsFor(workspace.id),
      )) {
        count++;
      }
    }
  }
  return count;
}
