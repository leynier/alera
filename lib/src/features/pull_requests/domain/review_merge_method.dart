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

/// Default merge strategy for automated and unselected merge actions.
///
/// Provider-default wins when the forge exposes it. Otherwise the first
/// remaining method is used, so a GitHub list that has already dropped merge
/// commits naturally falls through to squash.
ReviewMergeMethod? preferredReviewMergeMethod(
  Iterable<ReviewMergeMethod> methods,
) {
  final list = List<ReviewMergeMethod>.of(methods);
  if (list.contains(ReviewMergeMethod.providerDefault)) {
    return ReviewMergeMethod.providerDefault;
  }
  return list.firstOrNull;
}
