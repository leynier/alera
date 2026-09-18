part of 'workbench_controller.dart';

mixin _WorkbenchControllerWorkspaceSleep
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerWorkspacePanel,
        _WorkbenchControllerTabOpening {
  /// Sleeps a workspace: live terminal sessions stop, but tab records, layout,
  /// branch, and files are preserved so agent sessions resume on wake through
  /// their stored native session ids.
  Future<void> sleepWorkspace(Workspace workspace) async {
    try {
      await _repository.sleepWorkspace(workspace.id);
      ref.read(terminalRuntimeProvider).closeWorkspace(workspace.id);
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
