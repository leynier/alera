/// Merge strategies exposed by hosted-review providers.
enum ReviewMergeMethod {
  mergeCommit,
  squash,
  rebase;

  String get label => switch (this) {
    ReviewMergeMethod.mergeCommit => 'Create Merge Commit',
    ReviewMergeMethod.squash => 'Squash and Merge',
    ReviewMergeMethod.rebase => 'Rebase and Merge',
  };
}
