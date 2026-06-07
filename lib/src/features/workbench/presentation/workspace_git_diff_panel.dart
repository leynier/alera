import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/workbench/application/workspace_source_control_controller.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'workspace_git_diff_panel_tree.dart';

typedef OpenGitDiffTabCallback =
    Future<void> Function({
      String? relativePath,
      GitChangeArea? area,
      required WorkspaceGitDiffScope scope,
    });

class WorkspaceGitDiffPanel extends ConsumerStatefulWidget {
  const WorkspaceGitDiffPanel({
    super.key,
    required this.workspace,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.onOpenGitDiff,
  });

  final Workspace workspace;
  final GitDiffViewMode viewMode;
  final ValueChanged<GitDiffViewMode> onViewModeChanged;
  final OpenGitDiffTabCallback onOpenGitDiff;

  @override
  ConsumerState<WorkspaceGitDiffPanel> createState() =>
      _WorkspaceGitDiffPanelState();
}

class _WorkspaceGitDiffPanelState extends ConsumerState<WorkspaceGitDiffPanel> {
  final TextEditingController _messageController = TextEditingController();

  @override
  void didUpdateWidget(covariant WorkspaceGitDiffPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace.path != widget.workspace.path) {
      _messageController.clear();
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      workspaceSourceControlControllerProvider(widget.workspace.path),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SourceControlToolbar(
          messageController: _messageController,
          viewMode: widget.viewMode,
          state: state,
          onMessageChanged: () => setState(() {}),
          onViewModeChanged: widget.onViewModeChanged,
          onOpenAll: () =>
              unawaited(widget.onOpenGitDiff(scope: WorkspaceGitDiffScope.all)),
          onStageAll: () => unawaited(_stage(null)),
          onCommit: () => unawaited(_commit()),
          onSelectMenuAction: (action) => unawaited(_handleMenuAction(action)),
        ),
        const Divider(height: 1, color: AleraTokens.borderSubtle),
        Expanded(
          child: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _GitDiffMessage(message: _messageFor(error)),
            data: (data) {
              final entries = data.status.entries;
              if (entries.isEmpty) {
                return const _GitDiffMessage(message: 'No changes');
              }
              return _GitDiffGroups(
                groups: data.status.effectiveGroups,
                viewMode: widget.viewMode,
                busy: data.isBusy,
                onOpenGitDiff: widget.onOpenGitDiff,
                onStage: _stageEntry,
                onUnstage: _unstageEntry,
                onDiscard: _discardEntry,
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _handleMenuAction(_SourceControlMenuAction action) async {
    switch (action) {
      case _SourceControlMenuAction.refresh:
        await _run(
          () => _notifier.refresh(),
          successMessage: 'Source Control refreshed',
        );
      case _SourceControlMenuAction.unstageAll:
        await _run(() => _notifier.unstage(null), successMessage: 'Unstaged');
      case _SourceControlMenuAction.discardAll:
        await _discard(null);
      case _SourceControlMenuAction.fetch:
        await _run(() => _notifier.fetch(), successMessage: 'Fetched');
      case _SourceControlMenuAction.pull:
        await _run(() => _notifier.pull(), successMessage: 'Pulled');
      case _SourceControlMenuAction.push:
        await _run(() => _notifier.push(), successMessage: 'Pushed');
      case _SourceControlMenuAction.sync:
        await _run(() => _notifier.sync(), successMessage: 'Synced');
      case _SourceControlMenuAction.stash:
        await _run(() => _notifier.stash(), successMessage: 'Stashed');
      case _SourceControlMenuAction.stashPop:
        final stash = await _pickStash();
        if (stash == null) {
          return;
        }
        await _run(
          () => _notifier.stashPop(stash.index),
          successMessage: 'Stash popped',
        );
    }
  }

  Future<void> _stage(String? filePath) {
    return _run(() => _notifier.stage(filePath), successMessage: 'Staged');
  }

  Future<void> _stageEntry(GitChangeEntry entry) {
    return _run(() => _notifier.stageEntry(entry), successMessage: 'Staged');
  }

  Future<void> _unstageEntry(GitChangeEntry entry) {
    return _run(
      () => _notifier.unstageEntry(entry),
      successMessage: 'Unstaged',
    );
  }

  Future<void> _discard(String? filePath) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: filePath == null ? 'Discard all changes?' : 'Discard changes?',
        message: filePath == null
            ? 'This permanently discards unstaged and untracked changes in this workspace.'
            : 'This permanently discards unstaged and untracked changes in "$filePath".',
        confirmLabel: 'Discard',
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _run(
      () => _notifier.discard(filePath),
      successMessage: filePath == null
          ? 'Changes discarded'
          : 'Change discarded',
    );
  }

  Future<void> _discardEntry(GitChangeEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Discard changes?',
        message:
            'This permanently discards unstaged and untracked changes in "${entry.path}".',
        confirmLabel: 'Discard',
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _run(
      () => _notifier.discardEntry(entry),
      successMessage: 'Change discarded',
    );
  }

  Future<void> _commit() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      return;
    }
    final committed = await _run(
      () => _notifier.commit(message),
      successMessage: 'Committed',
    );
    if (committed && mounted) {
      _messageController.clear();
      setState(() {});
    }
  }

  Future<bool> _run(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    try {
      await action();
      if (mounted) {
        AleraToast.show(
          context,
          message: successMessage,
          tone: AleraToastTone.success,
        );
      }
      return true;
    } catch (error) {
      if (mounted) {
        AleraToast.show(
          context,
          message: _messageFor(error),
          tone: AleraToastTone.error,
        );
      }
      return false;
    }
  }

  Future<GitStashEntry?> _pickStash() {
    final current = ref
        .read(workspaceSourceControlControllerProvider(widget.workspace.path))
        .asData
        ?.value;
    final stashes = current?.stashes ?? const <GitStashEntry>[];
    if (stashes.isEmpty) {
      AleraToast.show(context, message: 'No stashes to pop');
      return Future<GitStashEntry?>.value();
    }
    return showDialog<GitStashEntry>(
      context: context,
      builder: (_) => _StashPickerDialog(stashes: stashes),
    );
  }

  WorkspaceSourceControlController get _notifier => ref.read(
    workspaceSourceControlControllerProvider(widget.workspace.path).notifier,
  );

  String _messageFor(Object? error) {
    if (error is NotARepositoryException) {
      return 'This workspace is not a Git repository.';
    }
    if (error is DetachedHeadException) {
      return 'Cannot push from detached HEAD.';
    }
    if (error is RemoteNotFoundException) {
      return 'Remote origin was not found.';
    }
    if (error is NothingToCommitException) {
      return 'Nothing to commit.';
    }
    if (error is GitConflictException) {
      return 'Resolve conflicts before continuing.';
    }
    if (error is GitException && error.context.trim().isNotEmpty) {
      return error.context;
    }
    return 'Git operation failed.';
  }
}

class _SourceControlToolbar extends StatelessWidget {
  const _SourceControlToolbar({
    required this.messageController,
    required this.viewMode,
    required this.state,
    required this.onMessageChanged,
    required this.onViewModeChanged,
    required this.onOpenAll,
    required this.onStageAll,
    required this.onCommit,
    required this.onSelectMenuAction,
  });

  final TextEditingController messageController;
  final GitDiffViewMode viewMode;
  final AsyncValue<WorkspaceSourceControlState> state;
  final VoidCallback onMessageChanged;
  final ValueChanged<GitDiffViewMode> onViewModeChanged;
  final VoidCallback onOpenAll;
  final VoidCallback onStageAll;
  final VoidCallback onCommit;
  final ValueChanged<_SourceControlMenuAction> onSelectMenuAction;

  @override
  Widget build(BuildContext context) {
    final data = state.asData?.value;
    final busy = state.isLoading || (data?.isBusy ?? false);
    final hasChanges = data?.hasChanges ?? false;
    final hasStagedChanges = data?.hasStagedChanges ?? false;
    final hasConflicts = data?.repositoryState.hasConflicts ?? false;
    final canCommit =
        !busy &&
        !hasConflicts &&
        hasStagedChanges &&
        messageController.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Source Control',
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
              _SourceControlMenuButton(
                busy: busy,
                state: data,
                onSelected: onSelectMenuAction,
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space8),
          AleraTextField(
            controller: messageController,
            hintText: 'Message',
            dense: true,
            enabled: !busy,
            onChanged: (_) => onMessageChanged(),
            onSubmitted: (_) {
              if (canCommit) {
                onCommit();
              }
            },
          ),
          const SizedBox(height: AleraTokens.space8),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: !busy && hasChanges ? onStageAll : null,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Stage all'),
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              FilledButton(
                onPressed: canCommit ? onCommit : null,
                child: const Text('Commit'),
              ),
            ],
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
  unstageAll,
  discardAll,
  fetch,
  pull,
  push,
  sync,
  stash,
  stashPop,
}

class _SourceControlMenuButton extends StatelessWidget {
  const _SourceControlMenuButton({
    required this.busy,
    required this.state,
    required this.onSelected,
  });

  final bool busy;
  final WorkspaceSourceControlState? state;
  final ValueChanged<_SourceControlMenuAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final hasStaged = state?.hasStagedChanges ?? false;
    final hasDiscardable = state?.hasUnstagedOrUntrackedChanges ?? false;
    final hasStashable = state?.hasStashableChanges ?? false;
    final hasStashes = state?.stashes.isNotEmpty ?? false;
    final hasConflicts = state?.repositoryState.hasConflicts ?? false;
    final hasUpstream = state?.repositoryState.hasUpstream ?? false;
    final hasData = state != null;
    return PopupMenuButton<_SourceControlMenuAction>(
      tooltip: 'More actions',
      enabled: !busy,
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: onSelected,
      itemBuilder: (context) => <PopupMenuEntry<_SourceControlMenuAction>>[
        const AleraDropdownEntry<_SourceControlMenuAction>(
          value: _SourceControlMenuAction.refresh,
          label: 'Refresh',
          leading: Icon(Icons.refresh, size: 16),
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
      ],
    );
  }
}

class _StashPickerDialog extends StatelessWidget {
  const _StashPickerDialog({required this.stashes});

  final List<GitStashEntry> stashes;

  @override
  Widget build(BuildContext context) {
    return AleraDialog(
      maxWidth: 460,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Stash pop', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: stashes.length,
                itemBuilder: (context, index) {
                  final stash = stashes[index];
                  return ListTile(
                    dense: true,
                    title: Text(
                      stash.reference,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      stash.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.of(context).pop(stash),
                  );
                },
              ),
            ),
            const SizedBox(height: AleraTokens.space12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GitDiffGroups extends StatelessWidget {
  const _GitDiffGroups({
    required this.groups,
    required this.viewMode,
    required this.busy,
    required this.onOpenGitDiff,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
  });

  final List<GitChangeGroup> groups;
  final GitDiffViewMode viewMode;
  final bool busy;
  final OpenGitDiffTabCallback onOpenGitDiff;
  final ValueChanged<GitChangeEntry> onStage;
  final ValueChanged<GitChangeEntry> onUnstage;
  final ValueChanged<GitChangeEntry> onDiscard;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space6),
      children: <Widget>[
        for (final group in groups)
          _GitDiffGroup(
            group: group,
            viewMode: viewMode,
            busy: busy,
            onOpenGitDiff: onOpenGitDiff,
            onStage: onStage,
            onUnstage: onUnstage,
            onDiscard: onDiscard,
          ),
      ],
    );
  }
}

class _GitDiffGroup extends StatelessWidget {
  const _GitDiffGroup({
    required this.group,
    required this.viewMode,
    required this.busy,
    required this.onOpenGitDiff,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
  });

  final GitChangeGroup group;
  final GitDiffViewMode viewMode;
  final bool busy;
  final OpenGitDiffTabCallback onOpenGitDiff;
  final ValueChanged<GitChangeEntry> onStage;
  final ValueChanged<GitChangeEntry> onUnstage;
  final ValueChanged<GitChangeEntry> onDiscard;

  @override
  Widget build(BuildContext context) {
    if (group.entries.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space8,
              vertical: AleraTokens.space4,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    group.area.label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
                Text(
                  '${group.entries.length}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundFaint,
                  ),
                ),
              ],
            ),
          ),
          if (viewMode == GitDiffViewMode.flat)
            for (final entry in group.entries)
              _GitDiffFileRow(
                entry: entry,
                depth: 0,
                showRelativePath: true,
                busy: busy,
                onStage: onStage,
                onUnstage: onUnstage,
                onDiscard: onDiscard,
                onTap: () => unawaited(
                  onOpenGitDiff(
                    relativePath: entry.path,
                    area: entry.area,
                    scope: WorkspaceGitDiffScope.file,
                  ),
                ),
              )
          else
            _GitDiffTree(
              rows: group.treeRows,
              busy: busy,
              onOpenGitDiff: onOpenGitDiff,
              onStage: onStage,
              onUnstage: onUnstage,
              onDiscard: onDiscard,
            ),
        ],
      ),
    );
  }
}

class _GitDiffMessage extends StatelessWidget {
  const _GitDiffMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space16),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundMuted),
        ),
      ),
    );
  }
}
