part of 'workspace_service.dart';

extension WorkspaceServiceRemoval on WorkspaceService {
  Future<void> removeWorkspace({
    required Project project,
    required Workspace workspace,
    required bool deleteBranch,
  }) async {
    if (workspace.isMain) {
      throw WorkspaceException('The main workspace cannot be removed');
    }
    final shouldDeleteBranch = deleteBranch && !workspace.reusesExistingBranch;
    final managedRuntime = _managedRuntime;
    if (managedRuntime != null) {
      await managedRuntime.removeWorkspace(
        workspace: workspace,
        deleteBranch: shouldDeleteBranch,
      );
      return;
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
      if (branch == null || branch.isEmpty) {
        throw WorkspaceException('Workspace Branch Is Required');
      }
      try {
        await _gitBackend.deleteBranch(
          repoPath: project.repoPath,
          branch: branch,
          force: true,
        );
      } on BranchNotFoundException {
        // The requested final state already exists.
      } on GitException catch (error) {
        throw WorkspaceException(
          'git branch -D $branch failed',
          stderr: error.context,
        );
      }
    }
    await _repository.removeWorkspace(workspace.id, cascadeTabs: true);
  }

  Future<bool> _filesystemEntryIsMissing(String path) async {
    try {
      return await FileSystemEntity.type(path, followLinks: false) ==
          FileSystemEntityType.notFound;
    } on FileSystemException catch (error) {
      throw WorkspaceException(
        'Could Not Inspect Workspace Path',
        stderr: error.message,
      );
    }
  }
}
