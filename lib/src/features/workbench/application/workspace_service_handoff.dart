part of 'workspace_service.dart';

extension WorkspaceServiceHandoff on WorkspaceService {
  Future<WorkspaceCreationResult> handOffWorkspace({
    String? relocationId,
    required Workspace workspace,
    required String branch,
    bool reuseExistingBranch = false,
    bool moveChanges = true,
    String? replacementBranch,
    String? name,
  }) async {
    if (!workspace.isMain) {
      throw WorkspaceException(
        'Hand off is only available from the main worktree',
      );
    }
    final managedRuntime = _managedRuntime;
    if (managedRuntime == null) {
      throw WorkspaceException(
        'Hand off requires the managed workspace runtime',
      );
    }
    return managedRuntime.handOffWorkspace(
      relocationId: relocationId,
      workspace: workspace,
      branch: branch.trim(),
      reuseExistingBranch: reuseExistingBranch,
      moveChanges: moveChanges,
      replacementBranch: replacementBranch,
      name: name,
    );
  }

  Future<WorkspaceHandOnResult> handOnWorkspace({
    String? relocationId,
    required Workspace workspace,
    String? activeWorkspaceId,
  }) async {
    if (workspace.isMain) {
      throw WorkspaceException(
        'Hand on is only available from a child worktree',
      );
    }
    final managedRuntime = _managedRuntime;
    if (managedRuntime == null) {
      throw WorkspaceException(
        'Hand on requires the managed workspace runtime',
      );
    }
    return managedRuntime.handOnWorkspace(
      relocationId: relocationId,
      workspace: workspace,
      activeWorkspaceId: activeWorkspaceId,
    );
  }
}
