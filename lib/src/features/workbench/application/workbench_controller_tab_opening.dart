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

  Future<WorkspaceTabRecord> openMobileEmulatorTab({
    required Workspace workspace,
    MobileEmulatorPlatform? platform,
    String? deviceId,
    String? targetGroupId,
  }) async {
    try {
      final previousTabs = state.tabsFor(workspace.id);
      final layout = _layoutForMutation(workspace.id, previousTabs);
      for (final tab in previousTabs) {
        if (tab.kind != WorkspaceTabKind.mobileEmulator) {
          continue;
        }
        final visibleLayout =
            state.layoutFor(workspace.id)?.groupIdForTab(tab.id) == null
            ? _layoutForMutation(
                workspace.id,
                previousTabs
                    .where((candidate) => candidate.id != tab.id)
                    .toList(growable: false),
              )
            : layout;
        await _showMobileEmulatorTab(
          layout: visibleLayout,
          tabs: previousTabs,
          tab: tab,
          targetGroupId: targetGroupId,
        );
        state = state.copyWith(error: null);
        return tab;
      }
      if (platform == null || deviceId == null || deviceId.trim().isEmpty) {
        throw StateError('Select a mobile emulator device.');
      }
      final attachment = await _mobileEmulatorService.attach(
        workspaceId: workspace.id,
        platform: platform,
        deviceId: deviceId,
      );
      final tab = attachment.tab;
      final tabs = <WorkspaceTabRecord>[...previousTabs, tab];
      _setTabsForWorkspace(workspace.id, tabs);
      await _showMobileEmulatorTab(
        layout: layout,
        tabs: tabs,
        tab: tab,
        targetGroupId: targetGroupId,
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

  Future<void> _showMobileEmulatorTab({
    required WorkbenchLayout layout,
    required List<WorkspaceTabRecord> tabs,
    required WorkspaceTabRecord tab,
    String? targetGroupId,
  }) async {
    final existingGroupId = layout.groupIdForTab(tab.id);
    if (existingGroupId != null) {
      await _applyLayout(
        layout.setActiveTab(groupId: existingGroupId, tabId: tab.id),
        persist: true,
      );
      return;
    }
    final sourceGroupId =
        targetGroupId != null && layout.groups.containsKey(targetGroupId)
        ? targetGroupId
        : layout.activeGroupId;
    final group = WorkbenchPaneGroup(
      id: _newPaneGroupId(),
      tabIds: <String>[tab.id],
      activeTabId: tab.id,
    );
    await _applyLayout(
      layout
          .splitWithGroup(
            targetGroupId: sourceGroupId,
            zone: WorkbenchDropZone.right,
            newGroup: group,
          )
          .sanitize(tabs),
      persist: true,
    );
  }

  Future<WorkspaceTabRecord> openEditorTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
  }) async {
    return _openFileBackedTab(
      workspace: workspace,
      relativePath: relativePath,
      targetGroupId: targetGroupId,
      createTab: _workspaceTabService.openOrCreateEditorTab,
    );
  }

  Future<WorkspaceTabRecord> openMarkdownViewerTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
  }) async {
    return _openFileBackedTab(
      workspace: workspace,
      relativePath: relativePath,
      targetGroupId: targetGroupId,
      createTab: _workspaceTabService.openOrCreateMarkdownViewerTab,
    );
  }

  Future<WorkspaceTabRecord> openPdfTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
  }) async {
    return _openFileBackedTab(
      workspace: workspace,
      relativePath: relativePath,
      targetGroupId: targetGroupId,
      createTab: _workspaceTabService.openOrCreatePdfTab,
    );
  }

  Future<WorkspaceTabRecord> openFileTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
  }) {
    if (isWorkspaceMarkdownFilePath(relativePath)) {
      return openMarkdownViewerTab(
        workspace: workspace,
        relativePath: relativePath,
        targetGroupId: targetGroupId,
      );
    }
    return isWorkspacePdfFilePath(relativePath)
        ? openPdfTab(
            workspace: workspace,
            relativePath: relativePath,
            targetGroupId: targetGroupId,
          )
        : openEditorTab(
            workspace: workspace,
            relativePath: relativePath,
            targetGroupId: targetGroupId,
          );
  }

  Future<WorkspaceTabRecord> _openFileBackedTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
    required Future<WorkspaceTabRecord> Function({
      required String workspaceId,
      required String relativePath,
    })
    createTab,
  }) async {
    try {
      final previousTabs = state.tabsFor(workspace.id);
      final layout = _layoutForMutation(workspace.id, previousTabs);
      final tab = await createTab(
        workspaceId: workspace.id,
        relativePath: relativePath,
      );
      final alreadyOpen = previousTabs.any(
        (candidate) => candidate.id == tab.id,
      );
      final tabs = alreadyOpen
          ? previousTabs
                .map((candidate) => candidate.id == tab.id ? tab : candidate)
                .toList(growable: false)
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

  Future<WorkspaceTabRecord> openGitDiffTab({
    required Workspace workspace,
    String? relativePath,
    GitChangeArea? area,
    required WorkspaceGitDiffScope scope,
    String? gitDiffRoot,
    String? targetGroupId,
  }) async {
    try {
      final previousTabs = state.tabsFor(workspace.id);
      final layout = _layoutForMutation(workspace.id, previousTabs);
      final tab = await _workspaceTabService.openOrCreateGitDiffTab(
        workspaceId: workspace.id,
        relativePath: relativePath,
        area: area,
        scope: scope,
        gitDiffRoot: gitDiffRoot,
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

  Future<WorkspaceTabRecord> openGitCommitDiffTab({
    required Workspace workspace,
    String? relativePath,
    String? oldPath,
    required WorkspaceGitDiffScope scope,
    String? gitDiffRoot,
    required String commitOid,
    String? parentOid,
    required String compareRef,
    String? subject,
    String? message,
    String? targetGroupId,
  }) async {
    try {
      final previousTabs = state.tabsFor(workspace.id);
      final layout = _layoutForMutation(workspace.id, previousTabs);
      final tab = await _workspaceTabService.openOrCreateGitCommitDiffTab(
        workspaceId: workspace.id,
        relativePath: relativePath,
        oldPath: oldPath,
        scope: scope,
        gitDiffRoot: gitDiffRoot,
        commitOid: commitOid,
        parentOid: parentOid,
        compareRef: compareRef,
        subject: subject,
        message: message,
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
