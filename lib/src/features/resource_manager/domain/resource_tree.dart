/// The workbench-shaped view of a resource snapshot: Project -> Workspace ->
/// Terminal session.
///
/// Metrics are nullable because not every row can be measured. A workspace on
/// an SSH host runs its PTYs on another machine, so its numbers are absent
/// rather than zero, and the panel renders a dash instead of a misleading 0%.
library;

enum ResourceSortColumn { name, cpu, memory }

class ResourceSessionRow {
  const ResourceSessionRow({
    required this.sessionId,
    required this.label,
    required this.tabId,
    required this.running,
    required this.orphan,
    required this.cpuPercent,
    required this.memoryBytes,
    required this.processCount,
    required this.history,
  });

  final String sessionId;
  final String label;
  final String tabId;
  final bool running;

  /// The host still has this session but the app has no tab for it. Killing an
  /// orphan is safe without a confirmation: there is no pane to lose.
  final bool orphan;
  final double? cpuPercent;
  final int? memoryBytes;
  final int processCount;
  final List<int> history;
}

class ResourceWorkspaceRow {
  const ResourceWorkspaceRow({
    required this.workspaceId,
    required this.name,
    required this.projectId,
    required this.remote,
    required this.sessions,
  });

  final String workspaceId;
  final String name;
  final String projectId;

  /// Driven by the workspace's `hostId`, never by missing samples: a local
  /// session that reconnected to a warm host has no samples for a moment and
  /// must not be relabelled as remote.
  final bool remote;
  final List<ResourceSessionRow> sessions;

  double? get cpuPercent =>
      _sumDoubles(sessions.map((session) => session.cpuPercent));

  int? get memoryBytes =>
      _sumInts(sessions.map((session) => session.memoryBytes));
}

class ResourceProjectGroup {
  const ResourceProjectGroup({
    required this.projectId,
    required this.name,
    required this.workspaces,
  });

  final String projectId;
  final String name;
  final List<ResourceWorkspaceRow> workspaces;

  double? get cpuPercent =>
      _sumDoubles(workspaces.map((workspace) => workspace.cpuPercent));

  int? get memoryBytes =>
      _sumInts(workspaces.map((workspace) => workspace.memoryBytes));
}

class ResourceTree {
  const ResourceTree({required this.projects, required this.orphanSessions});

  static const empty = ResourceTree(
    projects: <ResourceProjectGroup>[],
    orphanSessions: <ResourceSessionRow>[],
  );

  final List<ResourceProjectGroup> projects;

  /// Sessions the host reports that no tab claims, flattened out of the tree
  /// so the panel can offer a single "kill them all" action.
  final List<ResourceSessionRow> orphanSessions;

  bool get isEmpty => projects.isEmpty && orphanSessions.isEmpty;
}

/// Descending comparison where an absent metric always sorts last, so unmeasured
/// remote rows never displace real readings at the top of the panel.
int compareMetricDescending(num? left, num? right) {
  if (left == null && right == null) {
    return 0;
  }
  if (left == null) {
    return 1;
  }
  if (right == null) {
    return -1;
  }
  return right.compareTo(left);
}

double? _sumDoubles(Iterable<double?> values) {
  double? total;
  for (final value in values) {
    if (value == null) {
      continue;
    }
    total = (total ?? 0) + value;
  }
  return total;
}

int? _sumInts(Iterable<int?> values) {
  int? total;
  for (final value in values) {
    if (value == null) {
      continue;
    }
    total = (total ?? 0) + value;
  }
  return total;
}
