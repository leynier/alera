import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';

class WorkspaceAgentRun {
  const WorkspaceAgentRun({required this.tab, required this.status});

  final WorkspaceTabRecord tab;
  final AgentStatusEntry status;
}

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
  runs.sort(_compareAgentRuns);
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
  return runs.isEmpty ? null : runs.first.status;
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
