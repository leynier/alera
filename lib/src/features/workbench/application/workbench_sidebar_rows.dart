part of 'workbench_listing.dart';

/// A row to render in the workbench sidebar. The list returned by
/// [buildSidebarRows] is flat and self-describing.
sealed class WorkbenchSidebarRow {
  const WorkbenchSidebarRow();

  /// Stable identity for the list element that renders this row.
  ///
  /// Rows reorder live as agents change state, so without a key the list
  /// re-matches elements by index and row content slides between them, which
  /// restarts in-flight animations and scrambles per-element state.
  String get key;
}

class WorkbenchSidebarCollapseTargets {
  const WorkbenchSidebarCollapseTargets({
    required this.projectIds,
    required this.workspaceIds,
    required this.parentWorkspaceIds,
  });

  final Set<String> projectIds;
  final Set<String> workspaceIds;
  final Set<String> parentWorkspaceIds;

  bool get isEmpty =>
      projectIds.isEmpty && workspaceIds.isEmpty && parentWorkspaceIds.isEmpty;

  bool isCollapsed(WorkbenchViewPrefs prefs) {
    final projectsCollapsed = projectIds.every(
      prefs.collapsedProjectIds.contains,
    );
    final childTreesCollapsed = parentWorkspaceIds.every(
      prefs.collapsedParentWorkspaceIds.contains,
    );
    final agentsCollapsed = !workspaceIds.any(
      prefs.expandedWorkspaceIds.contains,
    );
    return projectsCollapsed && childTreesCollapsed && agentsCollapsed;
  }
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

  @override
  String get key => 'project:${project.id}';
}

class WorkbenchPinnedHeaderRow extends WorkbenchSidebarRow {
  const WorkbenchPinnedHeaderRow({
    required this.workspaceCount,
    required this.collapsed,
  });

  final int workspaceCount;
  final bool collapsed;

  @override
  String get key => 'pinned-header';
}

/// Header for the flat "All" section that follows the pinned section when the
/// sidebar is not grouped by project. It marks where the pinned copies end
/// and the regular workspace list begins, and can collapse the whole list.
class WorkbenchAllHeaderRow extends WorkbenchSidebarRow {
  const WorkbenchAllHeaderRow({
    required this.workspaceCount,
    required this.collapsed,
  });

  final int workspaceCount;
  final bool collapsed;

  @override
  String get key => 'all-header';
}

class WorkbenchWorkspaceRow extends WorkbenchSidebarRow {
  const WorkbenchWorkspaceRow({
    required this.project,
    required this.workspace,
    required this.showProjectChip,
    required this.indent,
    required this.expanded,
    this.agentRuns = const <WorkspaceAgentRun>[],
    this.agentRunGroups = const <WorkspaceAgentRunGroup>[],
    this.hasTerminalTabs = false,
    this.visibleChildCount = 0,
    this.childrenCollapsed = false,
    this.isPinnedCopy = false,
  });

  /// Computed here rather than per rebuild in the widget: the row build
  /// already walks this workspace's tabs and statuses.
  final List<WorkspaceAgentRun> agentRuns;
  final List<WorkspaceAgentRunGroup> agentRunGroups;
  final bool hasTerminalTabs;

  AgentStatusEntry? get aggregateStatus =>
      mostUrgentWorkspaceAgentRun(agentRuns)?.status;

  final Project project;
  final Workspace workspace;
  final bool showProjectChip;
  final bool expanded;
  final int visibleChildCount;
  final bool childrenCollapsed;
  final bool isPinnedCopy;
  final int indent;

  // A pinned workspace may also appear in the list below, so the section has
  // to be part of the key or the two copies would share one element.
  @override
  String get key =>
      'workspace:${isPinnedCopy ? 'pinned' : 'all'}:${workspace.id}';

  bool get hasVisibleChildren => visibleChildCount > 0;
}
