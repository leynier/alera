import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';

/// Display buckets for the compact agent summary. Enum order is display
/// order: attention-needing states surface first.
enum WorkspaceAgentGroupKind { waiting, blocked, interrupted, working, done }

class WorkspaceAgentRunGroup {
  const WorkspaceAgentRunGroup({required this.kind, required this.runs});

  final WorkspaceAgentGroupKind kind;
  final List<AgentPresenceSummary> runs;
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
