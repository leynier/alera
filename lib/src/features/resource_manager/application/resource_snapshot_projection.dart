import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/resource_manager/domain/resource_snapshot.dart';
import 'package:alera/src/features/resource_manager/domain/resource_tree.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';

/// Join the host's flat session list with the app's workspace tree.
///
/// The host knows pids and workspace/tab ids; only the app knows project and
/// workspace names, which tabs still exist, and which workspaces live on
/// another machine. Keeping this a pure function is deliberate: every ordering
/// and orphan rule below is covered by unit tests rather than by driving a
/// widget.
ResourceTree buildResourceTree({
  required ResourceSnapshot snapshot,
  required List<Project> projects,
  required List<Workspace> workspaces,
  required List<WorkspaceTabRecord> tabs,
  ResourceSortColumn sortColumn = ResourceSortColumn.memory,
}) {
  final workspacesById = <String, Workspace>{
    for (final workspace in workspaces) workspace.id: workspace,
  };
  final projectsById = <String, Project>{
    for (final project in projects) project.id: project,
  };
  final tabsBySessionId = <String, WorkspaceTabRecord>{
    for (final tab in tabs)
      if (tab.kind == WorkspaceTabKind.terminal) tab.terminalSessionId: tab,
  };

  final sessionsByWorkspace = <String, List<ResourceSessionRow>>{};
  final orphans = <ResourceSessionRow>[];
  for (final session in snapshot.sessions) {
    final tab = tabsBySessionId[session.sessionId];
    final workspace = workspacesById[session.workspaceId];
    final remote = workspace != null && workspace.hostId != 'local';
    final row = ResourceSessionRow(
      sessionId: session.sessionId,
      label: tab?.title.trim().isNotEmpty ?? false
          ? tab!.title.trim()
          : session.sessionId,
      tabId: session.tabId,
      running: session.running,
      // A session is orphaned when no terminal tab claims it. The workspace
      // being gone is not enough on its own: the host may simply be ahead of
      // an app that has not synced yet.
      orphan: tab == null,
      cpuPercent: remote || !session.measured ? null : session.cpuPercent,
      memoryBytes: remote || !session.measured ? null : session.memoryBytes,
      processCount: session.processCount,
      history: session.history,
    );
    if (row.orphan) {
      orphans.add(row);
      continue;
    }
    sessionsByWorkspace
        .putIfAbsent(session.workspaceId, () => <ResourceSessionRow>[])
        .add(row);
  }

  final workspacesByProject = <String, List<ResourceWorkspaceRow>>{};
  for (final entry in sessionsByWorkspace.entries) {
    final workspace = workspacesById[entry.key];
    if (workspace == null) {
      // The app has a tab for these sessions but no workspace, which only
      // happens mid-sync. Dropping them beats inventing a group.
      continue;
    }
    final sessions = entry.value..sort(_sessionComparator(sortColumn));
    final row = ResourceWorkspaceRow(
      workspaceId: workspace.id,
      name: workspace.name,
      projectId: workspace.projectId,
      remote: workspace.hostId != 'local',
      sessions: List<ResourceSessionRow>.unmodifiable(sessions),
    );
    workspacesByProject
        .putIfAbsent(workspace.projectId, () => <ResourceWorkspaceRow>[])
        .add(row);
  }

  final groups = <ResourceProjectGroup>[];
  for (final entry in workspacesByProject.entries) {
    final project = projectsById[entry.key];
    final rows = entry.value..sort(_workspaceComparator(sortColumn));
    groups.add(
      ResourceProjectGroup(
        projectId: entry.key,
        name: project?.name ?? entry.key,
        workspaces: List<ResourceWorkspaceRow>.unmodifiable(rows),
      ),
    );
  }
  groups.sort(_projectComparator(sortColumn));
  orphans.sort(_sessionComparator(sortColumn));

  return ResourceTree(
    projects: List<ResourceProjectGroup>.unmodifiable(groups),
    orphanSessions: List<ResourceSessionRow>.unmodifiable(orphans),
  );
}

int Function(ResourceSessionRow, ResourceSessionRow) _sessionComparator(
  ResourceSortColumn column,
) {
  return (left, right) => switch (column) {
    ResourceSortColumn.name => _byName(left.label, right.label),
    ResourceSortColumn.cpu => _thenByName(
      compareMetricDescending(left.cpuPercent, right.cpuPercent),
      left.label,
      right.label,
    ),
    ResourceSortColumn.memory => _thenByName(
      compareMetricDescending(left.memoryBytes, right.memoryBytes),
      left.label,
      right.label,
    ),
  };
}

int Function(ResourceWorkspaceRow, ResourceWorkspaceRow) _workspaceComparator(
  ResourceSortColumn column,
) {
  return (left, right) => switch (column) {
    ResourceSortColumn.name => _byName(left.name, right.name),
    ResourceSortColumn.cpu => _thenByName(
      compareMetricDescending(left.cpuPercent, right.cpuPercent),
      left.name,
      right.name,
    ),
    ResourceSortColumn.memory => _thenByName(
      compareMetricDescending(left.memoryBytes, right.memoryBytes),
      left.name,
      right.name,
    ),
  };
}

int Function(ResourceProjectGroup, ResourceProjectGroup) _projectComparator(
  ResourceSortColumn column,
) {
  return (left, right) => switch (column) {
    ResourceSortColumn.name => _byName(left.name, right.name),
    ResourceSortColumn.cpu => _thenByName(
      compareMetricDescending(left.cpuPercent, right.cpuPercent),
      left.name,
      right.name,
    ),
    ResourceSortColumn.memory => _thenByName(
      compareMetricDescending(left.memoryBytes, right.memoryBytes),
      left.name,
      right.name,
    ),
  };
}

int _byName(String left, String right) =>
    left.toLowerCase().compareTo(right.toLowerCase());

/// Name is the tiebreaker for every metric sort, so rows keep a stable order
/// instead of shuffling between polls when two of them read the same.
int _thenByName(int comparison, String left, String right) =>
    comparison != 0 ? comparison : _byName(left, right);
