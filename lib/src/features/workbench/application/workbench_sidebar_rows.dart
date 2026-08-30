part of 'workbench_listing.dart';

/// A row to render in the workbench sidebar. The list returned by
/// [buildSidebarRows] is flat and self-describing.
sealed class const WorkbenchSidebarRow() {
  /// Stable identity for the list element that renders this row.
  ///
  /// Rows reorder live as agents change state, so without a key the list
  /// re-matches elements by index and row content slides between them, which
  /// restarts in-flight animations and scrambles per-element state.
  String get key;
}

class const WorkbenchSidebarCollapseTargets({
  final Set<String> sectionIds = const {},
  final bool hasOthers = false,
  required final Set<String> projectIds,
  required final Set<String> workspaceIds,
  required final Set<String> parentWorkspaceIds,
}) {
  bool get isEmpty =>
      sectionIds.isEmpty &&
      !hasOthers &&
      projectIds.isEmpty &&
      workspaceIds.isEmpty &&
      parentWorkspaceIds.isEmpty;

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
    return sectionIds.every(prefs.collapsedSectionIds.contains) &&
        (!hasOthers || prefs.othersSectionCollapsed) &&
        projectsCollapsed &&
        childTreesCollapsed &&
        agentsCollapsed;
  }
}

class const WorkbenchProjectHeaderRow({
  required final Project project,
  required final int workspaceCount,
  required final bool collapsed,
}) extends WorkbenchSidebarRow {
  @override
  String get key => 'project:${project.id}';
}

class const WorkbenchPinnedHeaderRow({
  required final int workspaceCount,
  required final bool collapsed,
}) extends WorkbenchSidebarRow {
  @override
  String get key => 'pinned-header';
}

/// Header for the flat "All" section that follows the pinned section when the
/// sidebar is not grouped by project. It marks where the pinned copies end
/// and the regular workspace list begins, and can collapse the whole list.
class const WorkbenchAllHeaderRow({
  required final int workspaceCount,
  required final bool collapsed,
}) extends WorkbenchSidebarRow {
  @override
  String get key => 'all-header';
}

class const WorkbenchWorkspaceRow({
  required final Project project,
  required final Workspace workspace,
  required final bool showProjectChip,
  required final int indent,
  required final bool expanded,
  this.agentRuns = const <WorkspaceAgentRun>[],
  final List<WorkspaceAgentRunGroup> agentRunGroups =
      const <WorkspaceAgentRunGroup>[],
  final bool hasTerminalTabs = false,
  final int visibleChildCount = 0,
  final bool childrenCollapsed = false,
  final bool isPinnedCopy = false,
}) extends WorkbenchSidebarRow {
  /// Computed here rather than per rebuild in the widget: the row build
  /// already walks this workspace's tabs and statuses.
  final List<WorkspaceAgentRun> agentRuns;

  AgentStatusEntry? get aggregateStatus =>
      mostUrgentWorkspaceAgentRun(agentRuns)?.status;

  // A pinned workspace may also appear in the list below, so the section has
  // to be part of the key or the two copies would share one element.
  @override
  String get key =>
      'workspace:${isPinnedCopy ? 'pinned' : 'all'}:${workspace.id}';

  bool get hasVisibleChildren => visibleChildCount > 0;
}

class WorkbenchSectionHeaderRow extends WorkbenchSidebarRow {
  const WorkbenchSectionHeaderRow({
    required this.section,
    required this.workspaceCount,
    required this.collapsed,
  });
  final WorkspaceSection? section;
  final int workspaceCount;
  final bool collapsed;
  String get label => section?.name ?? 'Others';
  @override
  String get key =>
      section == null ? 'others-header' : 'section:${section!.id}';
}
