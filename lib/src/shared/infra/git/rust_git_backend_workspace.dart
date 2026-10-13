part of 'rust_git_backend.dart';

mixin _RustGitBackendWorkspace on _RustGitBackendHostedReview
    implements GitBackend {
  @override
  Future<String> workspaceDefaultBranch(String path) =>
      _guard(() => comparison_rust.gitWorkspaceDefaultBranch(path: path));

  @override
  Future<GitWorkspaceComparison> workspaceComparison(
    String path, {
    String? baseRef,
  }) => _guard(() async {
    final result = await comparison_rust.gitWorkspaceComparison(
      path: path,
      baseRef: baseRef,
    );
    return GitWorkspaceComparison(
      baseRef: result.baseRef,
      baseOid: result.baseOid,
      headOid: result.headOid,
      headRef: result.headRef,
      treeOid: result.treeOid,
      indexOid: result.indexOid,
      entries: result.entries
          .map((this as RustGitBackend)._toChangeEntry)
          .toList(growable: false),
      added: result.added,
      removed: result.removed,
    );
  });
  comparison_rust.GitWorkspaceComparison _nativeComparison(
    GitWorkspaceComparison snapshot,
  ) => comparison_rust.GitWorkspaceComparison(
    baseRef: snapshot.baseRef,
    baseOid: snapshot.baseOid,
    headOid: snapshot.headOid,
    headRef: snapshot.headRef,
    treeOid: snapshot.treeOid,
    indexOid: snapshot.indexOid,
    added: snapshot.added,
    removed: snapshot.removed,
    entries: [
      for (final entry in snapshot.entries)
        rust.GitChangeEntry(
          path: entry.path,
          oldPath: entry.oldPath,
          area: (this as RustGitBackend)._toRustArea(entry.area),
          status: rust.GitChangeStatus.values.byName(entry.status.name),
          added: entry.added,
          removed: entry.removed,
          isBinary: entry.isBinary,
          isLarge: entry.isLarge,
          submodule: null,
        ),
    ],
  );
  @override
  Future<GitDiffResult> workspaceComparisonDiff(
    String path,
    GitWorkspaceComparison snapshot,
    String filePath,
  ) => _guard(
    () async => (this as RustGitBackend)._toDiffResult(
      await comparison_rust.gitWorkspaceComparisonDiff(
        path: path,
        snapshot: _nativeComparison(snapshot),
        filePath: filePath,
      ),
    ),
  );
  @override
  Future<String> commitSelected(
    String path,
    GitWorkspaceComparison snapshot,
    List<String> filePaths,
    String message,
  ) => _guard(
    () => comparison_rust.gitCommitSelected(
      path: path,
      snapshot: _nativeComparison(snapshot),
      filePaths: filePaths,
      message: message,
    ),
  );
}
