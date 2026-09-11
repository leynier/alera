part of 'workbench_controller.dart';

mixin _WorkbenchControllerExperimentalLayout
    on _$WorkbenchController, _WorkbenchControllerInternals {
  final Map<String, Future<void>> _experimentalPrimaryLoads = {};

  @override
  void _maybeEnsureExperimentalPrimary(Workspace workspace) {
    if (state.isExperimentalLayout &&
        !state.tabsFor(workspace.id).any(isExperimentalPrimaryCandidate)) {
      unawaited(_ensureExperimentalPrimary(workspace));
    }
  }

  Future<void> _ensureExperimentalPrimary(Workspace workspace) {
    return _experimentalPrimaryLoads.putIfAbsent(workspace.id, () async {
      try {
        final tabs = await _workspaceTabService.listTabs(workspace.id);
        if (_disposed ||
            !state.isExperimentalLayout ||
            state.activeWorkspaceId != workspace.id ||
            _closingTabWorkspaceIds.contains(workspace.id)) {
          return;
        }
        if (tabs.any(isExperimentalPrimaryCandidate)) {
          return;
        }
        await _workspaceTabService.createTerminalTab(workspace.id);
        final current = await _workspaceTabService.listTabs(workspace.id);
        if (_disposed) {
          return;
        }
        _setTabsForWorkspace(workspace.id, current);
        _saveExperimentalPanel(
          workspace.id,
          state.experimentalPanelFor(workspace.id),
        );
      } catch (error) {
        if (!_disposed) {
          state = state.copyWith(error: error.toString());
        }
      } finally {
        _experimentalPrimaryLoads.remove(workspace.id);
      }
    });
  }

  void setDesktopWorkspaceLayout(DesktopWorkspaceLayout layout) {
    if (state.viewPrefs.desktopLayout == layout) return;
    final panels = <String, ExperimentalWorkspacePanel>{
      ...state.viewPrefs.experimentalPanels,
    };
    if (layout == DesktopWorkspaceLayout.experimental) {
      for (final workspaceId in state.tabsByWorkspace.keys) {
        panels[workspaceId] = state.experimentalPanelFor(workspaceId);
      }
    }
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(
        desktopLayout: layout,
        experimentalPanels: panels,
      ),
    );
    unawaited(_persistViewPrefs());
    _ensureSelectionHasTab();
  }

  @override
  void _seedExperimentalNewWorkspacePanel(String workspaceId) {
    if (!state.isExperimentalLayout) {
      return;
    }
    final tools = ExperimentalWorkspaceTool.uniqueInOrder(
      state.viewPrefs.experimentalNewWorkspaceTools,
    );
    if (tools.isEmpty) {
      return;
    }
    final panel = state.experimentalPanelFor(workspaceId);
    final alreadyHasTools = panel.occupiedKeys.any(
      (key) => ExperimentalWorkspaceTool.forKey(key) != null,
    );
    if (alreadyHasTools) {
      return;
    }
    _saveExperimentalPanel(
      workspaceId,
      panel.openToolsInOrder(tools),
      reveal: true,
    );
  }

  void selectExperimentalPanelKey(
    String workspaceId,
    String key, {
    String? groupId,
  }) {
    final panel = state.experimentalPanelFor(workspaceId);
    if (!panel.occupiedKeys.contains(key) &&
        ExperimentalWorkspaceTool.forKey(key) == null) {
      return;
    }
    final next = panel.select(key, groupId: groupId);
    _saveExperimentalPanel(
      workspaceId,
      next,
      reveal: next.treeForKey(key) == ExperimentalPanelTree.right,
    );
    if (panel.focusedKey == key) {
      _focusExperimentalTerminal(workspaceId, key);
    }
  }

  @override
  void _focusExperimentalTerminal(String workspaceId, String? key) {
    if (!state.isExperimentalLayout || state.activeWorkspaceId != workspaceId) {
      return;
    }
    final id = ExperimentalWorkspacePanel.tabId(key);
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

  void closeExperimentalTool(
    String workspaceId,
    ExperimentalWorkspaceTool tool,
  ) {
    _saveExperimentalPanel(
      workspaceId,
      state.experimentalPanelFor(workspaceId).closeTool(tool),
    );
  }

  String _experimentalPaneKey(String tabIdOrKey) {
    if (tabIdOrKey.startsWith('tab:') || tabIdOrKey.startsWith('tool:')) {
      return tabIdOrKey;
    }
    return ExperimentalWorkspacePanel.tabKey(tabIdOrKey);
  }

  void addTerminalToExperimentalPane({
    required String workspaceId,
    required WorkspaceTabRecord tab,
    required List<WorkspaceTabRecord> tabs,
    required List<WorkspaceTabRecord> previousTabs,
    String? targetGroupId,
  }) {
    final panel =
        (state.viewPrefs.experimentalPanels[workspaceId] ??
                const ExperimentalWorkspacePanel())
            .reconcile(
              previousTabs,
              preferredPrimaryId: state.layoutFor(workspaceId)?.activeTabId,
              workspaceId: workspaceId,
            );
    final main = panel.ensuredMainLayout(workspaceId);
    final right = panel.ensuredLayout(workspaceId);
    final addToMain =
        targetGroupId != null && main.groups.containsKey(targetGroupId);
    final layout = addToMain ? main : right;
    final groupId =
        targetGroupId != null && layout.groups.containsKey(targetGroupId)
        ? targetGroupId
        : layout.activeGroupId;
    final key = ExperimentalWorkspacePanel.tabKey(tab.id);
    final placed = layout.addTabToGroup(groupId: groupId, tabId: key);
    _saveExperimentalPanel(
      workspaceId,
      (addToMain
              ? panel.applyMainLayout(placed)
              : panel.applyPaneLayout(placed))
          .copyWith(focusedKey: key),
      reveal: !addToMain,
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

  Future<void> moveExperimentalPaneTab({
    required String workspaceId,
    required String tabId,
    required String targetGroupId,
    required WorkbenchDropZone zone,
    ExperimentalPanelTree source = ExperimentalPanelTree.right,
    ExperimentalPanelTree target = ExperimentalPanelTree.right,
    int? index,
  }) async {
    final panel = state.experimentalPanelFor(workspaceId);
    final key = _experimentalPaneKey(tabId);
    final newGroupId = _newPaneGroupId();
    final ExperimentalWorkspacePanel next;
    if (source == target) {
      final layout = source == ExperimentalPanelTree.main
          ? panel.ensuredMainLayout(workspaceId)
          : panel.ensuredLayout(workspaceId);
      final moved = layout.moveTab(
        tabId: key,
        targetGroupId: targetGroupId,
        zone: zone,
        newGroupId: newGroupId,
        index: index,
      );
      next = source == ExperimentalPanelTree.main
          ? panel.applyMainLayout(moved)
          : panel.applyPaneLayout(moved);
    } else {
      next = panel.moveKey(
        key: key,
        target: target,
        targetGroupId: targetGroupId,
        zone: zone,
        newGroupId: newGroupId,
        index: index,
      );
    }
    _saveExperimentalPanel(
      workspaceId,
      next.copyWith(focusedKey: key),
      reveal: target == ExperimentalPanelTree.right,
    );
  }

  Future<WorkspaceTabRecord> splitExperimentalPaneWithTerminal({
    required Workspace workspace,
    required String groupId,
    required WorkbenchDropZone zone,
  }) async {
    final previousTabs = state.tabsFor(workspace.id);
    final tab = await _workspaceTabService.createTerminalTab(workspace.id);
    final tabs = <WorkspaceTabRecord>[...previousTabs, tab];
    _setTabsForWorkspace(workspace.id, tabs);
    final panel =
        (state.viewPrefs.experimentalPanels[workspace.id] ??
                const ExperimentalWorkspacePanel())
            .reconcile(
              previousTabs,
              preferredPrimaryId: state.layoutFor(workspace.id)?.activeTabId,
              workspaceId: workspace.id,
            );
    final key = ExperimentalWorkspacePanel.tabKey(tab.id);
    final main = panel.ensuredMainLayout(workspace.id);
    final addToMain = main.groups.containsKey(groupId);
    final layout = addToMain ? main : panel.ensuredLayout(workspace.id);
    final split = layout.splitWithGroup(
      targetGroupId: groupId,
      zone: zone,
      newGroup: WorkbenchPaneGroup(
        id: _newPaneGroupId(),
        tabIds: <String>[key],
        activeTabId: key,
      ),
    );
    final next = addToMain
        ? panel.applyMainLayout(split)
        : panel.applyPaneLayout(split);
    _saveExperimentalPanel(
      workspace.id,
      next.copyWith(focusedKey: key),
      reveal: !addToMain,
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

  void mergeExperimentalPaneIntoSibling({
    required String workspaceId,
    required String groupId,
  }) {
    final panel = state.experimentalPanelFor(workspaceId);
    final main = panel.ensuredMainLayout(workspaceId);
    if (main.groups.containsKey(groupId)) {
      if (main.groups.length < 2) {
        return;
      }
      _saveExperimentalPanel(
        workspaceId,
        panel.applyMainLayout(main.mergeGroupIntoSibling(groupId)),
      );
      return;
    }
    final layout = panel.ensuredLayout(workspaceId);
    if (layout.groups.length < 2) {
      return;
    }
    _saveExperimentalPanel(
      workspaceId,
      panel.applyPaneLayout(layout.mergeGroupIntoSibling(groupId)),
    );
  }

  void updateExperimentalPaneSplitRatio({
    required String workspaceId,
    required List<int> nodePath,
    required double ratio,
    ExperimentalPanelTree tree = ExperimentalPanelTree.right,
  }) {
    final panel = state.experimentalPanelFor(workspaceId);
    if (tree == ExperimentalPanelTree.main) {
      _saveExperimentalPanel(
        workspaceId,
        panel.applyMainLayout(
          panel
              .ensuredMainLayout(workspaceId)
              .updateSplitRatio(nodePath, ratio),
        ),
      );
      return;
    }
    _saveExperimentalPanel(
      workspaceId,
      panel.applyPaneLayout(
        panel.ensuredLayout(workspaceId).updateSplitRatio(nodePath, ratio),
      ),
    );
  }
}
