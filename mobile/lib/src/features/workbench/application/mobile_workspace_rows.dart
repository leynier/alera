import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_agent_activity_sort.dart';
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

class MobileAllHeaderRow extends MobileWorkspaceRow {
  const MobileAllHeaderRow({required this.count, required this.collapsed});

  final int count;
  final bool collapsed;
}

class MobileWorkspaceEntryRow extends MobileWorkspaceRow {
  const MobileWorkspaceEntryRow({
    required this.entry,
    this.isPinnedCopy = false,
  });

  final WorkspaceTreeEntry entry;

  /// True for the flat copy rendered inside the pinned section.
  final bool isPinnedCopy;
}

class _PreparedWorkspaceListing {
  const _PreparedWorkspaceListing({
    required this.orderedWorkspaces,
    required this.directActivityByWorkspaceId,
  });

  final List<WorkspaceSummary> orderedWorkspaces;
  final Map<String, MobileAgentActivityRank?> directActivityByWorkspaceId;
}

List<MobileWorkspaceRow> buildMobileWorkspaceRows({
  required List<WorkspaceSummary> workspaces,
  required List<ProjectSummary> projects,
  required MobileViewPrefs prefs,
  Map<String, DateTime> activity = const <String, DateTime>{},
  List<AgentPresenceSummary> agentPresence = const <AgentPresenceSummary>[],
  Map<String, int> terminalTabCountByWorkspaceId = const <String, int>{},
  String searchQuery = '',
  DateTime? now,
}) {
  final projectById = <String, ProjectSummary>{
    for (final project in projects) project.id: project,
  };
  final listing = _prepareWorkspaceListing(
    workspaces: workspaces,
    projectById: projectById,
    prefs: prefs,
    activity: activity,
    agentPresence: agentPresence,
    terminalTabCountByWorkspaceId: terminalTabCountByWorkspaceId,
    searchQuery: searchQuery,
    now: now,
  );
  final visibleWorkspaces = listing.orderedWorkspaces;
  final pinned = <WorkspaceSummary>[
    for (final workspace in visibleWorkspaces)
      if (workspace.isPinned) workspace,
  ];
  final rows = <MobileWorkspaceRow>[];
  _appendPinnedSection(rows, pinned, prefs);

  final workspacesBelow = prefs.showPinnedWorkspacesBelow
      ? visibleWorkspaces
      : visibleWorkspaces
            .where((workspace) => !workspace.isPinned)
            .toList(growable: false);
  switch (prefs.groupBy) {
    case MobileWorkspaceGroupBy.project:
      _appendProjectSections(
        rows: rows,
        workspaces: workspacesBelow,
        projects: projects,
        projectById: projectById,
        prefs: prefs,
        directActivityByWorkspaceId: listing.directActivityByWorkspaceId,
      );
    case MobileWorkspaceGroupBy.none:
      _appendFlatSection(
        rows: rows,
        workspaces: workspacesBelow,
        hasPinnedSection: pinned.isNotEmpty,
        prefs: prefs,
      );
  }

  return rows;
}

_PreparedWorkspaceListing _prepareWorkspaceListing({
  required List<WorkspaceSummary> workspaces,
  required Map<String, ProjectSummary> projectById,
  required MobileViewPrefs prefs,
  required Map<String, DateTime> activity,
  required List<AgentPresenceSummary> agentPresence,
  required Map<String, int> terminalTabCountByWorkspaceId,
  required String searchQuery,
  required DateTime? now,
}) {
  final normalizedQuery = searchQuery.trim().toLowerCase();
  final clock = (now ?? DateTime.now()).toUtc();
  final workspacesWithAgentPresence = <String>{
    for (final status in agentPresence) status.workspaceId,
  };
  bool hasActivity(WorkspaceSummary workspace) {
    return (terminalTabCountByWorkspaceId[workspace.id] ?? 0) > 0 ||
        workspacesWithAgentPresence.contains(workspace.id);
  }

  final visibleWorkspaces = <WorkspaceSummary>[
    for (final workspace in workspaces)
      if (_matchesFilters(
            workspace,
            projectById[workspace.projectId],
            prefs,
            hasActivity: hasActivity(workspace),
          ) &&
          _matchesSearch(
            workspace,
            projectById[workspace.projectId],
            normalizedQuery,
          ))
        workspace,
  ];
  final directActivityByWorkspaceId = <String, MobileAgentActivityRank?>{
    for (final workspace in visibleWorkspaces)
      workspace.id: hasActivity(workspace)
          ? mobileAgentActivityRank(
              attention: mobileWorkspaceAttention(
                workspaceId: workspace.id,
                statuses: agentPresence,
                now: clock,
              ),
              fallback:
                  activity[workspace.id] ?? workspace.updatedAt ?? DateTime(0),
            )
          : null,
  };
  final subtreeActivityByWorkspaceId = aggregateMobileAgentActivityBySubtree(
    workspaces: visibleWorkspaces.map(
      (workspace) => (id: workspace.id, parentId: workspace.parentWorkspaceId),
    ),
    directActivityByWorkspaceId: directActivityByWorkspaceId,
  );
  visibleWorkspaces.sort(
    (left, right) =>
        _compareWorkspaces(left, right, prefs, subtreeActivityByWorkspaceId),
  );

  return _PreparedWorkspaceListing(
    orderedWorkspaces: visibleWorkspaces,
    directActivityByWorkspaceId: directActivityByWorkspaceId,
  );
}

void _appendPinnedSection(
  List<MobileWorkspaceRow> rows,
  List<WorkspaceSummary> pinned,
  MobileViewPrefs prefs,
) {
  if (pinned.isEmpty) {
    return;
  }
  rows.add(
    MobilePinnedHeaderRow(
      count: pinned.length,
      collapsed: prefs.pinnedSectionCollapsed,
    ),
  );
  if (prefs.pinnedSectionCollapsed) {
    return;
  }
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

void _appendProjectSections({
  required List<MobileWorkspaceRow> rows,
  required List<WorkspaceSummary> workspaces,
  required List<ProjectSummary> projects,
  required Map<String, ProjectSummary> projectById,
  required MobileViewPrefs prefs,
  required Map<String, MobileAgentActivityRank?> directActivityByWorkspaceId,
}) {
  final byProject = <String, List<WorkspaceSummary>>{};
  for (final workspace in workspaces) {
    byProject
        .putIfAbsent(workspace.projectId, () => <WorkspaceSummary>[])
        .add(workspace);
  }
  final orderedProjectIds =
      <String>[
        for (final project in projects)
          if (byProject.containsKey(project.id)) project.id,
        for (final projectId in byProject.keys)
          if (!projectById.containsKey(projectId)) projectId,
      ]..sort(
        (left, right) => _compareProjects(
          projectById[left],
          projectById[right],
          byProject[left] ?? const <WorkspaceSummary>[],
          byProject[right] ?? const <WorkspaceSummary>[],
          prefs,
          directActivityByWorkspaceId,
        ),
      );
  for (final projectId in orderedProjectIds) {
    final group = byProject[projectId]!;
    final collapsed = prefs.collapsedProjectIds.contains(projectId);
    rows.add(
      MobileProjectHeaderRow(
        projectId: projectId,
        projectName: projectById[projectId]?.name ?? projectId,
        count: group.length,
        collapsed: collapsed,
      ),
    );
    if (!collapsed) {
      _appendWorkspaceTreeRows(rows, group, prefs.collapsedParentWorkspaceIds);
    }
  }
}

void _appendFlatSection({
  required List<MobileWorkspaceRow> rows,
  required List<WorkspaceSummary> workspaces,
  required bool hasPinnedSection,
  required MobileViewPrefs prefs,
}) {
  // Without project grouping, "All" is only useful as a sibling of Pinned.
  // A lone All header just adds an extra collapse step.
  final showAllHeader = hasPinnedSection && workspaces.isNotEmpty;
  if (showAllHeader) {
    rows.add(
      MobileAllHeaderRow(
        count: workspaces.length,
        collapsed: prefs.allSectionCollapsed,
      ),
    );
    if (prefs.allSectionCollapsed) {
      return;
    }
  }
  _appendWorkspaceTreeRows(rows, workspaces, prefs.collapsedParentWorkspaceIds);
}

void _appendWorkspaceTreeRows(
  List<MobileWorkspaceRow> rows,
  List<WorkspaceSummary> workspaces,
  Set<String> collapsedParentWorkspaceIds,
) {
  for (final entry in buildWorkspaceTree(
    entries: workspaces,
    collapsedParentIds: collapsedParentWorkspaceIds,
  )) {
    rows.add(MobileWorkspaceEntryRow(entry: entry));
  }
}

bool _matchesFilters(
  WorkspaceSummary workspace,
  ProjectSummary? project,
  MobileViewPrefs prefs, {
  required bool hasActivity,
}) {
  if (prefs.selectedProjectIds.isNotEmpty &&
      !prefs.selectedProjectIds.contains(workspace.projectId)) {
    return false;
  }
  if (prefs.selectedTagIds.isNotEmpty &&
      !workspace.tagIds.any(prefs.selectedTagIds.contains)) {
    return false;
  }
  if (prefs.showActiveWorkspacesOnly && !hasActivity) {
    return false;
  }
  return switch (prefs.workspaceKindFilter) {
    MobileWorkspaceKindFilter.all => true,
    MobileWorkspaceKindFilter.defaultOnly => workspace.isMain,
    MobileWorkspaceKindFilter.nonDefaultOnly => !workspace.isMain,
  };
}

bool _matchesSearch(
  WorkspaceSummary workspace,
  ProjectSummary? project,
  String query,
) {
  if (query.isEmpty) {
    return true;
  }
  return <String?>[
    workspace.name,
    workspace.branch,
    workspace.path,
    project?.name,
    ...workspace.tagNames,
  ].whereType<String>().any((value) => value.toLowerCase().contains(query));
}

int _compareWorkspaces(
  WorkspaceSummary left,
  WorkspaceSummary right,
  MobileViewPrefs prefs,
  Map<String, MobileAgentActivityRank?> activityByWorkspaceId,
) {
  if (prefs.workspaceSort == MobileWorkbenchSortBy.name &&
      left.isMain != right.isMain) {
    return left.isMain ? -1 : 1;
  }
  if (prefs.workspaceSort == MobileWorkbenchSortBy.recent &&
      prefs.groupBy == MobileWorkspaceGroupBy.project &&
      left.isMain != right.isMain) {
    return left.isMain ? -1 : 1;
  }
  final order = switch (prefs.workspaceSort) {
    MobileWorkbenchSortBy.name => left.name.toLowerCase().compareTo(
      right.name.toLowerCase(),
    ),
    MobileWorkbenchSortBy.recent => _compareDates(
      right.updatedAt,
      left.updatedAt,
    ),
    MobileWorkbenchSortBy.activity => compareMobileAgentActivity(
      leftActivity: activityByWorkspaceId[left.id],
      leftName: left.name,
      rightActivity: activityByWorkspaceId[right.id],
      rightName: right.name,
    ),
  };
  return order != 0 ? order : left.name.compareTo(right.name);
}

int _compareProjects(
  ProjectSummary? left,
  ProjectSummary? right,
  List<WorkspaceSummary> leftWorkspaces,
  List<WorkspaceSummary> rightWorkspaces,
  MobileViewPrefs prefs,
  Map<String, MobileAgentActivityRank?> activityByWorkspaceId,
) {
  final order = switch (prefs.projectSort) {
    MobileWorkbenchSortBy.name => (left?.name ?? '').toLowerCase().compareTo(
      (right?.name ?? '').toLowerCase(),
    ),
    MobileWorkbenchSortBy.recent => _compareDates(
      right?.updatedAt,
      left?.updatedAt,
    ),
    MobileWorkbenchSortBy.activity => _compareProjectActivity(
      left,
      leftWorkspaces,
      right,
      rightWorkspaces,
      activityByWorkspaceId,
    ),
  };
  return order != 0 ? order : (left?.name ?? '').compareTo(right?.name ?? '');
}

int _compareProjectActivity(
  ProjectSummary? left,
  List<WorkspaceSummary> leftWorkspaces,
  ProjectSummary? right,
  List<WorkspaceSummary> rightWorkspaces,
  Map<String, MobileAgentActivityRank?> activityByWorkspaceId,
) {
  final leftRank = _projectActivityRank(leftWorkspaces, activityByWorkspaceId);
  final rightRank = _projectActivityRank(
    rightWorkspaces,
    activityByWorkspaceId,
  );
  return compareMobileAgentActivity(
    leftActivity: leftRank,
    leftName: left?.name ?? '',
    rightActivity: rightRank,
    rightName: right?.name ?? '',
  );
}

MobileAgentActivityRank? _projectActivityRank(
  List<WorkspaceSummary> workspaces,
  Map<String, MobileAgentActivityRank?> activityByWorkspaceId,
) {
  MobileAgentActivityRank? best;
  for (final workspace in workspaces) {
    best = bestMobileAgentActivityRank(
      best,
      activityByWorkspaceId[workspace.id],
    );
  }
  return best;
}

int _compareDates(DateTime? left, DateTime? right) {
  if (left == null && right == null) return 0;
  if (left == null) return 1;
  if (right == null) return -1;
  return left.compareTo(right);
}
