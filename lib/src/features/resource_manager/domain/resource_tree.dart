/// The workbench-shaped view of a resource snapshot: Project -> Workspace ->
/// Terminal session.
///
/// Metrics are nullable because not every row can be measured. A workspace on
/// an SSH host runs its PTYs on another machine, so its numbers are absent
/// rather than zero, and the panel renders a dash instead of a misleading 0%.
///
/// CPU here is already a share of the machine, unlike the per-core percentages
/// the host sends: `buildResourceTree` normalizes on the way in, so nothing
/// downstream has to remember which unit it is holding.
library;

enum ResourceSortColumn { name, cpu, memory }

class const ResourceSessionRow({
  required final String sessionId,
  required final String label,
  required final String tabId,
  required final bool running,
  required this.orphan,
  required this.cpuMachinePercent,
  required final int? memoryBytes,
  required final int processCount,
  required final List<int> history,
}) {
  /// The host still has this session but the app has no tab for it. Killing an
  /// orphan is safe without a confirmation: there is no pane to lose.
  final bool orphan;

  /// Percent of the machine's total CPU capacity.
  final double? cpuMachinePercent;
}

class const ResourceWorkspaceRow({
  required final String workspaceId,
  required final String name,
  required final String projectId,
  required this.remote,
  required final List<ResourceSessionRow> sessions,
}) {
  /// Driven by the workspace's `hostId`, never by missing samples: a local
  /// session that reconnected to a warm host has no samples for a moment and
  /// must not be relabelled as remote.
  final bool remote;

  double? get cpuMachinePercent =>
      _sumDoubles(sessions.map((session) => session.cpuMachinePercent));

  int? get memoryBytes =>
      _sumInts(sessions.map((session) => session.memoryBytes));
}

class const ResourceProjectGroup({
  required final String projectId,
  required final String name,
  required final List<ResourceWorkspaceRow> workspaces,
}) {
  double? get cpuMachinePercent =>
      _sumDoubles(workspaces.map((workspace) => workspace.cpuMachinePercent));

  int? get memoryBytes =>
      _sumInts(workspaces.map((workspace) => workspace.memoryBytes));
}

class const ResourceTree({
  required final List<ResourceProjectGroup> projects,
  required this.orphanSessions,
}) {
  static const empty = ResourceTree(
    projects: <ResourceProjectGroup>[],
    orphanSessions: <ResourceSessionRow>[],
  );

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
