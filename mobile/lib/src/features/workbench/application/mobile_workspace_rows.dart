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

  /// True for the flat duplicate rendered inside the pinned section; the same
  /// workspace still appears in its tree position below.
  final bool isPinnedCopy;
}

List<MobileWorkspaceRow> buildMobileWorkspaceRows({
  required List<WorkspaceSummary> workspaces,
  required List<ProjectSummary> projects,
  required MobileViewPrefs prefs,
  Map<String, DateTime> activity = const <String, DateTime>{},
  List<AgentPresenceSummary> agentPresence = const <AgentPresenceSummary>[],
  String searchQuery = '',
  DateTime? now,
}) {
  final rows = <MobileWorkspaceRow>[];
  final normalizedQuery = searchQuery.trim().toLowerCase();
  final projectById = <String, ProjectSummary>{
    for (final project in projects) project.id: project,
  };
  final clock = (now ?? DateTime.now()).toUtc();
  final attention = <String, MobileWorkspaceAttention>{};
  MobileWorkspaceAttention attentionOf(WorkspaceSummary workspace) {
    return attention.putIfAbsent(
      workspace.id,
      () => mobileWorkspaceAttention(
        workspaceId: workspace.id,
        statuses: agentPresence,
        now: clock,
      ),
    );
  }

  final visibleWorkspaces =
      <WorkspaceSummary>[
        for (final workspace in workspaces)
          if (_matchesFilters(
                workspace,
                projectById[workspace.projectId],
                prefs,
              ) &&
              _matchesSearch(
                workspace,
                projectById[workspace.projectId],
                normalizedQuery,
              ))
            workspace,
      ]..sort(
        (left, right) =>
            _compareWorkspaces(left, right, prefs, activity, attentionOf),
      );

  final pinned = <WorkspaceSummary>[
    for (final workspace in visibleWorkspaces)
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
    for (final workspace in visibleWorkspaces) {
      byProject
          .putIfAbsent(workspace.projectId, () => <WorkspaceSummary>[])
          .add(workspace);
    }
    final orderedProjectIds =
        <String>[
          for (final project in projects)
            if (byProject.containsKey(project.id)) project.id,
          for (final projectId in byProject.keys)
            if (!projectNames.containsKey(projectId)) projectId,
        ]..sort(
          (left, right) => _compareProjects(
            projectById[left],
            projectById[right],
            byProject[left] ?? const <WorkspaceSummary>[],
            byProject[right] ?? const <WorkspaceSummary>[],
            prefs,
            activity,
            attentionOf,
          ),
        );
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
    rows.add(
      MobileAllHeaderRow(
        count: visibleWorkspaces.length,
        collapsed: prefs.allSectionCollapsed,
      ),
    );
    if (prefs.allSectionCollapsed) {
      return rows;
    }
    for (final entry in buildWorkspaceTree(
      entries: visibleWorkspaces,
      collapsedParentIds: prefs.collapsedParentWorkspaceIds,
    )) {
      rows.add(MobileWorkspaceEntryRow(entry: entry));
    }
  }

  return rows;
}

bool _matchesFilters(
  WorkspaceSummary workspace,
  ProjectSummary? project,
  MobileViewPrefs prefs,
) {
  if (prefs.selectedProjectIds.isNotEmpty &&
      !prefs.selectedProjectIds.contains(workspace.projectId)) {
    return false;
  }
  if (prefs.selectedTagIds.isNotEmpty &&
      !workspace.tagIds.any(prefs.selectedTagIds.contains)) {
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
  Map<String, DateTime> activity,
  MobileWorkspaceAttention Function(WorkspaceSummary) attentionOf,
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
      leftAttention: attentionOf(left),
      leftFallback: activity[left.id] ?? left.updatedAt ?? DateTime(0),
      leftName: left.name,
      rightAttention: attentionOf(right),
      rightFallback: activity[right.id] ?? right.updatedAt ?? DateTime(0),
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
  Map<String, DateTime> activity,
  MobileWorkspaceAttention Function(WorkspaceSummary) attentionOf,
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
      activity,
      attentionOf,
    ),
  };
  return order != 0 ? order : (left?.name ?? '').compareTo(right?.name ?? '');
}

int _compareProjectActivity(
  ProjectSummary? left,
  List<WorkspaceSummary> leftWorkspaces,
  ProjectSummary? right,
  List<WorkspaceSummary> rightWorkspaces,
  Map<String, DateTime> activity,
  MobileWorkspaceAttention Function(WorkspaceSummary) attentionOf,
) {
  final leftRank = _projectActivityRank(
    left,
    leftWorkspaces,
    activity,
    attentionOf,
  );
  final rightRank = _projectActivityRank(
    right,
    rightWorkspaces,
    activity,
    attentionOf,
  );
  final byClass = leftRank.attention.attentionClass.index.compareTo(
    rightRank.attention.attentionClass.index,
  );
  if (byClass != 0) return byClass;
  return rightRank.at.compareTo(leftRank.at);
}

({MobileWorkspaceAttention attention, DateTime at}) _projectActivityRank(
  ProjectSummary? project,
  List<WorkspaceSummary> workspaces,
  Map<String, DateTime> activity,
  MobileWorkspaceAttention Function(WorkspaceSummary) attentionOf,
) {
  var best = MobileWorkspaceAttention.idle;
  var bestAt = project?.updatedAt ?? DateTime(0);
  for (final workspace in workspaces) {
    final candidate = attentionOf(workspace);
    final candidateAt =
        candidate.at ??
        activity[workspace.id] ??
        workspace.updatedAt ??
        DateTime(0);
    if (candidate.attentionClass.index < best.attentionClass.index ||
        (candidate.attentionClass == best.attentionClass &&
            candidateAt.isAfter(bestAt))) {
      best = candidate;
      bestAt = candidateAt;
    }
  }
  return (attention: best, at: bestAt);
}

int _compareDates(DateTime? left, DateTime? right) {
  if (left == null && right == null) return 0;
  if (left == null) return 1;
  if (right == null) return -1;
  return left.compareTo(right);
}
