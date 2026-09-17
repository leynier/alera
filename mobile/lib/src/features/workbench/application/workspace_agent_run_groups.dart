import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';

/// Display buckets for the compact agent summary. Enum order is display
/// order: attention-needing states surface first.
enum WorkspaceAgentGroupKind { waiting, blocked, interrupted, working, done }

class const WorkspaceAgentRunGroup({
  required final WorkspaceAgentGroupKind kind,
  required final List<AgentPresenceSummary> runs,
});

/// One agent is shown on the workspace row; two or more stay as nested runs.
class const WorkspaceAgentPresenceSplit({
  final AgentPresenceSummary? primary,
  final List<AgentPresenceSummary> listed = const <AgentPresenceSummary>[],
});

/// Desktop hides a single main-panel agent as nested rows and shows its
/// identity on the workspace instead. Mobile has no pane split, so one
/// agent in the workspace is the same case.
WorkspaceAgentPresenceSplit splitWorkspaceAgentPresence(
  List<AgentPresenceSummary> presence,
) {
  if (presence.length <= 1) {
    return WorkspaceAgentPresenceSplit(primary: presence.firstOrNull);
  }
  return WorkspaceAgentPresenceSplit(listed: presence);
}

/// Groups a workspace's agent presence by visual state for the compact summary
/// pill. Interruption wins over the reported state, mirroring the per-row
/// indicator.
List<WorkspaceAgentRunGroup> groupWorkspaceAgentRuns(
  List<AgentPresenceSummary> runs,
) {
  final byKind = <WorkspaceAgentGroupKind, List<AgentPresenceSummary>>{};
  for (final run in runs) {
    final kind = _groupKindOf(run);
    byKind.putIfAbsent(kind, () => <AgentPresenceSummary>[]).add(run);
  }
  return <WorkspaceAgentRunGroup>[
    for (final kind in WorkspaceAgentGroupKind.values)
      if (byKind[kind] case final List<AgentPresenceSummary> grouped)
        WorkspaceAgentRunGroup(kind: kind, runs: grouped),
  ];
}

WorkspaceAgentGroupKind _groupKindOf(AgentPresenceSummary status) {
  if (status.interrupted ?? false) {
    return WorkspaceAgentGroupKind.interrupted;
  }
  return switch (status.state) {
    'waiting' => WorkspaceAgentGroupKind.waiting,
    'blocked' => WorkspaceAgentGroupKind.blocked,
    'working' => WorkspaceAgentGroupKind.working,
    _ => WorkspaceAgentGroupKind.done,
  };
}
