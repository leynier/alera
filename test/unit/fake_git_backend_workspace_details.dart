part of 'fake_git_backend.dart';

mixin _FakeGitBackendWorkspaceDetails implements GitBackend {
  GitWorkspaceComparison? comparisonResult;
  @override
  Future<String> workspaceDefaultBranch(String path) => defaultBranch(path);

  @override
  Future<GitWorkspaceComparison> workspaceComparison(
    String path, {
    String? baseRef,
  }) async =>
      comparisonResult ??
      GitWorkspaceComparison(
        baseRef: baseRef,
        baseOid: 'base',
        headOid: 'head',
        headRef: 'refs/heads/main',
        treeOid: 'tree',
        indexOid: 'index',
        entries: const [],
        added: 0,
        removed: 0,
      );
  @override
  Future<GitDiffResult> workspaceComparisonDiff(
    String path,
    GitWorkspaceComparison snapshot,
    String filePath,
  ) async => const GitDiffResult(files: [], truncated: false);
  @override
  Future<String> commitSelected(
    String path,
    GitWorkspaceComparison snapshot,
    List<String> filePaths,
    String message,
  ) => commit(path: path, message: message);
}
