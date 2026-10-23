part of 'workspace_details_overlay.dart';

extension on _WorkspaceDetailsOverlayState {
  /// Opens Source Control in the right panel, or focuses it wherever the
  /// workspace already shows it.
  void _revealSourceControl() {
    ref.read(workbenchControllerProvider.notifier)
      ..setRightSidebarVisible(true)
      ..setContextPanelTab(.gitDiff);
  }

  /// Commits the branch is ahead of and behind its upstream, or a muted
  /// note when it was never published.
  Widget? _branchSync(WorkspaceDetailsState data) {
    final repo = data.sourceControl.repositoryState;
    final style = AleraTokens.monoCompactStyle.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    if (!repo.hasUpstream) {
      if (!data.hasRemote) return null;
      return Text('Unpublished', style: style);
    }
    if (repo.ahead == 0 && repo.behind == 0) return null;
    Widget count(IconData icon, int value) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: AleraTokens.iconSm,
          color: AleraTokens.foregroundMuted,
        ),
        Text('$value', style: style),
      ],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: AleraTokens.space4,
      children: [
        if (repo.ahead > 0) count(AleraIcons.arrowUp, repo.ahead),
        if (repo.behind > 0) count(AleraIcons.arrowDown, repo.behind),
      ],
    );
  }

  String _branchSyncHint(WorkspaceDetailsState data) {
    final repo = data.sourceControl.repositoryState;
    final upstream = repo.upstream;
    if (upstream == null || upstream.isEmpty) {
      return data.hasRemote
          ? 'This branch has no upstream yet. Push to publish it.'
          : 'This repository has no remote.';
    }
    final parts = [
      upstream,
      if (repo.ahead > 0) '${repo.ahead} ahead',
      if (repo.behind > 0) '${repo.behind} behind',
      if (repo.ahead == 0 && repo.behind == 0) 'up to date',
    ];
    return '${parts.join(' · ')}\nCounts reflect the last fetch.';
  }

  Future<void> _fetch() async {
    try {
      await ref
          .read(
            workspaceSourceControlControllerProvider(_scope.repoPath).notifier,
          )
          .fetch();
    } catch (error, stackTrace) {
      showActionFailure(action: 'fetch', error: error, stackTrace: stackTrace);
    }
  }

  /// Lines changed in the working tree, the same files Source Control lists,
  /// so the Changes counts describe what the row opens.
  ({int added, int removed}) _uncommittedLines(WorkspaceDetailsState data) {
    var added = 0;
    var removed = 0;
    for (final entry in data.sourceControl.status.entries) {
      added += entry.added ?? 0;
      removed += entry.removed ?? 0;
    }
    return (added: added, removed: removed);
  }

  String _uncommittedHint(WorkspaceDetailsState data) {
    final files = {
      for (final entry in data.sourceControl.status.entries) entry.path,
    }.length;
    return switch (files) {
      0 => 'No uncommitted changes. Open Source Control.',
      1 => '1 file with uncommitted changes. Open Source Control.',
      _ => '$files files with uncommitted changes. Open Source Control.',
    };
  }

  Future<String?> _menu(Rect anchor, List<PopupMenuEntry<String>> entries) {
    return showMenu<String>(
      context: context,
      position: aleraMenuBelow(context, anchor),
      items: entries,
    );
  }

  Future<void> _detailsOptions(Rect anchor) async {
    final issue = ref.read(workspaceLinkedIssueProvider(widget.workspace.id));
    final related = _relatedWorkspaces(
      ref.read(workbenchControllerProvider),
      widget.workspace.id,
    );
    final automations = _workspaceAutomations(
      ref.read(automationCatalogProvider).value,
      widget.workspace.id,
    );
    final choice = await _menu(anchor, [
      const AleraDropdownEntry(
        value: 'host',
        label: 'Host And Hand Off',
        leading: _MenuIcon(AleraIcons.host),
      ),
      const AleraDropdownEntry(
        value: 'open',
        label: 'Open In',
        leading: _MenuIcon(AleraIcons.folderOpen),
      ),
      if (issue != null)
        AleraDropdownEntry(
          value: 'issue',
          label: 'Issue ${issue.reference}',
          leading: LinkedIssueStateIcon(
            state: issue.state,
            size: AleraTokens.iconMd,
          ),
        ),
      if (!related.isEmpty)
        const AleraDropdownEntry(
          value: 'related',
          label: 'Related Workspaces',
          leading: _MenuIcon(AleraIcons.workspaceChildren),
        ),
      if (automations.isNotEmpty)
        AleraDropdownEntry(
          value: 'automations',
          label: automations.length == 1
              ? automations.single.name
              : '${automations.length} Automations',
          leading: const _MenuIcon(AleraIcons.checks),
        ),
    ]);
    if (!mounted) return;
    if (choice == 'automations') {
      await _automationsMenu(anchor, automations);
    }
    if (choice == 'related') await _relatedMenu(anchor, related);
    if (choice == 'host') await _hostMenu(anchor);
    if (choice == 'open') await _openMenu(anchor);
    if (choice == 'issue') await _issueMenu(anchor);
  }

  void _issueAction(String action) => unawaited(
    runLinkedIssueMenuAction(
      context,
      ProviderScope.containerOf(context, listen: false),
      workspace: widget.workspace,
      action: action,
    ),
  );

  Future<void> _issueMenu(Rect anchor) async {
    final choice = await _menu(anchor, const [
      AleraDropdownEntry(
        value: openLinkedIssueMenuAction,
        label: 'Open Issue In Browser',
        leading: _MenuIcon(AleraIcons.external),
      ),
      AleraDropdownEntry(
        value: changeLinkedIssueMenuAction,
        label: 'Change Linked Issue',
        leading: _MenuIcon(AleraIcons.link),
      ),
      AleraDropdownEntry(
        value: unlinkIssueMenuAction,
        label: 'Unlink Issue',
        leading: _MenuIcon(AleraIcons.unlink),
      ),
    ]);
    if (mounted && choice != null) _issueAction(choice);
  }

  /// Workspace-level actions, the same ones the sidebar row menu offers.
  Future<void> _hostMenu(Rect anchor) async {
    final workspace = widget.workspace;
    final state = ref.read(workbenchControllerProvider);
    final project = findProjectById(state, workspace.projectId);
    final relocates = project?.supportsLinkedWorkspaces ?? false;
    final canLink =
        ref.read(linkedIssuesSupportedProvider) &&
        ref.read(workspaceLinkedIssueProvider(workspace.id)) == null;
    final choice = await _menu(anchor, [
      if (relocates && workspace.isMain)
        const AleraDropdownEntry(
          value: 'handoff',
          label: 'Hand Off',
          leading: _MenuIcon(AleraIcons.gitFork),
        ),
      if (relocates && !workspace.isMain)
        const AleraDropdownEntry(
          value: 'handon',
          label: 'Hand On',
          leading: _MenuIcon(AleraIcons.workspaceMain),
        ),
      const AleraDropdownEntry(
        value: 'rename',
        label: 'Rename',
        leading: _MenuIcon(AleraIcons.edit),
      ),
      if (canLink)
        const AleraDropdownEntry(
          value: linkIssueMenuAction,
          label: 'Link Issue',
          leading: _MenuIcon(AleraIcons.link),
        ),
      const AleraDropdownEntry(
        value: _newAutomationMenuValue,
        label: 'New Automation Here',
        leading: _MenuIcon(AleraIcons.add),
      ),
      const PopupMenuDivider(),
      const AleraDropdownEntry(
        value: 'sleep',
        label: 'Sleep',
        leading: _MenuIcon(AleraIcons.theme),
      ),
      if (state.supportsArchive)
        AleraDropdownEntry(
          value: 'archive',
          label: workspace.isArchived ? 'Unarchive' : 'Archive',
          leading: _MenuIcon(
            workspace.isArchived ? AleraIcons.unarchive : AleraIcons.archive,
          ),
        ),
      if (project != null)
        const AleraDropdownEntry(
          value: 'remove',
          label: 'Remove',
          leading: _MenuIcon(AleraIcons.delete),
        ),
    ]);
    if (!mounted || choice == null) return;
    switch (choice) {
      case linkIssueMenuAction:
        _issueAction(linkIssueMenuAction);
      case _newAutomationMenuValue:
        _newAutomation();
      case 'handoff':
        await showHandOffWorkspaceFlow(context, ref, workspace: workspace);
      case 'handon' when project != null:
        await showHandOnWorkspaceFlow(
          context,
          ref,
          project: project,
          workspace: workspace,
        );
      case 'rename':
        await _renameWorkspace();
      case 'sleep':
        await showSleepWorkspaceFlow(context, ref, workspace);
      case 'archive':
        await showToggleWorkspaceArchivedFlow(context, ref, workspace);
      case 'remove' when project != null:
        await showWorkspaceRemovalFlow(
          context: context,
          ref: ref,
          project: project,
          workspace: workspace,
        );
    }
  }

  Future<void> _renameWorkspace() async {
    final workspace = widget.workspace;
    final name = await showRenameDialog(
      context,
      title: 'Rename Workspace',
      labelText: 'Workspace Name',
      initialValue: workspace.name,
      confirmLabel: 'Rename',
    );
    if (name == null || !mounted) return;
    try {
      await ref
          .read(workbenchControllerProvider.notifier)
          .renameWorkspace(workspaceId: workspace.id, name: name);
    } catch (error, stackTrace) {
      showActionFailure(
        action: 'rename workspace',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _openMenu(Rect anchor) async {
    final workspace = widget.workspace;
    final choice = await _menu(anchor, [
      AleraDropdownEntry(
        value: 'folder',
        label:
            'Open In ${ref.read(workspaceFolderOpenerProvider).fileManagerLabel}',
        leading: const _MenuIcon(AleraIcons.folderOpen),
        enabled: !workspace.isRemote,
      ),
      const AleraDropdownEntry(
        value: 'browser',
        label: 'Open In Browser',
        leading: _MenuIcon(AleraIcons.external),
      ),
      const AleraDropdownEntry(
        value: 'copy',
        label: 'Copy Path',
        leading: _MenuIcon(AleraIcons.copy),
      ),
    ]);
    if (!mounted) return;
    switch (choice) {
      case 'folder':
        await external_actions.openWorkspaceFolder(context, ref, workspace);
      case 'copy':
        await external_actions.copyWorkspacePath(context, workspace);
      case 'browser':
        await external_actions.openWorkspaceInBrowser(context, ref, workspace);
    }
  }
}

class const _MenuIcon(final IconData icon) extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: AleraTokens.iconMd, color: AleraTokens.foregroundMuted);
}
