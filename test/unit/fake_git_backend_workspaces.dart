part of 'fake_git_backend.dart';

mixin _FakeGitBackendWorkspaceState {
  List<GitBackendCall> get calls;
  String get headBranch;
  set headBranch(String value);
  bool get headBranchFails;
  List<String> get sourceBranches;
  Map<String, String?> get remotesByName;
  bool get listRemotesFails;

  GitException? createAndCheckoutBranchError;
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
    if (!sourceBranches.contains(branch)) {
      sourceBranches.add(branch);
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
