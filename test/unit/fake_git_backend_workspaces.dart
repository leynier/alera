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

  GitException? createAndCheckoutBranchError;
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
  }) async {
    calls.add(
      GitBackendCall('createAndCheckoutBranch', <String, Object?>{
        'path': path,
        'branch': branch,
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
}
