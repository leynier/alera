enum GitExplorerStatus { untracked, added, modified }

class GitExplorerStatusSnapshot {
  new(Map<String, GitExplorerStatus> statuses)
    : statuses = Map<String, GitExplorerStatus>.unmodifiableOf(statuses);

  const new empty() : statuses = const <String, GitExplorerStatus>{};

  final Map<String, GitExplorerStatus> statuses;

  GitExplorerStatus? statusFor(String relativePath) => statuses[relativePath];
}
