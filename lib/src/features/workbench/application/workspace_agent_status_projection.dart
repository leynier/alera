import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';

class WorkspaceAgentRun {
  const WorkspaceAgentRun({required this.tab, required this.status});

  final WorkspaceTabRecord tab;
  final AgentStatusEntry status;
}

// Runs keep the incoming tab order (creation order): sorting by status or
// recency would reshuffle sidebar rows on every agent hook event.
List<WorkspaceAgentRun> visibleWorkspaceAgentRuns({
  required Iterable<WorkspaceTabRecord> tabs,
  required Map<String, AgentStatusEntry> agentStatuses,
}) {
  final runs = <WorkspaceAgentRun>[];
  for (final tab in tabs) {
    final entry = matchingAgentStatusForTab(
      tab: tab,
      agentStatuses: agentStatuses,
    );
    if (entry == null) {
      continue;
    }
    runs.add(WorkspaceAgentRun(tab: tab, status: entry));
  }
  return runs;
}

AgentStatusEntry? aggregateWorkspaceAgentStatus({
  required Iterable<WorkspaceTabRecord> tabs,
  required Map<String, AgentStatusEntry> agentStatuses,
}) {
  final runs = visibleWorkspaceAgentRuns(
    tabs: tabs,
    agentStatuses: agentStatuses,
  );
  if (runs.isEmpty) {
    return null;
  }
  var mostUrgent = runs.first;
  for (final run in runs.skip(1)) {
    if (_compareAgentRuns(run, mostUrgent) < 0) {
      mostUrgent = run;
    }
  }
  return mostUrgent.status;
}

AgentStatusEntry? matchingAgentStatusForTab({
  required WorkspaceTabRecord tab,
  required Map<String, AgentStatusEntry> agentStatuses,
}) {
  if (tab.kind != WorkspaceTabKind.terminal) {
    return null;
  }
  final entry = agentStatuses[tab.terminalSessionId];
  if (entry == null ||
      entry.workspaceId != tab.workspaceId ||
      entry.tabId != tab.id ||
      entry.terminalSessionId != tab.terminalSessionId) {
    return null;
  }
  return entry;
}

// Urgency ranking for the aggregate workspace status only; row order stays
// in creation order.
int _compareAgentRuns(WorkspaceAgentRun a, WorkspaceAgentRun b) {
  final aPriority = _workspaceStatusPriority(a.status.state);
  final bPriority = _workspaceStatusPriority(b.status.state);
  if (aPriority != bPriority) {
    return bPriority.compareTo(aPriority);
  }
  final recency = b.status.updatedAt.compareTo(a.status.updatedAt);
  if (recency != 0) {
    return recency;
  }
  return a.tab.createdAt.compareTo(b.tab.createdAt);
}

int _workspaceStatusPriority(AgentStatusState state) {
  return switch (state) {
    AgentStatusState.blocked => 4,
    AgentStatusState.waiting => 3,
    AgentStatusState.working => 2,
    AgentStatusState.done => 1,
  };
}
