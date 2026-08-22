part of 'fake_git_backend.dart';

mixin _FakeGitBackendWorkspaceState {
  List<GitBackendCall> get calls;
  String get headBranch;
  bool get headBranchFails;
  Map<String, String?> get remotesByName;
  bool get listRemotesFails;

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
