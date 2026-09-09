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
    final shouldDeleteBranch = deleteBranch && !workspace.reusesExistingBranch;
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
      final branch = workspace.branch;
      if (branch == null ||
          branch.isEmpty ||
          await _gitBackend.currentBranch(workspace.path) != branch) {
        throw WorkspaceException(
          'Live branch ownership is uncertain. Keep the branch when removing this workspace.',
        );
      }
      final home = await _gitBackend.defaultBranch(project.repoPath);
      if (branch == home ||
          !await _gitBackend.isAncestor(
            path: project.repoPath,
            ancestorRef: branch,
            descendantRef: home,
          )) {
        throw WorkspaceException(
          'The branch is protected or has unmerged commits. Keep the branch.',
        );
      }
      final worktrees = await _gitBackend.listWorktrees(project.repoPath);
      if (worktrees.any(
        (entry) =>
            entry.branch == branch &&
            p.normalize(entry.path) != p.normalize(workspace.path),
      )) {
        throw WorkspaceException(
          'The branch is checked out in another worktree. Keep the branch.',
        );
      }
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
        throw WorkspaceException('Workspace branch is required');
      }
      try {
        await _gitBackend.deleteBranch(
          repoPath: project.repoPath,
          branch: branch,
          force: false,
        );
      } on BranchNotFoundException {
        // The requested final state already exists.
      } on GitException catch (error) {
        throw WorkspaceException(
          'Safe deletion of branch $branch failed',
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
        'Could not inspect workspace path',
        stderr: error.message,
      );
    }
  }
}
