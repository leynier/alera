import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_search_field.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/design_system/surfaces/hover_container.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_field_overlay.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_providers.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_service.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/workbench/application/workspace_explorer_reveal.dart';
import 'package:alera/src/features/workbench/application/workspace_source_control_controller.dart';
import 'package:alera/src/features/workbench/application/workspace_submodule_status_provider.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_source_control_scope.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/terminal_path_drop.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_history_graph.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

part 'workspace_git_diff_panel_types.dart';
part 'workspace_git_diff_panel_groups.dart';
part 'workspace_git_diff_panel_rows.dart';
part 'workspace_git_diff_panel_amend_dialog.dart';
part 'workspace_git_diff_panel_stash_dialog.dart';
part 'workspace_git_diff_panel_toolbar.dart';
part 'workspace_git_diff_panel_commit_message_field.dart';
part 'workspace_git_diff_panel_tree.dart';
part 'workspace_git_diff_panel_submodules.dart';
part 'workspace_git_history_panel.dart';
part 'workspace_git_history_panel_graph.dart';
part 'workspace_git_history_panel_row.dart';
part 'workspace_git_history_panel_files.dart';
part 'workspace_git_diff_panel_preview_opening.dart';
part 'workspace_git_diff_panel_context_menu.dart';
part 'workspace_git_diff_panel_inline_actions.dart';
part 'workspace_git_diff_panel_navigation.dart';

class const WorkspaceGitDiffPanel({
  super.key,
  required final Workspace workspace,
  required final WorkspaceSourceControlScope sourceControlScope,
  required final GitDiffViewMode viewMode,
  required final ValueChanged<GitDiffViewMode> onViewModeChanged,
  required final GitDiffGroupMode groupMode,
  required final ValueChanged<GitDiffGroupMode> onGroupModeChanged,
  required final OpenGitDiffTabCallback onOpenGitDiff,
  required final OpenGitCommitDiffTabCallback onOpenGitCommitDiff,
  final ValueChanged<String>? onOpenFile,
  final ValueChanged<String>? onRevealInExplorer,
  final VoidCallback? onClearSourceControlRoot,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<WorkspaceGitDiffPanel> createState() =>
      _WorkspaceGitDiffPanelState();
}

class _WorkspaceGitDiffPanelState extends ConsumerState<WorkspaceGitDiffPanel> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final TextEditingController _filterController = TextEditingController();
  final Set<String> _collapsedSections = <String>{};
  final Set<String> _collapsedTreeNodes = <String>{};
  final Set<String> _expandedSubmodules = <String>{};
  late final AiAssistService _aiAssistService;
  bool _filterVisible = false;
  bool _generatingCommitMessage = false;
  bool _historyCollapsed = true;
  bool _historyDirty = false;
  bool _historyRefreshing = false;
  Future<GitHistoryResult>? _historyFuture;
  GitHistoryResult? _historyResult;
  String? _historyError;
  final Map<String, GitCommitCompareResult> _commitCompareCache =
      <String, GitCommitCompareResult>{};
  int _commitMessageGenerationId = 0;
  final _GitDiffPreviewOpening _previewOpening = _GitDiffPreviewOpening();

  @override
  void initState() {
    super.initState();
    _aiAssistService = ref.read(aiAssistServiceProvider);
  }

  @override
  void didUpdateWidget(covariant WorkspaceGitDiffPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceControlScope.path != widget.sourceControlScope.path) {
      _aiAssistService.cancel(
        oldWidget.sourceControlScope.path,
        .commitMessage,
      );
      _commitMessageGenerationId += 1;
      _messageController.clear();
      _filterController.clear();
      _collapsedSections.clear();
      _collapsedTreeNodes.clear();
      _expandedSubmodules.clear();
      _filterVisible = false;
      _generatingCommitMessage = false;
      _historyCollapsed = true;
      _historyDirty = false;
      _historyFuture = null;
      _historyResult = null;
      _historyError = null;
      _historyRefreshing = false;
      _commitCompareCache.clear();
    }
  }

  @override
  void dispose() {
    _aiAssistService.cancel(widget.sourceControlScope.path, .commitMessage);
    _commitMessageGenerationId += 1;
    _messageController.dispose();
    _messageFocusNode.dispose();
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sourceControlProvider = workspaceSourceControlControllerProvider(
      widget.sourceControlScope.path,
    );
    ref.listen<AsyncValue<WorkspaceSourceControlState>>(sourceControlProvider, (
      previous,
      next,
    ) {
      final previousData = previous?.asData?.value;
      final nextData = next.asData?.value;
      if (previousData == null || nextData == null || nextData.isBusy) {
        return;
      }
      _invalidateGitHistoryAfterRepositoryChange();
    });
    final state = ref.watch(sourceControlProvider);
    final aiAssistSettings = ref.watch(
      settingsControllerProvider.select((settings) => settings.aiAssist),
    );
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        _SourceControlToolbar(
          messageController: _messageController,
          messageFocusNode: _messageFocusNode,
          filterController: _filterController,
          viewMode: widget.viewMode,
          groupMode: widget.groupMode,
          state: state,
          aiAssistSettings: aiAssistSettings,
          generatingCommitMessage: _generatingCommitMessage,
          allCollapsed: _allVisibleNodesCollapsed(state.asData?.value),
          filterVisible: _isFilterVisible,
          sourceControlRootLabel: widget.sourceControlScope.relativeRoot,
          onMessageChanged: () => setState(() {}),
          onGenerateCommitMessage: () => unawaited(_generateCommitMessage()),
          onCancelGenerateCommitMessage: _cancelGenerateCommitMessage,
          onFilterChanged: () => setState(() {}),
          onToggleFilter: _toggleFilterVisibility,
          onRefresh: () => unawaited(_refresh()),
          onClearSourceControlRoot: widget.onClearSourceControlRoot,
          onToggleCollapseAll: () =>
              _toggleAllVisibleNodes(state.asData?.value),
          onViewModeChanged: widget.onViewModeChanged,
          onGroupModeChanged: widget.onGroupModeChanged,
          onOpenAll: () => unawaited(
            widget.onOpenGitDiff(
              scope: .all,
              gitDiffRoot: widget.sourceControlScope.relativeRoot,
            ),
          ),
          onPrimaryAction: (action) => unawaited(_runToolbarAction(action)),
          onSelectMenuAction: (action) => unawaited(_handleMenuAction(action)),
        ),
        const Divider(height: 1, color: AleraTokens.borderSubtle),
        Expanded(
          child: Column(
            children: <Widget>[
              Expanded(
                child: state.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) =>
                      _GitDiffMessage(message: _messageFor(error)),
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
                      groups: _groupsFor(status),
                      workspacePath: widget.sourceControlScope.path,
                      viewMode: widget.viewMode,
                      busy: data.isBusy,
                      collapsedSections: _collapsedSections,
                      collapsedTreeNodes: _collapsedTreeNodes,
                      expandedSubmodules: _expandedSubmodules,
                      onToggleSection: _toggleSectionCollapsed,
                      onToggleTreeNode: _toggleTreeNodeCollapsed,
                      onToggleSubmodule: _toggleSubmodule,
                      onOpenGitDiff: _openGitDiff,
                      onOpenFile: widget.onOpenFile == null
                          ? null
                          : _openWorkspaceFile,
                      onRevealInExplorer: _revealInExplorer,
                      onStage: _stageEntry,
                      onUnstage: _unstageEntry,
                      onDiscard: _discardEntry,
                      onStageArea: _stageArea,
                      onUnstageArea: _unstageArea,
                      onDiscardArea: _discardAreaWithConfirmation,
                      onStagePath: _stage,
                      onUnstagePath: _unstage,
                      onDiscardPath: _discard,
                    );
                  },
                ),
              ),
              _GitHistoryPanel(
                state: _historyPanelState,
                collapsed: _historyCollapsed,
                onToggle: _toggleGitHistory,
                onRefresh: _refreshGitHistory,
                onLoadCommitFiles: _loadCommitFiles,
                onOpenCommit: _openCommitDiff,
                onOpenCommitFile: _openCommitFile,
                onCopyCommitText: _copyCommitText,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _toggleSubmodule(GitChangeEntry entry) {
    setState(() {
      if (!_expandedSubmodules.remove(entry.id)) {
        _expandedSubmodules.add(entry.id);
      }
    });
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
      case _SourceControlMenuAction.amend:
        await _amendAction();
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

  Future<void> _unstage(String? filePath) {
    return _run(() => _notifier.unstage(filePath), successMessage: 'Unstaged');
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
        title: filePath == null ? 'Discard All Changes?' : 'Discard Changes?',
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
        title: 'Discard Changes?',
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
        title: 'Discard Changes?',
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

  Future<void> _generateCommitMessage() async {
    final state = ref
        .read(
          workspaceSourceControlControllerProvider(
            widget.sourceControlScope.path,
          ),
        )
        .asData
        ?.value;
    final settings = ref.read(settingsControllerProvider).aiAssist;
    if (_generatingCommitMessage ||
        state == null ||
        !settings.enabled ||
        !state.hasStagedChanges ||
        state.repositoryState.hasConflicts ||
        state.isBusy) {
      return;
    }
    final requestWorkspacePath = widget.sourceControlScope.path;
    final generationId = _commitMessageGenerationId + 1;
    final initialText = _messageController.text;
    setState(() {
      _commitMessageGenerationId = generationId;
      _generatingCommitMessage = true;
    });
    try {
      final result = await ref
          .read(aiAssistServiceProvider)
          .generate(
            AiAssistRequest(
              operation: .commitMessage,
              workspacePath: requestWorkspacePath,
              settings: settings,
            ),
          );
      if (!mounted) {
        return;
      }
      if (!_isCurrentCommitMessageGeneration(
        workspacePath: requestWorkspacePath,
        generationId: generationId,
      )) {
        return;
      }
      if (_messageController.text == initialText) {
        _messageController.text = result.text;
        _messageController.selection = TextSelection.collapsed(
          offset: _messageController.text.length,
        );
        setState(() {});
        AleraToast.show(
          context,
          message: 'Commit message generated with ${result.agentLabel}',
          tone: .success,
        );
      } else {
        AleraToast.show(
          context,
          message:
              'Generated message was not applied because the field changed.',
          tone: .info,
        );
      }
    } on AiAssistCanceledException {
      return;
    } catch (error) {
      if (_isCurrentCommitMessageGeneration(
        workspacePath: requestWorkspacePath,
        generationId: generationId,
      )) {
        AleraToast.show(context, message: _messageFor(error), tone: .error);
      }
    } finally {
      if (_isCurrentCommitMessageGeneration(
        workspacePath: requestWorkspacePath,
        generationId: generationId,
      )) {
        setState(() => _generatingCommitMessage = false);
      }
    }
  }

  bool _isCurrentCommitMessageGeneration({
    required String workspacePath,
    required int generationId,
  }) {
    return mounted &&
        widget.sourceControlScope.path == workspacePath &&
        _commitMessageGenerationId == generationId;
  }

  void _cancelGenerateCommitMessage() {
    _aiAssistService.cancel(widget.sourceControlScope.path, .commitMessage);
  }

  Future<void> _amendAction() async {
    final state = ref
        .read(
          workspaceSourceControlControllerProvider(
            widget.sourceControlScope.path,
          ),
        )
        .asData
        ?.value;
    final initialMessage = state?.repositoryState.headMessage;
    if (initialMessage == null || initialMessage.trim().isEmpty) {
      return;
    }
    final message = await showDialog<String>(
      context: context,
      builder: (_) => _AmendCommitDialog(initialMessage: initialMessage),
    );
    if (message == null || !mounted) {
      return;
    }
    await _run(
      () => _notifier.amendCommit(message),
      successMessage: 'Commit amended',
    );
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

  List<GitChangeGroup> _groupsFor(GitStatusResult status) {
    if (widget.groupMode == GitDiffGroupMode.unified) {
      return GitChangeGroup.unifiedFromEntries(status.entries);
    }
    return status.effectiveGroups;
  }

  void _toggleSectionCollapsed(String key) {
    setState(() {
      if (!_collapsedSections.add(key)) {
        _collapsedSections.remove(key);
      }
    });
  }

  void _toggleTreeNodeCollapsed(String key) {
    setState(() {
      if (!_collapsedTreeNodes.add(key)) {
        _collapsedTreeNodes.remove(key);
      }
    });
  }

  bool get _isFilterVisible =>
      _filterVisible || _filterController.text.trim().isNotEmpty;

  void _toggleFilterVisibility() {
    setState(() {
      _filterVisible = !_isFilterVisible;
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
    for (final group in _groupsFor(status)) {
      if (group.entries.isEmpty) {
        continue;
      }
      keys.add(_sectionKeyForGroup(group));
      final folderAreaKey = group.unified ? 'unified' : group.area.key;
      for (final row in group.treeRows) {
        if (row.kind == GitChangeTreeRowKind.directory) {
          keys.add('folder:$folderAreaKey:${row.path}');
        }
      }
    }
    return keys;
  }

  Future<bool> _run(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    try {
      await action();
      if (mounted) {
        AleraToast.show(context, message: successMessage, tone: .success);
        _invalidateGitHistoryAfterMutation();
      }
      return true;
    } catch (error) {
      if (mounted) {
        AleraToast.show(context, message: _messageFor(error), tone: .error);
      }
      return false;
    }
  }

  Future<GitStashEntry?> _pickStash() {
    final current = ref
        .read(
          workspaceSourceControlControllerProvider(
            widget.sourceControlScope.path,
          ),
        )
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
    workspaceSourceControlControllerProvider(widget.sourceControlScope.path)
        .notifier,
  );

  _GitHistoryPanelLoadState get _historyPanelState {
    final future = _historyFuture;
    final result = _historyResult;
    if (_historyError case final error?) {
      return _GitHistoryPanelLoadState.error(
        error: error,
        result: result,
        loading: _historyRefreshing,
      );
    }
    if (future != null && result == null) {
      return const _GitHistoryPanelLoadState.loading();
    }
    if (result != null) {
      return _GitHistoryPanelLoadState.ready(
        result: result,
        loading: _historyRefreshing,
      );
    }
    return const _GitHistoryPanelLoadState.idle();
  }

  void _toggleGitHistory() {
    final opening = _historyCollapsed;
    setState(() => _historyCollapsed = !_historyCollapsed);
    if (opening &&
        (_historyDirty || (_historyResult == null && _historyFuture == null))) {
      unawaited(_loadGitHistory());
    }
  }

  void _invalidateGitHistoryAfterMutation() {
    _commitCompareCache.clear();
    if (_historyCollapsed) {
      _markCollapsedHistoryDirty();
      return;
    }
    unawaited(_loadGitHistory());
  }

  void _invalidateGitHistoryAfterRepositoryChange() {
    if (_historyResult == null && _historyFuture == null) {
      return;
    }
    _commitCompareCache.clear();
    if (_historyCollapsed) {
      setState(_markCollapsedHistoryDirty);
      return;
    }
    unawaited(_loadGitHistory());
  }

  void _markCollapsedHistoryDirty() {
    _historyDirty = true;
    _historyFuture = null;
    _historyRefreshing = false;
  }

  Future<void> _refreshGitHistory() async {
    if (_historyCollapsed) {
      setState(() => _historyCollapsed = false);
    }
    await _loadGitHistory();
  }

  Future<void> _loadGitHistory() async {
    final future = ref
        .read(gitBackendProvider)
        .history(widget.sourceControlScope.path, limit: 50);
    setState(() {
      _historyFuture = future;
      _historyError = null;
      _historyRefreshing = _historyResult != null;
    });
    try {
      final result = await future;
      if (!mounted || _historyFuture != future) {
        return;
      }
      setState(() {
        _historyResult = result;
        _historyDirty = false;
        _historyFuture = null;
        _historyRefreshing = false;
        _commitCompareCache.clear();
      });
    } catch (error) {
      if (!mounted || _historyFuture != future) {
        return;
      }
      setState(() {
        _historyError = _messageFor(error);
        _historyFuture = null;
        _historyRefreshing = false;
      });
    }
  }

  Future<List<GitCommitChangeEntry>> _loadCommitFiles(
    GitHistoryItem item,
  ) async {
    final compare = await _commitCompareFor(item);
    return compare.entries;
  }

  Future<void> _openCommitDiff(GitHistoryItem item) async {
    try {
      final compare = await _commitCompareFor(item);
      if (!mounted) {
        return;
      }
      await widget.onOpenGitCommitDiff(
        scope: .all,
        gitDiffRoot: widget.sourceControlScope.relativeRoot,
        commitOid: compare.summary.commitOid,
        parentOid: compare.summary.parentOid,
        compareRef: compare.summary.compareRef,
        subject: item.subject,
        message: item.message,
      );
    } catch (error) {
      if (mounted) {
        AleraToast.show(context, message: _messageFor(error), tone: .error);
      }
    }
  }

  Future<GitCommitCompareResult> _commitCompareFor(GitHistoryItem item) async {
    final cached = _commitCompareCache[item.id];
    if (cached != null) {
      return cached;
    }
    final result = await ref
        .read(gitBackendProvider)
        .commitCompare(path: widget.sourceControlScope.path, commitId: item.id);
    if (result.summary.status != GitCommitCompareStatus.ready) {
      throw GitInternalException(
        result.summary.errorMessage ?? 'Failed to load commit diff.',
      );
    }
    _commitCompareCache[item.id] = result;
    return result;
  }

  Future<void> _copyCommitText(String text, String label) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) {
        return;
      }
      AleraToast.show(context, message: '$label copied', tone: .success);
    } catch (_) {
      if (!mounted) {
        return;
      }
      AleraToast.show(context, message: 'Could not copy $label', tone: .error);
    }
  }
}
