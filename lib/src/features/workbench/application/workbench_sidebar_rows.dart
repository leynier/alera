part of 'workbench_listing.dart';

/// A row to render in the workbench sidebar. The list returned by
/// [buildSidebarRows] is flat and self-describing.
sealed class WorkbenchSidebarRow {
  const WorkbenchSidebarRow();
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
}

class WorkbenchPinnedHeaderRow extends WorkbenchSidebarRow {
  const WorkbenchPinnedHeaderRow({
    required this.workspaceCount,
    required this.collapsed,
  });

  final int workspaceCount;
  final bool collapsed;
}

/// Header for the flat "All" section that follows the pinned section when the
/// sidebar is not grouped by project. It marks where the pinned copies end
/// and the full workspace list begins, and can collapse the whole list.
class WorkbenchAllHeaderRow extends WorkbenchSidebarRow {
  const WorkbenchAllHeaderRow({
    required this.workspaceCount,
    required this.collapsed,
  });

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
    this.visibleChildCount = 0,
    this.childrenCollapsed = false,
    this.isPinnedCopy = false,
  });

  final Project project;
  final Workspace workspace;
  final bool showProjectChip;
  final bool expanded;
  final int visibleChildCount;
  final bool childrenCollapsed;
  final bool isPinnedCopy;
  final int indent;

  bool get hasVisibleChildren => visibleChildCount > 0;
}
