part of 'workbench_listing.dart';

List<Workspace> _sortSidebarWorkspaces(
  List<Workspace> workspaces, {
  required WorkbenchSortBy sortBy,
  required bool pinMainOnRecent,
  required AgentActivityRank? Function(Workspace) activityOf,
}) {
  final sorted = List<Workspace>.from(workspaces);
  switch (sortBy) {
    case WorkbenchSortBy.name:
      sorted.sort((a, b) {
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
      final subtreeActivity = aggregateAgentActivityBySubtree(
        workspaces: sorted.map(
          (workspace) =>
              (id: workspace.id, parentId: workspace.parentWorkspaceId),
        ),
        directActivityByWorkspaceId: <String, AgentActivityRank?>{
          for (final workspace in sorted) workspace.id: activityOf(workspace),
        },
      );
      sorted.sort(
        (a, b) => compareByAgentActivity(
          aActivity: subtreeActivity[a.id],
          aName: a.name,
          bActivity: subtreeActivity[b.id],
          bName: b.name,
        ),
      );
  }
  return sorted;
}

List<Project> _sortSidebarProjects(
  List<Project> projects, {
  required WorkbenchSortBy sortBy,
  required Iterable<Workspace> Function(String projectId) workspacesFor,
  required bool Function(Project, Workspace) workspaceVisible,
  required AgentActivityRank? Function(Workspace) activityOf,
}) {
  final sorted = List<Project>.from(projects);
  switch (sortBy) {
    case WorkbenchSortBy.name:
      sorted.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    case WorkbenchSortBy.recent:
      sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    case WorkbenchSortBy.activity:
      final rank = <String, AgentActivityRank?>{};
      for (final project in sorted) {
        AgentActivityRank? best;
        for (final workspace in workspacesFor(project.id)) {
          if (!workspaceVisible(project, workspace)) {
            continue;
          }
          best = bestAgentActivityRank(best, activityOf(workspace));
        }
        rank[project.id] = best;
      }
      sorted.sort(
        (a, b) => compareByAgentActivity(
          aActivity: rank[a.id],
          aName: a.name,
          bActivity: rank[b.id],
          bName: b.name,
        ),
      );
  }
  return sorted;
}
