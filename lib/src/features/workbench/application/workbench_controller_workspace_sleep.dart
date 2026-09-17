part of 'workbench_controller.dart';

mixin _WorkbenchControllerWorkspaceSleep
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerWorkspacePanel,
        _WorkbenchControllerTabOpening {
  Future<void> sleepWorkspace(Workspace workspace) async {
    try {
      final workspaceTabs = state.tabsFor(workspace.id);
      _closingTabWorkspaceIds.add(workspace.id);
      _workspaceIdsWithClearedLayout.add(workspace.id);
      _workspaceSleepGeneration[workspace.id] =
          (_workspaceSleepGeneration[workspace.id] ?? 0) + 1;
      _tabFocusHistory.forget(workspace.id);
      _panelSelectionRevisionByWorkspace.remove(workspace.id);
      await _repository.removeWorkspaceTabsForWorkspace(workspace.id);
      for (final tab in workspaceTabs) {
        await _releaseHostedReviewTab(workspace, tab);
      }

      final tabsByWorkspace = Map<String, List<WorkspaceTabRecord>>.from(
        state.tabsByWorkspace,
      )..[workspace.id] = const <WorkspaceTabRecord>[];
      final layoutsByWorkspace = Map<String, WorkbenchLayout>.from(
        state.layoutByWorkspace,
      )..remove(workspace.id);
      final activeTabsByWorkspace = Map<String, String>.from(
        state.activeTabIdByWorkspace,
      )..remove(workspace.id);
      final wasActive = state.activeWorkspaceId == workspace.id;
      final prefs = state.viewPrefs;
      var nextPrefs = prefs;
      if (prefs.rightSidebarWidthByWorkspaceId.containsKey(workspace.id)) {
        nextPrefs = prefs.copyWith(
          rightSidebarWidthByWorkspaceId: Map<String, double>.from(
            prefs.rightSidebarWidthByWorkspaceId,
          )..remove(workspace.id),
        );
      }

      state = state.copyWith(
        tabsByWorkspace: tabsByWorkspace,
        layoutByWorkspace: layoutsByWorkspace,
        activeTabIdByWorkspace: activeTabsByWorkspace,
        activeWorkspaceId: wasActive ? null : state.activeWorkspaceId,
        viewPrefs: nextPrefs,
        error: null,
      );
      if (!identical(nextPrefs, prefs)) {
        unawaited(_persistViewPrefs());
      }
      _pruneExplorerSessions();
    } catch (error) {
      _workspaceIdsWithClearedLayout.remove(workspace.id);
      state = state.copyWith(error: error.toString());
      rethrow;
    } finally {
      _closingTabWorkspaceIds.remove(workspace.id);
    }
  }
}
