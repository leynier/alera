part of 'workbench_controller.dart';

mixin _WorkbenchControllerWorkspaceSleep
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerWorkspacePanel,
        _WorkbenchControllerTabOpening {
  StreamSubscription<Map<String, List<String>>>? _sleptTabsSub;

  /// Follows the host's slept terminals so a sleep or wake from any client,
  /// including a paired phone, reaches the sidebar.
  void _startSleptTabs() {
    final repository = _repository;
    if (repository is! WorkspaceSleepRepository) return;
    _sleptTabsSub = (repository as WorkspaceSleepRepository)
        .watchSleptWorkspaceTabs()
        .listen((slept) {
          if (_disposed) return;
          state = state.copyWith(sleptTabIdsByWorkspaceId: slept);
        });
  }

  /// Sleeps a workspace: live terminal sessions stop, but tab records, layout,
  /// branch, and files are preserved so agent sessions resume on wake through
  /// their stored native session ids.
  Future<void> sleepWorkspace(Workspace workspace) async {
    try {
      await _repository.sleepWorkspace(workspace.id);
      ref.read(terminalRuntimeProvider).closeWorkspace(workspace.id);
      // The host records the same list; setting it here keeps the row from
      // showing running terminals until that snapshot arrives.
      final sleptTabIds = <String>[
        for (final tab in state.tabsFor(workspace.id))
          if (tab.kind == WorkspaceTabKind.terminal) tab.id,
      ];
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
        activeWorkspaceId: wasActive ? null : state.activeWorkspaceId,
        viewPrefs: nextPrefs,
        sleptTabIdsByWorkspaceId: sleptTabIds.isEmpty
            ? state.sleptTabIdsByWorkspaceId
            : <String, List<String>>{
                ...state.sleptTabIdsByWorkspaceId,
                workspace.id: sleptTabIds,
              },
        error: null,
      );
      if (!identical(nextPrefs, prefs)) {
        unawaited(_persistViewPrefs());
      }
      _pruneExplorerSessions();
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }
}
