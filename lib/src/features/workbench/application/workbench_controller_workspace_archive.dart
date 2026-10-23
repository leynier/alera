part of 'workbench_controller.dart';

mixin _WorkbenchControllerWorkspaceArchive
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerWorkspacePanel,
        _WorkbenchControllerTabOpening {
  /// Resolves archive support once the repository is ready. False until then,
  /// so no archive control is offered that an older host would reject.
  Future<void> _startArchiveSupport() async {
    try {
      state = state.copyWith(
        supportsArchive: await _repository.supportsArchive(),
      );
    } catch (_) {
      // Keep unsupported; archiving stays hidden rather than failing later.
    }
  }

  /// Archives a workspace: live terminal sessions stop and the workspace
  /// leaves the sidebar (unless archived workspaces are shown), while tab
  /// records, layout, branch, and files are preserved for resume. Git state
  /// is never touched.
  ///
  /// A failure is thrown, not stored in `state.error`: every caller reports
  /// it with the action's context, and storing it too would toast it twice.
  Future<void> archiveWorkspace(Workspace workspace) async {
    final updated = await _repository.setWorkspaceArchived(workspace.id, true);
    ref.read(terminalRuntimeProvider).closeWorkspace(workspace.id);
    _replaceWorkspaceInState(updated);
    final wasActive = state.activeWorkspaceId == workspace.id;
    state = state.copyWith(
      activeWorkspaceId: wasActive ? null : state.activeWorkspaceId,
      error: null,
    );
    _pruneExplorerSessions();
  }

  Future<void> unarchiveWorkspace(Workspace workspace) async {
    final updated = await _repository.setWorkspaceArchived(workspace.id, false);
    _replaceWorkspaceInState(updated);
    state = state.copyWith(error: null);
  }

  void _replaceWorkspaceInState(Workspace workspace) {
    final current = state.workspacesFor(workspace.projectId);
    state = state.copyWith(
      workspacesByProject: <String, List<Workspace>>{
        ...state.workspacesByProject,
        workspace.projectId: <Workspace>[
          for (final candidate in current)
            if (candidate.id == workspace.id) workspace else candidate,
        ],
      },
    );
  }
}
