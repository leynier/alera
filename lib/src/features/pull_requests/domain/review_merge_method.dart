/// Merge strategies exposed by hosted-review providers.
enum ReviewMergeMethod {
  providerDefault,
  mergeCommit,
  squash,
  rebase;

  String get label => switch (this) {
    ReviewMergeMethod.providerDefault => 'Merge Using Project Settings',
    ReviewMergeMethod.mergeCommit => 'Create Merge Commit',
    ReviewMergeMethod.squash => 'Squash and Merge',
    ReviewMergeMethod.rebase => 'Rebase and Merge',
  };
}
