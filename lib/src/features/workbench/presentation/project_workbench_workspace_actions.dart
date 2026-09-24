part of 'project_workbench_sidebar.dart';

/// OS-level workspace actions (open folder/browser, copy path, sleep) mixed into
/// the sidebar state so they share its [ref], [context], and [mounted] guard
/// without carrying a [BuildContext] across async gaps.
mixin _WorkspaceSidebarActions on ConsumerState<ProjectWorkbenchSidebar> {
  Future<void> openWorkspaceFolder(Workspace workspace) async {
    final result = await ref
        .read(workspaceFolderOpenerProvider)
        .open(workspace.path);
    if (!result.ok && mounted) {
      AleraToast.show(
        context,
        message: result.message ?? 'Could not open workspace folder.',
        tone: .error,
      );
    }
  }

  Future<void> copyWorkspacePath(Workspace workspace) async {
    await Clipboard.setData(ClipboardData(text: workspace.path));
    if (!mounted) {
      return;
    }
    AleraToast.show(context, message: 'Workspace path copied', tone: .success);
  }

  /// Opens the workspace's repository home page in the system browser. The
  /// project-level hosting override is best-effort: a timeout or error falls
  /// back to auto-detection instead of blocking or breaking the click.
  Future<void> openWorkspaceInBrowser(Workspace workspace) async {
    GitHostingProvider? override;
    try {
      override = await ref
          .read(
            effectiveHostingProviderOverrideProvider(workspace.projectId)
                .future,
          )
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      override = null;
    }

    final OpenRepositoryOutcome outcome;
    try {
      outcome = await ref
          .read(repositoryBrowserOpenerProvider)
          .open(repoPath: workspace.path, override: override);
    } catch (error) {
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Could not open the repository: $error',
        tone: .error,
      );
      return;
    }
    if (!mounted) {
      return;
    }
    switch (outcome) {
      case OpenRepositoryOutcome.opened:
        break;
      case OpenRepositoryOutcome.noRemote:
        AleraToast.show(
          context,
          message: 'No git remote configured for this workspace.',
          tone: .info,
        );
      case OpenRepositoryOutcome.undetectable:
        AleraToast.show(
          context,
          message:
              'Could not detect a supported git hosting provider '
              '(GitHub or Azure DevOps).',
          tone: .info,
        );
      case OpenRepositoryOutcome.openFailed:
        AleraToast.show(
          context,
          message: 'Could not open the browser.',
          tone: .error,
        );
    }
  }

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
