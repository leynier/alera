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
  Future<void> archiveWorkspace(Workspace workspace) async {
    try {
      final updated = await _repository.setWorkspaceArchived(
        workspace.id,
        true,
      );
      ref.read(terminalRuntimeProvider).closeWorkspace(workspace.id);
      _replaceWorkspaceInState(updated);
      final wasActive = state.activeWorkspaceId == workspace.id;
      state = state.copyWith(
        activeWorkspaceId: wasActive ? null : state.activeWorkspaceId,
        error: null,
      );
      _pruneExplorerSessions();
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> unarchiveWorkspace(Workspace workspace) async {
    try {
      final updated = await _repository.setWorkspaceArchived(
        workspace.id,
        false,
      );
      _replaceWorkspaceInState(updated);
      state = state.copyWith(error: null);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
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
