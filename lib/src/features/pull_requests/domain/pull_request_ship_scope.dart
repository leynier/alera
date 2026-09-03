/// Scope selected in the Ship confirmation dialog.
enum PullRequestShipScope {
  /// Commit only the currently staged changes.
  staged,

  /// Stage all working-tree changes first, then commit.
  all,
}
