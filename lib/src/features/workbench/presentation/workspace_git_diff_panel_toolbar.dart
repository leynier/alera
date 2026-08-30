part of 'workspace_git_diff_panel.dart';

class const _SourceControlToolbar({
  required final TextEditingController messageController,
  required final FocusNode messageFocusNode,
  required final TextEditingController filterController,
  required final GitDiffViewMode viewMode,
  required final GitDiffGroupMode groupMode,
  required final AsyncValue<WorkspaceSourceControlState> state,
  required final AiAssistSettings aiAssistSettings,
  required final bool generatingCommitMessage,
  required final bool allCollapsed,
  required final bool filterVisible,
  required final String? sourceControlRootLabel,
  required final VoidCallback onMessageChanged,
  required final VoidCallback onGenerateCommitMessage,
  required final VoidCallback onCancelGenerateCommitMessage,
  required final VoidCallback onFilterChanged,
  required final VoidCallback onToggleFilter,
  required final VoidCallback onRefresh,
  required final VoidCallback? onClearSourceControlRoot,
  required final VoidCallback onToggleCollapseAll,
  required final ValueChanged<GitDiffViewMode> onViewModeChanged,
  required final ValueChanged<GitDiffGroupMode> onGroupModeChanged,
  required final VoidCallback onOpenAll,
  required final ValueChanged<_SourceControlMenuAction> onPrimaryAction,
  required final ValueChanged<_SourceControlMenuAction> onSelectMenuAction,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final data = state.asData?.value;
    final busy = state.isLoading || (data?.isBusy ?? false);
    final hasStagedChanges = data?.hasStagedChanges ?? false;
    final hasConflicts = data?.repositoryState.hasConflicts ?? false;
    final canGenerateCommitMessage =
        aiAssistSettings.enabled && !busy && !hasConflicts && hasStagedChanges;
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
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Source Control',
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: .horizontal,
                  reverse: true,
                  child: Row(
                    mainAxisSize: .min,
                    children: <Widget>[
                      if (onClearSourceControlRoot != null) ...<Widget>[
                        AleraIconButton(
                          tooltip: 'Clear Source Control Root',
                          icon: AleraIcons.close,
                          onPressed: busy ? null : onClearSourceControlRoot,
                        ),
                        const SizedBox(width: AleraTokens.space2),
                      ],
                      if (aiAssistSettings.enabled ||
                          generatingCommitMessage) ...<Widget>[
                        _AiCommitMessageButton(
                          generating: generatingCommitMessage,
                          canGenerate: canGenerateCommitMessage,
                          onGenerate: onGenerateCommitMessage,
                          onCancel: onCancelGenerateCommitMessage,
                        ),
                        const SizedBox(width: AleraTokens.space2),
                      ],
                      AleraIconButton(
                        tooltip: 'All Changes',
                        icon: AleraIcons.diff,
                        onPressed: busy ? null : onOpenAll,
                      ),
                      const SizedBox(width: AleraTokens.space2),
                      AleraIconButton(
                        tooltip: viewMode == GitDiffViewMode.tree
                            ? 'Show Flat List'
                            : 'Show Tree',
                        icon: viewMode == GitDiffViewMode.tree
                            ? AleraIcons.listView
                            : AleraIcons.gitGraph,
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
                        tooltip: groupMode == GitDiffGroupMode.byArea
                            ? 'Show All Changes'
                            : 'Group By Staged State',
                        icon: groupMode == GitDiffGroupMode.byArea
                            ? AleraIcons.gridView
                            : AleraIcons.outline,
                        onPressed: busy
                            ? null
                            : () => onGroupModeChanged(
                                groupMode == GitDiffGroupMode.byArea
                                    ? GitDiffGroupMode.unified
                                    : GitDiffGroupMode.byArea,
                              ),
                      ),
                      const SizedBox(width: AleraTokens.space2),
                      AleraIconButton(
                        tooltip: filterVisible
                            ? 'Hide File Filter'
                            : 'Search Files',
                        icon: AleraIcons.search,
                        onPressed: busy ? null : onToggleFilter,
                      ),
                      const SizedBox(width: AleraTokens.space2),
                      AleraIconButton(
                        tooltip: allCollapsed ? 'Expand All' : 'Collapse All',
                        icon: allCollapsed
                            ? AleraIcons.expandAll
                            : AleraIcons.collapseAll,
                        onPressed: busy ? null : onToggleCollapseAll,
                      ),
                      const SizedBox(width: AleraTokens.space2),
                      AleraIconButton(
                        tooltip: 'Refresh',
                        icon: AleraIcons.gitRefresh,
                        onPressed: busy ? null : onRefresh,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space8),
          _CommitMessageField(
            controller: messageController,
            focusNode: messageFocusNode,
            enabled: !busy,
            generating: generatingCommitMessage,
            onChanged: (_) => onMessageChanged(),
            onSubmitted: (_) {
              if (canCommit) {
                onPrimaryAction(.commit);
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
          if (data case final state?) ...<Widget>[
            const SizedBox(height: AleraTokens.space6),
            Text(
              _repoSummary(state, sourceControlRootLabel),
              maxLines: 1,
              overflow: .ellipsis,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: AleraTokens.foregroundFaint),
            ),
          ],
          if (filterVisible) ...<Widget>[
            const SizedBox(height: AleraTokens.space8),
            AleraSearchField(
              controller: filterController,
              hintText: 'Filter files...',
              dense: true,
              onChanged: (_) => onFilterChanged(),
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
    if (state.hasStageableChanges) {
      return _SourceControlMenuAction.stageAll;
    }
    return _SourceControlMenuAction.fetch;
  }

  String _repoSummary(
    WorkspaceSourceControlState state,
    String? sourceControlRootLabel,
  ) {
    final repo = state.repositoryState;
    final parts = <String>[?sourceControlRootLabel, repo.branch];
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
      WorkspaceSourceControlAction.amend => 'amending',
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
  amend,
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

class const _AiCommitMessageButton({
  required final bool generating,
  required final bool canGenerate,
  required final VoidCallback onGenerate,
  required final VoidCallback onCancel,
}) extends StatefulWidget {
  @override
  State<_AiCommitMessageButton> createState() => _AiCommitMessageButtonState();
}

class _AiCommitMessageButtonState extends State<_AiCommitMessageButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final showingStop = widget.generating && _hovered;
    final onPressed = widget.generating
        ? widget.onCancel
        : widget.canGenerate
        ? widget.onGenerate
        : null;
    return MouseRegion(
      cursor: onPressed == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.generating
            ? 'Stop generating commit message'
            : 'Generate commit message with AI',
        child: IconButton(
          onPressed: onPressed,
          visualDensity: .compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: 30,
            minHeight: 30,
            maxWidth: 30,
            maxHeight: 30,
          ),
          style: IconButton.styleFrom(
            minimumSize: const Size(30, 30),
            maximumSize: const Size(30, 30),
            tapTargetSize: .shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            ),
          ),
          icon: AnimatedSwitcher(
            duration: AleraTokens.durationFast,
            child: widget.generating && !showingStop
                ? const SizedBox(
                    key: ValueKey<String>('ai-commit-loading'),
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AleraTokens.foregroundMuted,
                    ),
                  )
                : Icon(
                    showingStop ? AleraIcons.stop : AleraIcons.ai,
                    key: ValueKey<String>(
                      showingStop ? 'ai-commit-stop' : 'ai-commit-generate',
                    ),
                    size: 16,
                    color: showingStop
                        ? AleraTokens.error
                        : AleraTokens.foregroundMuted,
                  ),
          ),
        ),
      ),
    );
  }
}

class const _PrimaryActionButton({
  required final _SourceControlMenuAction? action,
  required final bool busy,
  required final WorkspaceSourceControlState? state,
  required final VoidCallback? onPressed,
  required final ValueChanged<_SourceControlMenuAction> onSelected,
}) extends StatelessWidget {
  static const double _height = 28;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    final label = action == null ? 'Fetch' : _actionLabel(action);
    final icon = action == null ? AleraIcons.gitFetch : _actionIcon(action);
    final enabled = onPressed != null && !busy;
    final textStyle = Theme.of(context).textTheme.labelLarge
        ?.copyWith(color: AleraTokens.onAccent);
    final cursor = busy ? SystemMouseCursors.basic : SystemMouseCursors.click;
    return MouseRegion(
      cursor: cursor,
      child: Opacity(
        opacity: enabled || !busy ? 1 : 0.38,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          child: Material(
            color: AleraTokens.accent,
            child: SizedBox(
              height: _height,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: InkWell(
                      mouseCursor: enabled
                          ? SystemMouseCursors.click
                          : SystemMouseCursors.basic,
                      onTap: enabled ? onPressed : null,
                      child: Center(
                        child: Row(
                          mainAxisSize: .min,
                          children: <Widget>[
                            Icon(icon, size: 15, color: AleraTokens.onAccent),
                            const SizedBox(width: AleraTokens.space8),
                            Text(label, style: textStyle),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 0.5,
                    height: 18,
                    color: AleraTokens.onAccent.withValues(alpha: 0.18),
                  ),
                  Tooltip(
                    message: 'Source Control Actions',
                    child: Builder(
                      builder: (context) {
                        return InkWell(
                          mouseCursor: cursor,
                          onTap: busy
                              ? null
                              : () => unawaited(_openMenu(context)),
                          child: const SizedBox(
                            width: 34,
                            height: _height,
                            child: Icon(
                              AleraIcons.chevronDown,
                              size: 17,
                              color: AleraTokens.onAccent,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openMenu(BuildContext context) async {
    final renderBox = context.findRenderObject() as RenderBox;
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (overlay is! RenderBox) {
      return;
    }
    final topLeft = renderBox.localToGlobal(.zero, ancestor: overlay);
    final bottomRight = renderBox.localToGlobal(
      renderBox.size.bottomRight(.zero),
      ancestor: overlay,
    );
    final selected = await showMenu<_SourceControlMenuAction>(
      context: context,
      position: .fromRect(
        .fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      items: _menuEntries(context),
    );
    if (selected != null) {
      onSelected(selected);
    }
  }

  List<PopupMenuEntry<_SourceControlMenuAction>> _menuEntries(
    BuildContext context,
  ) {
    final hasStaged = state?.hasStagedChanges ?? false;
    final hasDiscardable = state?.hasDiscardableChanges ?? false;
    final hasStashable = state?.hasStashableChanges ?? false;
    final hasStashes = state?.stashes.isNotEmpty ?? false;
    final hasConflicts = state?.repositoryState.hasConflicts ?? false;
    final hasUpstream = state?.repositoryState.hasUpstream ?? false;
    final hasHeadCommit = state?.repositoryState.hasHeadCommit ?? false;
    final hasData = state != null;
    final branch = state?.repositoryState.branch;
    final canPublish =
        hasData && !hasUpstream && branch != null && branch != 'HEAD';
    return <PopupMenuEntry<_SourceControlMenuAction>>[
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: .commit,
        label: 'Commit',
        enabled: hasStaged && !hasConflicts,
        leading: const Icon(AleraIcons.gitCommit, size: 16),
      ),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: .commitPush,
        label: 'Commit & Push',
        enabled: hasStaged && !hasConflicts,
        leading: const Icon(AleraIcons.gitPush, size: 16),
      ),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: .commitSync,
        label: 'Commit & Sync',
        enabled: hasStaged && !hasConflicts && hasUpstream,
        leading: const Icon(AleraIcons.gitSync, size: 16),
      ),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: .amend,
        label: 'Commit Amend',
        enabled: hasStaged && !hasConflicts && hasHeadCommit,
        leading: const Icon(AleraIcons.gitAmend, size: 16),
      ),
      const PopupMenuDivider(height: AleraTokens.space8),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: .stageAll,
        label: 'Stage All',
        enabled: state?.hasStageableChanges ?? false,
        leading: const Icon(AleraIcons.gitStage, size: 16),
      ),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: .unstageAll,
        label: 'Unstage All',
        enabled: hasStaged,
        leading: const Icon(AleraIcons.gitUnstage, size: 16),
      ),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: .discardAll,
        label: 'Discard All',
        enabled: hasDiscardable,
        leading: const Icon(AleraIcons.gitDiscard, size: 16),
      ),
      const PopupMenuDivider(height: AleraTokens.space8),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: .fetch,
        label: 'Fetch',
        enabled: hasData,
        leading: const Icon(AleraIcons.gitFetch, size: 16),
      ),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: .pull,
        label: 'Pull',
        enabled: hasData,
        leading: const Icon(AleraIcons.gitPull, size: 16),
      ),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: .push,
        label: 'Push',
        enabled: hasData && !hasConflicts,
        leading: const Icon(AleraIcons.gitPush, size: 16),
      ),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: .sync,
        label: 'Sync',
        enabled: hasData && !hasConflicts && hasUpstream,
        leading: const Icon(AleraIcons.gitSync, size: 16),
      ),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: .publishBranch,
        label: 'Publish Branch',
        enabled: canPublish,
        leading: const Icon(AleraIcons.gitPublish, size: 16),
      ),
      const PopupMenuDivider(height: AleraTokens.space8),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: .stash,
        label: 'Stash',
        enabled: hasStashable,
        leading: const Icon(AleraIcons.gitStash, size: 16),
      ),
      AleraDropdownEntry<_SourceControlMenuAction>(
        value: .stashPop,
        label: 'Stash Pop',
        enabled: hasStashes,
        leading: const Icon(AleraIcons.gitStashPop, size: 16),
      ),
    ];
  }

  String _actionLabel(_SourceControlMenuAction action) {
    return switch (action) {
      _SourceControlMenuAction.commit => 'Commit',
      _SourceControlMenuAction.commitPush => 'Commit & Push',
      _SourceControlMenuAction.commitSync => 'Commit & Sync',
      _SourceControlMenuAction.amend => 'Commit Amend',
      _SourceControlMenuAction.stageAll => 'Stage All',
      _SourceControlMenuAction.unstageAll => 'Unstage All',
      _SourceControlMenuAction.discardAll => 'Discard All',
      _SourceControlMenuAction.fetch => 'Fetch',
      _SourceControlMenuAction.pull => 'Pull',
      _SourceControlMenuAction.push => 'Push',
      _SourceControlMenuAction.sync => 'Sync',
      _SourceControlMenuAction.publishBranch => 'Publish Branch',
      _SourceControlMenuAction.stash => 'Stash',
      _SourceControlMenuAction.stashPop => 'Stash Pop',
      _SourceControlMenuAction.refresh => 'Refresh',
    };
  }

  IconData _actionIcon(_SourceControlMenuAction action) {
    return switch (action) {
      _SourceControlMenuAction.commit => AleraIcons.gitCommit,
      _SourceControlMenuAction.amend => AleraIcons.gitAmend,
      _SourceControlMenuAction.commitPush ||
      _SourceControlMenuAction.push => AleraIcons.gitPush,
      _SourceControlMenuAction.commitSync ||
      _SourceControlMenuAction.sync => AleraIcons.gitSync,
      _SourceControlMenuAction.stageAll => AleraIcons.gitStage,
      _SourceControlMenuAction.unstageAll => AleraIcons.gitUnstage,
      _SourceControlMenuAction.discardAll => AleraIcons.gitDiscard,
      _SourceControlMenuAction.fetch => AleraIcons.gitFetch,
      _SourceControlMenuAction.pull => AleraIcons.gitPull,
      _SourceControlMenuAction.publishBranch => AleraIcons.gitPublish,
      _SourceControlMenuAction.stash => AleraIcons.gitStash,
      _SourceControlMenuAction.stashPop => AleraIcons.gitStashPop,
      _SourceControlMenuAction.refresh => AleraIcons.gitRefresh,
    };
  }
}
