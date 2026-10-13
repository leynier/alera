/// Which Git queries a coalesced filesystem change invalidates.
class const SourceControlChanges({
  final bool worktree = false,
  final bool repository = false,
  final bool catalog = false,
}) {
  static const all = SourceControlChanges(
    worktree: true,
    repository: true,
    catalog: true,
  );
  static const files = SourceControlChanges(worktree: true);
  static const index = SourceControlChanges(worktree: true, repository: true);

  bool get any => worktree || repository || catalog;

  SourceControlChanges merge(SourceControlChanges other) =>
      SourceControlChanges(
        worktree: worktree || other.worktree,
        repository: repository || other.repository,
        catalog: catalog || other.catalog,
      );
}
