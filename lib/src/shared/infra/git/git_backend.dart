import 'package:alera/src/shared/infra/git/git_worktree_entry.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';

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

  /// Refreshes [sourceBranch] before it is used as a linked-workspace source.
  Future<void> refreshSourceBranch({
    required String repoPath,
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

  /// Lists changed files in the working tree split by Git area.
  Future<GitStatusResult> status(String path);

  /// Lists changed entries for a single workspace-relative file.
  Future<GitStatusResult> statusForPath({
    required String path,
    required String filePath,
  });

  /// Loads a read-only diff for [filePath] in [area].
  Future<GitDiffResult> diff({
    required String path,
    required String filePath,
    required GitChangeArea area,
  });

  /// Loads a combined read-only diff for all changed files, or a single file
  /// when [filePath] is provided.
  Future<GitDiffResult> diffAll({required String path, String? filePath});

  /// Branch/upstream/divergence information for the repository containing
  /// [path].
  Future<GitRepositoryState> repositoryState(String path);

  /// Stages all visible changes under [path], or a single workspace-relative
  /// [filePath] when provided.
  Future<void> stage({required String path, String? filePath});

  /// Stages visible changes in [area], optionally limited to a workspace
  /// relative file or directory [filePath].
  Future<void> stageArea({
    required String path,
    required GitChangeArea area,
    String? filePath,
  });

  /// Removes all visible staged changes under [path] from the index, or a
  /// single workspace-relative [filePath] when provided.
  Future<void> unstage({required String path, String? filePath});

  /// Removes visible changes in [area] from the index, optionally limited to a
  /// workspace relative file or directory [filePath].
  Future<void> unstageArea({
    required String path,
    required GitChangeArea area,
    String? filePath,
  });

  /// Discards unstaged/untracked changes under [path], or a single
  /// workspace-relative [filePath] when provided.
  Future<void> discard({required String path, String? filePath});

  /// Discards visible changes in [area], optionally limited to a workspace
  /// relative file or directory [filePath].
  Future<void> discardArea({
    required String path,
    required GitChangeArea area,
    String? filePath,
  });

  /// Creates a commit from the currently staged index.
  Future<String> commit({required String path, required String message});

  /// Amends the current HEAD commit using the currently staged index.
  Future<String> amendCommit({required String path, required String message});

  Future<void> fetch(String path);

  Future<void> pull(String path);

  Future<void> push(String path);

  Future<List<GitStashEntry>> listStashes(String path);

  /// Stashes tracked changes for the repository containing [path].
  Future<void> stash(String path);

  Future<void> stashPop({required String path, required int stashIndex});
}
