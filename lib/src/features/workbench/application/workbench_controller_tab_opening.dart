part of 'workbench_controller.dart';

/// Opening tabs: every entry point that adds a tab to a workspace.
///
/// Split out of `workbench_controller_tabs.dart`, which keeps the lifecycle of
/// tabs that already exist: closing, renaming, moving and splitting.
mixin _WorkbenchControllerTabOpening
    on _$WorkbenchController, _WorkbenchControllerInternals {
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
      final previousTabs = state.tabsFor(workspace.id);
      final layout = _layoutForMutation(workspace.id, previousTabs);
      final tab = await _workspaceTabService.createTerminalTab(
        workspace.id,
        title: title,
        initialCommand: initialCommand,
        spawnOnCreate: spawnOnCreate,
        initialCommandOnce: initialCommandOnce,
        autoCloseOnSuccess: autoCloseOnSuccess,
      );
      final tabs = <WorkspaceTabRecord>[...previousTabs, tab];
      _setTabsForWorkspace(workspace.id, tabs);
      final groupId = targetGroupId ?? layout.activeGroupId;
      final nextLayout = layout.addTabToGroup(groupId: groupId, tabId: tab.id);
      await _applyLayout(nextLayout.sanitize(tabs), persist: true);
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

  Future<WorkspaceTabRecord> createBrowserTab(
    Workspace workspace, {
    String? targetGroupId,
    String? pageId,
    String profileId = 'default',
    String? initialUrl,
  }) async {
    try {
      final previousTabs = state.tabsFor(workspace.id);
      final layout = _layoutForMutation(workspace.id, previousTabs);
      final tab = await _workspaceBrowserTabService.createTab(
        workspace.id,
        pageId: pageId,
        profileId: profileId,
        initialUrl: initialUrl,
      );
      final tabs = <WorkspaceTabRecord>[...previousTabs, tab];
      _setTabsForWorkspace(workspace.id, tabs);
      final groupId = targetGroupId ?? layout.activeGroupId;
      final nextLayout = layout.addTabToGroup(groupId: groupId, tabId: tab.id);
      await _applyLayout(nextLayout.sanitize(tabs), persist: true);
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

  Future<WorkspaceTabRecord> createCodexTab(
    Workspace workspace, {
    String? targetGroupId,
  }) async {
    try {
      final previousTabs = state.tabsFor(workspace.id);
      final layout = _layoutForMutation(workspace.id, previousTabs);
      final tab = await _workspaceTabService.createCodexTab(workspace.id);
      final tabs = <WorkspaceTabRecord>[...previousTabs, tab];
      _setTabsForWorkspace(workspace.id, tabs);
      final groupId = targetGroupId ?? layout.activeGroupId;
      await _applyLayout(
        layout.addTabToGroup(groupId: groupId, tabId: tab.id).sanitize(tabs),
        persist: true,
      );
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

  Future<WorkspaceTabRecord> openMermanPreviewTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
  }) async {
    try {
      final previousTabs = state.tabsFor(workspace.id);
      final layout = _layoutForMutation(workspace.id, previousTabs);
      final tab = await _workspaceTabService.openOrCreateMermanPreviewTab(
        workspaceId: workspace.id,
        relativePath: relativePath,
      );
      final alreadyOpen = previousTabs.any(
        (candidate) => candidate.id == tab.id,
      );
      final tabs = alreadyOpen
          ? previousTabs
          : <WorkspaceTabRecord>[...previousTabs, tab];
      _setTabsForWorkspace(workspace.id, tabs);
      final groupId = targetGroupId ?? layout.activeGroupId;
      final nextLayout = alreadyOpen
          ? layout.setActiveTab(
              groupId: layout.groupIdForTab(tab.id) ?? groupId,
              tabId: tab.id,
            )
          : layout.addTabToGroup(groupId: groupId, tabId: tab.id);
      await _applyLayout(nextLayout.sanitize(tabs), persist: true);
      state = state.copyWith(error: null);
      return tab;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }
}
