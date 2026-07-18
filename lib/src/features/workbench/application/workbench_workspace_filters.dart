import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';

/// OR semantics over the selected tag filter: an empty selection shows every
/// workspace; otherwise a workspace must carry at least one selected tag.
bool workspaceMatchesTagFilter(WorkbenchViewPrefs prefs, Workspace workspace) {
  if (prefs.selectedTagIds.isEmpty) {
    return true;
  }
  return workspace.tagIds.any(prefs.selectedTagIds.contains);
}

/// Whether [workspace] passes the workspace-kind visibility filter: the main
/// worktree counts as the project's default workspace.
bool workspaceMatchesKindFilter(WorkbenchViewPrefs prefs, Workspace workspace) {
  return switch (prefs.workspaceKindFilter) {
    WorkspaceKindFilter.all => true,
    WorkspaceKindFilter.defaultOnly => workspace.isMain,
    WorkspaceKindFilter.nonDefaultOnly => !workspace.isMain,
  };
}
