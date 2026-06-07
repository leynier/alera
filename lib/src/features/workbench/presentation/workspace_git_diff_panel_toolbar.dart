part of 'workspace_git_diff_panel.dart';

class _SourceControlToolbar extends StatelessWidget {
  const _SourceControlToolbar({
    required this.messageController,
    required this.filterController,
    required this.viewMode,
    required this.state,
    required this.allCollapsed,
    required this.onMessageChanged,
    required this.onFilterChanged,
    required this.onRefresh,
    required this.onToggleCollapseAll,
    required this.onViewModeChanged,
    required this.onOpenAll,
    required this.onPrimaryAction,
    required this.onSelectMenuAction,
  });

  final TextEditingController messageController;
  final TextEditingController filterController;
  final GitDiffViewMode viewMode;
  final AsyncValue<WorkspaceSourceControlState> state;
  final bool allCollapsed;
  final VoidCallback onMessageChanged;
  final VoidCallback onFilterChanged;
  final VoidCallback onRefresh;
  final VoidCallback onToggleCollapseAll;
  final ValueChanged<GitDiffViewMode> onViewModeChanged;
  final VoidCallback onOpenAll;
  final ValueChanged<_SourceControlMenuAction> onPrimaryAction;
  final ValueChanged<_SourceControlMenuAction> onSelectMenuAction;

  @override
  Widget build(BuildContext context) {
    final data = state.asData?.value;
    final busy = state.isLoading || (data?.isBusy ?? false);
    final hasStagedChanges = data?.hasStagedChanges ?? false;
    final hasConflicts = data?.repositoryState.hasConflicts ?? false;
    final canCommit =
        !busy &&
        !hasConflicts &&
        hasStagedChanges &&
        messageController.text.trim().isNotEmpty;
    final primaryAction = _primaryActionFor(
      data,
      busy: busy,
      canCommit: canCommit,
    );
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Source control',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              AleraIconButton(
                tooltip: 'All changes',
                icon: Icons.difference_outlined,
                onPressed: busy ? null : onOpenAll,
              ),
              const SizedBox(width: AleraTokens.space2),
              AleraIconButton(
                tooltip: viewMode == GitDiffViewMode.tree
                    ? 'Show flat list'
                    : 'Show tree',
                icon: viewMode == GitDiffViewMode.tree
                    ? Icons.view_list_outlined
                    : Icons.account_tree_outlined,
                onPressed: busy
                    ? null
                    : () => onViewModeChanged(
                        viewMode == GitDiffViewMode.tree
                            ? GitDiffViewMode.flat
                            : GitDiffViewMode.tree,
                      ),
              ),
              const SizedBox(width: AleraTokens.space2),
              AleraIconButton(
                tooltip: allCollapsed ? 'Expand all' : 'Collapse all',
                icon: allCollapsed
                    ? Icons.unfold_more_outlined
                    : Icons.unfold_less_outlined,
                onPressed: busy ? null : onToggleCollapseAll,
              ),
              const SizedBox(width: AleraTokens.space2),
              AleraIconButton(
                tooltip: 'Refresh',
                icon: Icons.refresh,
                onPressed: busy ? null : onRefresh,
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space8),
          _CommitMessageField(
            controller: messageController,
            enabled: !busy,
            onChanged: (_) => onMessageChanged(),
            onSubmitted: (_) {
              if (canCommit) {
                onPrimaryAction(_SourceControlMenuAction.commit);
              }
            },
          ),
          const SizedBox(height: AleraTokens.space8),
          Row(
            children: <Widget>[
              Expanded(
                child: _PrimaryActionButton(
                  action: primaryAction,
                  state: data,
                  busy: busy,
                  onPressed: primaryAction == null
                      ? null
                      : () => onPrimaryAction(primaryAction),
                  onSelected: onSelectMenuAction,
                ),
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space8),
          AleraTextField(
            controller: filterController,
            hintText: 'Filter files...',
            prefixIcon: Icons.search,
            dense: true,
            enabled: !busy,
            onChanged: (_) => onFilterChanged(),
          ),
          if (data case final state?) ...<Widget>[
            const SizedBox(height: AleraTokens.space6),
            Text(
              _repoSummary(state),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AleraTokens.foregroundFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }

  _SourceControlMenuAction? _primaryActionFor(
    WorkspaceSourceControlState? state, {
    required bool busy,
    required bool canCommit,
  }) {
    if (busy || state == null) {
      return null;
    }
    if (canCommit) {
      return _SourceControlMenuAction.commit;
    }
    final repo = state.repositoryState;
    if (repo.hasConflicts) {
      return _SourceControlMenuAction.fetch;
    }
    if (!repo.hasUpstream && repo.branch != 'HEAD') {
      return _SourceControlMenuAction.publishBranch;
    }
    if (repo.hasUpstream && repo.ahead > 0 && repo.behind > 0) {
      return _SourceControlMenuAction.sync;
    }
    if (repo.hasUpstream && repo.behind > 0) {
      return _SourceControlMenuAction.pull;
    }
    if (repo.hasUpstream && repo.ahead > 0) {
      return _SourceControlMenuAction.push;
    }
    if (state.hasUnstagedOrUntrackedChanges) {
      return _SourceControlMenuAction.stageAll;
    }
    return _SourceControlMenuAction.fetch;
  }

  String _repoSummary(WorkspaceSourceControlState state) {
    final repo = state.repositoryState;
    final parts = <String>[repo.branch];
    if (repo.upstream case final upstream?) {
      parts.add(upstream);
    }
    if (repo.ahead > 0) {
      parts.add('ahead ${repo.ahead}');
    }
    if (repo.behind > 0) {
      parts.add('behind ${repo.behind}');
    }
    if (repo.hasConflicts) {
      parts.add('conflicts');
    }
    if (state.action case final action?) {
      parts.add(_actionLabel(action));
    }
    return parts.join(' · ');
  }

  String _actionLabel(WorkspaceSourceControlAction action) {
    return switch (action) {
      WorkspaceSourceControlAction.refresh => 'refreshing',
      WorkspaceSourceControlAction.stage => 'staging',
      WorkspaceSourceControlAction.unstage => 'unstaging',
      WorkspaceSourceControlAction.discard => 'discarding',
      WorkspaceSourceControlAction.commit => 'committing',
      WorkspaceSourceControlAction.commitPush => 'committing and pushing',
      WorkspaceSourceControlAction.commitSync => 'committing and syncing',
      WorkspaceSourceControlAction.fetch => 'fetching',
      WorkspaceSourceControlAction.pull => 'pulling',
      WorkspaceSourceControlAction.push => 'pushing',
      WorkspaceSourceControlAction.sync => 'syncing',
      WorkspaceSourceControlAction.stash => 'stashing',
      WorkspaceSourceControlAction.stashPop => 'popping stash',
    };
  }
}

enum _SourceControlMenuAction {
  refresh,
  commit,
  commitPush,
  commitSync,
  stageAll,
  unstageAll,
  discardAll,
  fetch,
  pull,
  push,
  sync,
  publishBranch,
  stash,
  stashPop,
}

class _CommitMessageField extends StatelessWidget {
  const _CommitMessageField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      enabled: enabled,
      minLines: 3,
      maxLines: 6,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: theme.textTheme.bodySmall?.copyWith(color: AleraTokens.foreground),
      cursorColor: AleraTokens.foreground,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AleraTokens.surface,
        hintText: 'Message',
        hintStyle: theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foregroundFaint,
        ),
        contentPadding: const EdgeInsets.all(AleraTokens.space8),
        border: _messageBorder(AleraTokens.borderSubtle),
        enabledBorder: _messageBorder(AleraTokens.borderSubtle),
        focusedBorder: _messageBorder(AleraTokens.border),
      ),
    );
  }

  OutlineInputBorder _messageBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
    borderSide: BorderSide(color: color),
  );
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.action,
    required this.busy,
    required this.state,
    required this.onPressed,
    required this.onSelected,
  });

  final _SourceControlMenuAction? action;
  final bool busy;
  final WorkspaceSourceControlState? state;
  final VoidCallback? onPressed;
  final ValueChanged<_SourceControlMenuAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    final label = action == null ? 'Fetch' : _actionLabel(action);
    final icon = action == null ? Icons.download_outlined : _actionIcon(action);
    return Row(
      children: <Widget>[
        Expanded(
          child: FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            label: Text(label),
          ),
        ),
        const SizedBox(width: AleraTokens.space2),
        PopupMenuButton<_SourceControlMenuAction>(
          tooltip: 'Source control actions',
          enabled: !busy,
          icon: const Icon(Icons.expand_more, size: 18),
          onSelected: onSelected,
          itemBuilder: _menuEntries,
        ),
      ],
    );
  }

  List<PopupMenuEntry<_SourceControlMenuAction>> _menuEntries(
    BuildContext context,
  ) {
    final hasStaged = state?.hasStagedChanges ?? false;
    final hasDiscardable = state?.hasUnstagedOrUntrackedChanges ?? false;
    final hasStashable = state?.hasStashableChanges ?? false;
    final hasStashes = state?.stashes.isNotEmpty ?? false;
    final hasConflicts = state?.repositoryState.hasConflicts ?? false;
    final hasUpstream = state?.repositoryState.hasUpstream ?? false;
    final hasData = state != null;
    final branch = state?.repositoryState.branch;
    final canPublish =
        hasData && !hasUpstream && branch != null && branch != 'HEAD';
    return <PopupMenuEntry<_SourceControlMenuAction>>[
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: _SourceControlMenuAction.commit,
        label: 'Commit',
        enabled: hasStaged && !hasConflicts,
        leading: const Icon(Icons.check, size: 16),
      ),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: _SourceControlMenuAction.commitPush,
        label: 'Commit & push',
        enabled: hasStaged && !hasConflicts,
        leading: const Icon(Icons.north, size: 16),
      ),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: _SourceControlMenuAction.commitSync,
        label: 'Commit & sync',
        enabled: hasStaged && !hasConflicts && hasUpstream,
        leading: const Icon(Icons.sync, size: 16),
      ),
      const PopupMenuDivider(height: AleraTokens.space8),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: _SourceControlMenuAction.stageAll,
        label: 'Stage all',
        enabled: state?.hasUnstagedOrUntrackedChanges ?? false,
        leading: const Icon(Icons.add, size: 16),
      ),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: _SourceControlMenuAction.unstageAll,
        label: 'Unstage all',
        enabled: hasStaged,
        leading: const Icon(Icons.remove, size: 16),
      ),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: _SourceControlMenuAction.discardAll,
        label: 'Discard all',
        enabled: hasDiscardable,
        leading: const Icon(Icons.close, size: 16),
      ),
      const PopupMenuDivider(height: AleraTokens.space8),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: _SourceControlMenuAction.fetch,
        label: 'Fetch',
        enabled: hasData,
        leading: const Icon(Icons.download_outlined, size: 16),
      ),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: _SourceControlMenuAction.pull,
        label: 'Pull',
        enabled: hasData,
        leading: const Icon(Icons.south, size: 16),
      ),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: _SourceControlMenuAction.push,
        label: 'Push',
        enabled: hasData && !hasConflicts,
        leading: const Icon(Icons.north, size: 16),
      ),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: _SourceControlMenuAction.sync,
        label: 'Sync',
        enabled: hasData && !hasConflicts && hasUpstream,
        leading: const Icon(Icons.sync, size: 16),
      ),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: _SourceControlMenuAction.publishBranch,
        label: 'Publish branch',
        enabled: canPublish,
        leading: const Icon(Icons.cloud_upload_outlined, size: 16),
      ),
      const PopupMenuDivider(height: AleraTokens.space8),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: _SourceControlMenuAction.stash,
        label: 'Stash',
        enabled: hasStashable,
        leading: const Icon(Icons.inventory_2_outlined, size: 16),
      ),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: _SourceControlMenuAction.stashPop,
        label: 'Stash pop',
        enabled: hasStashes,
        leading: const Icon(Icons.unarchive_outlined, size: 16),
      ),
    ];
  }

  String _actionLabel(_SourceControlMenuAction action) {
    return switch (action) {
      _SourceControlMenuAction.commit => 'Commit',
      _SourceControlMenuAction.commitPush => 'Commit & push',
      _SourceControlMenuAction.commitSync => 'Commit & sync',
      _SourceControlMenuAction.stageAll => 'Stage all',
      _SourceControlMenuAction.unstageAll => 'Unstage all',
      _SourceControlMenuAction.discardAll => 'Discard all',
      _SourceControlMenuAction.fetch => 'Fetch',
      _SourceControlMenuAction.pull => 'Pull',
      _SourceControlMenuAction.push => 'Push',
      _SourceControlMenuAction.sync => 'Sync',
      _SourceControlMenuAction.publishBranch => 'Publish branch',
      _SourceControlMenuAction.stash => 'Stash',
      _SourceControlMenuAction.stashPop => 'Stash pop',
      _SourceControlMenuAction.refresh => 'Refresh',
    };
  }

  IconData _actionIcon(_SourceControlMenuAction action) {
    return switch (action) {
      _SourceControlMenuAction.commit => Icons.check,
      _SourceControlMenuAction.commitPush ||
      _SourceControlMenuAction.push => Icons.north,
      _SourceControlMenuAction.commitSync ||
      _SourceControlMenuAction.sync => Icons.sync,
      _SourceControlMenuAction.stageAll => Icons.add,
      _SourceControlMenuAction.unstageAll => Icons.remove,
      _SourceControlMenuAction.discardAll => Icons.close,
      _SourceControlMenuAction.fetch => Icons.download_outlined,
      _SourceControlMenuAction.pull => Icons.south,
      _SourceControlMenuAction.publishBranch => Icons.cloud_upload_outlined,
      _SourceControlMenuAction.stash => Icons.inventory_2_outlined,
      _SourceControlMenuAction.stashPop => Icons.unarchive_outlined,
      _SourceControlMenuAction.refresh => Icons.refresh,
    };
  }
}
