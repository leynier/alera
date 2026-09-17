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

/// Desktop merges at most one main-panel agent onto the workspace row and
/// always lists right-pane runs. [mainTabIds] are those main-panel tabs;
/// an empty set is an older host, so every agent counts as main.
WorkspaceAgentPresenceSplit splitWorkspaceAgentPresence(
  List<AgentPresenceSummary> presence, {
  Set<String> mainTabIds = const <String>{},
}) {
  if (presence.isEmpty) {
    return const WorkspaceAgentPresenceSplit();
  }
  final hasMainAssignment = mainTabIds.isNotEmpty;
  final mainRuns = hasMainAssignment
      ? presence.where((run) => mainTabIds.contains(run.tabId)).toList()
      : presence;
  final secondaryRuns = hasMainAssignment
      ? presence.where((run) => !mainTabIds.contains(run.tabId)).toList()
      : const <AgentPresenceSummary>[];
  final mergeMainAgent = mainRuns.length <= 1;
  return WorkspaceAgentPresenceSplit(
    primary: mergeMainAgent ? mainRuns.firstOrNull : null,
    listed: <AgentPresenceSummary>[
      if (!mergeMainAgent) ...mainRuns,
      ...secondaryRuns,
    ],
  );
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
