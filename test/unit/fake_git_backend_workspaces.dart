part of 'fake_git_backend.dart';

mixin _FakeGitBackendWorkspaceState {
  List<GitBackendCall> get calls;
  String get headBranch;
  set headBranch(String value);
  bool get headBranchFails;
  List<String> get sourceBranches;
  Map<String, String?> get remotesByName;
  bool get listRemotesFails;
  GitRepositoryState get gitRepositoryStateResult;
  set gitRepositoryStateResult(GitRepositoryState value);

  String defaultBranchName = 'main';

  Future<String> defaultBranch(String path) async => defaultBranchName;

  GitException? createAndCheckoutBranchError;
  GitException? resetBranchToRefError;
  GitException? checkoutBranchError;
  String? checkoutBranchResult;
  final Map<String, String> currentBranchesByPath = <String, String>{};
  final Map<String, Map<String, String?>> remotesByPath =
      <String, Map<String, String?>>{};

  Future<String> currentBranch(String path) async {
    calls.add(GitBackendCall('currentBranch', <String, Object?>{'path': path}));
    if (headBranchFails) {
      throw const GitInternalException('no head');
    }
    return currentBranchesByPath[path] ?? headBranch;
  }

  Future<void> createAndCheckoutBranch({
    required String path,
    required String branch,
    String? expectedHead,
    String? expectedOid,
  }) async {
    calls.add(
      GitBackendCall('createAndCheckoutBranch', <String, Object?>{
        'path': path,
        'branch': branch,
        'expectedHead': ?expectedHead,
        'expectedOid': ?expectedOid,
      }),
    );
    final error = createAndCheckoutBranchError;
    if (error != null) {
      throw error;
    }
    headBranch = branch;
    currentBranchesByPath[path] = branch;
    gitRepositoryStateResult = GitRepositoryState(
      branch: branch,
      upstream: gitRepositoryStateResult.upstream,
      ahead: gitRepositoryStateResult.ahead,
      behind: gitRepositoryStateResult.behind,
      hasConflicts: gitRepositoryStateResult.hasConflicts,
      headMessage: gitRepositoryStateResult.headMessage,
    );
    if (!sourceBranches.contains(branch)) {
      sourceBranches.add(branch);
    }
  }

  Future<void> resetBranchToRef({
    required String path,
    required String branch,
    required String targetRef,
    String? expectedOid,
  }) async {
    calls.add(
      GitBackendCall('resetBranchToRef', <String, Object?>{
        'path': path,
        'branch': branch,
        'targetRef': targetRef,
        'expectedOid': ?expectedOid,
      }),
    );
    final error = resetBranchToRefError;
    if (error != null) {
      throw error;
    }
  }

  Future<void> checkoutBranch({
    required String path,
    required String branch,
  }) async {
    calls.add(
      GitBackendCall('checkoutBranch', <String, Object?>{
        'path': path,
        'branch': branch,
      }),
    );
    final error = checkoutBranchError;
    if (error != null) {
      throw error;
    }
    final resolved = checkoutBranchResult ?? branch;
    headBranch = resolved;
    currentBranchesByPath[path] = resolved;
    gitRepositoryStateResult = GitRepositoryState(
      branch: resolved,
      upstream: gitRepositoryStateResult.upstream,
      ahead: gitRepositoryStateResult.ahead,
      behind: gitRepositoryStateResult.behind,
      hasConflicts: gitRepositoryStateResult.hasConflicts,
      headMessage: gitRepositoryStateResult.headMessage,
    );
    if (!sourceBranches.contains(resolved)) {
      sourceBranches.add(resolved);
    }
  }

  Future<List<GitRemote>> listRemotes(String path) async {
    calls.add(GitBackendCall('listRemotes', <String, Object?>{'path': path}));
    if (listRemotesFails) {
      throw const GitInternalException('not a git repository');
    }
    final remotes = remotesByPath[path] ?? remotesByName;
    return <GitRemote>[
      for (final entry in remotes.entries)
        GitRemote(name: entry.key, url: entry.value),
    ];
  }

  bool includeQueriedRepoAsMain = false;
  Map<String, String> liveBranchByPath = <String, String>{};
  bool worktreeListFails = false;
  final Set<String> failingWorktreeAddBranches = <String>{};
  final Set<String> failingWorktreeRemovePaths = <String>{};
  GitException? removeWorktreeError;
  final Set<String> failingBranchDeletes = <String>{};
  GitException? deleteBranchError;
  GitException? refreshSourceBranchError;
  final Map<(String, String), bool> ancestorResults =
      <(String, String), bool>{};
  GitException? isAncestorError;

  Future<bool> isAncestor({
    required String path,
    required String ancestorRef,
    required String descendantRef,
  }) async {
    calls.add(
      GitBackendCall('isAncestor', <String, Object?>{
        'path': path,
        'ancestorRef': ancestorRef,
        'descendantRef': descendantRef,
      }),
    );
    final error = isAncestorError;
    if (error != null) {
      throw error;
    }
    return ancestorResults[(ancestorRef, descendantRef)] ?? true;
  }

  Future<void> createWorktree({
    required String repoPath,
    required String targetBranch,
    required String path,
    required String sourceBranch,
    bool reuseExistingBranch = false,
  }) async {
    calls.add(
      GitBackendCall('createWorktree', <String, Object?>{
        'repoPath': repoPath,
        'targetBranch': targetBranch,
        'path': path,
        'sourceBranch': sourceBranch,
        'reuseExistingBranch': reuseExistingBranch,
      }),
    );
    if (failingWorktreeAddBranches.contains(targetBranch)) {
      throw const GitInternalException('add failed');
    }
  }

  Future<void> refreshSourceBranch({
    required String repoPath,
    required String sourceBranch,
  }) async {
    calls.add(
      GitBackendCall('refreshSourceBranch', <String, Object?>{
        'repoPath': repoPath,
        'sourceBranch': sourceBranch,
      }),
    );
    final error = refreshSourceBranchError;
    if (error != null) {
      throw error;
    }
  }

  Future<void> removeWorktree({
    required String repoPath,
    required String path,
    bool force = true,
  }) async {
    calls.add(
      GitBackendCall('removeWorktree', <String, Object?>{
        'repoPath': repoPath,
        'path': path,
        'force': force,
      }),
    );
    if (failingWorktreeRemovePaths.contains(path)) {
      throw const GitInternalException('remove failed');
    }
    final error = removeWorktreeError;
    if (error != null) {
      throw error;
    }
  }

  Future<void> deleteBranch({
    required String repoPath,
    required String branch,
    bool force = true,
  }) async {
    calls.add(
      GitBackendCall('deleteBranch', <String, Object?>{
        'repoPath': repoPath,
        'branch': branch,
        'force': force,
      }),
    );
    if (failingBranchDeletes.contains(branch)) {
      throw const GitInternalException('delete failed');
    }
    final error = deleteBranchError;
    if (error != null) {
      throw error;
    }
    if (!force) {
      final home = defaultBranchName;
      final mergedLocal = ancestorResults[(branch, home)];
      final mergedOrigin = ancestorResults[(branch, 'origin/$home')];
      if ((mergedLocal != null || mergedOrigin != null) &&
          mergedLocal != true &&
          mergedOrigin != true) {
        throw const GitConflictException(
          'Branch has commits not merged into the default branch',
        );
      }
    }
    sourceBranches.remove(branch);
  }

  Future<List<GitWorktreeEntry>> listWorktrees(String repoPath) async {
    calls.add(
      GitBackendCall('listWorktrees', <String, Object?>{'repoPath': repoPath}),
    );
    if (worktreeListFails) {
      throw const GitInternalException('not a git repository');
    }
    return <GitWorktreeEntry>[
      if (includeQueriedRepoAsMain)
        GitWorktreeEntry(path: repoPath, branch: headBranch),
      for (final entry in liveBranchByPath.entries)
        GitWorktreeEntry(path: entry.key, branch: entry.value),
    ];
  }
}
