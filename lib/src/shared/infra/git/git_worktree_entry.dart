/// A single git worktree, mirroring one record of `git worktree list`. The main
/// work tree is included alongside linked worktrees so callers can use its
/// presence as a liveness guard.
class const GitWorktreeEntry({
  required final String path,
  required final String branch,
});
