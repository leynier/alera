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

  void selectSimplePanelKey(String workspaceId, String key) {
    final panel = state.simplePanelFor(workspaceId);
    if (!panel.tabKeys.contains(key) &&
        key != SimpleWorkspacePanel.tabKey(panel.primaryTabId ?? '') &&
        SimpleWorkspaceTool.forKey(key) == null) {
      return;
    }
    _saveSimplePanel(
      workspaceId,
      panel.select(key),
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
}
