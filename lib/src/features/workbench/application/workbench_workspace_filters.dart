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
