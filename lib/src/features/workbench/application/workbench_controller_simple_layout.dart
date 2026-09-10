part of 'workbench_controller.dart';

mixin _WorkbenchControllerSimpleLayout
    on _$WorkbenchController, _WorkbenchControllerInternals {
  void setDesktopWorkspaceLayout(DesktopWorkspaceLayout layout) {
    if (state.viewPrefs.desktopLayout == layout) return;
    final panels = <String, SimpleWorkspacePanel>{
      ...state.viewPrefs.simplePanels,
    };
    if (layout == DesktopWorkspaceLayout.simple) {
      for (final workspaceId in state.tabsByWorkspace.keys) {
        panels[workspaceId] = state.simplePanelFor(workspaceId);
      }
    }
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(
        desktopLayout: layout,
        simplePanels: panels,
      ),
    );
    unawaited(_persistViewPrefs());
    _ensureSelectionHasTab();
  }

  void selectSimplePanelKey(String workspaceId, String key, {String? groupId}) {
    final panel = state.simplePanelFor(workspaceId);
    if (!panel.tabKeys.contains(key) &&
        key != SimpleWorkspacePanel.tabKey(panel.primaryTabId ?? '') &&
        SimpleWorkspaceTool.forKey(key) == null) {
      return;
    }
    _saveSimplePanel(
      workspaceId,
      panel.select(key, groupId: groupId),
      reveal: key != SimpleWorkspacePanel.tabKey(panel.primaryTabId ?? ''),
    );
    if (panel.focusedKey == key) {
      _focusSimpleTerminal(workspaceId, key);
    }
  }

  @override
  void _focusSimpleTerminal(String workspaceId, String? key) {
    if (!state.isSimpleLayout || state.activeWorkspaceId != workspaceId) {
      return;
    }
    final id = SimpleWorkspacePanel.tabId(key);
    final tab = state
        .tabsFor(workspaceId)
        .where((tab) => tab.id == id)
        .firstOrNull;
    final workspace = _workspaceById(workspaceId);
    if (tab?.kind == WorkspaceTabKind.terminal && workspace != null) {
      ref
          .read(terminalRuntimeProvider)
          .sessionFor(workspace: workspace, tab: tab!)
          .requestFocus();
    }
  }

  void closeSimpleTool(String workspaceId, SimpleWorkspaceTool tool) {
    _saveSimplePanel(
      workspaceId,
      state.simplePanelFor(workspaceId).closeTool(tool),
    );
  }

  String _simplePaneKey(String tabIdOrKey) {
    if (tabIdOrKey.startsWith('tab:') || tabIdOrKey.startsWith('tool:')) {
      return tabIdOrKey;
    }
    return SimpleWorkspacePanel.tabKey(tabIdOrKey);
  }

  void addTerminalToSimplePane({
    required String workspaceId,
    required WorkspaceTabRecord tab,
    required List<WorkspaceTabRecord> tabs,
    required List<WorkspaceTabRecord> previousTabs,
    String? targetGroupId,
  }) {
    final panel =
        (state.viewPrefs.simplePanels[workspaceId] ??
                const SimpleWorkspacePanel())
            .reconcile(
              previousTabs,
              preferredPrimaryId: state.layoutFor(workspaceId)?.activeTabId,
              workspaceId: workspaceId,
            );
    final layout = panel.ensuredLayout(workspaceId);
    final groupId =
        targetGroupId != null && layout.groups.containsKey(targetGroupId)
        ? targetGroupId
        : layout.activeGroupId;
    final key = SimpleWorkspacePanel.tabKey(tab.id);
    _saveSimplePanel(
      workspaceId,
      panel
          .applyPaneLayout(layout.addTabToGroup(groupId: groupId, tabId: key))
          .copyWith(focusedKey: key),
      reveal: true,
    );
    final classic = _layoutForMutation(workspaceId, tabs);
    final nextLayouts = Map<String, WorkbenchLayout>.from(
      state.layoutByWorkspace,
    )..[workspaceId] = classic;
    state = state.copyWith(
      layoutByWorkspace: nextLayouts,
      activeTabIdByWorkspace: _activeTabsWithLayout(classic),
    );
    unawaited(_repository.upsertWorkbenchLayout(classic));
  }

  Future<void> moveSimplePaneTab({
    required String workspaceId,
    required String tabId,
    required String targetGroupId,
    required WorkbenchDropZone zone,
    int? index,
  }) async {
    final panel = state.simplePanelFor(workspaceId);
    final key = _simplePaneKey(tabId);
    final next = panel.applyPaneLayout(
      panel
          .ensuredLayout(workspaceId)
          .moveTab(
            tabId: key,
            targetGroupId: targetGroupId,
            zone: zone,
            newGroupId: _newPaneGroupId(),
            index: index,
          ),
    );
    _saveSimplePanel(workspaceId, next.copyWith(focusedKey: key), reveal: true);
  }

  Future<WorkspaceTabRecord> splitSimplePaneWithTerminal({
    required Workspace workspace,
    required String groupId,
    required WorkbenchDropZone zone,
  }) async {
    final previousTabs = state.tabsFor(workspace.id);
    final tab = await _workspaceTabService.createTerminalTab(workspace.id);
    final tabs = <WorkspaceTabRecord>[...previousTabs, tab];
    _setTabsForWorkspace(workspace.id, tabs);
    final panel =
        (state.viewPrefs.simplePanels[workspace.id] ??
                const SimpleWorkspacePanel())
            .reconcile(
              previousTabs,
              preferredPrimaryId: state.layoutFor(workspace.id)?.activeTabId,
              workspaceId: workspace.id,
            );
    final key = SimpleWorkspacePanel.tabKey(tab.id);
    final next = panel.applyPaneLayout(
      panel
          .ensuredLayout(workspace.id)
          .splitWithGroup(
            targetGroupId: groupId,
            zone: zone,
            newGroup: WorkbenchPaneGroup(
              id: _newPaneGroupId(),
              tabIds: <String>[key],
              activeTabId: key,
            ),
          ),
    );
    _saveSimplePanel(
      workspace.id,
      next.copyWith(focusedKey: key),
      reveal: true,
    );
    final classic = _layoutForMutation(workspace.id, tabs);
    final nextLayouts = Map<String, WorkbenchLayout>.from(
      state.layoutByWorkspace,
    )..[workspace.id] = classic;
    state = state.copyWith(
      layoutByWorkspace: nextLayouts,
      activeTabIdByWorkspace: _activeTabsWithLayout(classic),
    );
    await _repository.upsertWorkbenchLayout(classic);
    return tab;
  }

  void mergeSimplePaneIntoSibling({
    required String workspaceId,
    required String groupId,
  }) {
    final panel = state.simplePanelFor(workspaceId);
    final layout = panel.ensuredLayout(workspaceId);
    if (layout.groups.length < 2) {
      return;
    }
    _saveSimplePanel(
      workspaceId,
      panel.applyPaneLayout(layout.mergeGroupIntoSibling(groupId)),
    );
  }

  void updateSimplePaneSplitRatio({
    required String workspaceId,
    required List<int> nodePath,
    required double ratio,
  }) {
    final panel = state.simplePanelFor(workspaceId);
    _saveSimplePanel(
      workspaceId,
      panel.applyPaneLayout(
        panel.ensuredLayout(workspaceId).updateSplitRatio(nodePath, ratio),
      ),
    );
  }
}
