part of 'workspace_git_diff_panel.dart';

extension on _WorkspaceGitDiffPanelState {
  Widget _buildScrollablePanel({
    required AsyncValue<WorkspaceSourceControlState> state,
    required AiAssistSettings aiAssistSettings,
  }) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Column(
            mainAxisSize: .min,
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
                onMessageChanged: _markDirty,
                onGenerateCommitMessage: () =>
                    unawaited(_generateCommitMessage()),
                onCancelGenerateCommitMessage: _cancelGenerateCommitMessage,
                onFilterChanged: _markDirty,
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
                onPrimaryAction: (action) =>
                    unawaited(_runToolbarAction(action)),
                onSelectMenuAction: (action) =>
                    unawaited(_handleMenuAction(action)),
                onSelectBranch: () => unawaited(_openBranchSwitcher()),
              ),
              const Divider(height: 1, color: AleraTokens.borderSubtle),
              WorkspaceAgentCommentDraftScope(workspaceId: widget.workspace.id),
            ],
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                children: <Widget>[
                  Expanded(child: _buildChangesList(state)),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.min(
                        constraints.maxHeight,
                        math.max(
                          AleraTokens.sidebarHeaderHeight +
                              (_historyCollapsed ? 1.0 : AleraTokens.space6),
                          constraints.maxHeight * 0.55,
                        ),
                      ),
                    ),
                    child: _GitHistoryPanel(
                      state: _historyPanelState,
                      collapsed: _historyCollapsed,
                      onToggle: _toggleGitHistory,
                      onRefresh: _refreshGitHistory,
                      onLoadCommitFiles: _loadCommitFiles,
                      onOpenCommit: _openCommitDiff,
                      onOpenCommitFile: _openCommitFile,
                      onCopyCommitText: _copyCommitText,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChangesList(AsyncValue<WorkspaceSourceControlState> state) {
    return state.when(
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
          onOpenFile: widget.onOpenFile == null ? null : _openWorkspaceFile,
          onComment: _commentOnChange,
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
    );
  }
}
