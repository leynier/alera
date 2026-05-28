import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';

/// A row to render in the workbench sidebar. The list returned by
/// [buildSidebarRows] is flat and self-describing — callers iterate and render
/// each variant with the right widget.
sealed class WorkbenchSidebarRow {
  const WorkbenchSidebarRow();
}

class WorkbenchProjectHeaderRow extends WorkbenchSidebarRow {
  const WorkbenchProjectHeaderRow({
    required this.project,
    required this.workspaceCount,
    required this.collapsed,
  });

  final Project project;
  final int workspaceCount;
  final bool collapsed;
}

class WorkbenchWorkspaceRow extends WorkbenchSidebarRow {
  const WorkbenchWorkspaceRow({
    required this.project,
    required this.workspace,
    required this.showProjectChip,
    required this.indent,
    required this.expanded,
  });

  final Project project;
  final Workspace workspace;
  final bool showProjectChip;
  final bool expanded;

  /// How deeply the row should be indented from the left edge of the sidebar
  /// (in token-space units). `0` for top-level rows, `1` for workspaces inside
  /// a project group, etc.
  final int indent;
}

class SidebarAgentRunRow extends WorkbenchSidebarRow {
  const SidebarAgentRunRow({
    required this.workspace,
    required this.tab,
    required this.status,
    required this.indent,
  });

  final Workspace workspace;
  final WorkspaceTabRecord tab;
  final AgentStatusEntry status;
  final int indent;
}

/// Builds the flat list of rows the sidebar should render for the current
/// [state]. Pure function — easy to unit test.
List<WorkbenchSidebarRow> buildSidebarRows(
  WorkbenchState state, {
  Map<String, AgentStatusEntry> agentStatuses =
      const <String, AgentStatusEntry>{},
}) {
  final prefs = state.viewPrefs;
  final query = state.searchQuery.trim().toLowerCase();

  bool projectVisible(Project project) {
    // Positive selection: when no projects are selected we show everything;
    // otherwise we show only the explicitly selected ones.
    if (prefs.selectedProjectIds.isEmpty) {
      return true;
    }
    return prefs.selectedProjectIds.contains(project.id);
  }

  bool workspaceMatchesQuery(Project project, Workspace workspace) {
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

  List<Project> sortProjects(List<Project> projects) {
    final sorted = List<Project>.from(projects);
    switch (prefs.projectSort) {
      case WorkbenchSortBy.name:
        sorted.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case WorkbenchSortBy.recent:
        sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    return sorted;
  }

  List<Workspace> sortWorkspaces(List<Workspace> workspaces) {
    final sorted = List<Workspace>.from(workspaces);
    switch (prefs.workspaceSort) {
      case WorkbenchSortBy.name:
        sorted.sort((a, b) {
          // Keep the main worktree pinned at the top regardless of name.
          if (a.isMain != b.isMain) {
            return a.isMain ? -1 : 1;
          }
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      case WorkbenchSortBy.recent:
        sorted.sort((a, b) {
          if (a.isMain != b.isMain) {
            return a.isMain ? -1 : 1;
          }
          return b.updatedAt.compareTo(a.updatedAt);
        });
    }
    return sorted;
  }

  void appendSidebarAgentRunRows(
    List<WorkbenchSidebarRow> rows,
    Workspace workspace,
    int indent,
  ) {
    if (!prefs.expandedWorkspaceIds.contains(workspace.id)) {
      return;
    }
    final runs = visibleWorkspaceAgentRuns(
      tabs: state.tabsFor(workspace.id),
      agentStatuses: agentStatuses,
    );
    for (final run in runs) {
      rows.add(
        SidebarAgentRunRow(
          workspace: workspace,
          tab: run.tab,
          status: run.status,
          indent: indent,
        ),
      );
    }
  }

  final rows = <WorkbenchSidebarRow>[];
  final visibleProjects = state.projects.where(projectVisible).toList();

  switch (prefs.groupBy) {
    case WorkbenchGroupBy.project:
      final sortedProjects = sortProjects(visibleProjects);
      for (final project in sortedProjects) {
        final workspaces = sortWorkspaces(
          state
              .workspacesFor(project.id)
              .where((w) => workspaceMatchesQuery(project, w))
              .toList(),
        );
        if (query.isNotEmpty && workspaces.isEmpty) {
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
        for (final workspace in workspaces) {
          rows.add(
            WorkbenchWorkspaceRow(
              project: project,
              workspace: workspace,
              showProjectChip: false,
              indent: 1,
              expanded: prefs.expandedWorkspaceIds.contains(workspace.id),
            ),
          );
          appendSidebarAgentRunRows(rows, workspace, 2);
        }
      }
    case WorkbenchGroupBy.none:
      final entries = <({Project project, Workspace workspace})>[];
      for (final project in visibleProjects) {
        for (final workspace in state.workspacesFor(project.id)) {
          if (!workspaceMatchesQuery(project, workspace)) {
            continue;
          }
          entries.add((project: project, workspace: workspace));
        }
      }
      switch (prefs.workspaceSort) {
        case WorkbenchSortBy.name:
          entries.sort((a, b) {
            if (a.workspace.isMain != b.workspace.isMain) {
              return a.workspace.isMain ? -1 : 1;
            }
            return a.workspace.name.toLowerCase().compareTo(
              b.workspace.name.toLowerCase(),
            );
          });
        case WorkbenchSortBy.recent:
          entries.sort((a, b) {
            return b.workspace.updatedAt.compareTo(a.workspace.updatedAt);
          });
      }
      for (final entry in entries) {
        rows.add(
          WorkbenchWorkspaceRow(
            project: entry.project,
            workspace: entry.workspace,
            showProjectChip: true,
            indent: 0,
            expanded: prefs.expandedWorkspaceIds.contains(entry.workspace.id),
          ),
        );
        appendSidebarAgentRunRows(rows, entry.workspace, 1);
      }
  }

  return rows;
}

/// Counts the workspaces currently visible in the sidebar for the header label
/// (`Workspaces N`). Honors filters and search but ignores group collapse.
int countVisibleWorkspaces(WorkbenchState state) {
  final prefs = state.viewPrefs;
  final query = state.searchQuery.trim().toLowerCase();
  var count = 0;
  for (final project in state.projects) {
    if (prefs.selectedProjectIds.isNotEmpty &&
        !prefs.selectedProjectIds.contains(project.id)) {
      continue;
    }
    for (final workspace in state.workspacesFor(project.id)) {
      if (query.isEmpty) {
        count++;
        continue;
      }
      final projectMatches = project.name.toLowerCase().contains(query);
      final workspaceMatches =
          workspace.name.toLowerCase().contains(query) ||
          (workspace.branch?.toLowerCase().contains(query) ?? false) ||
          (workspace.sourceBranch?.toLowerCase().contains(query) ?? false);
      if (projectMatches || workspaceMatches) {
        count++;
      }
    }
  }
  return count;
}
