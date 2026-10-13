part of 'project_workbench_sidebar.dart';

/// OS-level workspace actions (open folder/browser, copy path, sleep) mixed into
/// the sidebar state so they share its [ref], [context], and [mounted] guard
/// without carrying a [BuildContext] across async gaps.
mixin _WorkspaceSidebarActions on ConsumerState<ProjectWorkbenchSidebar> {
  Future<void> openWorkspaceFolder(Workspace workspace) =>
      external_actions.openWorkspaceFolder(context, ref, workspace);
  Future<void> copyWorkspacePath(Workspace workspace) =>
      external_actions.copyWorkspacePath(context, workspace);
  Future<void> openWorkspaceInBrowser(Workspace workspace) =>
      external_actions.openWorkspaceInBrowser(context, ref, workspace);

  Future<void> sleepWorkspace(Workspace workspace) =>
      showSleepWorkspaceFlow(context, ref, workspace);

  Future<void> toggleWorkspaceArchived(Workspace workspace) =>
      showToggleWorkspaceArchivedFlow(context, ref, workspace);
}
