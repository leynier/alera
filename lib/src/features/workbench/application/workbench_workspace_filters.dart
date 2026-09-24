import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';

/// OR semantics over the selected tag filter: an empty selection shows every
/// workspace; otherwise a workspace must carry at least one selected tag.
bool workspaceMatchesTagFilter(WorkbenchViewPrefs prefs, Workspace workspace) {
  if (prefs.selectedTagIds.isEmpty) {
    return true;
  }
  return workspace.tagIds.any(prefs.selectedTagIds.contains);
}

/// OR semantics over the selected section filter: an empty selection shows
/// every workspace; otherwise a workspace must belong to at least one selected
/// section.
bool workspaceMatchesSectionFilter(
  WorkbenchViewPrefs prefs,
  Workspace workspace,
) {
  if (prefs.selectedSectionIds.isEmpty) {
    return true;
  }
  final sectionId = workspace.sectionId;
  if (sectionId == null) {
    return false;
  }
  return prefs.selectedSectionIds.contains(sectionId);
}

/// Legacy saved kind filters no longer hide tasks on shared checkouts.
bool workspaceMatchesKindFilter(WorkbenchViewPrefs prefs, Workspace workspace) {
  return true;
}

/// Whether [tabs] make a workspace active for sidebar filtering and activity
/// sorting. Other workbench tabs do not represent a running agent session.
bool workspaceMatchesActiveFilter(
  WorkbenchViewPrefs prefs,
  Iterable<WorkspaceTabRecord> tabs,
) {
  if (!prefs.showActiveWorkspacesOnly) {
    return true;
  }
  return tabs.any((tab) => tab.kind == WorkspaceTabKind.terminal);
}

/// Archived workspaces stay hidden unless the user opts in through View
/// Options. Pinned copies follow the same rule as their regular row.
bool workspaceMatchesArchivedFilter(
  WorkbenchViewPrefs prefs,
  Workspace workspace,
) {
  if (prefs.showArchivedWorkspaces) {
    return true;
  }
  return !workspace.isArchived;
}
