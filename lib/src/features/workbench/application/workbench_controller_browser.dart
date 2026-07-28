part of 'workbench_controller.dart';

/// Browser-specific persistence that also refreshes the in-memory workbench.
mixin _WorkbenchControllerBrowser
    on _$WorkbenchController, _WorkbenchControllerInternals {
  Future<WorkspaceTabRecord> updateBrowserTabState({
    required String tabId,
    required String profileId,
    String? url,
    String? runtimeTitle,
  }) async {
    try {
      final tab = await _workspaceBrowserTabService.updateState(
        tabId: tabId,
        profileId: profileId,
        url: url,
        runtimeTitle: runtimeTitle,
      );
      _setTabsForWorkspace(tab.workspaceId, <WorkspaceTabRecord>[
        for (final candidate in state.tabsFor(tab.workspaceId))
          if (candidate.id == tab.id) tab else candidate,
      ]);
      state = state.copyWith(error: null);
      return tab;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }
}
