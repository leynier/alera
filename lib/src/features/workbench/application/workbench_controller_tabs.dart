part of 'workbench_controller.dart';

mixin _WorkbenchControllerTabs
    on _$WorkbenchController, _WorkbenchControllerInternals {
  Future<WorkspaceTabRecord> createTerminalTab(
    Workspace workspace, {
    String? targetGroupId,
  }) async {
    try {
      final previousTabs = state.tabsFor(workspace.id);
      final layout = _layoutForMutation(workspace.id, previousTabs);
      final tab = await _workspaceTabService.createTerminalTab(workspace.id);
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
    // Capture before closing: the tab watcher can sanitise the layout (and
    // replace the active tab) synchronously while the close is in flight.
    final priorActiveTabId = state.layoutFor(workspace.id)?.activeTabId;
    final closedActiveTab =
        priorActiveTabId != null && ids.contains(priorActiveTabId);
    try {
      _closingTabWorkspaceIds.add(workspace.id);
      for (final tabId in ids) {
        await _workspaceTabService.closeTab(tabId);
      }
      final remaining = state
          .tabsFor(workspace.id)
          .where((tab) => !ids.contains(tab.id))
          .toList(growable: false);
      if (remaining.isNotEmpty) {
        _setTabsForWorkspace(workspace.id, remaining);
        var layout = _layoutForMutation(workspace.id, remaining);
        for (final tabId in ids) {
          layout = layout.removeTab(tabId);
        }
        layout = layout.sanitize(remaining);
        if (closedActiveTab) {
          final openTabIds = <String>{for (final tab in remaining) tab.id};
          final mruTabId = _mostRecentlyFocusedOpenTab(
            workspace.id,
            openTabIds,
          );
          final mruGroupId = mruTabId == null
              ? null
              : layout.groupIdForTab(mruTabId);
          if (mruTabId != null && mruGroupId != null) {
            layout = layout.setActiveTab(groupId: mruGroupId, tabId: mruTabId);
          }
        }
        await _applyLayout(layout, persist: true);
      } else {
        _tabFocusHistoryByWorkspace.remove(workspace.id);
        _setTabsForWorkspace(workspace.id, const <WorkspaceTabRecord>[]);
        final layout = WorkbenchLayout.single(
          workspaceId: workspace.id,
          tabIds: const <String>[],
        );
        await _applyLayout(layout, persist: true);
      }
      state = state.copyWith(
        activeWorkspaceId:
            remaining.isEmpty && state.activeWorkspaceId == workspace.id
            ? null
            : state.activeWorkspaceId,
        error: null,
      );
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    } finally {
      _closingTabWorkspaceIds.remove(workspace.id);
    }
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
    final layout = state.layoutFor(workspaceId);
    if (layout == null || layout.activeGroupId == groupId) {
      return;
    }
    final tabId = layout.groups[groupId]?.activeTabId;
    if (tabId == null) {
      return;
    }
    final nextLayout = layout.setActiveTab(groupId: groupId, tabId: tabId);
    _applyLayoutInBackground(nextLayout, persist: false);
  }

  Future<void> moveWorkspaceTab({
    required String workspaceId,
    required String tabId,
    required String targetGroupId,
    required WorkbenchDropZone zone,
    int? index,
  }) async {
    try {
      final tabs = state.tabsFor(workspaceId);
      final layout = _layoutForMutation(workspaceId, tabs);
      final nextLayout = layout
          .moveTab(
            tabId: tabId,
            targetGroupId: targetGroupId,
            zone: zone,
            newGroupId: _newPaneGroupId(),
            index: index,
          )
          .sanitize(tabs);
      await _applyLayout(nextLayout, persist: true);
      state = state.copyWith(error: null);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<WorkspaceTabRecord> splitWorkbenchGroupWithTerminal({
    required Workspace workspace,
    required String groupId,
    required WorkbenchDropZone zone,
  }) async {
    try {
      final previousTabs = state.tabsFor(workspace.id);
      final layout = _layoutForMutation(workspace.id, previousTabs);
      final tab = await _workspaceTabService.createTerminalTab(workspace.id);
      final tabs = <WorkspaceTabRecord>[...previousTabs, tab];
      _setTabsForWorkspace(workspace.id, tabs);
      final nextLayout = layout
          .splitWithGroup(
            targetGroupId: groupId,
            zone: zone,
            newGroup: WorkbenchPaneGroup(
              id: _newPaneGroupId(),
              tabIds: <String>[tab.id],
              activeTabId: tab.id,
            ),
          )
          .sanitize(tabs);
      await _applyLayout(nextLayout, persist: true);
      state = state.copyWith(error: null);
      return tab;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> mergeWorkbenchGroupIntoSibling({
    required String workspaceId,
    required String groupId,
  }) async {
    try {
      final tabs = state.tabsFor(workspaceId);
      final layout = _layoutForMutation(
        workspaceId,
        tabs,
      ).mergeGroupIntoSibling(groupId).sanitize(tabs);
      await _applyLayout(layout, persist: true);
      state = state.copyWith(error: null);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  void updateWorkbenchSplitRatio({
    required String workspaceId,
    required List<int> nodePath,
    required double ratio,
  }) {
    final tabs = state.tabsFor(workspaceId);
    final layout = _layoutForMutation(
      workspaceId,
      tabs,
    ).updateSplitRatio(nodePath, ratio).sanitize(tabs);
    _applyLayoutInBackground(layout, persist: true);
  }
}
