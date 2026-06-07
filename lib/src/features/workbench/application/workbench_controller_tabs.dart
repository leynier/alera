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
        await _applyLayout(layout, persist: true);
      } else {
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

  Future<void> syncEditorTabsAfterPathMove({
    required Workspace workspace,
    required String oldRelativePath,
    required String newRelativePath,
  }) async {
    try {
      final updatedTabs = await _workspaceTabService.updateEditorPathsAfterMove(
        workspaceId: workspace.id,
        oldRelativePath: oldRelativePath,
        newRelativePath: newRelativePath,
      );
      if (updatedTabs.isEmpty) {
        return;
      }
      final byId = <String, WorkspaceTabRecord>{
        for (final tab in updatedTabs) tab.id: tab,
      };
      final tabs = <WorkspaceTabRecord>[
        for (final tab in state.tabsFor(workspace.id)) byId[tab.id] ?? tab,
      ];
      _setTabsForWorkspace(workspace.id, tabs);
      state = state.copyWith(error: null);
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
    unawaited(_applyLayout(nextLayout, persist: false));
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
    unawaited(_applyLayout(layout, persist: true));
  }
}
