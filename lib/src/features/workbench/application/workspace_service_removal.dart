part of 'workspace_service.dart';

extension WorkspaceServiceRemoval on WorkspaceService {
  Future<void> removeWorkspace({
    required Project project,
    required Workspace workspace,
    required bool deleteBranch,
    String? activeWorkspaceId,
  }) async {
    if (workspace.isMain) {
      throw WorkspaceException('The main workspace cannot be removed');
    }
    var shouldDeleteBranch = deleteBranch && !workspace.reusesExistingBranch;
    final managedRuntime = _managedRuntime;
    if (managedRuntime != null) {
      await managedRuntime.removeWorkspace(
        workspace: workspace,
        deleteBranch: shouldDeleteBranch,
        activeWorkspaceId: activeWorkspaceId,
      );
      return;
    }
    if (shouldDeleteBranch) {
      shouldDeleteBranch = await _branchDeletionIdentityAllowsDelete(
        project: project,
        workspace: workspace,
      );
    }
    try {
      await _gitBackend.removeWorktree(
        repoPath: project.repoPath,
        path: workspace.path,
        force: true,
      );
    } on WorktreeNotFoundException catch (error) {
      if (!await _filesystemEntryIsMissing(workspace.path)) {
        throw WorkspaceException(
          'git worktree remove failed',
          stderr: error.context,
        );
      }
    } on GitException catch (error) {
      throw WorkspaceException(
        'git worktree remove failed',
        stderr: error.context,
      );
    }
    if (shouldDeleteBranch) {
      final branch = workspace.branch;
      if (branch != null && branch.isNotEmpty) {
        try {
          await _gitBackend.deleteBranch(
            repoPath: project.repoPath,
            branch: branch,
            force: false,
          );
        } on BranchNotFoundException {
          // The requested final state already exists.
        } on GitException {
          // Worktree is already gone; keep the branch rather than failing cleanup.
        }
      }
    }
    await _repository.removeWorkspace(workspace.id, cascadeTabs: true);
  }

  Future<bool> _branchDeletionIdentityAllowsDelete({
    required Project project,
    required Workspace workspace,
  }) async {
    final branch = workspace.branch;
    if (branch == null || branch.isEmpty) {
      return false;
    }
    try {
      if (await _gitBackend.currentBranch(workspace.path) != branch) {
        return false;
      }
      final home = await _gitBackend.defaultBranch(project.repoPath);
      if (branch == home) {
        return false;
      }
      final worktrees = await _gitBackend.listWorktrees(project.repoPath);
      return !worktrees.any(
        (entry) =>
            entry.branch == branch &&
            p.normalize(entry.path) != p.normalize(workspace.path),
      );
    } on GitException {
      return false;
    }
  }

  Future<bool> _filesystemEntryIsMissing(String path) async {
    try {
      return await FileSystemEntity.type(path, followLinks: false) ==
          FileSystemEntityType.notFound;
    } on FileSystemException catch (error) {
      throw WorkspaceException(
        'Could not inspect workspace path',
        stderr: error.message,
      );
    }
  }
}
