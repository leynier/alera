part of 'project_workbench_sidebar.dart';

/// Context-menu action ids, entry builder, and OS-level workspace action
/// methods extracted from [ProjectWorkbenchSidebar] and [_WorkspaceRow] to keep
/// those presentation files under the line budget. Everything here is
/// library-private and consumed only by the sidebar parts.

const String _renameAction = 'rename';
const String _openFolderAction = 'open-folder';
const String _copyPathAction = 'copy-path';
const String _openInBrowserAction = 'open-in-browser';
const String _sleepAction = 'sleep';
const String _manageTagsAction = 'manage-tags';
const String _togglePinAction = 'toggle-pin';
const String _setParentAction = 'set-parent';
const String _clearParentAction = 'clear-parent';
const String _removeAction = 'remove';

/// Builds the right-click menu entries for a workspace row. [hasClearParent]
/// gates the "Clear Parent Workspace" item and [canRemove] disables the remove
/// action for the main (non-deletable) workspace.
List<PopupMenuEntry<String>> workspaceContextMenuEntries({
  required String fileManagerLabel,
  required bool hasClearParent,
  required bool canRemove,
  required bool isPinned,
}) {
  return <PopupMenuEntry<String>>[
    const AleraDropdownEntry<String>(
      value: _renameAction,
      leading: Icon(AleraIcons.edit, size: 16),
      label: 'Rename',
    ),
    AleraDropdownEntry<String>(
      value: _togglePinAction,
      leading: Icon(isPinned ? AleraIcons.pinOff : AleraIcons.pin, size: 16),
      label: isPinned ? 'Unpin Workspace' : 'Pin Workspace',
    ),
    const AleraDropdownEntry<String>(
      value: _manageTagsAction,
      leading: Icon(AleraIcons.tag, size: 16),
      label: 'Manage Tags',
    ),
    const AleraDropdownEntry<String>(
      value: _setParentAction,
      leading: Icon(AleraIcons.link, size: 16),
      label: 'Set Parent Workspace',
    ),
    if (hasClearParent)
      const AleraDropdownEntry<String>(
        value: _clearParentAction,
        leading: Icon(AleraIcons.close, size: 16),
        label: 'Clear Parent Workspace',
      ),
    const PopupMenuDivider(height: AleraTokens.space8),
    const AleraDropdownEntry<String>(
      value: _openInBrowserAction,
      leading: Icon(
        AleraIcons.external,
        size: 16,
        color: AleraTokens.foreground,
      ),
      label: 'Open in Browser',
    ),
    AleraDropdownEntry<String>(
      value: _openFolderAction,
      leading: const Icon(
        AleraIcons.folderOpen,
        size: 16,
        color: AleraTokens.foreground,
      ),
      label: 'Open in $fileManagerLabel',
    ),
    const AleraDropdownEntry<String>(
      value: _copyPathAction,
      leading: Icon(AleraIcons.copy, size: 16, color: AleraTokens.foreground),
      label: 'Copy Path',
    ),
    const PopupMenuDivider(height: AleraTokens.space8),
    const AleraDropdownEntry<String>(
      value: _sleepAction,
      leading: Icon(AleraIcons.theme, size: 16, color: AleraTokens.foreground),
      label: 'Sleep',
    ),
    AleraDropdownEntry<String>(
      value: _removeAction,
      leading: Icon(
        AleraIcons.delete,
        size: 16,
        color: canRemove ? AleraTokens.foreground : AleraTokens.foregroundFaint,
      ),
      label: 'Remove',
      enabled: canRemove,
    ),
  ];
}

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
        tone: AleraToastTone.error,
      );
    }
  }

  Future<void> copyWorkspacePath(Workspace workspace) async {
    await Clipboard.setData(ClipboardData(text: workspace.path));
    if (!mounted) {
      return;
    }
    AleraToast.show(
      context,
      message: 'Workspace path copied',
      tone: AleraToastTone.success,
    );
  }

  /// Opens the workspace's repository home page in the system browser. The
  /// project-level hosting override is best-effort: a timeout or error falls
  /// back to auto-detection instead of blocking or breaking the click.
  Future<void> openWorkspaceInBrowser(Workspace workspace) async {
    GitHostingProvider? override;
    try {
      override = await ref
          .read(
            effectiveHostingProviderOverrideProvider(
              workspace.projectId,
            ).future,
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
        tone: AleraToastTone.error,
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
          tone: AleraToastTone.info,
        );
      case OpenRepositoryOutcome.undetectable:
        AleraToast.show(
          context,
          message:
              'Could not detect a supported git hosting provider '
              '(GitHub or Azure DevOps).',
          tone: AleraToastTone.info,
        );
      case OpenRepositoryOutcome.openFailed:
        AleraToast.show(
          context,
          message: 'Could not open the browser.',
          tone: AleraToastTone.error,
        );
    }
  }

  void sleepWorkspace(Workspace workspace) {
    ref.read(terminalRuntimeProvider).closeWorkspace(workspace.id);
    AleraToast.show(
      context,
      message: 'Workspace Slept',
      tone: AleraToastTone.success,
    );
  }
}
