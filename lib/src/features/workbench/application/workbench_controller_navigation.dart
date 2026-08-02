part of 'workbench_controller.dart';

mixin _WorkbenchControllerNavigation
    on
        _$WorkbenchController,
        _WorkbenchControllerInternals,
        _WorkbenchControllerProjects {
  Future<void> goBack() async {
    _pruneWorktreeNavigationHistory();
    final target = _worktreeNavigationHistory.peekBack(
      isValid: _isLiveWorktreeNavigationTarget,
    );
    if (target == null) {
      return;
    }
    final project = _projectById(state.projects, target.projectId);
    final workspace = project == null
        ? null
        : state
              .workspacesFor(project.id)
              .where((candidate) => candidate.id == target.workspaceId)
              .firstOrNull;
    if (project == null || workspace == null) {
      _pruneWorktreeNavigationHistory();
      return;
    }
    await _selectWorkspace(
      project: project,
      workspace: workspace,
      ensureInitialTerminal: true,
      recordHistory: false,
    );
    _worktreeNavigationHistory.commitBack(target);
    _notifyNavigationHistoryChanged();
  }

  Future<void> goForward() async {
    _pruneWorktreeNavigationHistory();
    final target = _worktreeNavigationHistory.peekForward(
      isValid: _isLiveWorktreeNavigationTarget,
    );
    if (target == null) {
      return;
    }
    final project = _projectById(state.projects, target.projectId);
    final workspace = project == null
        ? null
        : state
              .workspacesFor(project.id)
              .where((candidate) => candidate.id == target.workspaceId)
              .firstOrNull;
    if (project == null || workspace == null) {
      _pruneWorktreeNavigationHistory();
      return;
    }
    await _selectWorkspace(
      project: project,
      workspace: workspace,
      ensureInitialTerminal: true,
      recordHistory: false,
    );
    _worktreeNavigationHistory.commitForward(target);
    _notifyNavigationHistoryChanged();
  }
}
