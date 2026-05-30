import 'package:alera/src/shared/infra/git/git_worktree_entry.dart';

/// Injectable boundary for git operations. Mirrors the raw git plumbing only;
/// orchestration (paths, slugs, persistence, reconciliation) lives in the
/// feature services that depend on this.
///
/// Methods complete normally on success and throw a `GitException` subtype on
/// failure. The production implementation (`RustGitBackend`) is backed by Rust
/// (libgit2 for local operations, the `git` CLI for clone) through
/// flutter_rust_bridge; tests use an in-memory fake.
abstract interface class GitBackend {
  /// Whether [path] resolves to a git repository work tree.
  Future<bool> isGitRepository(String path);

  /// Local and remote-tracking branch short names, sorted and de-duplicated.
  Future<List<String>> listBranches(String path);

  /// The current branch short name, or `HEAD` when detached.
  Future<String> currentBranch(String path);

  /// Whether a local branch named [branch] exists in [repoPath].
  Future<bool> branchExists(String repoPath, String branch);

  /// Whether [name] is a valid git branch name.
  Future<bool> isValidBranchName(String name);

  /// Creates [newBranch] from [sourceBranch] and adds a linked worktree at
  /// [path].
  Future<void> createWorktree({
    required String repoPath,
    required String newBranch,
    required String path,
    required String sourceBranch,
  });

  /// Removes the worktree whose checkout lives at [path], deleting its working
  /// tree files when [force] is set.
  Future<void> removeWorktree({
    required String repoPath,
    required String path,
    bool force = true,
  });

  /// Deletes the local branch [branch].
  Future<void> deleteBranch({
    required String repoPath,
    required String branch,
    bool force = true,
  });

  /// The main work tree plus every linked worktree, with each entry's branch.
  Future<List<GitWorktreeEntry>> listWorktrees(String repoPath);

  /// Clones [url] into [destinationPath] using the system `git` CLI so the
  /// user's credential helper authenticates private remotes.
  Future<void> clone({required String url, required String destinationPath});
}
