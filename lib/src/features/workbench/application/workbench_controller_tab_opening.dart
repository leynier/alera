part of 'workbench_controller.dart';

/// Opening tabs: every entry point that adds a tab to a workspace.
///
/// Split out of `workbench_controller_tabs.dart`, which keeps the lifecycle of
/// tabs that already exist: closing, renaming, moving and splitting.
mixin _WorkbenchControllerTabOpening
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerWorkspacePanel,
        _WorkbenchControllerWorkspacePanelPanes {
  Future<WorkspaceTabRecord> createTerminalTab(
    Workspace workspace, {
    String? targetGroupId,
    String? title,
    String? initialCommand,
    bool spawnOnCreate = false,
    bool initialCommandOnce = false,
    bool autoCloseOnSuccess = false,
  }) async {
    try {
      final sleepGeneration = _workspaceSleepGeneration[workspace.id] ?? 0;
      final tab = await _workspaceTabService.createTerminalTab(
        workspace.id,
        title: title,
        initialCommand: initialCommand,
        spawnOnCreate: spawnOnCreate,
        initialCommandOnce: initialCommandOnce,
        autoCloseOnSuccess: autoCloseOnSuccess,
      );
      if (_isStaleWorkspaceOpen(workspace.id, sleepGeneration) ||
          _isClosedTabId(tab.id)) {
        await _discardStalePrimaryTerminal(workspace, tab);
        throw StateError('Workspace is no longer available for a new terminal');
      }
      final live = state
          .tabsFor(workspace.id)
          .where((existing) => existing.id != tab.id)
          .toList(growable: false);
      final tabs = <WorkspaceTabRecord>[...live, tab];
      _setTabsForWorkspace(workspace.id, tabs);
      addTerminalToWorkspacePanel(
        workspaceId: workspace.id,
        tab: tab,
        tabs: tabs,
        previousTabs: live,
        targetGroupId: targetGroupId,
      );
      if (state.activeWorkspaceId == workspace.id) {
        ref
            .read(terminalRuntimeProvider)
            .sessionFor(workspace: workspace, tab: tab)
            .requestFocus();
      }
      ref
          .read(workspaceActivityControllerProvider.notifier)
          .recordActivity(workspace.id, DateTime.now().toUtc());
      state = state.copyWith(error: null);
      return tab;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  /// Opens the "Setup" terminal for a workspace whose worktree setup the host
  /// prepared instead of running, so a long `pnpm install` is visible work
  /// rather than a spinner on the create dialog.
  ///
  /// A failure here does not fail the creation: the workspace exists and the
  /// setup can be run by hand, so it is reported as an error on the state
  /// instead of unwinding the flow.
  Future<void> _openDeferredSetupTab(WorkspaceCreationResult result) async {
    final command = result.deferredSetupCommand?.trim();
    if (command == null || command.isEmpty) {
      return;
    }
    try {
      await createTerminalTab(
        result.workspace,
        title: 'Setup',
        initialCommand: command,
        spawnOnCreate: true,
        initialCommandOnce: true,
        autoCloseOnSuccess: true,
      );
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<WorkspaceTabRecord> openMermanPreviewTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
  }) async {
    try {
      final sleepGeneration = _workspaceSleepGeneration[workspace.id] ?? 0;
      final previousIds = <String>{
        for (final candidate in state.tabsFor(workspace.id)) candidate.id,
      };
      final tab = await _workspaceTabService.openOrCreateMermanPreviewTab(
        workspaceId: workspace.id,
        relativePath: relativePath,
      );
      final existedBeforeRequest = previousIds.contains(tab.id);
      if (_isStaleWorkspaceOpen(workspace.id, sleepGeneration) ||
          _isClosedTabId(tab.id)) {
        await _discardStaleOpenedTab(
          tab,
          existedBeforeRequest: existedBeforeRequest && !_isClosedTabId(tab.id),
        );
        throw StateError('Workspace is no longer available for a preview tab');
      }
      final live = state.tabsFor(workspace.id);
      final tabs =
          existedBeforeRequest ||
              live.any((candidate) => candidate.id == tab.id)
          ? live
                .map((candidate) => candidate.id == tab.id ? tab : candidate)
                .toList(growable: false)
          : <WorkspaceTabRecord>[...live, tab];
      _setTabsForWorkspace(workspace.id, tabs);
      _selectOpenedWorkspaceTab(
        workspaceId: workspace.id,
        tab: tab,
        existedBeforeRequest: existedBeforeRequest,
        targetGroupId: targetGroupId,
      );
      final persisted = _layoutForMutation(workspace.id, tabs);
      state = state.copyWith(
        layoutByWorkspace: <String, WorkbenchLayout>{
          ...state.layoutByWorkspace,
          workspace.id: persisted,
        },
        error: null,
      );
      _persistLayoutInBackground(persisted);
      return tab;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }
}
