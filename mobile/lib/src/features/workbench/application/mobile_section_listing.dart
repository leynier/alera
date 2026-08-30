part of 'mobile_workspace_rows.dart';

class MobileCustomSectionHeaderRow extends MobileWorkspaceRow {
  const MobileCustomSectionHeaderRow({
    required this.section,
    required this.count,
    required this.collapsed,
  });
  final WorkspaceSectionSummary? section;
  final int count;
  final bool collapsed;
}

void _appendCustomSections({
  required List<MobileWorkspaceRow> rows,
  required List<WorkspaceSummary> workspaces,
  required List<WorkspaceSectionSummary> sections,
  required MobileViewPrefs prefs,
  required Map<String, MobileAgentActivityRank?> directActivityByWorkspaceId,
}) {
  final knownIds = sections.map((section) => section.id).toSet();
  final members = <String?, List<WorkspaceSummary>>{};
  for (final workspace in workspaces) {
    final id = knownIds.contains(workspace.sectionId)
        ? workspace.sectionId
        : null;
    members.putIfAbsent(id, () => []).add(workspace);
  }
  final ordered = sections
      .where((section) => members.containsKey(section.id))
      .toList();
  final ranks = <String, MobileAgentActivityRank?>{};
  for (final section in ordered) {
    MobileAgentActivityRank? rank;
    for (final workspace in members[section.id]!) {
      rank = bestMobileAgentActivityRank(
        rank,
        directActivityByWorkspaceId[workspace.id],
      );
    }
    ranks[section.id] = rank;
  }
  ordered.sort((a, b) {
    final order = switch (prefs.sectionSort) {
      MobileWorkbenchSortBy.name => a.name.toLowerCase().compareTo(
        b.name.toLowerCase(),
      ),
      MobileWorkbenchSortBy.recent => b.updatedAt.compareTo(a.updatedAt),
      MobileWorkbenchSortBy.activity => compareMobileAgentActivity(
        leftActivity: ranks[a.id],
        leftName: a.name,
        rightActivity: ranks[b.id],
        rightName: b.name,
      ),
    };
    return order != 0 ? order : a.id.compareTo(b.id);
  });
  for (final section in <WorkspaceSectionSummary?>[
    ...ordered,
    if (members.containsKey(null)) null,
  ]) {
    final group = members[section?.id]!;
    // Parent activity must not rank siblings in a different section.
    final activity = aggregateMobileAgentActivityBySubtree(
      workspaces: group.map(
        (workspace) =>
            (id: workspace.id, parentId: workspace.parentWorkspaceId),
      ),
      directActivityByWorkspaceId: directActivityByWorkspaceId,
    );
    group.sort((a, b) => _compareWorkspaces(a, b, prefs, activity));
    final collapsed = section == null
        ? prefs.othersSectionCollapsed
        : prefs.collapsedSectionIds.contains(section.id);
    rows.add(
      MobileCustomSectionHeaderRow(
        section: section,
        count: group.length,
        collapsed: collapsed,
      ),
    );
    if (!collapsed) {
      _appendWorkspaceTreeRows(rows, group, prefs.collapsedParentWorkspaceIds);
    }
  }
}
