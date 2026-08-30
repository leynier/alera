part of 'workbench_listing.dart';

extension _SectionListing on _WorkbenchSidebarRowBuilder {
  void _appendSectionGroups(
    List<WorkbenchSidebarRow> rows,
    List<Project> projects,
  ) {
    final projectById = {for (final project in projects) project.id: project};
    final sectionsById = {
      for (final section in state.sections) section.id: section,
    };
    final members = <String?, List<Workspace>>{};
    for (final project in projects) {
      for (final workspace in state.workspacesFor(project.id)) {
        if (!_isWorkspaceVisibleBelow(project, workspace)) continue;
        final id = sectionsById.containsKey(workspace.sectionId)
            ? workspace.sectionId
            : null;
        members.putIfAbsent(id, () => []).add(workspace);
      }
    }
    final sections = state.sections
        .where((section) => members.containsKey(section.id))
        .toList();
    final ranks = <String, AgentActivityRank?>{};
    if (prefs.sectionSort == WorkbenchSortBy.activity) {
      for (final section in sections) {
        AgentActivityRank? rank;
        for (final workspace in members[section.id]!) {
          rank = bestAgentActivityRank(rank, _activityOf(workspace));
        }
        ranks[section.id] = rank;
      }
    }
    sections.sort((a, b) {
      final result = switch (prefs.sectionSort) {
        WorkbenchSortBy.name => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
        WorkbenchSortBy.recent => b.updatedAt.compareTo(a.updatedAt),
        WorkbenchSortBy.activity => compareByAgentActivity(
          aActivity: ranks[a.id],
          aName: a.name,
          bActivity: ranks[b.id],
          bName: b.name,
        ),
      };
      return result != 0 ? result : a.id.compareTo(b.id);
    });
    for (final section in <WorkspaceSection?>[
      ...sections,
      if (members.containsKey(null)) null,
    ]) {
      final workspaces = _sortWorkspaces(
        members[section?.id]!,
        pinMainOnRecent: true,
      );
      final collapsed = section == null
          ? prefs.othersSectionCollapsed
          : prefs.collapsedSectionIds.contains(section.id);
      rows.add(
        WorkbenchSectionHeaderRow(
          section: section,
          workspaceCount: workspaces.length,
          collapsed: collapsed,
        ),
      );
      if (collapsed) continue;
      _appendWorkspaceTreeRows(
        rows,
        workspaces: workspaces,
        projectOf: (workspace) => projectById[workspace.projectId]!,
        baseIndent: 1,
        showProjectChip: true,
      );
    }
  }
}

bool _sectionNameMatches(
  WorkbenchState state,
  Workspace workspace,
  String query,
) =>
    query.isNotEmpty &&
    state.sections.any(
      (section) =>
          section.id == workspace.sectionId &&
          section.name.toLowerCase().contains(query),
    );
