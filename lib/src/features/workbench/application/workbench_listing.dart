import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_agent_activity_sort.dart';
import 'package:alera/src/features/workbench/application/workbench_listing_tree.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workbench_workspace_filters.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';

part 'workbench_sidebar_rows.dart';

/// Builds the flat list of rows the sidebar should render for the current
/// [state]. Pure function - easy to unit test.
///
/// [lastActivityByWorkspaceId] supplies the persisted recency fallback for the
/// Agent Activity sort; [previousWorkspaceOrder] is the workspace-id order of
/// the previous render, used to keep the active workspace pinned in place
/// while live statuses reshuffle its siblings.
List<WorkbenchSidebarRow> buildSidebarRows(
  WorkbenchState state, {
  Map<String, AgentStatusEntry> agentStatuses =
      const <String, AgentStatusEntry>{},
  Map<String, DateTime> lastActivityByWorkspaceId = const <String, DateTime>{},
  List<String> previousWorkspaceOrder = const <String>[],
  DateTime? now,
}) {
  final prefs = state.viewPrefs;
  final query = state.searchQuery.trim().toLowerCase();
  final clock = now ?? DateTime.now().toUtc();

  bool projectVisible(Project project) {
    // Positive selection: when no projects are selected we show everything;
    // otherwise we show only the explicitly selected ones.
    if (prefs.selectedProjectIds.isEmpty) {
      return true;
    }
    return prefs.selectedProjectIds.contains(project.id);
  }

  final attentionCache = <String, WorkspaceAttention>{};
  WorkspaceAttention attentionOf(Workspace workspace) {
    return attentionCache.putIfAbsent(
      workspace.id,
      () => workspaceAttention(
        tabs: state.tabsFor(workspace.id),
        agentStatuses: agentStatuses,
        now: clock,
      ),
    );
  }

  DateTime fallbackActivityOf(Workspace workspace) {
    return lastActivityByWorkspaceId[workspace.id] ?? workspace.updatedAt;
  }

  bool workspaceVisible(Project project, Workspace workspace) {
    if (!workspaceMatchesKindFilter(prefs, workspace)) {
      return false;
    }
    if (!workspaceMatchesTagFilter(prefs, workspace)) {
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

  // The flat view mixes several projects, so pinning each project's main
  // worktree only applies to the name sort there; grouped mode pins it for
  // name and recent. Agent Activity never pins - urgency owns the order.
  List<Workspace> sortWorkspaces(
    List<Workspace> workspaces, {
    required bool pinMainOnRecent,
  }) {
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
          if (pinMainOnRecent && a.isMain != b.isMain) {
            return a.isMain ? -1 : 1;
          }
          return b.updatedAt.compareTo(a.updatedAt);
        });
      case WorkbenchSortBy.activity:
        // Urgency outranks the main-worktree pin in this mode.
        sorted.sort(
          (a, b) => compareByAgentActivity(
            aAttention: attentionOf(a),
            aFallback: fallbackActivityOf(a),
            aName: a.name,
            bAttention: attentionOf(b),
            bFallback: fallbackActivityOf(b),
            bName: b.name,
          ),
        );
    }
    return stabilizeActiveEntry(
      sorted: sorted,
      idOf: (workspace) => workspace.id,
      previousOrder: previousWorkspaceOrder,
      activeId: prefs.workspaceSort == WorkbenchSortBy.activity
          ? state.activeWorkspaceId
          : null,
    );
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
      case WorkbenchSortBy.activity:
        // Rank each project by its most urgent / most recently active visible
        // workspace.
        final rank = <String, ({WorkspaceAttention attention, DateTime at})>{};
        for (final project in sorted) {
          var best = WorkspaceAttention.idle;
          var bestAt = project.updatedAt;
          for (final workspace in state.workspacesFor(project.id)) {
            if (!workspaceVisible(project, workspace)) {
              continue;
            }
            final attention = attentionOf(workspace);
            final at = attention.attentionAt ?? fallbackActivityOf(workspace);
            final better =
                attention.attentionClass.index < best.attentionClass.index ||
                (attention.attentionClass == best.attentionClass &&
                    at.isAfter(bestAt));
            if (better) {
              best = attention;
              bestAt = at;
            }
          }
          rank[project.id] = (attention: best, at: bestAt);
        }
        sorted.sort((a, b) {
          final ra = rank[a.id]!;
          final rb = rank[b.id]!;
          final byClass = ra.attention.attentionClass.index.compareTo(
            rb.attention.attentionClass.index,
          );
          if (byClass != 0) {
            return byClass;
          }
          final byTime = rb.at.compareTo(ra.at);
          if (byTime != 0) {
            return byTime;
          }
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    }
    return sorted;
  }

  void appendWorkspaceTreeRows(
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
      final indent = baseIndent + entry.depth;
      rows.add(
        WorkbenchWorkspaceRow(
          project: projectOf(entry.workspace),
          workspace: entry.workspace,
          showProjectChip: showProjectChip,
          indent: indent,
          expanded: prefs.expandedWorkspaceIds.contains(entry.workspace.id),
          visibleChildCount: entry.visibleChildCount,
          childrenCollapsed: entry.childrenCollapsed,
          isPinnedCopy: isPinnedCopy,
        ),
      );
    }
  }

  final rows = <WorkbenchSidebarRow>[];
  final visibleProjects = state.projects.where(projectVisible).toList();
  final filtersHideEmptyProjects =
      query.isNotEmpty ||
      prefs.selectedTagIds.isNotEmpty ||
      prefs.workspaceKindFilter != WorkspaceKindFilter.all;

  final pinnedRows = <WorkbenchSidebarRow>[];
  var pinnedWorkspaceCount = 0;
  switch (prefs.groupBy) {
    case WorkbenchGroupBy.project:
      for (final project in sortProjects(visibleProjects)) {
        final pinned = sortWorkspaces(
          state
              .workspacesFor(project.id)
              .where(
                (workspace) =>
                    workspace.isPinned && workspaceVisible(project, workspace),
              )
              .toList(),
          pinMainOnRecent: true,
        );
        pinnedWorkspaceCount += pinned.length;
        appendWorkspaceTreeRows(
          pinnedRows,
          workspaces: pinned,
          projectOf: (_) => project,
          baseIndent: 0,
          showProjectChip: true,
          isPinnedCopy: true,
          collapsedParentIds: const <String>{},
        );
      }
    case WorkbenchGroupBy.none:
      final projectByWorkspaceId = <String, Project>{};
      final pinned = <Workspace>[];
      for (final project in visibleProjects) {
        for (final workspace in state.workspacesFor(project.id)) {
          if (!workspace.isPinned || !workspaceVisible(project, workspace)) {
            continue;
          }
          projectByWorkspaceId[workspace.id] = project;
          pinned.add(workspace);
        }
      }
      pinnedWorkspaceCount = pinned.length;
      appendWorkspaceTreeRows(
        pinnedRows,
        workspaces: sortWorkspaces(pinned, pinMainOnRecent: false),
        projectOf: (workspace) => projectByWorkspaceId[workspace.id]!,
        baseIndent: 0,
        showProjectChip: true,
        isPinnedCopy: true,
        collapsedParentIds: const <String>{},
      );
  }
  if (pinnedRows.isNotEmpty) {
    rows.add(
      WorkbenchPinnedHeaderRow(
        workspaceCount: pinnedWorkspaceCount,
        collapsed: prefs.pinnedSectionCollapsed,
      ),
    );
    if (!prefs.pinnedSectionCollapsed) {
      rows.addAll(pinnedRows);
    }
  }

  switch (prefs.groupBy) {
    case WorkbenchGroupBy.project:
      final sortedProjects = sortProjects(visibleProjects);
      for (final project in sortedProjects) {
        final workspaces = sortWorkspaces(
          state
              .workspacesFor(project.id)
              .where((w) => workspaceVisible(project, w))
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
        appendWorkspaceTreeRows(
          rows,
          workspaces: workspaces,
          projectOf: (_) => project,
          baseIndent: 1,
          showProjectChip: false,
        );
      }
    case WorkbenchGroupBy.none:
      final projectByWorkspaceId = <String, Project>{};
      final workspaces = <Workspace>[];
      for (final project in visibleProjects) {
        for (final workspace in state.workspacesFor(project.id)) {
          if (!workspaceVisible(project, workspace)) {
            continue;
          }
          projectByWorkspaceId[workspace.id] = project;
          workspaces.add(workspace);
        }
      }
      // The flat list only gets an "All" header when a pinned section sits
      // above it - without pins there is nothing to separate it from.
      final hasPinnedSection = pinnedRows.isNotEmpty;
      if (hasPinnedSection) {
        rows.add(
          WorkbenchAllHeaderRow(
            workspaceCount: workspaces.length,
            collapsed: prefs.allSectionCollapsed,
          ),
        );
      }
      if (!hasPinnedSection || !prefs.allSectionCollapsed) {
        appendWorkspaceTreeRows(
          rows,
          workspaces: sortWorkspaces(workspaces, pinMainOnRecent: false),
          projectOf: (workspace) => projectByWorkspaceId[workspace.id]!,
          baseIndent: 0,
          showProjectChip: true,
        );
      }
  }

  return rows;
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
      prefs.workspaceKindFilter != WorkspaceKindFilter.all;
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
          (workspace) => _workspaceVisible(prefs, query, project, workspace),
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
        final workspaces = visibleWorkspacesFor(
          project,
        ).toList(growable: false);
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
) {
  if (!workspaceMatchesKindFilter(prefs, workspace)) {
    return false;
  }
  if (!workspaceMatchesTagFilter(prefs, workspace)) {
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

/// The workspace-id order of the rendered rows, used to remember the previous
/// ordering for [buildSidebarRows]'s active-row stabilization.
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
      if (_workspaceVisible(prefs, query, project, workspace)) {
        count++;
      }
    }
  }
  return count;
}
