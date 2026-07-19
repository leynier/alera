import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_listing_tree.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';

/// Flattened list model for the mobile workspace list, mirroring the desktop
/// sidebar sections: an optional pinned section on top, then either project
/// groups or one flat tree.
sealed class MobileWorkspaceRow {
  const MobileWorkspaceRow();
}

class MobilePinnedHeaderRow extends MobileWorkspaceRow {
  const MobilePinnedHeaderRow({required this.count, required this.collapsed});

  final int count;
  final bool collapsed;
}

class MobileProjectHeaderRow extends MobileWorkspaceRow {
  const MobileProjectHeaderRow({
    required this.projectId,
    required this.projectName,
    required this.count,
    required this.collapsed,
  });

  final String projectId;
  final String projectName;
  final int count;
  final bool collapsed;
}

class MobileWorkspaceEntryRow extends MobileWorkspaceRow {
  const MobileWorkspaceEntryRow({
    required this.entry,
    this.isPinnedCopy = false,
  });

  final WorkspaceTreeEntry entry;

  /// True for the flat duplicate rendered inside the pinned section; the same
  /// workspace still appears in its tree position below.
  final bool isPinnedCopy;
}

List<MobileWorkspaceRow> buildMobileWorkspaceRows({
  required List<WorkspaceSummary> workspaces,
  required List<ProjectSummary> projects,
  required MobileViewPrefs prefs,
}) {
  final rows = <MobileWorkspaceRow>[];

  final pinned = <WorkspaceSummary>[
    for (final workspace in workspaces)
      if (workspace.isPinned) workspace,
  ];
  if (pinned.isNotEmpty) {
    rows.add(
      MobilePinnedHeaderRow(
        count: pinned.length,
        collapsed: prefs.pinnedSectionCollapsed,
      ),
    );
    if (!prefs.pinnedSectionCollapsed) {
      for (final workspace in pinned) {
        rows.add(
          MobileWorkspaceEntryRow(
            entry: WorkspaceTreeEntry(
              workspace: workspace,
              depth: 0,
              visibleChildCount: 0,
              childrenCollapsed: false,
            ),
            isPinnedCopy: true,
          ),
        );
      }
    }
  }

  if (prefs.groupBy == MobileWorkspaceGroupBy.project) {
    final projectNames = <String, String>{
      for (final project in projects) project.id: project.name,
    };
    final byProject = <String, List<WorkspaceSummary>>{};
    for (final workspace in workspaces) {
      byProject
          .putIfAbsent(workspace.projectId, () => <WorkspaceSummary>[])
          .add(workspace);
    }
    final orderedProjectIds = <String>[
      for (final project in projects)
        if (byProject.containsKey(project.id)) project.id,
      for (final projectId in byProject.keys)
        if (!projectNames.containsKey(projectId)) projectId,
    ];
    for (final projectId in orderedProjectIds) {
      final group = byProject[projectId]!;
      final collapsed = prefs.collapsedProjectIds.contains(projectId);
      rows.add(
        MobileProjectHeaderRow(
          projectId: projectId,
          projectName: projectNames[projectId] ?? projectId,
          count: group.length,
          collapsed: collapsed,
        ),
      );
      if (collapsed) {
        continue;
      }
      for (final entry in buildWorkspaceTree(
        entries: group,
        collapsedParentIds: prefs.collapsedParentWorkspaceIds,
      )) {
        rows.add(MobileWorkspaceEntryRow(entry: entry));
      }
    }
  } else {
    for (final entry in buildWorkspaceTree(
      entries: workspaces,
      collapsedParentIds: prefs.collapsedParentWorkspaceIds,
    )) {
      rows.add(MobileWorkspaceEntryRow(entry: entry));
    }
  }

  return rows;
}
