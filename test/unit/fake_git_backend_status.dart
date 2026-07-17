part of 'fake_git_backend.dart';

mixin _FakeGitBackendStatus {
  List<GitBackendCall> get calls;
  GitException? get statusError;

  GitStatusResult gitStatusResult = const GitStatusResult(entries: []);
  GitExplorerStatusSnapshot gitExplorerStatusSnapshot =
      const GitExplorerStatusSnapshot.empty();

  Future<GitStatusResult> status(String path) async {
    calls.add(GitBackendCall('status', <String, Object?>{'path': path}));
    final error = statusError;
    if (error != null) {
      throw error;
    }
    return gitStatusResult;
  }

  Future<GitExplorerStatusSnapshot> explorerStatusSnapshot(String path) async {
    calls.add(
      GitBackendCall('explorerStatusSnapshot', <String, Object?>{'path': path}),
    );
    return gitExplorerStatusSnapshot;
  }
}
