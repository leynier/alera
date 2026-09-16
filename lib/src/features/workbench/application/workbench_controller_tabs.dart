part of 'workbench_controller.dart';

mixin _WorkbenchControllerTabs
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerWorkspacePanel {
  Future<void> closeWorkspaceTab({
    required Workspace workspace,
    required String tabId,
  }) async {
    await closeWorkspaceTabs(workspace: workspace, tabIds: <String>[tabId]);
  }

  Future<void> closeWorkspaceTabs({
    required Workspace workspace,
    required List<String> tabIds,
  }) async {
    final ids = <String>{...tabIds};
    if (ids.isEmpty) {
      return;
    }
    final focusedKeyBeforeClose = state
        .workspacePanelFor(workspace.id)
        .focusedKey;
    final focusedTabId = WorkspacePanel.tabId(focusedKeyBeforeClose);
    final closedFocusedTab = focusedTabId != null && ids.contains(focusedTabId);
    final selectionRevisionBeforeClose =
        _panelSelectionRevisionByWorkspace[workspace.id] ?? 0;
    final sleepGeneration = _workspaceSleepGeneration[workspace.id] ?? 0;
    final closingTabs = <String, WorkspaceTabRecord>{
      for (final tab in state.tabsFor(workspace.id))
        if (ids.contains(tab.id)) tab.id: tab,
    };
    try {
      _closingTabWorkspaceIds.add(workspace.id);
      final closedIds = <String>{};
      Object? closeError;
      StackTrace? closeStack;
      for (final tabId in ids) {
        try {
          await _workspaceTabService.closeTab(tabId);
        } catch (error, stackTrace) {
          closeError = error;
          closeStack = stackTrace;
          break;
        }
        closedIds.add(tabId);
        _closedTabIds.add(tabId);
        final closedTab = closingTabs[tabId];
        if (closedTab != null) {
          await _releaseHostedReviewTab(workspace, closedTab);
        }
        // Every close path must drop the live terminal handle and the editor
        // document, or the xterm scrollback buffer outlives the tab. This is
        // deliberately centralized here: callers used to pair these calls at
        // every site, and the one that forgot leaked the whole emulator.
        ref.read(terminalRuntimeProvider).closeTab(tabId);
        ref.read(editorSessionRegistryProvider).forget(tabId);
      }
      if (_isStaleWorkspaceOpen(workspace.id, sleepGeneration)) {
        _pruneExplorerSessions();
        if (closeError != null) {
          state = state.copyWith(error: closeError.toString());
          Error.throwWithStackTrace(closeError, closeStack ?? StackTrace.current);
        }
        return;
      }
      if (closedIds.isNotEmpty) {
        await _finalizeClosedWorkspaceTabs(
          workspace: workspace,
          closedIds: closedIds,
          closedFocusedTab: closedFocusedTab && closedIds.contains(focusedTabId),
          selectionRevisionBeforeClose: selectionRevisionBeforeClose,
        );
      }
      if (closeError != null) {
        state = state.copyWith(error: closeError.toString());
        Error.throwWithStackTrace(closeError, closeStack ?? StackTrace.current);
      }
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    } finally {
      _closingTabWorkspaceIds.remove(workspace.id);
      if (state.activeWorkspaceId == workspace.id &&
          !_isStaleWorkspaceOpen(workspace.id, sleepGeneration)) {
        _maybeEnsurePrimaryTerminal(workspace);
        _ensureSelectionHasTab();
      }
    }
  }

  Future<void> _finalizeClosedWorkspaceTabs({
    required Workspace workspace,
    required Set<String> closedIds,
    required bool closedFocusedTab,
    required int selectionRevisionBeforeClose,
  }) async {
    final remaining = state
        .tabsFor(workspace.id)
        .where((tab) => !closedIds.contains(tab.id))
        .toList(growable: false);
    if (remaining.isNotEmpty) {
      _setTabsForWorkspace(workspace.id, remaining);
      var panel = state.workspacePanelFor(workspace.id);
      for (final tabId in closedIds) {
        panel = panel.closeKey(WorkspacePanel.tabKey(tabId));
      }
      final remainingIds = <String>{for (final tab in remaining) tab.id};
      final selectionChangedDuringClose =
          (_panelSelectionRevisionByWorkspace[workspace.id] ?? 0) >
          selectionRevisionBeforeClose;
      final liveRecentId = closedFocusedTab && !selectionChangedDuringClose
          ? _tabFocusHistory.mostRecentOpen(workspace.id, remainingIds)
          : null;
      if (liveRecentId != null) {
        panel = panel.select(WorkspacePanel.tabKey(liveRecentId));
      }
      _saveWorkspacePanel(
        workspace.id,
        panel,
        reveal:
            state.activeWorkspaceId == workspace.id &&
            panel.focusedKey != null &&
            panel.treeForKey(panel.focusedKey!) == WorkspacePanelTree.right,
      );
      if (closedFocusedTab &&
          !selectionChangedDuringClose &&
          state.activeWorkspaceId == workspace.id) {
        _focusPanelTerminal(workspace.id, panel.focusedKey);
      }
      _tabFocusHistory.pruneClosed(workspace.id, remainingIds);
      final layout = _layoutForMutation(workspace.id, remaining);
      await _applyLayout(layout, persist: true);
      return;
    }
    _tabFocusHistory.forget(workspace.id);
    _panelSelectionRevisionByWorkspace.remove(workspace.id);
    _setTabsForWorkspace(workspace.id, const <WorkspaceTabRecord>[]);
    final layout = WorkbenchLayout.single(
      workspaceId: workspace.id,
      tabIds: const <String>[],
    );
    await _applyLayout(layout, persist: true);
    final activeTabs = Map<String, String>.from(state.activeTabIdByWorkspace)
      ..remove(workspace.id);
    state = state.copyWith(
      activeWorkspaceId: state.activeWorkspaceId == workspace.id
          ? null
          : state.activeWorkspaceId,
      activeTabIdByWorkspace: activeTabs,
    );
    _pruneExplorerSessions();
  }

  Future<void> renameWorkspaceTab({
    required String tabId,
    required String title,
  }) async {
    try {
      final tab = await _workspaceTabService.renameTab(
        tabId: tabId,
        title: title,
      );
      final tabs = <WorkspaceTabRecord>[
        for (final candidate in state.tabsFor(tab.workspaceId))
          if (candidate.id == tab.id) tab else candidate,
      ];
      _setTabsForWorkspace(tab.workspaceId, tabs);
      state = state.copyWith(error: null);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> syncFileTabsAfterPathMove({
    required Workspace workspace,
    required String oldRelativePath,
    required String newRelativePath,
  }) async {
    try {
      final result = await _workspaceTabService.updateFileTabPathsAfterMove(
        workspaceId: workspace.id,
        oldRelativePath: oldRelativePath,
        newRelativePath: newRelativePath,
      );
      if (result.isEmpty) {
        return;
      }
      final closedIds = result.closedTabIds.toSet();
      final byId = <String, WorkspaceTabRecord>{
        for (final tab in result.updatedTabs) tab.id: tab,
      };
      final tabs = <WorkspaceTabRecord>[
        for (final tab in state.tabsFor(workspace.id))
          if (!closedIds.contains(tab.id)) byId[tab.id] ?? tab,
      ];
      _setTabsForWorkspace(workspace.id, tabs);
      if (closedIds.isNotEmpty) {
        if (tabs.isNotEmpty) {
          var layout = _layoutForMutation(workspace.id, tabs);
          for (final tabId in closedIds) {
            layout = layout.removeTab(tabId);
          }
          await _applyLayout(layout.sanitize(tabs), persist: true);
        } else {
          final layout = WorkbenchLayout.single(
            workspaceId: workspace.id,
            tabIds: const <String>[],
          );
          await _applyLayout(layout, persist: true);
        }
      }
      state = state.copyWith(
        activeWorkspaceId:
            tabs.isEmpty && state.activeWorkspaceId == workspace.id
            ? null
            : state.activeWorkspaceId,
        error: null,
      );
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  void setActiveTab({required String workspaceId, required String tabId}) {
    final layout = state.layoutFor(workspaceId);
    final groupId = layout?.groupIdForTab(tabId);
    _setActiveTabInternal(
      workspaceId: workspaceId,
      tabId: tabId,
      groupId: groupId,
    );
  }

  void setActiveWorkspaceTab({
    required String workspaceId,
    required String groupId,
    required String tabId,
  }) {
    _setActiveTabInternal(
      workspaceId: workspaceId,
      groupId: groupId,
      tabId: tabId,
    );
  }

  /// Promotes [groupId] to the workspace's active group when a pane in it
  /// receives real keyboard focus. Idempotent so it can be wired directly to
  /// focus-change events without risking loops or redundant rebuilds.
  ///
  /// Focus is ephemeral session state, so the new layout is applied in memory
  /// only; the next explicit user action (tab click, split, merge, rename)
  /// will persist the latest layout. This avoids a SQLite write on every
  /// pane click.
  void focusWorkbenchGroup({
    required String workspaceId,
    required String groupId,
  }) {
    final panel = state.workspacePanelFor(workspaceId);
    if (panel.treeForGroup(groupId) == null) {
      return;
    }
    final layout = panel.treeForGroup(groupId) == WorkspacePanelTree.main
        ? panel.ensuredMainLayout(workspaceId)
        : panel.ensuredLayout(workspaceId);
    if (layout.activeGroupId == groupId) {
      return;
    }
    final key = layout.groups[groupId]?.activeTabId;
    if (key == null) {
      return;
    }
    selectWorkspacePanelKey(workspaceId, key, groupId: groupId);
  }

  Future<void> moveWorkspaceTab({
    required String workspaceId,
    required String tabId,
    required String targetGroupId,
    required WorkbenchDropZone zone,
    int? index,
  }) async {
    final panel = state.workspacePanelFor(workspaceId);
    final key = _workspacePaneKey(tabId);
    await moveWorkspacePaneTab(
      workspaceId: workspaceId,
      tabId: tabId,
      targetGroupId: targetGroupId,
      zone: zone,
      index: index,
      source: panel.treeForKey(key) ?? WorkspacePanelTree.right,
      target: panel.treeForGroup(targetGroupId) ?? WorkspacePanelTree.right,
    );
  }

  Future<WorkspaceTabRecord> splitWorkbenchGroupWithTerminal({
    required Workspace workspace,
    required String groupId,
    required WorkbenchDropZone zone,
  }) {
    return splitWorkspacePaneWithTerminal(
      workspace: workspace,
      groupId: groupId,
      zone: zone,
    );
  }

  Future<void> mergeWorkbenchGroupIntoSibling({
    required String workspaceId,
    required String groupId,
  }) async {
    mergeWorkspacePaneIntoSibling(workspaceId: workspaceId, groupId: groupId);
  }

  void updateWorkbenchSplitRatio({
    required String workspaceId,
    required List<int> nodePath,
    required double ratio,
  }) {
    final panel = state.workspacePanelFor(workspaceId);
    final tree =
        panel.treeForKey(panel.focusedKey ?? '') ?? WorkspacePanelTree.right;
    updateWorkspacePaneSplitRatio(
      workspaceId: workspaceId,
      nodePath: nodePath,
      ratio: ratio,
      tree: tree,
    );
  }
}
