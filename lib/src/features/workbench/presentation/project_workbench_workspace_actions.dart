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

  Future<void> sleepWorkspace(Workspace workspace) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AleraConfirmDialog(
        title: 'Sleep Workspace?',
        message:
            'This closes terminal sessions for "${workspace.name}". Tabs, '
            'branch, and files will be preserved, and agent sessions can '
            'resume when the workspace wakes.',
        confirmLabel: 'Sleep',
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await ref
          .read(workbenchControllerProvider.notifier)
          .sleepWorkspace(workspace);
      // The controller releases the live handles; keep this call so sidebar
      // sleep still drops them when the controller is stubbed. Double close
      // is idempotent.
      ref.read(terminalRuntimeProvider).closeWorkspace(workspace.id);
      if (!mounted) {
        return;
      }
      AleraToast.show(context, message: 'Workspace slept', tone: .success);
    } catch (error) {
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Could not sleep workspace: $error',
        tone: .error,
      );
    }
  }

  Future<void> toggleWorkspaceArchived(Workspace workspace) async {
    if (workspace.isArchived) {
      try {
        await ref
            .read(workbenchControllerProvider.notifier)
            .unarchiveWorkspace(workspace);
        if (!mounted) {
          return;
        }
        AleraToast.show(
          context,
          message: 'Workspace unarchived',
          tone: .success,
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        AleraToast.show(
          context,
          message: 'Could not unarchive workspace: $error',
          tone: .error,
        );
      }
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AleraConfirmDialog(
        title: 'Archive Workspace?',
        message:
            'This closes terminal sessions for "${workspace.name}" and hides '
            'it from the sidebar. Tabs, branch, and files will be preserved, '
            'and agent sessions can resume when it is unarchived.',
        confirmLabel: 'Archive',
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref
          .read(workbenchControllerProvider.notifier)
          .archiveWorkspace(workspace);
      if (!mounted) {
        return;
      }
      AleraToast.show(context, message: 'Workspace archived', tone: .success);
    } catch (error) {
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Could not archive workspace: $error',
        tone: .error,
      );
    }
  }
}
