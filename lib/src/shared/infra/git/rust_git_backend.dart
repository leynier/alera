import 'package:alera/src/rust/api/git.dart' as rust;
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_worktree_entry.dart';

/// [GitBackend] backed by the Rust crate through flutter_rust_bridge. This is
/// the only place that knows about the generated bridge types; it translates
/// the native `GitError` into a domain [GitException] and the native worktree
/// records into [GitWorktreeEntry].
class RustGitBackend implements GitBackend {
  const RustGitBackend();

  @override
  Future<bool> isGitRepository(String path) =>
      _guard(() => rust.isGitRepository(path: path));

  @override
  Future<List<String>> listBranches(String path) =>
      _guard(() => rust.listBranches(path: path));

  @override
  Future<String> currentBranch(String path) =>
      _guard(() => rust.currentBranch(path: path));

  @override
  Future<bool> branchExists(String repoPath, String branch) =>
      _guard(() => rust.branchExists(repoPath: repoPath, branch: branch));

  @override
  Future<bool> isValidBranchName(String name) =>
      _guard(() => rust.isValidBranchName(name: name));

  @override
  Future<void> createWorktree({
    required String repoPath,
    required String newBranch,
    required String path,
    required String sourceBranch,
  }) => _guard(
    () => rust.createWorktree(
      repoPath: repoPath,
      newBranch: newBranch,
      path: path,
      sourceBranch: sourceBranch,
    ),
  );

  @override
  Future<void> removeWorktree({
    required String repoPath,
    required String path,
    bool force = true,
  }) => _guard(
    () => rust.removeWorktree(repoPath: repoPath, path: path, force: force),
  );

  @override
  Future<void> deleteBranch({
    required String repoPath,
    required String branch,
    bool force = true,
  }) => _guard(
    () => rust.deleteBranch(repoPath: repoPath, branch: branch, force: force),
  );

  @override
  Future<List<GitWorktreeEntry>> listWorktrees(String repoPath) => _guard(
    () async {
      final entries = await rust.listWorktrees(repoPath: repoPath);
      return entries
          .map(
            (entry) =>
                GitWorktreeEntry(path: entry.path, branch: entry.branch),
          )
          .toList(growable: false);
    },
  );

  @override
  Future<void> clone({
    required String url,
    required String destinationPath,
  }) => _guard(
    () => rust.cloneRepository(url: url, destinationPath: destinationPath),
  );

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on rust.GitError catch (error) {
      throw _toException(error);
    }
  }

  GitException _toException(rust.GitError error) {
    final context = error.context;
    return switch (error.kind) {
      rust.GitErrorKind.notARepository => NotARepositoryException(context),
      rust.GitErrorKind.accessDenied => AccessDeniedException(context),
      rust.GitErrorKind.branchNotFound => BranchNotFoundException(context),
      rust.GitErrorKind.branchAlreadyExists =>
        BranchAlreadyExistsException(context),
      rust.GitErrorKind.invalidBranchName =>
        InvalidBranchNameException(context),
      rust.GitErrorKind.worktreeAlreadyExists =>
        WorktreeAlreadyExistsException(context),
      rust.GitErrorKind.worktreeNotFound => WorktreeNotFoundException(context),
      rust.GitErrorKind.cloneFailed => CloneFailedException(context),
      rust.GitErrorKind.gitCli => GitCliException(context),
      rust.GitErrorKind.internal => GitInternalException(context),
    };
  }
}
