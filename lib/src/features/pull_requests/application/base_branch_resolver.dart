/// Strips a remote-tracking prefix (`origin/…`) so forge create flags receive
/// short branch names (`main`, not `origin/main`).
String shortBranchName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  final slash = trimmed.indexOf('/');
  if (slash <= 0) {
    return trimmed;
  }
  // Only strip a single remote/ segment (origin/feature/foo → feature/foo).
  return trimmed.substring(slash + 1);
}

/// Normalizes [rawBranches] from [GitBackend.listBranches] into de-duplicated
/// short names suitable for pull-request base selection.
List<String> normalizeBaseBranches(Iterable<String> rawBranches) {
  final seen = <String>{};
  final result = <String>[];
  for (final raw in rawBranches) {
    final short = shortBranchName(raw);
    if (short.isEmpty || !seen.add(short)) {
      continue;
    }
    result.add(short);
  }
  result.sort();
  return result;
}

/// Picks the base branch for a new pull request.
///
/// Order: preferred (when present in [branches] after normalization), then
/// `main`, then `master`, then the first listed branch, else `main`.
String pickDefaultBaseBranch(List<String> branches, {String? preferred}) {
  final preferredShort = preferred == null || preferred.trim().isEmpty
      ? null
      : shortBranchName(preferred);
  if (preferredShort != null && branches.contains(preferredShort)) {
    return preferredShort;
  }
  for (final candidate in const <String>['main', 'master']) {
    if (branches.contains(candidate)) {
      return candidate;
    }
  }
  if (branches.isNotEmpty) {
    return branches.first;
  }
  return preferredShort ?? 'main';
}
