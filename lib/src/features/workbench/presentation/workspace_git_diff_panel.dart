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

part 'workspace_git_diff_panel_groups.dart';
part 'workspace_git_diff_panel_stash_dialog.dart';
part 'workspace_git_diff_panel_toolbar.dart';
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
  final TextEditingController _filterController = TextEditingController();
  final Set<String> _collapsedSections = <String>{};
  final Set<String> _collapsedTreeNodes = <String>{};

  @override
  void didUpdateWidget(covariant WorkspaceGitDiffPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace.path != widget.workspace.path) {
      _messageController.clear();
      _filterController.clear();
      _collapsedSections.clear();
      _collapsedTreeNodes.clear();
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _filterController.dispose();
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
          filterController: _filterController,
          viewMode: widget.viewMode,
          state: state,
          allCollapsed: _allVisibleNodesCollapsed(state.asData?.value),
          onMessageChanged: () => setState(() {}),
          onFilterChanged: () => setState(() {}),
          onRefresh: () => unawaited(_refresh()),
          onToggleCollapseAll: () =>
              _toggleAllVisibleNodes(state.asData?.value),
          onViewModeChanged: widget.onViewModeChanged,
          onOpenAll: () =>
              unawaited(widget.onOpenGitDiff(scope: WorkspaceGitDiffScope.all)),
          onPrimaryAction: (action) => unawaited(_runToolbarAction(action)),
          onSelectMenuAction: (action) => unawaited(_handleMenuAction(action)),
        ),
        const Divider(height: 1, color: AleraTokens.borderSubtle),
        Expanded(
          child: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _GitDiffMessage(message: _messageFor(error)),
            data: (data) {
              final status = _filteredStatus(data.status);
              final entries = status.entries;
              if (entries.isEmpty) {
                return _GitDiffMessage(
                  message: _filterController.text.trim().isEmpty
                      ? 'No changes'
                      : 'No files match the current filter',
                );
              }
              return _GitDiffGroups(
                groups: status.effectiveGroups,
                viewMode: widget.viewMode,
                busy: data.isBusy,
                collapsedSections: _collapsedSections,
                collapsedTreeNodes: _collapsedTreeNodes,
                onToggleSection: _toggleSectionCollapsed,
                onToggleTreeNode: _toggleTreeNodeCollapsed,
                onOpenGitDiff: widget.onOpenGitDiff,
                onStage: _stageEntry,
                onUnstage: _unstageEntry,
                onDiscard: _discardEntry,
                onStageArea: _stageArea,
                onUnstageArea: _unstageArea,
                onDiscardArea: _discardAreaWithConfirmation,
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _refresh() {
    return _run(
      () => _notifier.refresh(),
      successMessage: 'Source control refreshed',
    );
  }

  Future<void> _runToolbarAction(_SourceControlMenuAction action) async {
    if (_actionRequiresMessage(action)) {
      await _commitAction(action);
      return;
    }
    await _handleMenuAction(action);
  }

  Future<void> _handleMenuAction(_SourceControlMenuAction action) async {
    switch (action) {
      case _SourceControlMenuAction.refresh:
        await _refresh();
      case _SourceControlMenuAction.commit:
      case _SourceControlMenuAction.commitPush:
      case _SourceControlMenuAction.commitSync:
        await _commitAction(action);
      case _SourceControlMenuAction.stageAll:
        await _stage(null);
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
      case _SourceControlMenuAction.publishBranch:
        await _run(() => _notifier.push(), successMessage: 'Branch published');
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

  Future<void> _stageArea(GitChangeArea area, String? filePath) {
    return _run(
      () => _notifier.stageArea(area, filePath: filePath),
      successMessage: 'Staged',
    );
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

  Future<void> _unstageArea(GitChangeArea area, String? filePath) {
    return _run(
      () => _notifier.unstageArea(area, filePath: filePath),
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

  Future<void> _discardAreaWithConfirmation(
    GitChangeArea area,
    String? filePath,
  ) async {
    final target = filePath ?? area.label.toLowerCase();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Discard changes?',
        message: 'This permanently discards changes in "$target".',
        confirmLabel: 'Discard',
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _run(
      () => _notifier.discardArea(area, filePath: filePath),
      successMessage: 'Changes discarded',
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

  Future<void> _commitAction(_SourceControlMenuAction action) async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      return;
    }
    final committed = await switch (action) {
      _SourceControlMenuAction.commit => _run(
        () => _notifier.commit(message),
        successMessage: 'Committed',
      ),
      _SourceControlMenuAction.commitPush => _run(
        () => _notifier.commitAndPush(message),
        successMessage: 'Committed and pushed',
      ),
      _SourceControlMenuAction.commitSync => _run(
        () => _notifier.commitAndSync(message),
        successMessage: 'Committed and synced',
      ),
      _ => Future<bool>.value(false),
    };
    if (committed && mounted) {
      _messageController.clear();
      setState(() {});
    }
  }

  bool _actionRequiresMessage(_SourceControlMenuAction action) {
    return switch (action) {
      _SourceControlMenuAction.commit ||
      _SourceControlMenuAction.commitPush ||
      _SourceControlMenuAction.commitSync => true,
      _ => false,
    };
  }

  GitStatusResult _filteredStatus(GitStatusResult status) {
    final query = _filterController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return status;
    }
    final entries = status.entries
        .where((entry) {
          return entry.path.toLowerCase().contains(query) ||
              (entry.oldPath?.toLowerCase().contains(query) ?? false);
        })
        .toList(growable: false);
    return GitStatusResult(
      entries: entries,
      groups: GitChangeGroup.fromEntries(entries),
    );
  }

  void _toggleSectionCollapsed(GitChangeArea area) {
    setState(() {
      final key = _sectionKey(area);
      if (!_collapsedSections.add(key)) {
        _collapsedSections.remove(key);
      }
    });
  }

  void _toggleTreeNodeCollapsed(GitChangeArea area, String path) {
    setState(() {
      final key = _treeNodeKey(area, path);
      if (!_collapsedTreeNodes.add(key)) {
        _collapsedTreeNodes.remove(key);
      }
    });
  }

  bool _allVisibleNodesCollapsed(WorkspaceSourceControlState? state) {
    final keys = _visibleCollapsibleKeys(state);
    return keys.isNotEmpty &&
        keys.every(
          (key) =>
              _collapsedSections.contains(key) ||
              _collapsedTreeNodes.contains(key),
        );
  }

  void _toggleAllVisibleNodes(WorkspaceSourceControlState? state) {
    final keys = _visibleCollapsibleKeys(state);
    if (keys.isEmpty) {
      return;
    }
    setState(() {
      final allCollapsed = keys.every(
        (key) =>
            _collapsedSections.contains(key) ||
            _collapsedTreeNodes.contains(key),
      );
      for (final key in keys) {
        if (key.startsWith('section:')) {
          if (allCollapsed) {
            _collapsedSections.remove(key);
          } else {
            _collapsedSections.add(key);
          }
        } else {
          if (allCollapsed) {
            _collapsedTreeNodes.remove(key);
          } else {
            _collapsedTreeNodes.add(key);
          }
        }
      }
    });
  }

  Set<String> _visibleCollapsibleKeys(WorkspaceSourceControlState? state) {
    if (state == null) {
      return const <String>{};
    }
    final status = _filteredStatus(state.status);
    final keys = <String>{};
    for (final group in status.effectiveGroups) {
      if (group.entries.isEmpty) {
        continue;
      }
      keys.add(_sectionKey(group.area));
      for (final row in group.treeRows) {
        if (row.kind == GitChangeTreeRowKind.directory) {
          keys.add(_treeNodeKey(group.area, row.path));
        }
      }
    }
    return keys;
  }

  String _sectionKey(GitChangeArea area) => 'section:${area.key}';

  String _treeNodeKey(GitChangeArea area, String path) {
    return 'folder:${area.key}:$path';
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
