String? resolveWorkspaceComparisonBase({
  required List<String> branches,
  required String defaultBranch,
  String? explicitBase,
  String? openReviewBase,
  String? sourceBranch,
  List<String> remoteNames = const ['origin'],
}) {
  String? available(String base) {
    for (final name in [
      if (remoteNames.contains('origin')) 'origin',
      ...remoteNames.where((name) => name != 'origin'),
    ]) {
      final remote = '$name/$base';
      if (branches.contains(remote)) return remote;
    }
    return branches.contains(base) ? base : null;
  }

  // An explicit missing ref reaches Git unchanged so it produces an error
  // instead of silently comparing against a different branch.
  if (explicitBase != null) return available(explicitBase) ?? explicitBase;
  for (final base in [?openReviewBase, ?sourceBranch, defaultBranch]) {
    final resolved = available(base);
    if (resolved != null) return resolved;
  }
  return null;
}

String shortWorkspaceBranchRef(String branch, List<String> remoteNames) {
  for (final remote in remoteNames) {
    if (branch.startsWith('$remote/')) {
      return branch.substring(remote.length + 1);
    }
  }
  return branch;
}
