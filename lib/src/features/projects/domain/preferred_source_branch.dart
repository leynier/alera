/// Chooses the Source Branch picker value from [branches].
///
/// [preferred] is the project default from `alera.toml` or Settings. When it
/// is missing from [branches], Alera also tries the local or `origin/` twin.
/// Otherwise it falls back to `main` / `master`, then the first listed branch.
String? pickDefaultSourceBranch(
  Iterable<String> branches, {
  String? preferred,
}) {
  final names = <String>[for (final branch in branches) branch];
  if (names.isEmpty) {
    return null;
  }
  for (final candidate in preferredSourceBranchCandidates(preferred)) {
    if (names.contains(candidate)) {
      return candidate;
    }
  }
  for (final fallback in const <String>[
    'main',
    'origin/main',
    'master',
    'origin/master',
  ]) {
    if (names.contains(fallback)) {
      return fallback;
    }
  }
  return names.first;
}

List<String> preferredSourceBranchCandidates(String? preferred) {
  final trimmed = preferred?.trim() ?? '';
  if (trimmed.isEmpty) {
    return const <String>[];
  }
  if (trimmed.startsWith('origin/')) {
    final local = trimmed.substring('origin/'.length);
    if (local.isEmpty) {
      return <String>[trimmed];
    }
    return <String>[trimmed, local];
  }
  return <String>[trimmed, 'origin/$trimmed'];
}
