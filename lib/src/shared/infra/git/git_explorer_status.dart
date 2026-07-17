enum GitExplorerStatus { untracked, added, modified }

class GitExplorerStatusSnapshot {
  GitExplorerStatusSnapshot(Map<String, GitExplorerStatus> statuses)
    : statuses = Map<String, GitExplorerStatus>.unmodifiable(statuses);

  const GitExplorerStatusSnapshot.empty()
    : statuses = const <String, GitExplorerStatus>{};

  final Map<String, GitExplorerStatus> statuses;

  GitExplorerStatus? statusFor(String relativePath) => statuses[relativePath];
}
